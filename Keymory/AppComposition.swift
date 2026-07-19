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
/// This is the pop-up-tracking variant: a listen-only event-tap detector for
/// non-activating panels (Input Monitoring), plus the default TIS input client.
enum AppComposition {
    /// Keyboard input-source backend. The system Carbon/TIS client on this
    /// build.
    static func makeInputSourceClient() -> InputSourceClient {
        SystemInputSourceClient()
    }

    /// Supplementary activation detector layered on top of `NSWorkspace`
    /// activation: the annotated-session event tap that surfaces non-activating
    /// panels once Input Monitoring is granted.
    static func makeActivationDetector() -> ActivationDetector? {
        SystemEventTapClient()
    }
}
