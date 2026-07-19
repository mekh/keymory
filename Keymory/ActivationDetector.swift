//
//  ActivationDetector.swift
//  Keymory
//

import Foundation

/// A supplementary source of "the user's typing context moved to this app"
/// signals, layered on top of the built-in `NSWorkspace` app-activation that
/// every build uses. A build injects one of these to catch contexts that fire
/// no activation notification — e.g. a listen-only event tap that reacts to the
/// first event routed to a non-activating panel (App Store build), or
/// Accessibility focus observation that fires *before* the first keystroke
/// (non-sandboxed personal build).
///
/// `SwitchController` stays agnostic to the mechanism: it only receives target
/// bundle identifiers and drives the detector's lifecycle. This protocol
/// therefore imports Foundation only — a build that injects no detector links
/// no Carbon / CGEvent / Accessibility code, keeping the App Store binary clean.
///
/// Any surface-ignore policy (Dock, Control Center, …) belongs to the concrete
/// detector, not here: which surfaces emit spurious signals is mechanism-
/// specific, so the detector simply must not report them.
@MainActor
protocol ActivationDetector: AnyObject {
    /// Whether the detector is currently installed and delivering events.
    var isActive: Bool { get }

    /// Title for the menu toggle that enables this detector, e.g.
    /// "Track Pop-up Windows" or "Track All Windows".
    var menuTitle: String { get }

    /// Deep link to the System Settings pane that grants this detector's
    /// permission (Input Monitoring / Accessibility), or `nil` if none applies.
    var settingsURL: URL? { get }

    /// Whether the detector's permission is granted (or none is required).
    /// Cheap; safe to poll when the menu opens.
    func permissionGranted() -> Bool

    /// Shows the system permission prompt when the OS still allows one. Returns
    /// the (usually `false`) immediately-granted state; the real grant happens
    /// in System Settings and typically takes effect after an app relaunch.
    @discardableResult
    func requestPermission() -> Bool

    /// Installs the detector. `onActivation` is called with the bundle id an
    /// input event / focus change is routed to (`nil` when unresolvable).
    /// Idempotent; returns `false` when the detector cannot start (e.g. the
    /// permission is missing).
    func start(onActivation: @escaping (String?) -> Void) -> Bool

    func stop()
}
