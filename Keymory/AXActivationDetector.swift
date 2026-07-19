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

    private let systemWide = AXUIElementCreateSystemWide()
    private var pollTask: Task<Void, Never>?
    private var onActivation: ((String?) -> Void)?
    /// Pid that last held focus; downstream work is gated on it changing so a
    /// steady focus produces no repeated activations.
    private var lastPID: pid_t = -1

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
    }

    private func poll() {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return
        }
        // Safe: the type id check above guarantees this is an AXUIElement.
        let appElement = value as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(appElement, &pid) == .success, pid > 0 else { return }
        guard pid != lastPID else { return }
        lastPID = pid
        onActivation?(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }
}
