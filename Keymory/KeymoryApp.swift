//
//  KeymoryApp.swift
//  Keymory
//

import AppKit
import ServiceManagement
import SwiftUI

@main
struct KeymoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app: no visible window. This Settings scene is never
        // opened; it only satisfies the App's required `some Scene`.
        Settings {
            EmptyView()
        }
    }
}

/// Owns the status-bar item and the controller. A classic AppKit `NSStatusItem`
/// is used instead of SwiftUI's `MenuBarExtra`: on this macOS the MenuBarExtra
/// item did not reliably appear for a menu-bar-only (LSUIElement) app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let inputSourceChangedNotification =
        Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")
    /// Menu bar label size relative to the default menu bar font. Bump to make
    /// the flag/code indicator larger.
    private static let labelScale: CGFloat = 1.30

    private var statusItem: NSStatusItem?
    private var sourceChangeObserver: NSObjectProtocol?
    private let controller = SwitchController(
        store: MappingStore(defaults: .standard),
        inputSources: SystemInputSourceClient()
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders with INFOPLIST_KEY_LSUIElement: never show a Dock
        // icon or an app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Persist the user's Cmd-drag position across launches. Without this a
        // crowded (notched) menu bar puts the item back behind the notch on
        // every relaunch.
        item.autosaveName = "KeymoryStatusItem"
        item.menu = makeMenu()
        statusItem = item

        controller.start()
        updateStatusAppearance()

        // Reflect the live input source in the menu bar. Both our own restores
        // and the user's manual switches post this notification.
        sourceChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.inputSourceChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusAppearance()
            }
        }
    }

    /// Shows the current input source in the menu bar — a flag (🇺🇸/🇺🇦/🇮🇱) when
    /// "Show Flag" is on, otherwise a language code (EN/UA/HE). Falls back to a
    /// keyboard glyph when the language can't be determined.
    private func updateStatusAppearance() {
        guard let button = statusItem?.button else { return }
        let scaledSize = NSFont.menuBarFont(ofSize: 0).pointSize * Self.labelScale
        let style: MenuBarStyle = controller.showFlag ? .flag : .code
        button.title = ""
        if let label = MenuBarLabel.text(languageCode: controller.currentSourceLanguageCode(),
                                         style: style) {
            // Render into a vertically centered image: setting it as the button
            // title aligns emoji on the text baseline (visibly off-center),
            // whereas NSStatusItem centers an image cleanly.
            button.image = renderLabelImage(label, pointSize: scaledSize)
        } else if let image = NSImage(systemSymbolName: "keyboard",
                                      accessibilityDescription: "Keymory") {
            let config = NSImage.SymbolConfiguration(pointSize: scaledSize, weight: .regular)
            let scaled = image.withSymbolConfiguration(config) ?? image
            scaled.isTemplate = true
            button.image = scaled
        } else {
            button.image = nil
            button.title = "⌨"
        }
    }

    /// Draws the label centered in an image the height of the menu bar. Text
    /// codes are templated (adapt to light/dark); flag emoji stay in color.
    private func renderLabelImage(_ text: String, pointSize: CGFloat) -> NSImage {
        let hasFlag = text.unicodeScalars.contains { (0x1F1E6...0x1F1FF).contains($0.value) }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: pointSize),
            .foregroundColor: NSColor.black,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let height = NSStatusBar.system.thickness
        let width = ceil(textSize.width) + 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        attributed.draw(in: NSRect(x: 0, y: (height - textSize.height) / 2,
                                   width: width, height: textSize.height))
        image.unlockFocus()
        // Non-flag text tints with the menu bar color; emoji must keep color.
        image.isTemplate = !hasFlag
        return image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
    }

    @objc private func openKeyboardSettings() {
        // Same destination as the system input menu's "Open Keyboard Settings…"
        // — the Keyboard pane, whose Input Sources section holds the Edit sheet.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleShowFlag() {
        controller.showFlag.toggle()
        updateStatusAppearance()
    }

    @objc private func setDefaultToCurrent() {
        controller.defaultSourceID = nil
    }

    @objc private func selectDefaultLanguage(_ sender: NSMenuItem) {
        controller.defaultSourceID = sender.representedObject as? String
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Keymory: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func forgetAll() {
        controller.forgetAll()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    // Rebuild before each open so the toggle states and the count are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Enabled",
                                 action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = controller.isEnabled ? .on : .off
        menu.addItem(enabled)

        let showFlag = NSMenuItem(title: "Show Flag",
                                  action: #selector(toggleShowFlag), keyEquivalent: "")
        showFlag.target = self
        showFlag.state = controller.showFlag ? .on : .off
        menu.addItem(showFlag)

        let launch = NSMenuItem(title: "Launch at Login",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)

        let defaultLanguage = NSMenuItem(title: "Default Language",
                                         action: nil, keyEquivalent: "")
        defaultLanguage.submenu = makeDefaultLanguageSubmenu()
        menu.addItem(defaultLanguage)

        let keyboardSettings = NSMenuItem(title: "Open Keyboard Settings…",
                                          action: #selector(openKeyboardSettings), keyEquivalent: "")
        keyboardSettings.target = self
        menu.addItem(keyboardSettings)

        menu.addItem(.separator())

        let count = NSMenuItem(title: "Remembering \(controller.mappingCount) apps",
                               action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)

        let forget = NSMenuItem(title: "Forget All",
                                action: #selector(forgetAll), keyEquivalent: "")
        forget.target = self
        // Destructive action: tint it red (systemRed adapts to light/dark).
        // attributedTitle is required — NSMenuItem.title has no per-item color.
        forget.attributedTitle = NSAttributedString(
            string: "Forget All",
            attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: 0),
            ])
        menu.addItem(forget)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Keymory",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // The submenu of available input sources. The active default is checkmarked;
    // "Use current input source" is checkmarked when no default is set. macOS
    // opens the submenu on whichever side has room, so a menu bar item near the
    // notch expands to the left automatically.
    private func makeDefaultLanguageSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let currentDefault = controller.defaultSourceID

        let useCurrent = NSMenuItem(title: "Use current input source",
                                    action: #selector(setDefaultToCurrent), keyEquivalent: "")
        useCurrent.target = self
        useCurrent.state = currentDefault == nil ? .on : .off
        submenu.addItem(useCurrent)

        submenu.addItem(.separator())

        for source in controller.availableInputSources() {
            let item = NSMenuItem(title: source.name,
                                  action: #selector(selectDefaultLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = source.id == currentDefault ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }
}
