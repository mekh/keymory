# Privacy Policy

**Effective date:** July 18, 2026

Keymory is designed to respect your privacy completely.

## Summary

**Keymory does not collect, store, transmit, or share any personal data.** Everything the app does happens entirely on your Mac.

## What Keymory stores

Keymory remembers which keyboard input source (language/layout) you use in each application, so it can restore it automatically. This information is:

- stored **only on your Mac**, in the app's local preferences (its sandbox container);
- never transmitted anywhere, and never shared with the developer or any third party.

The stored data is limited to application bundle identifiers (e.g. `com.apple.finder`) paired with keyboard input source identifiers. It contains no personal information, no keystrokes, and no document contents.

## What Keymory does NOT do

- **No network connections.** Keymory never connects to the internet.
- **No analytics or tracking.** There is no telemetry, no usage tracking, and no advertising.
- **No account.** Keymory requires no sign-in and no personal information.
- **No third-party services or SDKs.**

## Permissions

Keymory runs inside the macOS App Sandbox and does not request Accessibility or any other sensitive permissions to provide its core functionality.

### Optional: Input Monitoring (for "Track Pop-up Windows")

The optional **Track Pop-up Windows** feature (off by default) follows keyboard focus into non-activating panels such as iTerm2's hotkey window, Spotlight, and Raycast. macOS exposes this information only through an input event tap, which requires the **Input Monitoring** permission.

When — and only when — this option is enabled, Keymory installs a **listen-only** event tap and reads exactly one field of each keyboard/click event: the identifier of the process the event is delivered to. This is used solely to decide which application's input language to restore.

- Keymory **never reads key codes or characters** — it cannot see what you type, only which app you are typing into.
- Nothing from the event stream is stored or transmitted; the target app identifier is compared in memory and discarded.
- Turning the option off (or quitting Keymory) removes the event tap entirely.
- The implementation is open source and auditable: [`Keymory/EventTapClient.swift`](https://github.com/mekh/keymory/blob/main/Keymory/EventTapClient.swift).

## Children

Keymory does not collect any data from anyone, including children.

## Changes to this policy

If this policy changes, the updated version will be published at this same URL with a new effective date.

## Contact

Questions about privacy? Open an issue at <https://github.com/mekh/keymory/issues>.
