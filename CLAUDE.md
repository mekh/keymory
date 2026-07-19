# Keymory — project guide

macOS menu-bar utility that remembers the keyboard input source (language/layout)
**per application** and restores it automatically when you switch apps.

**The one rule:** on app activation, set the input source last used in that app.
First-seen app → adopt the current source (or the configured *Default Language*).
A remembered source that is no longer installed/enabled → keep the current source
silently. Memory persists indefinitely (no eviction). Every app is auto-remembered.

- Repo: `github.com/mekh/keymory` · Bundle ID: `toxic0der.Keymory`
- Distribution: free, non-tracking, App Store (Utilities). Also runnable via direct build.

## Branches / build variants

The app is maintained as variants that share **one identical core** and differ only at the
edges — *how an app activation is detected*, and whether the app is sandboxed:

- **`shared-core`** — the App Store base / `main` candidate. Detection is `NSWorkspace`
  app-activation only; App Sandbox ON; no extra permission. Injects **no** activation
  detector, so the extra-window-tracking apparatus is dormant and the "Track…" menu item
  is hidden. **← this branch**; see "This branch" below.
- **`popup-window-tracking`** — App Store + optional pop-up tracking via a listen-only
  `CGEventTap` (Input Monitoring). Adds `Keymory/SystemEventTapClient.swift`.
- **`personal`** (planned) — non-sandboxed build that switches proactively in any window
  (iTerm, Spotlight, …) via the Accessibility API. Would inject an AX detector, and may
  inject a more aggressive `InputSourceClient` for terminal stickiness.
- **`main`** — left untouched for now; `shared-core` is its eventual replacement.

**Shared core — byte-identical across all branches:** `SwitchController.swift`,
`KeymoryApp.swift`, `InputSourceClient.swift`, `MappingStore.swift`, `MenuBarLabel.swift`,
`ActivationDetector.swift`, all of `KeymoryTests/`, `Config/App.xcconfig`, and
`Keymory.xcodeproj/project.pbxproj`. A business-logic fix touches these once and
propagates by **overwrite**, not cherry-pick:

```sh
git checkout <source-branch> -- \
  Keymory/SwitchController.swift Keymory/KeymoryApp.swift \
  Keymory/InputSourceClient.swift Keymory/MappingStore.swift \
  Keymory/MenuBarLabel.swift Keymory/ActivationDetector.swift \
  KeymoryTests/ Config/App.xcconfig Keymory.xcodeproj/project.pbxproj
```

Because those files are identical, the overwrite cannot conflict. **Per-branch files**
(never cross-merged): `Keymory/AppComposition.swift` (the composition root — present on
every branch, different contents) and each branch's detector implementation
(`SystemEventTapClient.swift` on popup; an AX detector on personal; **none** here).
Docs (`CLAUDE.md`, `README.md`, `PRIVACY.md`) are also per-branch.

## Naming / layout

Renamed from **SmartInputSwitch** → **Keymory** (product, scheme, targets, folders,
bundle id — no trace of the old name should reappear).

- Xcode project: `Keymory.xcodeproj`, scheme `Keymory`, targets `Keymory` /
  `KeymoryTests` / `KeymoryUITests`.
- Source folders: `Keymory/`, `KeymoryTests/`, `KeymoryUITests/`.
- The **local checkout folder is still `smart-input-switch`** (kebab). The GitHub repo
  is `keymory`. Renaming the local folder is optional and not done.
- `objectVersion 77` file-system-synchronized groups: new `.swift` files under the
  target folders are picked up automatically — **no `project.pbxproj` edits needed** to
  add sources. This is why a per-branch detector file swaps in with no project-file edit
  (and why the shared `project.pbxproj` stays identical across branches).

## Architecture (shared core, all MainActor)

