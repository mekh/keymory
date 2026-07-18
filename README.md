<p align="center">
  <img src="docs/hero.svg" alt="Keymory — your keyboard remembers every app" width="100%">
</p>

<h1 align="center">Keymory</h1>

<p align="center">
  <b>The macOS menu-bar app that gives every application its own perfect keyboard language — automatically.</b>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-000000?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white">
  <img alt="UI" src="https://img.shields.io/badge/UI-AppKit%20menu%20bar-5b8cff">
  <img alt="Privacy" src="https://img.shields.io/badge/data-100%25%20on%20device-2ea043">
  <img alt="Permissions" src="https://img.shields.io/badge/Accessibility-not%20required-2ea043">
  <img alt="Sandbox" src="https://img.shields.io/badge/App%20Sandbox-enabled-2ea043">
</p>

---

## 😩 The problem you've stopped noticing

You live in more than one language. Your browser is English. Your code editor is your mother tongue. Your terminal is English, your messenger is not. And macOS? macOS keeps **one** global input language and expects *you* to babysit it.

So you do the little dance a hundred times a day:

- Cmd-Tab to your editor → start typing → **wrong language** → delete → `⌃Space` → retype.
- Jump to the browser → search bar → **wrong language again** → delete → switch → retype.
- Multiply by every app switch, every day, forever. 🫠

It's death by a thousand keystrokes. macOS's built-in "switch per document" is unreliable and half-hidden, and every manual switch is a tiny tax on your focus.

## ✨ The fix: Keymory

**Keymory remembers the keyboard input language for every single app — and restores it the instant that app comes to the front.**

Set it once by just *using* your Mac the way you already do. From then on, the right language is simply *there*. No shortcuts to press. No thinking. No dance.

<p align="center">
  <img src="docs/how-it-works.svg" alt="Every app keeps the language you last used in it" width="100%">
</p>

> One rule, zero configuration: **when you activate an app, Keymory sets the language you last used in it.** First time it sees an app, it keeps whatever you're using and starts remembering from there. That's the whole mental model.

## 🚀 Why you'll love it

- 🧠 **Per-app memory that actually sticks.** English in Chrome, Ukrainian in your editor, whatever-you-want everywhere else. Keymory keeps them straight so you never fix a mis-typed first word again.
- ⏳ **Remembers forever.** Didn't open an app for a year? Keymory still nails its language the second you reopen it. Memory survives quits, reboots, and time.
- 🪄 **Zero setup.** No rules to define, no per-app lists to maintain. It learns silently as you work. Every app is remembered automatically.
- 🏳️ **A gorgeous live indicator.** See your current language right in the menu bar — as a **flag** (🇺🇸 🇺🇦 🇮🇱) or a crisp **code** (EN / UA / HE). One click to switch styles.
- 🌍 **Set a default language for new apps.** Want every brand-new app to start in English? Pick a default. Prefer it to adopt whatever's active? That's the default default.
- ⚡ **Invisible & featherweight.** A tiny menu-bar agent. No Dock icon, no window, no clutter, no lag.
- 🔒 **Private & contained.** Everything stays on your Mac — no network, no analytics, no account, and **no Accessibility permission required.** Runs inside the **macOS App Sandbox**, so it's locked down to only what it needs.
- 🔁 **Launch at login.** Turn it on once and forget Keymory exists — which is exactly the point.
- 🛟 **Bulletproof.** Verifies each switch and retries if the system stalls. Remembered a layout you later removed? Keymory quietly leaves your current one alone instead of breaking.

<p align="center">
  <img src="docs/flags.svg" alt="Keymory shows a flag or a language code" width="100%">
</p>

## 🖱️ Everything, one click away

<p align="center">
  <img src="docs/menu.svg" alt="Keymory menu" width="480">
</p>

| Menu item | What it does |
| --- | --- |
| **Enabled** | Master switch for automatic switching. |
| **Show Flag** | Toggle the menu-bar indicator between a flag and a language code. |
| **Launch at Login** | Start Keymory automatically when you log in. |
| **Default Language ▸** | Language for apps Keymory hasn't seen yet (or "Use current input source"). |
| **Open Keyboard Settings…** | Jump straight to macOS Keyboard ▸ Input Sources. |
| **Remembering N apps** | How many apps Keymory currently knows. |
| **Forget All** | Wipe the memory and start fresh. |
| **Quit Keymory** | Quit the app. |

## 📦 Install

Keymory is currently built from source (a signed release is on the roadmap).

```bash
git clone git@github.com:mekh/keymory.git
cd keymory

# Build a Release app
xcodebuild -project Keymory.xcodeproj -scheme Keymory \
  -configuration Release -derivedDataPath build.noindex build

# Install it
cp -R build.noindex/Build/Products/Release/Keymory.app /Applications/
open /Applications/Keymory.app
```

Or just open `Keymory.xcodeproj` in Xcode and press **Run**.

On first launch, look for the language indicator in your menu bar and enable **Launch at Login**. That's it — go back to work and let Keymory disappear into the background.

> **A note on menu bars with a notch:** if your menu bar is crowded, macOS may tuck new items behind the camera notch. Hold **⌘** and drag Keymory's indicator to a spot you can see — it'll stay put.

## 🧠 Why "Keymory"?

**Key** + **memory.** A keyboard with a memory for every app. It also happens to remember so you don't have to.

## 🔍 How it works (for the curious)

Keymory listens for app-activation events and, when you switch apps, restores that app's remembered input source via Apple's Text Input Source (TIS) API. While an app is frontmost, it quietly notes any language change you make and files it under that app. Everything is a tiny `bundle id → input source` map persisted locally — a few bytes per app, kept forever.

- Reads/writes input sources with `TISCopyCurrentKeyboardInputSource` / `TISSelectInputSource`.
- Tracks the frontmost app via `NSWorkspace` activation notifications.
- Persists to `UserDefaults`; no files, no database, no cloud.
- No Accessibility permission needed for the core experience.
- Runs under the **App Sandbox** — TIS switching, `NSWorkspace` activation and the input-source-change notification all work sandboxed, so Keymory stays contained by macOS.

## 🤏 Good to know

Keymory is honest about the edges:

- A few apps that manage their own text input (some Electron/terminal/Java apps) may occasionally ignore a system-level switch. Rare, and on the roadmap.
- Non-activating overlays like Spotlight/Raycast don't report focus changes, so a language change made there is attributed to the previous app. It self-corrects the next time you actually type.
- Complex IME languages (Chinese/Japanese/Korean) are not the focus of this version — Latin/Cyrillic layouts are first-class today.

## 🤝 Contributing

Keymory focuses on Latin and Cyrillic layouts today. **If your language or input method isn't supported well — CJK/IME (Chinese, Japanese, Korean), or anything else — your PR is highly welcome!** The switch logic has a verify/retry seam in `SwitchController.restore(...)` that's the natural place to plug in IME-specific handling.

## 🗺️ Roadmap

- Signed & notarized release + Homebrew cask

## 📄 License

Released under the [MIT License](LICENSE). © 2026 Oleksandr Miekh.

---

<p align="center"><b>Stop babysitting your keyboard. Let Keymory remember.</b></p>
