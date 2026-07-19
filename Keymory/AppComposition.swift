//
//  AppComposition.swift
//  Keymory
//

import Foundation

/// Composition root — the single per-branch-divergent source file. It selects
/// the concrete input-source client and activation detector for this build
/// variant. Keeping the choice here is what lets `SwitchController`,
/// `KeymoryApp`, and the shared tests stay byte-identical across the three
/// branches (App Store, pop-up tracking, non-sandboxed personal), so a
/// business-logic fix propagates by overwriting those files with zero conflicts.
///
/// This is the App Store / `main` variant: no supplementary detector (detection
/// is `NSWorkspace` activation only), and the default TIS-backed input client.
enum AppComposition {
    /// Keyboard input-source backend. The system Carbon/TIS client on this
    /// build; the personal build may substitute a more aggressive client to
    /// make switches stick in terminals.
    static func makeInputSourceClient() -> InputSourceClient {
        SystemInputSourceClient()
    }

    /// Supplementary activation detector layered on top of `NSWorkspace`
    /// activation. `nil` here → sandbox-only detection, no extra permission,
    /// and the "Track…" menu item stays hidden.
    static func makeActivationDetector() -> ActivationDetector? {
        nil
    }
}
