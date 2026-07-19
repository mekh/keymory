//
//  SwitchControllerTests.swift
//  KeymoryTests
//

import XCTest
@testable import Keymory

@MainActor
final class MockInputSourceClient: InputSourceClient {
    var currentID: String?
    /// Return value of selectSource (false simulates a missing/disabled layout).
    var selectSucceeds = true
    /// Whether a successful select actually changes the current source
    /// (false simulates the switch silently not taking effect).
    var selectLands = true
    var sources: [InputSourceInfo] = []
    private(set) var selectedIDs: [String] = []

    func currentSourceID() -> String? { currentID }

    func selectSource(id: String) -> Bool {
        selectedIDs.append(id)
        guard selectSucceeds else { return false }
        if selectLands {
            currentID = id
        }
        return true
    }

    func availableSources() -> [InputSourceInfo] { sources }

    func currentSourceLanguageCode() -> String? { currentID }
}

@MainActor
final class MockActivationDetector: ActivationDetector {
    /// Whether the (simulated) permission is granted.
    var permission = true
    var menuTitle = "Track Windows"
    var settingsURL: URL? = URL(string: "x-apple.systempreferences:test")
    private(set) var isActive = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var requestCount = 0
    private var sink: ((String?) -> Void)?

    func permissionGranted() -> Bool { permission }

    @discardableResult
    func requestPermission() -> Bool {
        requestCount += 1
        return permission
    }

    func start(onActivation: @escaping (String?) -> Void) -> Bool {
        sink = onActivation
        isActive = true
        startCount += 1
        return true
    }

    func stop() {
        sink = nil
        isActive = false
        stopCount += 1
    }

    /// Simulates an input event / focus change routed to `bundleID`.
    func emit(_ bundleID: String?) {
        sink?(bundleID)
    }
}

@MainActor
final class SwitchControllerTests: XCTestCase {
    private static let ownBundleID = "test.keymory"

