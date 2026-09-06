import XCTest

@testable import Talkable

final class TalkableTests: XCTestCase {
    // MARK: TextProcessor

    func testPolishCapitalizesAndAddsPeriod() {
        XCTAssertEqual(TextProcessor.polish("hello world", enabled: true), "Hello world.")
    }

    func testPolishKeepsExistingFinalPunctuation() {
        XCTAssertEqual(TextProcessor.polish("hello world!", enabled: true), "Hello world!")
        XCTAssertEqual(TextProcessor.polish("hello world?", enabled: true), "Hello world?")
        XCTAssertEqual(TextProcessor.polish("hello world…", enabled: true), "Hello world…")
    }

    func testPolishDisabledOnlyTrims() {
        XCTAssertEqual(TextProcessor.polish("  hello world ", enabled: false), "hello world")
    }

    func testPolishEmptyStringStaysEmpty() {
        XCTAssertEqual(TextProcessor.polish("   ", enabled: true), "")
    }

    func testPolishCapitalizesAccentedCharacters() {
        XCTAssertEqual(TextProcessor.polish("árbol verde", enabled: true), "Árbol verde.")
    }

    // MARK: SettingsStore.fallbackLocaleID

    func testFallbackLocaleSupportedLanguages() {
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "en_US"), "en_US")
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "es_ES"), "es_ES")
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "fr_FR"), "fr_FR")
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "pt_BR"), "pt_BR")
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "it_IT"), "it_IT")
    }

    func testFallbackLocaleUnsupportedLanguageFallsBackToEnglish() {
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "de_DE"), "en_US")
        XCTAssertEqual(SettingsStore.fallbackLocaleID(forSystem: "ja_JP"), "en_US")
    }
}
