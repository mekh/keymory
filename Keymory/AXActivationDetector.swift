//
//  AXActivationDetector.swift
//  Keymory
//

import AppKit
import ApplicationServices

/// `ActivationDetector` backed by the Accessibility API. This is the
/// non-sandboxed personal build's detector; the only file here that touches
/// Accessibility. The protocol lives in the shared `ActivationDetector.swift`.
///
/// Why this build exists: a listen-only event tap (the sandboxed pop-up build)
/// can only react to the *first event* routed to a non-activating panel, so the
/// first character after opening e.g. an iTerm hotkey window may still land in
/// the previous layout. The Accessibility API sees keyboard focus move
/// *before* any key is pressed, which lets this build switch the layout with no
/// extra keystroke or click — the whole point of dropping the sandbox.
///
/// Mechanism: poll the system-wide element's `kAXFocusedApplicationAttribute`,
/// which reflects the process that currently owns keyboard focus — including a
/// non-activating panel whose owner never becomes `frontmostApplication`
/// (verified: iTerm hotkey window, Spotlight, Raycast, …). On each change the
/// resolved bundle id is reported; `SwitchController` centrally ignores
/// transient system surfaces (Dock, Control Center, …), so this detector
/// reports every resolved target. A poll (rather than per-app AX observers) is
/// deliberate: reading the system-wide focused application is the reliable
/// signal, whereas per-app focus notifications are famously flaky for
/// non-activating panels; the read is cheap (it hits the AX runtime, not the
/// target app) and only runs while the option is enabled.
///
/// AX-silent apps: Chromium-based apps (Chrome, Slack, Electron, …) take
/// keyboard focus without the AX runtime ever reporting a focused application
/// (`kAXErrorNoValue` on every poll). A panel hiding over such an app then
/// produces no focus signal at all — the tracked context would stay stuck on
/// the panel's app and the layout would never be restored (verified in-app
/// 2026-07-19: iTerm hotkey window hiding over an Electron frontmost app).
/// When the read keeps failing, the frontmost app is the only possible typing
/// target, so after a short debounce it is reported as the focus owner.
///
/// Privacy: this reads *which application* holds focus — never keystrokes or
/// window contents. It does not use the event-input APIs at all.
@MainActor
final class AXActivationDetector: ActivationDetector {
    /// Focus is sampled this often. Fast enough to switch before the user
    /// starts typing into a freshly opened panel, cheap enough to be idle.
    private static let pollInterval: Duration = .milliseconds(120)
    /// Upper bound on a single AX request so an unresponsive target can never
    /// stall the poll. The focused-application read normally returns instantly.
    private static let messagingTimeout: Float = 0.25
    /// Consecutive read failures before falling back to the frontmost app.
    /// Two polls (240 ms) debounce transient mid-transition errors while
    /// staying well ahead of the user's next keystroke.
    private static let readFailureThreshold = 2

    private let systemWide = AXUIElementCreateSystemWide()
    private var pollTask: Task<Void, Never>?
    private var onActivation: ((String?) -> Void)?
    /// Pid that last held focus; downstream work is gated on it changing so a
    /// steady focus produces no repeated activations.
    private var lastPID: pid_t = -1
    /// Consecutive AX read failures; see `readFailureThreshold`.
    private var readFailures = 0

    var isActive: Bool { pollTask != nil }

    var menuTitle: String { "Track All Windows" }

    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func permissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start(onActivation: @escaping (String?) -> Void) -> Bool {
        self.onActivation = onActivation
        guard pollTask == nil else { return true }
        guard AXIsProcessTrusted() else {
            self.onActivation = nil
            return false
        }
        lastPID = -1
        readFailures = 0
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        return true
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        onActivation = nil
        lastPID = -1
        readFailures = 0
    }

    private func poll() {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            fallBackToFrontmost()
            return
        }
        // Safe: the type id check above guarantees this is an AXUIElement.
        let appElement = value as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(appElement, &pid) == .success, pid > 0 else {
            fallBackToFrontmost()
            return
        }
        readFailures = 0
        guard pid != lastPID else { return }
        lastPID = pid
        onActivation?(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }

    /// When the AX read keeps failing (AX-silent apps such as Chromium-based
    /// ones return `kAXErrorNoValue` even while their window holds keyboard
    /// focus), no focus-holder exists as far as AX is concerned, so the
    /// frontmost app is the only possible typing target. After the debounce
    /// threshold it is reported as the focus owner, which lets the controller
    /// leave a stuck panel context and restore the frontmost app's layout.
    private func fallBackToFrontmost() {
        readFailures += 1
        guard readFailures >= Self.readFailureThreshold,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != lastPID else { return }
        lastPID = app.processIdentifier
        onActivation?(app.bundleIdentifier)
    }
}
