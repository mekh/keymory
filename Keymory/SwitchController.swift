//
//  SwitchController.swift
//  Keymory
//

import AppKit
import Observation

/// The state machine: restores the remembered input source when an app is
/// activated and records the user's layout changes for the frontmost app.
@Observable @MainActor
final class SwitchController {
    private static let isEnabledKey = "isEnabled"
    private static let defaultSourceIDKey = "defaultSourceID"
    private static let showFlagKey = "showFlag"
    /// Persisted intent for optional extra-window tracking. Literal kept as
    /// `"trackPopUpWindows"` for backward compatibility: the shipped pop-up
    /// build shares the `toxic0der.Keymory` defaults domain, so renaming the
    /// key would silently reset an existing user's toggle.
    private static let trackExtraWindowsKey = "trackPopUpWindows"
    private static let suppressionWindow: Duration = .seconds(1)
    /// How long to wait before reading the current source after a change
    /// notification. Immediately after the notification
    /// `TISCopyCurrentKeyboardInputSource` can still return the *previous*
    /// source (the process-local value settles asynchronously; observed in the
    /// field as recording/showing the source one switch behind).
    private static let settleDelay: Duration = .milliseconds(250)
    private static let inputSourceChangedNotification =
        Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")
    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    /// Transient system surfaces that grab clicks or keystrokes but must never
    /// own the layout context: reacting to them would flip the layout on every
    /// Dock click or menu-bar interaction. Any other detected target — any
    /// app's non-activating panel, present or future — is tracked. Kept in the
    /// core (not the detector) so the guarantee stays unit-testable and every
    /// variant shares it; a detector may additionally suppress its own noise.
    private static let systemUIBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
        "com.apple.screencaptureui",
        "com.apple.Siri",
    ]

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.isEnabledKey)
            updateDetector()
            if isEnabled {
                seedFrontmostApp()
            }
        }
    }

    private(set) var mappingCount: Int

    /// Input source applied to apps not yet in the store (first-seen apps).
    /// `nil` means keep whatever source is currently active — the original
    /// behavior. Persisted so the choice survives relaunches.
    var defaultSourceID: String? {
        didSet {
            if let defaultSourceID {
                defaults.set(defaultSourceID, forKey: Self.defaultSourceIDKey)
            } else {
                defaults.removeObject(forKey: Self.defaultSourceIDKey)
            }
        }
    }

    /// Whether the menu bar shows the current source as a flag (true) or a
    /// language code (false). Presentation only; persisted.
    var showFlag: Bool {
        didSet { defaults.set(showFlag, forKey: Self.showFlagKey) }
    }

    /// Whether optional extra-window tracking is on — non-activating panels of
    /// any app: iTerm hotkey window, Spotlight, Raycast, 1Password Quick
    /// Access, and whatever ships tomorrow. This is the persisted *intent*: it
    /// may be true while the detector's permission is still missing — the
    /// detector only runs once the permission is granted. Entirely dormant on a
    /// build that injects no detector (`supportsExtraTracking == false`).
    var trackExtraWindows: Bool {
        didSet {
            defaults.set(trackExtraWindows, forKey: Self.trackExtraWindowsKey)
            updateDetector()
            if !trackExtraWindows {
                // Drop a possible detected context so later source changes are
                // attributed to the real frontmost app again.
                seedFrontmostApp()
            }
        }
    }

    enum ExtraTrackingOutcome {
        case enabled, disabled, permissionRequired
    }

    private let store: MappingStore
    private let inputSources: InputSourceClient
    /// Supplementary activation detector (event tap / AX focus). `nil` on builds
    /// that rely only on `NSWorkspace` activation — the whole extra-tracking
    /// apparatus below then stays dormant.
    private let detector: ActivationDetector?
    private let defaults: UserDefaults
    private let ownBundleID: String?
    private let frontmostProvider: () -> String?
    private let clock = ContinuousClock()

    private var frontmostBundleID: String?
    private(set) var restoreTask: Task<Void, Never>?
    /// Deferred recording of a manual source change (see `settleDelay`).
    /// Cancelled on app activation: once the frontmost app changes, the
    /// pending read could observe the next app's restored source instead.
    private(set) var recordTask: Task<Void, Never>?
    /// Our own recent programmatic switch: change notifications matching this
    /// source inside the deadline are ours and must not be recorded. Passive
    /// expiry (no clearing) avoids any clear-too-early race with the
    /// asynchronously delivered distributed notification.
    private var suppression: (sourceID: String, deadline: ContinuousClock.Instant)?
    /// Outcome of the most recent restore, used to guard the switch-away
    /// snapshot: after an unverified restore the current system source does
    /// not reflect the user's choice for that app.
    private var lastRestore: (bundleID: String, verified: Bool)?
    private var isScreenLocked = false
    private var started = false
    /// Tokens returned by addObserver(forName:) must be retained: the
    /// observation is removed as soon as its token is deallocated.
    private var observers: [NSObjectProtocol] = []

    init(
        store: MappingStore,
        inputSources: InputSourceClient,
        detector: ActivationDetector? = nil,
        defaults: UserDefaults = .standard,
        ownBundleID: String? = Bundle.main.bundleIdentifier,
        frontmostProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.store = store
        self.inputSources = inputSources
        self.detector = detector
        self.defaults = defaults
        self.ownBundleID = ownBundleID
        self.frontmostProvider = frontmostProvider
        self.mappingCount = store.count
        self.isEnabled = defaults.object(forKey: Self.isEnabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.isEnabledKey)
        self.defaultSourceID = defaults.string(forKey: Self.defaultSourceIDKey)
        self.showFlag = defaults.bool(forKey: Self.showFlagKey)
        self.trackExtraWindows = defaults.bool(forKey: Self.trackExtraWindowsKey)
    }

    /// Enabled, select-capable keyboard input sources for the default-language
    /// picker, sorted by localized name.
    func availableInputSources() -> [InputSourceInfo] {
        inputSources.availableSources()
    }

    /// Primary language code of the current input source, for the menu bar icon.
    func currentSourceLanguageCode() -> String? {
        inputSources.currentSourceLanguageCode()
    }

    func start() {
        // Idempotent: guard against a second start() doubling the observers.
        guard !started else { return }
        started = true

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.handleActivation(bundleID: bundleID)
            }
        })

        let distributedCenter = DistributedNotificationCenter.default()
        observers.append(distributedCenter.addObserver(
            forName: Self.inputSourceChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSourceChange()
            }
        })
        observers.append(distributedCenter.addObserver(
            forName: Self.screenLockedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenLockChange(locked: true)
            }
        })
        observers.append(distributedCenter.addObserver(
            forName: Self.screenUnlockedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenLockChange(locked: false)
            }
        })

        // Launch baseline: no didActivate fires for the already-frontmost app.
        // Track it, but neither restore (no surprise layout flip at launch)
        // nor record (must not overwrite a stored preference).
        seedFrontmostApp()

        updateDetector()
    }

    // MARK: - Extra-window tracking (dormant when no detector is injected)

    /// Whether a detector is available at all. Drives whether the menu offers
    /// the toggle: builds that rely only on `NSWorkspace` activation hide it.
    var supportsExtraTracking: Bool { detector != nil }

    /// Menu title / permission deep-link supplied by the injected detector, so
    /// the menu code stays mechanism-neutral across builds.
    var extraTrackingTitle: String? { detector?.menuTitle }
    var extraTrackingSettingsURL: URL? { detector?.settingsURL }

    /// Whether the detector is actually delivering — false while its permission
    /// is still missing, which the menu renders as a mixed state.
    var extraTrackingActive: Bool { detector?.isActive ?? false }

    /// Flips extra-window tracking. `.permissionRequired` means the intent was
    /// stored and the system prompt was requested, but the permission is not
    /// granted yet — the caller should route the user to System Settings.
    func toggleExtraTracking() -> ExtraTrackingOutcome {
        guard !trackExtraWindows else {
            trackExtraWindows = false
            return .disabled
        }
        trackExtraWindows = true
        guard let detector, !detector.permissionGranted() else { return .enabled }
        detector.requestPermission()
        return .permissionRequired
    }

    /// Re-evaluates whether the detector should run. Safe to call any time;
    /// used when the menu opens to pick up a permission granted in Settings.
    func refreshExtraTracking() {
        updateDetector()
    }

    /// An input event / focus change was routed to `bundleID` (the detector's
    /// resolved target). Any target can take the tracked context — that is what
    /// makes arbitrary apps' pop-ups work with no per-app list — except the
    /// transient system surfaces in `systemUIBundleIDs`. Leaving a pop-up needs
    /// no special case: the next signal simply targets the app underneath.
    func handleDetectedActivation(bundleID: String?) {
        guard isEnabled, trackExtraWindows, !isScreenLocked else { return }
        guard let bundleID, bundleID != ownBundleID, bundleID != frontmostBundleID else {
            return
        }
        guard !Self.systemUIBundleIDs.contains(bundleID) else { return }
        handleActivation(bundleID: bundleID)
    }

    func handleActivation(bundleID: String?) {
        guard isEnabled, !isScreenLocked else { return }
        // Interacting with our own menu must not disturb tracking of the app
        // the user is actually working in.
        guard bundleID != ownBundleID else { return }

        restoreTask?.cancel()
        recordTask?.cancel()

        // Switch-away snapshot: capture the outgoing app's source in case its
        // change notification was late or swallowed by the suppression window.
        // Skipped after an unverified restore for that app, when the current
        // source would not reflect the user's actual choice.
        if let outgoing = frontmostBundleID,
           !(lastRestore?.bundleID == outgoing && lastRestore?.verified == false),
           let current = inputSources.currentSourceID() {
            store.record(sourceID: current, for: outgoing)
        }

        frontmostBundleID = bundleID
        defer { mappingCount = store.count }

        guard let bundleID, let current = inputSources.currentSourceID() else { return }

        guard let entry = store.entry(for: bundleID) else {
            // First-seen app: switch to the default language if one is set,
            // otherwise adopt the current source, and remember it from here.
            // If the default source is unavailable, restore() keeps the current
            // source silently and the stored default stays dormant (the guarded
            // switch-away snapshot won't overwrite it, since restore fails
            // unverified).
            let target = defaultSourceID ?? current
            store.record(sourceID: target, for: bundleID)
            if target != current {
                restoreTask = Task {
                    await restore(target, for: bundleID)
                }
            }
            return
        }
        if entry.sourceID != current {
            restoreTask = Task {
                await restore(entry.sourceID, for: bundleID)
            }
        }
    }

    func handleSourceChange() {
        guard isEnabled, !isScreenLocked else { return }
        guard let bundleID = frontmostBundleID else { return }
        recordTask?.cancel()
        recordTask = Task {
            await recordSettledSource(for: bundleID)
        }
    }

    /// Reads the current source only after `settleDelay` so a stale
    /// notification-time value is never recorded, then applies the same
    /// suppression / attribution rules as before.
    private func recordSettledSource(for bundleID: String) async {
        try? await Task.sleep(for: Self.settleDelay)
        guard !Task.isCancelled, isEnabled, !isScreenLocked else { return }
        // Frontmost changed mid-delay: the switch-away snapshot in
        // handleActivation already captured the outgoing app.
        guard frontmostBundleID == bundleID else { return }
        guard let current = inputSources.currentSourceID() else { return }
        if let suppression,
           suppression.sourceID == current,
           clock.now < suppression.deadline {
            return
        }
        store.record(sourceID: current, for: bundleID)
        mappingCount = store.count
    }

    func forgetAll() {
        store.removeAll()
        mappingCount = 0
    }

    func handleScreenLockChange(locked: Bool) {
        isScreenLocked = locked
        updateDetector()
        if !locked {
            // The login window may have switched the source; re-baseline so
            // its changes are not attributed to the frontmost app.
            seedFrontmostApp()
        }
    }

    /// Starts or stops the injected detector to match the current intent.
    /// No-op when no detector is injected. Safe to call repeatedly.
    private func updateDetector() {
        guard let detector else { return }
        if isEnabled && trackExtraWindows && !isScreenLocked && detector.permissionGranted() {
            _ = detector.start { [weak self] bundleID in
                self?.handleDetectedActivation(bundleID: bundleID)
            }
        } else {
            detector.stop()
        }
    }

    private func seedFrontmostApp() {
        let bundleID = frontmostProvider()
        frontmostBundleID = bundleID == ownBundleID ? nil : bundleID
    }

    private func restore(_ targetID: String, for bundleID: String) async {
        lastRestore = (bundleID, verified: false)
        for _ in 0..<3 {
            guard !Task.isCancelled else { return }
            suppression = (targetID, clock.now.advanced(by: Self.suppressionWindow))
            // Missing/disabled layout: keep the current source silently and
            // keep the stored entry — the user may re-enable the layout later.
            guard inputSources.selectSource(id: targetID) else { return }
            // Give the switch time to land before verifying. This verify/retry
            // loop is the seam where CJKV-specific remediation (e.g. the
            // macism temporary-window trick) would plug in if ever needed.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if inputSources.currentSourceID() == targetID {
                lastRestore = (bundleID, verified: true)
                return
            }
        }
    }
}
