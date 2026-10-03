import XCTest
@testable import VieLotusCore

final class WordSuggestionEngineTests: XCTestCase {
    func testBundleLoadsSuccessfully() {
        let engine = WordSuggestionEngine.shared
        XCTAssertFalse(engine.isEmpty, "Engine should load entries from bundled dictionary")
        XCTAssertGreaterThan(engine.count, 4000, "Dictionary should have over 4000 headwords (expected ~4648)")
    }

    func testSuggestionsForCommonWords() {
        let engine = WordSuggestionEngine.shared

        // Test "cộng"
        let congSuggestions = engine.suggestions(for: "cộng")
        XCTAssertFalse(congSuggestions.isEmpty, "Should have suggestions for 'cộng'")
        XCTAssertTrue(congSuggestions.contains("đồng"), "Should contain 'đồng' for 'cộng'")

        // Test "chúc"
        let chucSuggestions = engine.suggestions(for: "chúc")
        XCTAssertFalse(chucSuggestions.isEmpty, "Should have suggestions for 'chúc'")
        XCTAssertTrue(chucSuggestions.contains("mừng"), "Should contain 'mừng' for 'chúc'")

        // Test "quốc"
        let quocSuggestions = engine.suggestions(for: "quốc")
        XCTAssertFalse(quocSuggestions.isEmpty, "Should have suggestions for 'quốc'")
        XCTAssertTrue(quocSuggestions.contains("gia"), "Should contain 'gia' for 'quốc'")
    }

    func testCaseInsensitivityAndTrimming() {
        let engine = WordSuggestionEngine.shared
        let lower = engine.suggestions(for: "cộng")
        let upper = engine.suggestions(for: "CỘNG")
        let mixed = engine.suggestions(for: "  Cộng  \n")

        XCTAssertEqual(lower, upper)
        XCTAssertEqual(lower, mixed)
    }

    func testLimitParameter() {
        let engine = WordSuggestionEngine.shared
        let all = engine.suggestions(for: "cộng")
        XCTAssertGreaterThan(all.count, 3)

        let limited = engine.suggestions(for: "cộng", limit: 3)
        XCTAssertEqual(limited.count, 3)
        XCTAssertEqual(limited, Array(all.prefix(3)))
    }

    func testEmptyAndUnknownWords() {
        let engine = WordSuggestionEngine.shared
        XCTAssertEqual(engine.suggestions(for: ""), [])
        XCTAssertEqual(engine.suggestions(for: "   "), [])
        XCTAssertEqual(engine.suggestions(for: "nonexistentwordxyz123"), [])
        XCTAssertFalse(engine.hasSuggestions(for: "nonexistentwordxyz123"))
    }

    func testSubscriptAndAliases() {
        let engine = WordSuggestionEngine.shared
        let standard = engine.suggestions(for: "chúc")
        let alias = engine.nextWordSuggestions(for: "chúc")
        let subscriptResult = engine["chúc"]

        XCTAssertEqual(standard, alias)
        XCTAssertEqual(standard, subscriptResult)
        XCTAssertTrue(engine.hasSuggestions(for: "chúc"))
    }

    func testParseCustomTextWithHeader() {
        let sample = """
        3
        xin chào
        xin lỗi
        hẹn gặp lại
        """
        let parsed = WordSuggestionEngine.parse(text: sample)
        XCTAssertEqual(parsed["xin"], ["chào", "lỗi"])
        XCTAssertEqual(parsed["hẹn"], ["gặp lại"])
    }

    func testParseCustomTextWithoutHeader() {
        let sample = """
        việt nam
        việt nam anh hùng
        bác hồ
        """
        let parsed = WordSuggestionEngine.parse(text: sample)
        XCTAssertEqual(parsed["việt"], ["nam", "nam anh hùng"])
        XCTAssertEqual(parsed["bác"], ["hồ"])
    }

    func testDirectTxtFileParsing() {
        guard let txtURL = Bundle.module.url(forResource: "TuDienTuGhep", withExtension: "txt") else {
            XCTFail("TuDienTuGhep.txt should exist in module bundle")
            return
        }
        let customEngine = WordSuggestionEngine(fileURL: txtURL)
        XCTAssertGreaterThan(customEngine.count, 4000)
        XCTAssertTrue(customEngine.suggestions(for: "cộng").contains("đồng"))
    }

