//
//  MenuBarLabel.swift
//  Keymory
//

/// How the current input source is shown in the menu bar.
enum MenuBarStyle {
    case code
    case flag
}

/// Formats the menu bar label for the current input source. Pure (no platform
/// dependencies) so it can be unit-tested.
enum MenuBarLabel {
    /// Region code used to build the flag, for languages whose flag country
    /// differs from an uppercased language code (e.g. English → US, Ukrainian
    /// → UA). Languages not listed fall back to the uppercased language code,
    /// which is already correct for de, fr, ru, it, es, pl, …
    private static let flagRegionByLanguage: [String: String] = [
        "en": "US", "uk": "UA", "ja": "JP", "zh": "CN", "ko": "KR",
        "cs": "CZ", "da": "DK", "el": "GR", "he": "IL", "sv": "SE",
        "nb": "NO", "nn": "NO", "no": "NO", "be": "BY", "et": "EE",
        "sl": "SI", "ca": "ES", "gl": "ES", "eu": "ES",
    ]

    /// Displayed code where it should differ from the plain uppercased language
    /// code (Ukrainian "uk" → "UA" so it is not confused with the UK).
    private static let codeOverrides: [String: String] = [
        "uk": "UA",
    ]

    /// The country flag emoji for a language, e.g. "🇺🇸", "🇺🇦", used to prefix a
    /// layout name in the quick-switch list. `nil` when the language is missing
    /// or resolves to no flag, so the caller shows the name alone.
    static func flag(languageCode: String?) -> String? {
        guard let raw = languageCode?.lowercased(), !raw.isEmpty else { return nil }
        let lang = String(raw.prefix(2))
        let region = flagRegionByLanguage[lang] ?? lang.uppercased()
        return flagEmoji(region: region)
    }

    /// The text to place in the menu bar, or `nil` if `languageCode` is missing
    /// (the caller then falls back to a keyboard glyph).
    static func text(languageCode: String?, style: MenuBarStyle) -> String? {
        guard let raw = languageCode?.lowercased(), !raw.isEmpty else { return nil }
        let lang = String(raw.prefix(2))
        switch style {
        case .code:
            return codeOverrides[lang] ?? lang.uppercased()
        case .flag:
            let region = flagRegionByLanguage[lang] ?? lang.uppercased()
            return flagEmoji(region: region) ?? codeOverrides[lang] ?? lang.uppercased()
        }
    }

    /// Converts a two-letter region code into its flag emoji via Unicode
    /// regional indicator symbols (A = U+1F1E6).
    private static func flagEmoji(region: String) -> String? {
        let upper = region.uppercased()
        guard upper.count == 2, upper.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            return nil
        }
        var result = ""
        for scalar in upper.unicodeScalars {
            guard let indicator = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            result.unicodeScalars.append(indicator)
        }
        return result
    }
}