- `Keymory/KeymoryApp.swift` — `@main` App with `NSApplicationDelegateAdaptor`. The
  `AppDelegate` owns an AppKit **`NSStatusItem`** (menu bar) and the `SwitchController`,
  which it builds via `AppComposition.makeInputSourceClient()` +
  `makeActivationDetector()`. Uses `NSStatusItem` **not** SwiftUI `MenuBarExtra`
  (MenuBarExtra did not reliably appear for a menu-bar-only app on this macOS). Menu is an
  `NSMenu` rebuilt in `menuNeedsUpdate`. `updateStatusAppearance()` renders the
  current-language indicator (flag or code) into a vertically-centred image; skips
  identical repaints (`renderedLabelKey`); refreshed on the distributed TIS notification
  **plus a re-check cascade** (`scheduleLabelRecheck`: 150 ms + 1 s) and on
  `didActivateApplication` — a TIS read at notification time can still return the previous
  source (see Critical facts). `item.autosaveName = "KeymoryStatusItem"` persists the icon
  position. "Forget All" tinted red via `attributedTitle`. The extra-tracking menu item is
  shown **only** when `controller.supportsExtraTracking` (a detector is injected); its
  title + Settings deep-link come from the detector (`extraTrackingTitle` /
  `extraTrackingSettingsURL`), it renders `.mixed` while the detector's permission is
  missing, `menuNeedsUpdate` calls `refreshExtraTracking()` so a grant made in Settings is
  picked up on the next open, and on `.permissionRequired` the app opens the detector's
  `settingsURL`.
