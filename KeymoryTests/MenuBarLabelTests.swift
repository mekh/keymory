//
//  MenuBarLabelTests.swift
//  KeymoryTests
//

import XCTest
@testable import Keymory

final class MenuBarLabelTests: XCTestCase {
    func testCodeStyleUppercasesLanguage() {
        XCTAssertEqual(MenuBarLabel.text(languageCode: "en", style: .code), "EN")
        XCTAssertEqual(MenuBarLabel.text(languageCode: "fr", style: .code), "FR")
        XCTAssertEqual(MenuBarLabel.text(languageCode: "he", style: .code), "HE")
    }

    func testCodeStyleAppliesUkraineOverride() {
        XCTAssertEqual(MenuBarLabel.text(languageCode: "uk", style: .code), "UA")
    }

    func testFlagStyleMapsLanguageToCountryFlag() {
        XCTAssertEqual(MenuBarLabel.text(languageCode: "en", style: .flag), "🇺🇸")
        XCTAssertEqual(MenuBarLabel.text(languageCode: "uk", style: .flag), "🇺🇦")
        XCTAssertEqual(MenuBarLabel.text(languageCode: "fr", style: .flag), "🇫🇷")
        XCTAssertEqual(MenuBarLabel.text(languageCode: "he", style: .flag), "🇮🇱")
    }

    func testLongLanguageTagIsTruncatedToTwoLetters() {
        XCTAssertEqual(MenuBarLabel.text(languageCode: "hi_Latn", style: .code), "HI")
    }

    func testNilOrEmptyLanguageReturnsNil() {
        XCTAssertNil(MenuBarLabel.text(languageCode: nil, style: .code))
        XCTAssertNil(MenuBarLabel.text(languageCode: "", style: .flag))
    }

    func testFlagReturnsCountryFlagForLanguage() {
        XCTAssertEqual(MenuBarLabel.flag(languageCode: "en"), "🇺🇸")
        XCTAssertEqual(MenuBarLabel.flag(languageCode: "uk"), "🇺🇦")
        XCTAssertEqual(MenuBarLabel.flag(languageCode: "he"), "🇮🇱")
        XCTAssertEqual(MenuBarLabel.flag(languageCode: "fr"), "🇫🇷")
    }

    func testFlagReturnsNilForMissingLanguage() {
        XCTAssertNil(MenuBarLabel.flag(languageCode: nil))
        XCTAssertNil(MenuBarLabel.flag(languageCode: ""))
    }
}
