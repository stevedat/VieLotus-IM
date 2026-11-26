import XCTest
@testable import VieLotusCore

final class UILanguagePreferenceTests: XCTestCase {
    func testFromStoredNormalizesWhitespaceCaseAndUnknownValues() {
        XCTAssertEqual(UILanguagePreference.fromStored(nil), .auto)
        XCTAssertEqual(UILanguagePreference.fromStored(""), .auto)
        XCTAssertEqual(UILanguagePreference.fromStored("   "), .auto)
        XCTAssertEqual(UILanguagePreference.fromStored("AUTO"), .auto)
        XCTAssertEqual(UILanguagePreference.fromStored(" vi "), .vietnamese)
        XCTAssertEqual(UILanguagePreference.fromStored("VI"), .vietnamese)
        XCTAssertEqual(UILanguagePreference.fromStored("en"), .english)
        XCTAssertEqual(UILanguagePreference.fromStored(" EN "), .english)
        XCTAssertEqual(UILanguagePreference.fromStored("fr"), .auto)
        XCTAssertEqual(UILanguagePreference.fromStored("vi-VN"), .auto)
    }

    func testResolvedIsEnglishRespectsExplicitOverrides() {
        XCTAssertFalse(UILanguagePreference.vietnamese.resolvedIsEnglish(preferredLanguages: ["en-US"]))
        XCTAssertFalse(UILanguagePreference.vietnamese.resolvedIsEnglish(preferredLanguages: []))
        XCTAssertTrue(UILanguagePreference.english.resolvedIsEnglish(preferredLanguages: ["vi-VN"]))
        XCTAssertTrue(UILanguagePreference.english.resolvedIsEnglish(preferredLanguages: []))
    }

    func testResolvedIsEnglishAutoMatchesPrimaryLocaleSubtag() {
        XCTAssertFalse(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["vi-VN", "en-US"]))
        XCTAssertFalse(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["vi"]))
        XCTAssertFalse(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["vi_VN"]))
        XCTAssertFalse(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["VI-vn"]))

        XCTAssertTrue(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["en-US", "vi-VN"]))
        XCTAssertTrue(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["en-GB"]))
        XCTAssertTrue(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: ["ja-JP"]))
        XCTAssertTrue(UILanguagePreference.auto.resolvedIsEnglish(preferredLanguages: []))
    }

    func testShortBadges() {
        XCTAssertEqual(UILanguagePreference.auto.shortBadge, "Auto")
        XCTAssertEqual(UILanguagePreference.vietnamese.shortBadge, "VI")
        XCTAssertEqual(UILanguagePreference.english.shortBadge, "EN")
    }
}