- `Keymory/SwitchController.swift` — `@Observable @MainActor` state machine (the field fix
  `371a6cf` lives here). `handleActivation` order: guard enabled/lock → ignore own bundle
  id → cancel `restoreTask` + `recordTask` → **switch-away snapshot** (record outgoing
  app's current source, guarded by `lastRestore.verified`) → set frontmost → first-seen
  (adopt Default Language or current) / known (restore if differs). `handleSourceChange`
  records manual switches **after a 250 ms settle delay** (cancellable `recordTask`,
  cancelled on activation; a notification-time TIS read can return the previous source),
  skipped inside the **suppression window** (value + monotonic `ContinuousClock` deadline
  — not a boolean; the distributed notification arrives asynchronously). `restore()` =
  cancellable verify/retry loop (select → sleep 50 ms → confirm, ×3) — the seam where
  CJKV / terminal-stickiness remediation would plug in (via a per-branch
  `InputSourceClient`). `start()` idempotent (`started` guard), seeds the frontmost app at
  launch **without** restoring or recording, handles screen lock/unlock. **Extra-window
  tracking apparatus (dormant when no detector is injected — as on this branch):**
  `trackExtraWindows` is the persisted *intent* (UserDefaults key kept as
  `"trackPopUpWindows"` for compat; may be true while the permission is missing);
  `handleDetectedActivation` accepts **any** detector target as the new context —
  arbitrary apps' panels work with no per-app list, incl. future apps — except transient
  system surfaces (`systemUIBundleIDs`: Dock, Control Center, Notification Center,
  WindowManager, …), filtered **centrally here** (not in the detector) so the guarantee
  stays unit-tested and every variant shares it. `updateDetector` starts/stops the detector
  iff enabled ∧ trackExtraWindows ∧ unlocked ∧ granted; `toggleExtraTracking` →
  `.enabled/.disabled/.permissionRequired`; `refreshExtraTracking` re-evaluates. Both
  detection paths reuse `handleActivation` wholesale (snapshot → restore → attribution).
- `Keymory/ActivationDetector.swift` — the mechanism-neutral **seam**: a `@MainActor`
  protocol (`isActive`, `menuTitle`, `settingsURL`, `permissionGranted`,
  `requestPermission`, `start(onActivation:)`, `stop`). **Foundation-only** imports, so a
  build that injects no detector (this one) links no Carbon/CGEvent/Accessibility code.
  The concrete detector is per-branch (see Branches).
- `Keymory/AppComposition.swift` — **the one intentionally per-branch source file.**
  `makeInputSourceClient()` + `makeActivationDetector()` pick this variant's concrete
  types. This indirection is what lets every other core file stay byte-identical across
  branches.
- `Keymory/InputSourceClient.swift` — protocol + `SystemInputSourceClient`; the **only**
  file that touches Carbon/TIS. `currentSourceID()` uses
  `TISCopyCurrentKeyboardInputSource` (mode-level id, correct for IME sub-modes — never
  `...KeyboardLayoutInputSource`). `selectSource` queries `TISCreateInputSourceList` fresh
  each call (respects layouts added/removed at runtime), filtered by keyboard category +
  `IsSelectCapable` + `IsEnabled`. `currentSourceLanguageCode()` → primary language code.
- `Keymory/MappingStore.swift` — persistence. `[String: AppEntry]` (bundleID → sourceID)
  JSON-encoded into one UserDefaults blob under key `"mappings.v1"`. `AppEntry` holds only
  `sourceID`. `record` skips the write when unchanged; there is **no `touch()`** — a bare
  app activation writes nothing (avoids per-Cmd-Tab write amplification). Backward-
  compatible decode (extra keys ignored).
- `Keymory/MenuBarLabel.swift` — pure, testable formatter. Language code → code
  ("EN"/"UA"/…) or flag emoji. `flagRegionByLanguage` maps language→region where they
  differ (`en`→US, `uk`→UA, `he`→IL, …); `codeOverrides` (`uk`→UA so it isn't confused
  with the UK). No RU examples are used anywhere in the project.
- Tests in `KeymoryTests/`: `MappingStoreTests`, `SwitchControllerTests`
  (with `MockInputSourceClient` and `MockActivationDetector`), `MenuBarLabelTests`.

## This branch (shared-core)

`AppComposition.makeActivationDetector()` returns `nil`; the input client is the default
`SystemInputSourceClient`. Behaviour is exactly the App Store base: detection via
`NSWorkspace` activation only, the extra-window-tracking apparatus dormant, the "Track…"
menu item hidden. App Sandbox ON. This branch is the eventual replacement for `main`.

## Build / test / run

Always build into a **`.noindex`** derived-data path (Spotlight ignores `*.noindex`;
it is gitignored) to avoid duplicate `Keymory.app` entries in Spotlight/Finder.

```sh
# Build (Release)
xcodebuild -project Keymory.xcodeproj -scheme Keymory -configuration Release \
  -derivedDataPath build.noindex build

# Unit tests — the app target signs with the real Team ID while test bundles sign
# ad-hoc, and dlopen rejects the mix ("different Team IDs"). Override to ad-hoc for
# the whole test run:
xcodebuild -project Keymory.xcodeproj -scheme Keymory -configuration Debug \
  -derivedDataPath build.noindex test -only-testing:KeymoryTests \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual

# Install / run a dev build. NOT /Applications: that copy is the App Store install
# (root-owned, has _MASReceipt) — leave it alone. Run a dev build straight from
# build.noindex:
/usr/bin/open build.noindex/Build/Products/Release/Keymory.app
```

- **Never** build into the default DerivedData or an in-project `build/` — both are
  Spotlight-indexed and create duplicate app entries. Use `build.noindex`.
- Shell gotchas (zsh): `open` is aliased to `xdg-open` (missing) — use **`/usr/bin/open`**.
  Unquoted `for f in $VAR` does **not** word-split in zsh — use `while IFS= read -r f`.
- App is menu-bar-only (`LSUIElement`), `activationPolicy == .accessory`; it does **not**
  appear in Force Quit — that is expected.
- Verify a real change end-to-end by driving apps: `osascript -e 'tell application "X"
  to activate'` + set/read the input source, then check restore (Finder ↔ Calculator).

## Key build settings

Version, signing team, and the sandbox flag are extracted into **`Config/App.xcconfig`**
(wired via the app target's `baseConfigurationReference`) so `project.pbxproj` stays
identical across branches and a version bump no longer edits the shared project file:
`CURRENT_PROJECT_VERSION`, `MARKETING_VERSION`, `DEVELOPMENT_TEAM`, `ENABLE_APP_SANDBOX`
(YES here; the personal build overrides to NO). Still in `project.pbxproj` (app target
Debug+Release): `INFOPLIST_KEY_LSUIElement = YES`,
`INFOPLIST_KEY_CFBundleDisplayName = Keymory`,
`INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`,
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, `GENERATE_INFOPLIST_FILE = YES`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `ENABLE_HARDENED_RUNTIME = YES`,
`PRODUCT_NAME = Keymory` (test targets' `TEST_HOST` reference `Keymory.app`). Unit tests
use the ad-hoc CLI override above rather than a per-target `DEVELOPMENT_TEAM`, so the
test-target configs stay identical across branches.

## Critical technical facts (verified empirically)

- **App Sandbox is ON and everything works under it**: `TISSelectInputSource`,
  `NSWorkspace` activation notifications, `SMAppService`, `UserDefaults`, and the
  distributed notification `com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged`
  (via `DistributedNotificationCenter`) are all delivered under sandbox. No polling and no
  Darwin notify center needed. (An earlier belief that sandbox blocks
  `TISSelectInputSource` or the notification was WRONG.)
- **Sandboxed prefs live in the container**, not `~/Library/Preferences`:
  `~/Library/Containers/toxic0der.Keymory/Data/Library/Preferences/toxic0der.Keymory.plist`.
- **Do NOT verify a UserDefaults write or notification delivery by reading the plist file
  directly** — `cfprefsd` caches it and the on-disk file can be stale (this produced a
  false "notification blocked" result). Use a file append from the handler, or the live UI.
- **A TIS read inside the `TISNotifySelectedKeyboardInputSourceChanged` handler can still
  return the PREVIOUS source** — the process-local value settles asynchronously (reliably
  only after a keystroke or window switch; kawa PR #21, macism's 150 ms wait). This is why
  the menu-bar label uses a re-check cascade and `handleSourceChange` uses the `recordTask`
  settle delay; never read TIS synchronously off that notification.
- **Detection is a per-branch seam because sandbox blocks the Accessibility API on other
  apps entirely** — no grant changes that; `AXIsProcessTrusted()` stays false in-sandbox
  (Apple DTS forum threads 749494, 805556, 810677). The AX-based proactive detector
  therefore belongs on the non-sandboxed personal branch. MAS window managers that look
  like counterexamples (Magnet, BetterSnapTool) are pre-2012 grandfathered non-sandboxed
  apps. Likewise `CGWindowListCopyWindowInfo` is useless here on macOS 26: without Screen
  Recording it returns only the caller's own windows (verified on 26.5.2). Window-presence
  heuristics are dead; do not revisit. The sandbox-legal detection mechanism is the
  listen-only annotated-session `CGEventTap` under Input Monitoring — see the
  `popup-window-tracking` branch.
- Image tooling (CoreGraphics): in a `CGBitmapContext` here, **memory row 0 = top**
  (`memory_row == top-based y`) — do not flip when reading raw pixels. Drawing ops
  (`ctx.draw`/`ctx.fill`) still use the bottom-left coordinate system.
- No network, no cryptography, no third-party dependencies.

## Conventions

- **Git (from the `git-flow` skill):** never `git commit`/`git push` (or merge/rebase/
  force-push/open a PR) without the user's **explicit per-request** permission — staging
  and read-only git are fine. **Never add a `Co-Authored-By` trailer.**
- Gitignored: `build/`, `build.noindex/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`.
- Documentation and code comments are **English only**.

## Distribution assets

- App icon (K + memory-loop mark) generated natively via CoreGraphics; iconset in
  `Keymory/Assets.xcassets/AppIcon.appiconset/`.
- Marketing SVGs in `docs/` (hero, menu, how-it-works, flags). App Store screenshots
  (2560×1600) in `docs/appstore/` — 3 SVG posters + 3 real-UI captures.
- Privacy policy: `PRIVACY.md` → `https://github.com/mekh/keymory/blob/main/PRIVACY.md`
  (no data collected).

## Out of scope / known limitations (see README)

- **CJKV** (Chinese/Japanese/Korean/Vietnamese IMEs) — not the focus; the verify/retry
  loop in `restore()` is where it would be added.
- Electron/terminal/Java apps that cache the input source per TSM document may ignore an
  otherwise-successful system switch.
- Non-activating panels (Spotlight/Raycast, iTerm hotkey window, …) fire no
  `didActivate`, so on this branch a layout change made there is attributed to the
  previously frontmost app (self-corrects on next use). The optional
  **"Track Pop-up Windows"** mode on the `popup-window-tracking` branch covers them via a
  detector; the `personal` branch will switch proactively via the AX detector.