    private var defaults: UserDefaults!
    private var store: MappingStore!
    private var mock: MockInputSourceClient!
    private var controller: SwitchController!
    private var frontmostForSeed: String?

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")
        store = MappingStore(defaults: defaults)
        mock = MockInputSourceClient()
        controller = SwitchController(
            store: store,
            inputSources: mock,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { [weak self] in self?.frontmostForSeed }
        )
    }

    private func awaitRestore() async {
        await controller.restoreTask?.value
    }

    private func awaitRecord() async {
        await controller.recordTask?.value
    }

    private func makeController(detector: ActivationDetector) -> SwitchController {
        SwitchController(
            store: store,
            inputSources: mock,
            detector: detector,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { [weak self] in self?.frontmostForSeed }
        )
    }

    // MARK: - Activation

    func testFirstSeenAppAdoptsCurrentSource() {
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.a")

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertNil(controller.restoreTask)
    }

    // MARK: - Default language

    func testFirstSeenAppWithDefaultSwitchesToDefault() async {
        controller.defaultSourceID = "uk"
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.a")
        await awaitRestore()

        XCTAssertEqual(mock.selectedIDs, ["uk"])
        XCTAssertEqual(mock.currentID, "uk")
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testFirstSeenAppWithDefaultAlreadyActiveSkipsSelect() {
        controller.defaultSourceID = "en"
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.a")

        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertNil(controller.restoreTask)
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
    }

    func testFirstSeenAppWithUnavailableDefaultKeepsCurrentButStoresDefault() async {
        controller.defaultSourceID = "uk"
        mock.currentID = "en"
        mock.selectSucceeds = false

        controller.handleActivation(bundleID: "app.a")
        await awaitRestore()

        XCTAssertEqual(mock.currentID, "en")
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testClearingDefaultReturnsToAdoptCurrent() {
        controller.defaultSourceID = "uk"
        controller.defaultSourceID = nil
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.a")

        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
    }

    func testDefaultSourceIDPersistsAcrossInstances() {
        controller.defaultSourceID = "uk"

        let reloaded = SwitchController(
            store: store,
            inputSources: mock,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { nil }
        )

        XCTAssertEqual(reloaded.defaultSourceID, "uk")
    }

    func testAvailableInputSourcesReflectsClient() {
        mock.sources = [
            InputSourceInfo(id: "en", name: "ABC"),
            InputSourceInfo(id: "uk", name: "Ukrainian"),
        ]

        XCTAssertEqual(controller.availableInputSources(), mock.sources)
    }

    // MARK: - Activation (known apps)

    func testKnownAppRestoresStoredSource() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.b")
        await awaitRestore()

        XCTAssertEqual(mock.selectedIDs, ["uk"])
        XCTAssertEqual(mock.currentID, "uk")
    }

    func testKnownAppWithSameSourceSkipsSelect() {
        store.record(sourceID: "en", for: "app.a")
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.a")

        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertNil(controller.restoreTask)
    }

    func testMissingLayoutKeepsCurrentSourceAndMapping() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"
        mock.selectSucceeds = false

        controller.handleActivation(bundleID: "app.b")
        await awaitRestore()

        XCTAssertEqual(mock.currentID, "en")
        XCTAssertEqual(mock.selectedIDs, ["uk"])
        XCTAssertEqual(store.entry(for: "app.b")?.sourceID, "uk")
    }

    func testSnapshotSkippedAfterFailedRestore() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"
        mock.selectSucceeds = false

        controller.handleActivation(bundleID: "app.b")
        await awaitRestore()
        controller.handleActivation(bundleID: "app.c")

        XCTAssertEqual(store.entry(for: "app.b")?.sourceID, "uk")
    }

    func testOwnBundleIDIsIgnored() async {
        mock.currentID = "en"

        controller.handleActivation(bundleID: Self.ownBundleID)

        XCTAssertEqual(store.count, 0)

        // Tracking of the previous app must be undisturbed as well.
        controller.handleActivation(bundleID: "app.a")
        controller.handleActivation(bundleID: Self.ownBundleID)
        mock.currentID = "uk"
        controller.handleSourceChange()
        await awaitRecord()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testNilBundleIDIsNeverPersisted() async {
        mock.currentID = "en"

        controller.handleActivation(bundleID: nil)

        XCTAssertEqual(store.count, 0)

        // Layout changes while an unattributed process is frontmost are dropped.
        mock.currentID = "uk"
        controller.handleSourceChange()
        await awaitRecord()

        XCTAssertEqual(store.count, 0)
    }

    func testDisabledControllerDoesNothing() {
        controller.isEnabled = false
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.a")
        controller.handleSourceChange()

        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(mock.selectedIDs.isEmpty)
    }

    func testIsEnabledPersistsAcrossInstances() {
        controller.isEnabled = false

        let reloaded = SwitchController(
            store: store,
            inputSources: mock,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { nil }
        )

        XCTAssertFalse(reloaded.isEnabled)
    }

    // MARK: - Source-change recording

    func testSourceChangeRecordedForFrontmostApp() async {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        mock.currentID = "uk"
        controller.handleSourceChange()
        await awaitRecord()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testSourceChangeRecordsSettledValueNotNotificationTimeValue() async {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        // Field bug: at notification time TIS still reports the old source
        // ("en"); the switch to "uk" becomes visible only after the settle
        // delay. The deferred read must record the settled value.
        controller.handleSourceChange()
        mock.currentID = "uk"
        await awaitRecord()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testActivationCancelsPendingSourceChangeRecord() async {
        store.record(sourceID: "fr", for: "app.b")
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        // Manual switch, then an app activation before the deferred read
        // fires: the pending record must not observe app.b's restored source
        // and attribute it to app.a.
        controller.handleSourceChange()
        let pending = controller.recordTask
        mock.currentID = "uk"
        controller.handleActivation(bundleID: "app.b")
        await pending?.value
        await awaitRestore()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
        XCTAssertEqual(mock.currentID, "fr")
    }

    func testSwitchAwaySnapshotCapturesMissedChange() {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        // The user switches the layout but the change notification is lost.
        mock.currentID = "uk"
        controller.handleActivation(bundleID: "app.b")

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testManualChangeToDifferentSourceDuringSuppressionIsRecorded() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"

        controller.handleActivation(bundleID: "app.b")
        await awaitRestore()

        // Manual switch inside the suppression window, to a different source
        // than the one we just restored: must still be recorded.
        mock.currentID = "fr"
        controller.handleSourceChange()
        await awaitRecord()

        XCTAssertEqual(store.entry(for: "app.b")?.sourceID, "fr")
    }

    // MARK: - Restore retries and cancellation

    func testRestoreRetriesWhenSwitchDoesNotLand() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"
        mock.selectLands = false

        controller.handleActivation(bundleID: "app.b")
        await awaitRestore()

        XCTAssertEqual(mock.selectedIDs, ["uk", "uk", "uk"])
        XCTAssertEqual(store.entry(for: "app.b")?.sourceID, "uk")
    }

    func testActivationCancelsInFlightRestore() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"
        mock.selectLands = false

        controller.handleActivation(bundleID: "app.b")
        let inFlight = controller.restoreTask
        // Let the restore task run up to its first post-select sleep.
        await Task.yield()

        controller.handleActivation(bundleID: "app.c")
        await inFlight?.value

        XCTAssertEqual(mock.selectedIDs.filter { $0 == "uk" }, ["uk"])
    }

    // MARK: - Screen lock

    func testChangesWhileLockedAreNotRecorded() {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        controller.handleScreenLockChange(locked: true)
        mock.currentID = "abc"
        controller.handleSourceChange()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
    }

    func testUnlockReseedsFrontmostApp() async {
        mock.currentID = "en"
        frontmostForSeed = "app.a"

        controller.handleScreenLockChange(locked: true)
        controller.handleScreenLockChange(locked: false)
        mock.currentID = "uk"
        controller.handleSourceChange()
        await awaitRecord()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    // MARK: - Forget all

    func testForgetAllClearsMappings() {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        controller.forgetAll()

        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(controller.mappingCount, 0)
    }

    // MARK: - Extra-window tracking (detector)

    func testNoDetectorMeansExtraTrackingUnsupported() {
        // setUp's controller is built without a detector (the App Store build).
        XCTAssertFalse(controller.supportsExtraTracking)
        XCTAssertFalse(controller.extraTrackingActive)
        XCTAssertNil(controller.extraTrackingTitle)
    }

    func testEnablingTrackingStartsDetectorWhenPermitted() {
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)

        XCTAssertTrue(controller.supportsExtraTracking)
        XCTAssertEqual(controller.toggleExtraTracking(), .enabled)

        XCTAssertTrue(controller.trackExtraWindows)
        XCTAssertTrue(detector.isActive)
        XCTAssertTrue(controller.extraTrackingActive)
        XCTAssertEqual(detector.startCount, 1)
    }

    func testTrackingStaysInactiveWithoutPermission() {
        let detector = MockActivationDetector()
        detector.permission = false
        let controller = makeController(detector: detector)

        XCTAssertEqual(controller.toggleExtraTracking(), .permissionRequired)
        XCTAssertTrue(controller.trackExtraWindows)   // intent is stored
        XCTAssertFalse(detector.isActive)             // but nothing is delivered
        XCTAssertFalse(controller.extraTrackingActive)
        XCTAssertEqual(detector.requestCount, 1)      // the prompt was requested
    }

    func testTogglingOffStopsDetector() {
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()
        XCTAssertTrue(detector.isActive)

        XCTAssertEqual(controller.toggleExtraTracking(), .disabled)
        XCTAssertFalse(controller.trackExtraWindows)
        XCTAssertFalse(detector.isActive)
    }

    func testDetectedActivationRestoresStoredSource() async {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()

        detector.emit("app.b")
        await controller.restoreTask?.value

        XCTAssertEqual(mock.selectedIDs, ["uk"])
        XCTAssertEqual(mock.currentID, "uk")
    }

    func testDetectedActivationDedupsCurrentContext() {
        store.record(sourceID: "en", for: "app.a")
        mock.currentID = "en"
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()
        controller.handleActivation(bundleID: "app.a")   // frontmost = app.a

        // A detector signal for the app that already holds the context is a
        // no-op — no restore/record churn.
        detector.emit("app.a")

        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertNil(controller.restoreTask)
    }

    func testDetectedActivationIgnoredWhenTrackingOff() {
        store.record(sourceID: "uk", for: "app.b")
        mock.currentID = "en"
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        // Tracking never enabled: a stray emit must do nothing.
        detector.emit("app.b")

        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertNil(controller.restoreTask)
    }

    func testDetectedActivationIgnoresSystemUISurfaces() {
        mock.currentID = "en"
        store.record(sourceID: "uk", for: "com.apple.dock")   // even with a stored mapping
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()
        controller.handleActivation(bundleID: "app.a")        // frontmost = app.a

        detector.emit("com.apple.dock")                        // a click on the Dock

        // The Dock must never take the context: no restore, no churn.
        XCTAssertTrue(mock.selectedIDs.isEmpty)
        XCTAssertNil(controller.restoreTask)
    }

    func testDisablingControllerStopsDetector() {
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()
        XCTAssertTrue(detector.isActive)

        controller.isEnabled = false

        XCTAssertFalse(detector.isActive)
    }

    func testScreenLockStopsDetectorAndUnlockRestarts() {
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()
        XCTAssertTrue(detector.isActive)

        controller.handleScreenLockChange(locked: true)
        XCTAssertFalse(detector.isActive)

        controller.handleScreenLockChange(locked: false)
        XCTAssertTrue(detector.isActive)
    }

    func testTrackExtraWindowsPersistsAcrossInstances() {
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()
        XCTAssertTrue(controller.trackExtraWindows)

        let reloaded = SwitchController(
            store: store,
            inputSources: mock,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { nil }
        )

        XCTAssertTrue(reloaded.trackExtraWindows)
    }

    func testDetectedActivationPreservesPendingManualSwitchViaSnapshot() async {
        // A detector-driven activation routes through handleActivation, which
        // cancels a pending deferred recordTask. The outgoing context's manual
        // switch must still be preserved — captured by the switch-away
        // snapshot — rather than silently dropped.
        mock.currentID = "en"
        let detector = MockActivationDetector()
        let controller = makeController(detector: detector)
        _ = controller.toggleExtraTracking()

        controller.handleActivation(bundleID: "panel")   // frontmost = panel (adopts en)
        mock.currentID = "uk"                             // user switches layout in the panel
        controller.handleSourceChange()                  // schedules the deferred record
        let pending = controller.recordTask

        detector.emit("app.a")                            // new context before the record settles
        await pending?.value                              // the record was cancelled
        await controller.restoreTask?.value

        XCTAssertEqual(store.entry(for: "panel")?.sourceID, "uk")
    }
}
