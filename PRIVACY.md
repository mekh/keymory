# Privacy Policy

**Effective date:** July 19, 2026

Keymory is designed to respect your privacy completely.

## Summary

**Keymory does not collect, store, transmit, or share any personal data.** Everything the app does happens entirely on your Mac.

## What Keymory stores

Keymory remembers which keyboard input source (language/layout) you use in each application, so it can restore it automatically. This information is:

- stored **only on your Mac**, in the app's local preferences;
- never transmitted anywhere, and never shared with the developer or any third party.

The stored data is limited to application bundle identifiers (e.g. `com.apple.finder`) paired with keyboard input source identifiers. It contains no personal information, no keystrokes, and no document contents.

## What Keymory does NOT do

- **No network connections.** Keymory never connects to the internet.
- **No analytics or tracking.** There is no telemetry, no usage tracking, and no advertising.
- **No account.** Keymory requires no sign-in and no personal information.
- **No third-party services or SDKs.**

## Permissions

Keymory's core functionality requires no permissions.

This build offers an optional feature — **Track All Windows** — that switches the input language for pop-up windows which never activate their app (for example a hotkey terminal, Spotlight, or Raycast) before you type. Because that requires observing keyboard focus across applications, this build:

- runs **outside** the macOS App Sandbox (the sandbox forbids this API), and
- asks for the **Accessibility** permission — only when you turn Track All Windows on.

When enabled, Keymory uses Accessibility to read **only which application currently has keyboard focus**. It never reads your keystrokes, never reads window or document contents, and stores nothing beyond the same `bundle id → input source` mapping described above. Turn the feature off and Keymory stops using Accessibility entirely.

The separate Mac App Store build of Keymory is fully sandboxed and does not include this feature.

## Children

Keymory does not collect any data from anyone, including children.

## Changes to this policy

If this policy changes, the updated version will be published at this same URL with a new effective date.

## Contact

Questions about privacy? Open an issue at <https://github.com/mekh/keymory/issues>.
