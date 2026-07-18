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
final class MockEventTapClient: EventTapClient {
    var granted = true
    private(set) var requestCount = 0
    private var onEvent: ((String?) -> Void)?

    var isRunning: Bool { onEvent != nil }

    func permissionGranted() -> Bool { granted }

    @discardableResult
    func requestPermission() -> Bool {
        requestCount += 1
        return false
    }

    func start(onEvent: @escaping (String?) -> Void) -> Bool {
        guard granted else { return false }
        self.onEvent = onEvent
        return true
    }

    func stop() { onEvent = nil }

    /// Simulates an input event routed to the given bundle id.
    func send(_ bundleID: String?) { onEvent?(bundleID) }
}

@MainActor
final class SwitchControllerTests: XCTestCase {
    private static let ownBundleID = "test.keymory"
    private static let iterm = "com.googlecode.iterm2"

    private var defaults: UserDefaults!
    private var store: MappingStore!
    private var mock: MockInputSourceClient!
    private var tap: MockEventTapClient!
    private var controller: SwitchController!
    private var frontmostForSeed: String?

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")
        store = MappingStore(defaults: defaults)
        mock = MockInputSourceClient()
        tap = MockEventTapClient()
        controller = SwitchController(
            store: store,
            inputSources: mock,
            eventTap: tap,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { [weak self] in self?.frontmostForSeed }
        )
    }

    private func awaitRestore() async {
        await controller.restoreTask?.value
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

    func testOwnBundleIDIsIgnored() {
        mock.currentID = "en"

        controller.handleActivation(bundleID: Self.ownBundleID)

        XCTAssertEqual(store.count, 0)

        // Tracking of the previous app must be undisturbed as well.
        controller.handleActivation(bundleID: "app.a")
        controller.handleActivation(bundleID: Self.ownBundleID)
        mock.currentID = "uk"
        controller.handleSourceChange()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testNilBundleIDIsNeverPersisted() {
        mock.currentID = "en"

        controller.handleActivation(bundleID: nil)

        XCTAssertEqual(store.count, 0)

        // Layout changes while an unattributed process is frontmost are dropped.
        mock.currentID = "uk"
        controller.handleSourceChange()

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

    func testSourceChangeRecordedForFrontmostApp() {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        mock.currentID = "uk"
        controller.handleSourceChange()

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
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

    func testUnlockReseedsFrontmostApp() {
        mock.currentID = "en"
        frontmostForSeed = "app.a"

        controller.handleScreenLockChange(locked: true)
        controller.handleScreenLockChange(locked: false)
        mock.currentID = "uk"
        controller.handleSourceChange()

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

    // MARK: - Pop-up window tracking

    func testToggleWithPermissionStartsTap() {
        XCTAssertEqual(controller.toggleTrackPopUps(), .enabled)

        XCTAssertTrue(controller.trackPopUps)
        XCTAssertTrue(tap.isRunning)
        XCTAssertTrue(controller.popUpTrackingActive)
    }

    func testToggleWithoutPermissionStoresIntentAndRequests() {
        tap.granted = false

        XCTAssertEqual(controller.toggleTrackPopUps(), .permissionRequired)

        XCTAssertTrue(controller.trackPopUps)
        XCTAssertEqual(tap.requestCount, 1)
        XCTAssertFalse(tap.isRunning)
        XCTAssertFalse(controller.popUpTrackingActive)
    }

    func testRefreshStartsTapOncePermissionAppears() {
        tap.granted = false
        _ = controller.toggleTrackPopUps()

        tap.granted = true
        controller.refreshPopUpTracking()

        XCTAssertTrue(tap.isRunning)
    }

    func testToggleOffStopsTapAndReattributesToFrontmost() {
        frontmostForSeed = "app.front"
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.front")
        _ = controller.toggleTrackPopUps()
        controller.handleEventTarget(bundleID: Self.iterm)

        XCTAssertEqual(controller.toggleTrackPopUps(), .disabled)

        XCTAssertFalse(tap.isRunning)
        // Context must be re-seeded: later changes belong to the real
        // frontmost app, not the pop-up.
        mock.currentID = "uk"
        controller.handleSourceChange()
        XCTAssertEqual(store.entry(for: "app.front")?.sourceID, "uk")
        XCTAssertEqual(store.entry(for: Self.iterm)?.sourceID, "en")
    }

    func testPopUpEventRestoresRememberedSourceAndSnapshotsOutgoing() async {
        store.record(sourceID: "uk", for: Self.iterm)
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")
        _ = controller.toggleTrackPopUps()

        tap.send(Self.iterm)
        await awaitRestore()

        XCTAssertEqual(mock.currentID, "uk")
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
    }

    func testPopUpDismissRestoresFrontmostAppSource() async {
        frontmostForSeed = "app.a"
        store.record(sourceID: "uk", for: Self.iterm)
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")
        _ = controller.toggleTrackPopUps()
        tap.send(Self.iterm)
        await awaitRestore()

        // Panel dismissed: the next event targets the still-frontmost app.
        tap.send("app.a")
        await awaitRestore()

        XCTAssertEqual(mock.currentID, "en")
        XCTAssertEqual(store.entry(for: Self.iterm)?.sourceID, "uk")
    }

    func testSourceChangeDuringPopUpAttributedToPopUp() {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")
        _ = controller.toggleTrackPopUps()
        tap.send("com.apple.Spotlight")

        mock.currentID = "uk"
        controller.handleSourceChange()

        XCTAssertEqual(store.entry(for: "com.apple.Spotlight")?.sourceID, "uk")
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
    }

    func testSystemUITargetsAreIgnored() {
        frontmostForSeed = "app.a"
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")
        _ = controller.toggleTrackPopUps()

        // Dock is a transient system surface — never a layout context.
        tap.send("com.apple.dock")

        XCTAssertNil(store.entry(for: "com.apple.dock"))
        XCTAssertNil(controller.restoreTask)
        mock.currentID = "uk"
        controller.handleSourceChange()
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "uk")
    }

    func testAnyAppPanelIsTrackedWithoutAllowlisting() async {
        store.record(sourceID: "uk", for: "com.1password.1password")
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")
        _ = controller.toggleTrackPopUps()

        tap.send("com.1password.1password")
        await awaitRestore()

        XCTAssertEqual(mock.currentID, "uk")
        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "en")
    }

    func testEventsIgnoredWhileTrackingDisabled() {
        mock.currentID = "en"
        controller.handleActivation(bundleID: "app.a")

        controller.handleEventTarget(bundleID: Self.iterm)

        XCTAssertNil(store.entry(for: Self.iterm))
    }

    func testDisablingControllerStopsTap() {
        _ = controller.toggleTrackPopUps()
        XCTAssertTrue(tap.isRunning)

        controller.isEnabled = false
        XCTAssertFalse(tap.isRunning)

        controller.isEnabled = true
        XCTAssertTrue(tap.isRunning)
    }

    func testScreenLockSuspendsTap() {
        _ = controller.toggleTrackPopUps()

        controller.handleScreenLockChange(locked: true)
        XCTAssertFalse(tap.isRunning)

        controller.handleScreenLockChange(locked: false)
        XCTAssertTrue(tap.isRunning)
    }

    func testTrackPopUpsPersistsAcrossInstances() {
        _ = controller.toggleTrackPopUps()

        let reloaded = SwitchController(
            store: store,
            inputSources: mock,
            eventTap: tap,
            defaults: defaults,
            ownBundleID: Self.ownBundleID,
            frontmostProvider: { nil }
        )

        XCTAssertTrue(reloaded.trackPopUps)
    }
}
