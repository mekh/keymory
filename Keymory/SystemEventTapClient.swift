//
//  SystemEventTapClient.swift
//  Keymory
//

import AppKit

/// `ActivationDetector` backed by a listen-only `CGEventTap`. This is the
/// pop-up-tracking build's detector; the only file here that touches
/// CGEventTap. The protocol lives in the shared `ActivationDetector.swift`.
///
/// The tap sits at `kCGAnnotatedSessionEventTap` — the point where the window
/// server has already annotated each event with the process it is routed to
/// (`kCGEventTargetUnixProcessID`). That annotation is what makes non-activating
/// panels (iTerm hotkey window, Spotlight, Raycast) visible: their key events
/// target the panel's owner while `frontmostApplication` still reports the
/// previous app. Verified empirically inside the sandbox on macOS 26.
///
/// Privacy: the tap is listen-only and reads a single integer field — the
/// target pid. Key codes and characters are never inspected. Filtering of
/// transient system surfaces (Dock, Control Center, …) is handled centrally by
/// `SwitchController`, so this detector reports every resolved target.
@MainActor
final class SystemEventTapClient: ActivationDetector {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onActivation: ((String?) -> Void)?
    /// Target pid of the most recent event: the callback fires per keystroke
    /// and click, so downstream work is gated on the target changing.
    private var lastPID: pid_t = -1

    var isActive: Bool { tap != nil }

    var menuTitle: String { "Track Pop-up Windows" }

    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func permissionGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func start(onActivation: @escaping (String?) -> Void) -> Bool {
        self.onActivation = onActivation
        guard tap == nil else { return true }
        lastPID = -1

        func bit(_ type: CGEventType) -> CGEventMask {
            CGEventMask(1) << CGEventMask(type.rawValue)
        }
        // keyDown: typing into a panel. leftMouseDown: clicking (back) into
        // a visible panel. flagsChanged: modifier-based launcher hotkeys
        // (⌘Space) emit a trailing flags event already routed to the panel —
        // it arrives before the first character, so the switch beats typing.
        let mask = bit(.keyDown) | bit(.leftMouseDown) | bit(.flagsChanged)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // The runloop source lives on the main runloop, so the
                // callback always arrives on the main thread.
                let client = Unmanaged<SystemEventTapClient>.fromOpaque(refcon!)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    client.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon)
        else {
            self.onActivation = nil
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        onActivation = nil
        lastPID = -1
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        source = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap it considers unresponsive; re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid != lastPID else { return }
        lastPID = pid
        onActivation?(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }
}
