# Keymory — project guide

macOS menu-bar utility that remembers the keyboard input source (language/layout)
**per application** and restores it automatically when you switch apps.

**The one rule:** on app activation, set the input source last used in that app.
First-seen app → adopt the current source (or the configured *Default Language*).
A remembered source that is no longer installed/enabled → keep the current source
silently. Memory persists indefinitely (no eviction). Every app is auto-remembered.

- Repo: `github.com/mekh/keymory` · Bundle ID: `toxic0der.Keymory`
- Distribution: free, non-tracking, App Store (Utilities). Also runnable via direct build.

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
  add sources.

## Architecture (4 app files + 1 formatter, all MainActor)

- `Keymory/KeymoryApp.swift` — `@main` App with `NSApplicationDelegateAdaptor`. The
  `AppDelegate` owns an AppKit **`NSStatusItem`** (menu bar) and the `SwitchController`.
  Uses `NSStatusItem` **not** SwiftUI `MenuBarExtra` (MenuBarExtra did not reliably
  appear for a menu-bar-only app on this macOS). Menu is an `NSMenu` rebuilt in
  `menuNeedsUpdate`. `updateStatusAppearance()` renders the current-language indicator
  (flag or code) into a vertically-centred image; it is refreshed on the distributed TIS
  notification. `item.autosaveName = "KeymoryStatusItem"` persists the icon position.
  "Forget All" is tinted red via `attributedTitle` (NSColor.systemRed).
- `Keymory/SwitchController.swift` — `@Observable @MainActor` state machine.
  `handleActivation` order: guard enabled/lock → ignore own bundle id → cancel
  `restoreTask` → **switch-away snapshot** (record outgoing app's current source, guarded
  by `lastRestore.verified`) → set frontmost → first-seen (adopt Default Language or
  current) / known (restore if differs). `handleSourceChange` records the user's manual
  switches, skipped when inside the **suppression window** (value + monotonic
  `ContinuousClock` deadline — not a boolean; the distributed notification arrives
  asynchronously). `restore()` = cancellable verify/retry loop (select → sleep 50ms →
  confirm, ×3) — this loop is the seam where CJKV handling would plug in. `start()` is
  idempotent (`started` guard), seeds the frontmost app at launch **without** restoring
  or recording, and handles screen lock/unlock.
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
  (with `MockInputSourceClient`), `MenuBarLabelTests`.

## Build / test / run

Always build into a **`.noindex`** derived-data path (Spotlight ignores `*.noindex`;
it is gitignored) to avoid duplicate `Keymory.app` entries in Spotlight/Finder.

```sh
# Build (Release)
xcodebuild -project Keymory.xcodeproj -scheme Keymory -configuration Release \
  -derivedDataPath build.noindex build

# Unit tests
xcodebuild -project Keymory.xcodeproj -scheme Keymory -configuration Debug \
  -derivedDataPath build.noindex test -only-testing:KeymoryTests

# Install / run
cp -R build.noindex/Build/Products/Release/Keymory.app /Applications/
/usr/bin/open /Applications/Keymory.app
```

- **Never** build into the default DerivedData or an in-project `build/` — both are
  Spotlight-indexed and create duplicate app entries. Use `build.noindex`.
- Shell gotchas (zsh): `open` is aliased to `xdg-open` (missing) — use **`/usr/bin/open`**.
  Unquoted `for f in $VAR` does **not** word-split in zsh — use `while IFS= read -r f`.
- App is menu-bar-only (`LSUIElement`), `activationPolicy == .accessory`; it does **not**
  appear in Force Quit — that is expected.
- Verify a real change end-to-end by driving apps: `osascript -e 'tell application "X"
  to activate'` + set/read the input source, then check restore (Finder ↔ Calculator).

## Key build settings (`project.pbxproj`, app target Debug+Release)

`ENABLE_APP_SANDBOX = YES`, `INFOPLIST_KEY_LSUIElement = YES`,
`INFOPLIST_KEY_CFBundleDisplayName = Keymory`,
`INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`,
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`,
`GENERATE_INFOPLIST_FILE = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
`PRODUCT_NAME = Keymory` (test targets' `TEST_HOST` reference `Keymory.app`).

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
- Image tooling (CoreGraphics): in a `CGBitmapContext` here, **memory row 0 = top**
  (`memory_row == top-based y`) — do not flip when reading raw pixels. Drawing ops
  (`ctx.draw`/`ctx.fill`) still use the bottom-left coordinate system.
- No network, no cryptography, no third-party dependencies.

## Conventions

- **Git (from the `git-flow` skill):** never `git commit`/`git push` (or merge/rebase/
  force-push/open a PR) without the user's **explicit per-request** permission — staging
  and read-only git are fine. **Never add a `Co-Authored-By` trailer.** History was
  squashed to a single "Initial commit"; new work goes on top.
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
- Non-activating panels (Spotlight/Raycast) fire no `didActivate`, so a layout change made
  there is attributed to the previously frontmost app (self-corrects on next use).