    func testZeroAndNegativeLimitReturnsEmpty() {
        let engine = WordSuggestionEngine.shared
        XCTAssertEqual(engine.suggestions(for: "cộng", limit: 0), [])
        XCTAssertEqual(engine.suggestions(for: "cộng", limit: -1), [])
    }

    func testPunctuationHandling() {
        let engine = WordSuggestionEngine.shared
        let base = engine.suggestions(for: "cộng")
        let comma = engine.suggestions(for: "cộng,")
        let dot = engine.suggestions(for: "cộng.")

        XCTAssertEqual(base, comma)
        XCTAssertEqual(base, dot)
        XCTAssertTrue(engine.hasSuggestions(for: "cộng,"))
    }

    func testParseCustomTextWithCRLFAndExtraWhitespace() {
        let sample = "4\r\n  xin   chào  \r\n\r\n  xin   lỗi  \r\n  hẹn   gặp lại  \r\n"
        let parsed = WordSuggestionEngine.parse(text: sample)
        XCTAssertEqual(parsed["xin"], ["chào", "lỗi"])
        XCTAssertEqual(parsed["hẹn"], ["gặp lại"])
    }

    func testThreadSafetyConcurrentLookups() {
        let engine = WordSuggestionEngine.shared
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            let word = i % 2 == 0 ? "cộng" : "chúc"
            let results = engine.suggestions(for: word, limit: 5)
            XCTAssertFalse(results.isEmpty)
        }
    }

    func testMultiWordPhraseFallbackToLastWord() {
        let engine = WordSuggestionEngine.shared
        let suggestions = engine.suggestions(for: "việt nam")
        XCTAssertFalse(suggestions.isEmpty, "Should fallback to last word 'nam' when multi-word phrase is passed")
        XCTAssertTrue(suggestions.contains("bộ") || suggestions.contains("bình") || suggestions.contains("bán cầu"))
        XCTAssertTrue(engine.hasSuggestions(for: "việt nam"))
    }

    func testTabSeparatedParsing() {
        let sample = "xin\tchào\nxin\tlỗi\n"
        let parsed = WordSuggestionEngine.parse(text: sample)
        XCTAssertEqual(parsed["xin"], ["chào", "lỗi"])
    }

    func testMultipleWhitespaceBetweenWords() {
        let sample = "việt    nam\r\nviệt\t\tquốc"
        let parsed = WordSuggestionEngine.parse(text: sample)
        XCTAssertEqual(parsed["việt"], ["nam", "quốc"])
    }

    func testMalformedJSONFileURLReturnsEmpty() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("malformed_test_\(UUID().uuidString).json")
        try? "{\"not_valid_json: 123".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let engine = WordSuggestionEngine(fileURL: tempURL)
        XCTAssertTrue(engine.isEmpty, "Malformed JSON file should yield empty dictionary rather than parsing invalid text")
    }

    func testExplicitBundleModuleUsage() {
        let engine = WordSuggestionEngine(bundle: Bundle.module)
        XCTAssertFalse(engine.isEmpty, "Engine initialized with Bundle.module should load entries")
        XCTAssertGreaterThan(engine.count, 4000)
        XCTAssertTrue(engine.suggestions(for: "cộng").contains("đồng"))
    }

    func testUTF8BOMHandlingInCustomText() {
        let bomSample = "\u{FEFF}xin chào\nxin lỗi\n"
        let parsed = WordSuggestionEngine.parse(text: bomSample)
        XCTAssertEqual(parsed["xin"], ["chào", "lỗi"], "UTF-8 BOM at the start of text should be cleanly stripped")
    }

    func testHyphenatedCompoundWordSuggestions() {
        let engine = WordSuggestionEngine.shared
        let suggestions = engine.suggestions(for: "việt-nam")
        XCTAssertFalse(suggestions.isEmpty, "Hyphenated compound 'việt-nam' should yield continuations for 'nam'")
        XCTAssertTrue(suggestions.contains("bộ") || suggestions.contains("bình"))
    }

    func testTrailingWhitespaceAfterPunctuationSuggestions() {
        let engine = WordSuggestionEngine.shared
        let suggestions = engine.suggestions(for: "việt nam, ")
        XCTAssertFalse(suggestions.isEmpty, "Phrase with trailing punctuation and space should fallback to 'nam'")
        XCTAssertTrue(suggestions.contains("bộ") || suggestions.contains("bình"))
    }
}
