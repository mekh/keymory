//
//  AppComposition.swift
//  Keymory
//

import Foundation

/// Composition root — the single per-branch-divergent source file. It selects
/// the concrete input-source client and activation detector for this build
/// variant. Keeping the choice here is what lets `SwitchController`,
/// `KeymoryApp`, and the shared tests stay byte-identical across the branches
/// (App Store, pop-up tracking, non-sandboxed personal), so a business-logic
/// fix propagates by overwriting those files with zero conflicts.
///
/// This is the non-sandboxed personal variant: an Accessibility-based detector
/// that switches the layout for non-activating panels *before the first
/// keystroke*, plus the default TIS input client. App Sandbox is OFF on this
/// branch (see `Config/App.xcconfig`); that is what lets the Accessibility API
/// observe other processes at all.
enum AppComposition {
    /// Keyboard input-source backend. The system Carbon/TIS client on this
    /// build.
    static func makeInputSourceClient() -> InputSourceClient {
        SystemInputSourceClient()
    }

    /// Supplementary activation detector layered on top of `NSWorkspace`
    /// activation: Accessibility focus observation that fires before the first
    /// keystroke once the Accessibility permission is granted.
    static func makeActivationDetector() -> ActivationDetector? {
        AXActivationDetector()
    }
}
