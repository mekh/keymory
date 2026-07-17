//
//  InputSourceClient.swift
//  Keymory
//

import Carbon

/// An input source that can be picked as the default language.
struct InputSourceInfo: Equatable {
    let id: String
    let name: String
}

/// Abstraction over the Text Input Source Services (TIS) API so the state
/// machine can be unit-tested with a mock.
protocol InputSourceClient {
    /// Input source ID of the currently selected keyboard input source,
    /// e.g. "com.apple.keylayout.Ukrainian". Mode-level for IMEs.
    func currentSourceID() -> String?

    /// Selects the enabled, select-capable keyboard input source with the
    /// given ID. Returns false when no such source exists (e.g. the layout
    /// was removed in System Settings) or the selection call fails.
    func selectSource(id: String) -> Bool

    /// All enabled, select-capable keyboard input sources (what appears in the
    /// system input menu), sorted by localized name — for the default-language
    /// picker.
    func availableSources() -> [InputSourceInfo]

    /// Primary language code of the current source, e.g. "en", "uk", "he".
    /// `nil` if the source declares no language. Used to build the menu bar
    /// label (code or flag).
    func currentSourceLanguageCode() -> String?
}

struct SystemInputSourceClient: InputSourceClient {
    func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return stringProperty(kTISPropertyInputSourceID, of: source)
    }

    func selectSource(id: String) -> Bool {
        // The list is queried fresh on every call so layouts added or removed
        // in System Settings at runtime are always respected.
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else {
            return false
        }
        let target = list.first { source in
            stringProperty(kTISPropertyInputSourceID, of: source) == id
                && stringProperty(kTISPropertyInputSourceCategory, of: source)
                    == (kTISCategoryKeyboardInputSource as String)
                && boolProperty(kTISPropertyInputSourceIsSelectCapable, of: source)
                && boolProperty(kTISPropertyInputSourceIsEnabled, of: source)
        }
        guard let target else { return false }
        return TISSelectInputSource(target) == noErr
    }

    func availableSources() -> [InputSourceInfo] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else {
            return []
        }
        let sources = list.compactMap { source -> InputSourceInfo? in
            guard stringProperty(kTISPropertyInputSourceCategory, of: source)
                    == (kTISCategoryKeyboardInputSource as String),
                  boolProperty(kTISPropertyInputSourceIsSelectCapable, of: source),
                  boolProperty(kTISPropertyInputSourceIsEnabled, of: source),
                  let id = stringProperty(kTISPropertyInputSourceID, of: source) else {
                return nil
            }
            let name = stringProperty(kTISPropertyLocalizedName, of: source) ?? id
            return InputSourceInfo(id: id, name: name)
        }
        var seen = Set<String>()
        return sources
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func currentSourceLanguageCode() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return languagesProperty(of: source).first
    }

    private func stringProperty(_ key: CFString, of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private func languagesProperty(of source: TISInputSource) -> [String] {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        return Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
    }

    private func boolProperty(_ key: CFString, of source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
