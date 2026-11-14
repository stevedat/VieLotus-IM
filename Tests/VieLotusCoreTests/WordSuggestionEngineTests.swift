import XCTest
@testable import VieLotusCore

final class WordSuggestionEngineTests: XCTestCase {
    func testConcurrentSuggestionWorkersMatchSerialResults() async {
        let engine = WordSuggestionEngine(userStore: UserFrequencyStore())
        let contexts = [
            SuggestionInputContext(beforeContext: "tôi đang "),
            SuggestionInputContext(beforeContext: "học sinh "),
            SuggestionInputContext(beforeContext: "apple meta ", composingWord: "có", isComposing: true),
            SuggestionInputContext(beforeContext: "")
        ]
        let expected = contexts.map { engine.suggest(context: $0, limit: 3) }
        let matches = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for i in 0..<64 {
                let index = i % contexts.count
                group.addTask {
                    engine.suggest(context: contexts[index], limit: 3) == expected[index]
                }
            }
            for await matches in group { if !matches { return false } }
            return true
        }
        XCTAssertTrue(matches, "Immutable dictionary and locked user frequencies must support worker queries")
    }

    func testLiteralABCDoesNotOfferVietnameseSuggestions() {
        let engine = WordSuggestionEngine.shared
        XCTAssertFalse(engine.suggest(context: SuggestionInputContext(beforeContext: "")).isEmpty)
        XCTAssertTrue(engine.suggest(context: SuggestionInputContext(
            beforeContext: "", typingMode: .literalABC
        )).isEmpty)
        XCTAssertTrue(engine.suggest(context: SuggestionInputContext(
            beforeContext: "apple meta ", composingWord: "cos",
            isComposing: true, typingMode: .literalABC
        )).isEmpty)
    }

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
        guard let txtURL = Bundle.vieLotusCore.url(forResource: "TuDienTuGhep", withExtension: "txt") else {
            XCTFail("TuDienTuGhep.txt should exist in vieLotusCore bundle")
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
        let engine = WordSuggestionEngine(bundle: Bundle.vieLotusCore)
        XCTAssertFalse(engine.isEmpty, "Engine initialized with Bundle.vieLotusCore should load entries")
        XCTAssertGreaterThan(engine.count, 4000)
        XCTAssertTrue(engine.suggestions(for: "cộng").contains("đồng"))
    }

    func testRelocatedAppBundleContentsResourcesResolution() throws {
        // Simulate a signed macOS .app bundle installed at /Library/Input Methods/VieLotusIM.app
        // on a user machine where the CI build directory (/Users/runner/work/...) does not exist
        // and VietLotusIM_VieLotusCore.bundle resides inside Contents/Resources/.
        let fm = FileManager.default
        let fakeAppRoot = fm.temporaryDirectory.appendingPathComponent("VieLotusIM_\(UUID().uuidString).app", isDirectory: true)
        let fakeResources = fakeAppRoot.appendingPathComponent("Contents/Resources", isDirectory: true)
        let fakeCoreBundle = fakeResources.appendingPathComponent("VietLotusIM_VieLotusCore.bundle", isDirectory: true)
        try fm.createDirectory(at: fakeCoreBundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fakeAppRoot) }

        let sampleJSON = "{\"việt\": [\"nam\", \"ngữ\"]}"
        try sampleJSON.write(to: fakeCoreBundle.appendingPathComponent("TuDienTuGhep.json"), atomically: true, encoding: .utf8)

        let nonExistentCIPath = URL(fileURLWithPath: "/Users/runner/work/VieLotus-IM/VieLotus-IM/.build/scratch-arm64/arm64-apple-macosx/release")
        let resolvedBundle = Bundle.resolveVieLotusCore(
            in: [fakeResources, fakeAppRoot, nonExistentCIPath],
            fallbackBundles: [],
            sourceResourcesURL: nil
        )
        XCTAssertEqual(resolvedBundle.bundleURL.standardizedFileURL, fakeCoreBundle.standardizedFileURL)

        let engine = WordSuggestionEngine(bundle: resolvedBundle)
        XCTAssertEqual(engine.suggestions(for: "việt"), ["nam", "ngữ"])
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

    func testApplyCasing() {
        XCTAssertEqual(WordSuggestionEngine.applyCasing(of: "cộng", to: "đồng"), "đồng")
        XCTAssertEqual(WordSuggestionEngine.applyCasing(of: "CỘNG", to: "đồng"), "ĐỒNG")
        XCTAssertEqual(WordSuggestionEngine.applyCasing(of: "Cộng", to: "đồng"), "đồng")
        XCTAssertEqual(WordSuggestionEngine.applyCasing(of: "", to: "đồng"), "đồng")
        XCTAssertEqual(WordSuggestionEngine.applyCasing(of: "CỘNG", to: ""), "")
    }

    func testCompoundSuggestions() {
        let engine = WordSuggestionEngine.shared
        let lower = engine.compoundSuggestions(for: "cộng", limit: 3)
        XCTAssertFalse(lower.isEmpty)
        XCTAssertTrue(lower.contains("cộng đồng"))

        let capitalized = engine.compoundSuggestions(for: "Cộng", limit: 3)
        XCTAssertFalse(capitalized.isEmpty)
        XCTAssertTrue(capitalized.contains("Cộng đồng"))

        let upper = engine.compoundSuggestions(for: "CỘNG", limit: 3)
        XCTAssertFalse(upper.isEmpty)
        XCTAssertTrue(upper.contains("CỘNG ĐỒNG"))
    }

    func testNextWordSuggestionsWithCasing() {
        let engine = WordSuggestionEngine.shared
        let lower = engine.nextWordSuggestions(for: "cộng", limit: 3)
        XCTAssertTrue(lower.contains("đồng"))

        let upper = engine.nextWordSuggestions(for: "CỘNG", limit: 3)
        XCTAssertTrue(upper.contains("ĐỒNG"))
    }

    // MARK: - Context-Aware Suggestion Engine Tests (Rules 1 - 6)

    func testV1FrequencyRankingEliminatesAlphabeticalNoise() {
        let engine = WordSuggestionEngine.shared

        let thanh = engine.suggestions(for: "thành", limit: 5)
        XCTAssertEqual(Array(thanh.prefix(4)), ["phố", "công", "lập", "tích"])

        let toi = engine.suggestions(for: "tôi", limit: 5)
        XCTAssertEqual(Array(toi.prefix(5)), ["là", "đang", "muốn", "có", "không"])

        let cong = engine.suggestions(for: "công", limit: 4)
        XCTAssertEqual(cong, ["ty", "việc", "nghệ", "trình"])

        let giao = engine.suggestions(for: "giáo", limit: 3)
        XCTAssertEqual(giao, ["viên", "dục", "trình"])

        let benh = engine.suggestions(for: "bệnh", limit: 3)
        XCTAssertEqual(benh, ["viện", "nhân", "án"])
    }

    func testRule1MultiSyllableContextDisambiguatesHoc() {
        let engine = WordSuggestionEngine.shared

        // Context A: "Tôi đang đi học " -> ["tiếng Anh", "ở trường", "thêm", ...]
        let ctxA = SuggestionInputContext(beforeContext: "Tôi đang đi học ", isComposing: false)
        let resA = engine.suggest(context: ctxA, limit: 5).map(\.displayText)
        XCTAssertTrue(resA.contains("tiếng Anh"), "Expected 'tiếng Anh' in \(resA)")
        XCTAssertTrue(resA.contains("ở trường"), "Expected 'ở trường' in \(resA)")

        // Context B: "Hôm nay tôi học " -> ["bài", "được", "về", ...]
        let ctxB = SuggestionInputContext(beforeContext: "Hôm nay tôi học ", isComposing: false)
        let resB = engine.suggest(context: ctxB, limit: 5).map(\.displayText)
        XCTAssertEqual(resB.first, "bài")
        XCTAssertTrue(resB.contains("được"))

        // Context C: "Trường tiểu học " -> ["Nguyễn Du", "này", "của tôi", ...]
        let ctxC = SuggestionInputContext(beforeContext: "Trường tiểu học ", isComposing: false)
        let resC = engine.suggest(context: ctxC, limit: 5).map(\.displayText)
        XCTAssertEqual(resC.first, "Nguyễn Du")
        XCTAssertTrue(resC.contains("này"))
    }

    func testRule2CompoundCompletionAndNextWordPrediction() {
        let engine = WordSuggestionEngine.shared

        // After compound "thành phố " -> predicts "Hồ Chí Minh", "Hà Nội", "này" (NOT looking up only "phố")
        let thanhPho = engine.suggest(
            context: SuggestionInputContext(beforeContext: "thành phố ", isComposing: false),
            limit: 5
        ).map(\.displayText)
        XCTAssertEqual(thanhPho.first, "Hồ Chí Minh")
        XCTAssertTrue(thanhPho.contains("Hà Nội"))
        XCTAssertTrue(thanhPho.contains("này"))

        // After compound "công ty " -> predicts "tôi", "chúng tôi", "đang", "có"
        let congTy = engine.suggest(
            context: SuggestionInputContext(beforeContext: "công ty ", isComposing: false),
            limit: 5
        ).map(\.displayText)
        XCTAssertEqual(Array(congTy.prefix(4)), ["tôi", "chúng tôi", "đang", "có"])

        // After "tôi muốn " -> predicts "hỏi", "biết", "mua", "đi", "làm"
        let toiMuon = engine.suggest(
            context: SuggestionInputContext(beforeContext: "tôi muốn ", isComposing: false),
            limit: 5
        ).map(\.displayText)
        XCTAssertEqual(toiMuon, ["hỏi", "biết", "mua", "đi", "làm"])

        // Verbal context override: "tôi thành " -> prioritizes "công" over "phố"
        let toiThanh = engine.suggest(
            context: SuggestionInputContext(beforeContext: "tôi thành ", isComposing: false),
            limit: 5
        ).map(\.displayText)
        XCTAssertEqual(toiThanh.first, "công")
    }

    func testRule3ComposingPreservesUserInputAndSupportsPrefixMatch() {
        let engine = WordSuggestionEngine.shared

        // Composing "thành" -> Slot 0 is "thành" (.keepComposing), followed by compound completions (.replaceComposing)
        let composingCtx = SuggestionInputContext(
            beforeContext: "",
            composingWord: "thành",
            isComposing: true
        )
        let compRes = engine.suggest(context: composingCtx, limit: 5)
        XCTAssertEqual(compRes.first?.displayText, "thành")
        XCTAssertEqual(compRes.first?.replacementMode, .keepComposing)
        XCTAssertTrue(compRes.dropFirst().contains(where: { $0.displayText == "thành phố" && $0.replacementMode == .replaceComposing }))

        // Typing prefix "ph" after "thành " -> offers "phố" with .replaceComposing (preventing "thành thành phố")
        let prefixCtx = SuggestionInputContext(
            beforeContext: "thành ",
            composingWord: "ph",
            isComposing: true
        )
        let prefixRes = engine.suggest(context: prefixCtx, limit: 5)
        XCTAssertEqual(prefixRes.first?.displayText, "ph")
        XCTAssertTrue(prefixRes.dropFirst().contains(where: { $0.displayText == "phố" && $0.replacementMode == .replaceComposing }))
    }

    func testRule5EnglishSuppressionAndProperNouns() {
        let engine = WordSuggestionEngine.shared

        // After English word "restrict " -> returns empty list rather than random Vietnamese starter words
        let enCtx = SuggestionInputContext(
            beforeContext: "con cá qua sông bị restrict ",
            isComposing: false
        )
        let enRes = engine.suggest(context: enCtx, limit: 5)
        XCTAssertTrue(enRes.isEmpty, "Should not suggest random Vietnamese words after an English token")

        // Capitalized "Hà " -> boosts proper noun continuations "Nội", "Lan"
        let haCtx = SuggestionInputContext(
            beforeContext: "Hà ",
            isComposing: false
        )
        let haRes = engine.suggest(context: haCtx, limit: 5).map(\.displayText)
        XCTAssertEqual(haRes.first, "Nội")
        XCTAssertTrue(haRes.contains("Lan"))
    }

    func testRule6OnDevicePersonalizationWithTimeDecay() {
        let suiteName = "vielotus.test.userfreq.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Seed legacy key to verify it is purged on init (Zero Data Collection)
        testDefaults.set(Data("legacy".utf8), forKey: "vielotus.suggestion.user_freq.v1")
        let store = UserFrequencyStore(defaults: testDefaults)
        XCTAssertNil(testDefaults.data(forKey: "vielotus.suggestion.user_freq.v1"), "Legacy persisted frequency key must be purged on init")

        let engine = WordSuggestionEngine(dictionary: WordSuggestionEngine.shared.bigrams, userStore: store)

        let now = Date().timeIntervalSince1970
        // User repeatedly selects "án" after "giáo"
        for _ in 0..<8 {
            store.recordSelection(candidate: "án", contextKey: "giáo", now: now)
        }
        // Verify nothing is written to UserDefaults (strictly RAM-only)
        XCTAssertNil(testDefaults.data(forKey: "vielotus.suggestion.user_freq.v1"), "UserFrequencyStore must never persist user history to disk")

        let ctx = SuggestionInputContext(beforeContext: "giáo ", isComposing: false)
        let suggestions = engine.suggest(context: ctx, limit: 5).map(\.displayText)
        XCTAssertEqual(suggestions.first, "án", "Frequently selected 'án' after 'giáo' should rise to #1")

        // Verify time decay after 60 days significantly reduces boost
        let boostNow = store.userBoost(for: "án", contextKey: "giáo", now: now)
        let boostAfter60Days = store.userBoost(for: "án", contextKey: "giáo", now: now + 60 * 86400)
        XCTAssertLessThan(boostAfter60Days, boostNow * 0.4)
    }

    func testCommonHeadwordsHaveSingleSyllableTopSuggestions() {
        let engine = WordSuggestionEngine.shared
        let commonHeads = ["đi", "làm", "ăn", "của", "nhiều", "con", "một", "nói", "hỏi", "mua", "bán", "biết"]
        for head in commonHeads {
            let top5 = engine.suggestions(for: head, limit: 5)
            XCTAssertEqual(top5.count, 5, "Headword '\(head)' should have at least 5 suggestions")
            for item in top5 {
                XCTAssertFalse(item.contains(" "), "Top-5 suggestion '\(item)' for '\(head)' must be a clean 1-syllable continuation, not a multi-word idiom")
            }
        }
        XCTAssertEqual(Array(engine.suggestions(for: "đi", limit: 3)), ["làm", "học", "về"])
        XCTAssertEqual(Array(engine.suggestions(for: "làm", limit: 3)), ["việc", "ăn", "gì"])
        XCTAssertEqual(Array(engine.suggestions(for: "ăn", limit: 3)), ["uống", "cơm", "sáng"])
    }

    func testSuggestionEngineLatencyUnder10msP95() {
        let engine = WordSuggestionEngine.shared
        let sampleContexts = [
            SuggestionInputContext(beforeContext: "Tôi đang đi học ", isComposing: false),
            SuggestionInputContext(beforeContext: "Ở thành phố ", isComposing: false),
            SuggestionInputContext(beforeContext: "Hôm nay công ty ", isComposing: false),
            SuggestionInputContext(beforeContext: "Tôi muốn ", composingWord: "h", isComposing: true),
            SuggestionInputContext(beforeContext: "", composingWord: "thành", isComposing: true)
        ]

        var durationsMs: [Double] = []
        durationsMs.reserveCapacity(200)
        for i in 0..<200 {
            let ctx = sampleContexts[i % sampleContexts.count]
            let start = Date().timeIntervalSinceReferenceDate
            _ = engine.suggest(context: ctx, limit: 5)
            let elapsedMs = (Date().timeIntervalSinceReferenceDate - start) * 1000.0
            durationsMs.append(elapsedMs)
        }
        durationsMs.sort()
        let p95 = durationsMs[Int(Double(durationsMs.count) * 0.95)]
        XCTAssertLessThan(p95, 10.0, "p95 suggestion latency (\(p95) ms) must be well under 10 ms")
    }

    func testBilingualTwinSurfacesHisAndRawWordTwinsWithoutBreakingVietnameseCompounds() {
        let engine = WordSuggestionEngine.shared

        // 1. Composing "Hí" from raw "His" at sentence start surfaces "His" in top-3 suggestions
        let hisCtx = SuggestionInputContext(
            beforeContext: "",
            composingWord: "Hí",
            rawWord: "His",
            isComposing: true
        )
        let hisSuggestions = engine.suggest(context: hisCtx, limit: 3).map(\.displayText)
        XCTAssertEqual(hisSuggestions.first, "Hí", "Primary composing echo must remain 'Hí'")
        XCTAssertTrue(hisSuggestions.contains("His"), "English twin 'His' must appear in top-3 suggestions (got \(hisSuggestions))")

        // 2. Composing "há" from raw "has" surfaces "has" via forwarded rawWord
        let hasCtx = SuggestionInputContext(
            beforeContext: "",
            composingWord: "há",
            rawWord: "has",
            isComposing: true
        )
        let hasSuggestions = engine.suggest(context: hasCtx, limit: 3).map(\.displayText)
        XCTAssertEqual(hasSuggestions.first, "há")
        XCTAssertTrue(hasSuggestions.contains("has"), "Forwarded rawWord 'has' must surface in top-3 suggestions (got \(hasSuggestions))")

        // 3. Vietnamese compound typing and post-space continuations remain intact for "Hí hửng", "Thí sinh", "Cả nhà"
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        session.setGrammarProfile(.senFlex)

        func drivePhrase(_ keystrokes: String) -> String {
            session.reset()
            session.clearContext()
            var buffer = ""
            for ch in keystrokes {
                if session.isWordBoundary(ch) {
                    let action = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    if case .commit(let bs, let text, _) = action {
                        if bs > 0 && buffer.count >= bs {
                            buffer.removeLast(bs)
                        }
                        buffer.append(text)
                    }
                    buffer.append(ch)
                    continue
                }
                let action = session.handleCharacter(ch)
                switch action {
                case .passThrough:
                    buffer.append(ch)
                case .consumed, .reset:
                    break
                case .replace(let bs, let text), .commit(let bs, let text, _):
                    if bs > 0 && buffer.count >= bs {
                        buffer.removeLast(bs)
                    }
                    buffer.append(text)
                }
            }
            return buffer
        }

        // Vietnamese compounds remain 100% preserved (including retroactive His/his -> Hí/hí on compound continuation)
        XCTAssertEqual(drivePhrase("His huwngr "), "Hí hửng ")
        XCTAssertEqual(drivePhrase("his huwngr "), "hí hửng ")
        XCTAssertEqual(drivePhrase("His hoays "), "Hí hoáy ")
        XCTAssertEqual(drivePhrase("Cuwowif his "), "Cười hí ")
        XCTAssertEqual(drivePhrase("Mawts his "), "Mắt hí ")
        XCTAssertEqual(drivePhrase("Hown her "), "Hơn hẻ ")
        XCTAssertEqual(drivePhrase("This sinh "), "Thí sinh ")
        XCTAssertEqual(drivePhrase("This nghieemj "), "Thí nghiệm ")
        XCTAssertEqual(drivePhrase("This ddieemr "), "Thí điểm ")
        XCTAssertEqual(drivePhrase("Car nhaf "), "Cả nhà ")
        XCTAssertEqual(drivePhrase("Car lowps "), "Cả lớp ")
        XCTAssertEqual(drivePhrase("Was nuowcs mawts "), "Ứa nước mắt ")

        // Standalone His/Her prefer English, and on inline bilingual (iOS) lowercase his/her also prefer English
        XCTAssertEqual(drivePhrase("His "), "His ")
        XCTAssertEqual(drivePhrase("Her "), "Her ")
        session.inlineBilingualEnabled = true
        XCTAssertEqual(drivePhrase("his "), "his ")
        XCTAssertEqual(drivePhrase("her "), "her ")
        XCTAssertEqual(drivePhrase("his huwngr "), "hí hửng ")
        XCTAssertEqual(drivePhrase("This is "), "This is ")
        XCTAssertEqual(drivePhrase("this is "), "this is ")
        session.inlineBilingualEnabled = false

        // English sentence-initial collision phrases ("This is...", "His car is...", "Her car is...", "This car is...", "More time...", "Is this...", "Did you...")
        XCTAssertEqual(drivePhrase("This is "), "This is ")
        XCTAssertEqual(drivePhrase("this is "), "this is ")
        XCTAssertEqual(drivePhrase("His car is "), "His car is ")
        XCTAssertEqual(drivePhrase("his car is "), "his car is ")
        XCTAssertEqual(drivePhrase("Her car is "), "Her car is ")
        XCTAssertEqual(drivePhrase("her car is "), "her car is ")
        XCTAssertEqual(drivePhrase("This car is "), "This car is ")
        XCTAssertEqual(drivePhrase("More time "), "More time ")
        XCTAssertEqual(drivePhrase("Is this "), "Is this ")
        XCTAssertEqual(drivePhrase("Did you "), "Did you ")
        XCTAssertEqual(drivePhrase("Car is "), "Car is ")
        XCTAssertEqual(drivePhrase("His name is "), "His name is ")
        XCTAssertEqual(drivePhrase("Her friend is "), "Her friend is ")

        let hiPostSpace = engine.suggest(context: SuggestionInputContext(beforeContext: "Hí ", isComposing: false), limit: 5).map(\.displayText)
        XCTAssertTrue(hiPostSpace.contains("hửng"), "Post-space after 'Hí ' must still predict 'hửng' (got \(hiPostSpace))")

        let thiPostSpace = engine.suggest(context: SuggestionInputContext(beforeContext: "Thí ", isComposing: false), limit: 5).map(\.displayText)
        XCTAssertTrue(thiPostSpace.contains("sinh"), "Post-space after 'Thí ' must still predict 'sinh' (got \(thiPostSpace))")

        let caPostSpace = engine.suggest(context: SuggestionInputContext(beforeContext: "Cả ", isComposing: false), limit: 5).map(\.displayText)
        XCTAssertTrue(caPostSpace.contains("nhà"), "Post-space after 'Cả ' must still predict 'nhà' (got \(caPostSpace))")
    }
}
