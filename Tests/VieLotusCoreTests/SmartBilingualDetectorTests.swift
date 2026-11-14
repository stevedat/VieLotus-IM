import XCTest
@testable import VieLotusCore

final class SmartBilingualDetectorTests: XCTestCase {
    func testCoreVietnameseWords() {
        // "gì" should not be restored to "gif"
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "gif", rendered: "gì"))
        // "đó" should not be restored to "ddos"
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddos", rendered: "đó"))
        // "có" should not be restored to "cos"
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "cos", rendered: "có"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "coong", context: "cồn", rendered: "công"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "coong", context: "cồn công", rendered: "công"))
        // "coong" ("công") is not a valid English word and must stay Vietnamese even after English context,
        // whereas a real English collision word like "room" ("rôm") restores in English context.
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "coong", context: "the latest deployment", rendered: "công"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "room", context: "the latest deployment", rendered: "rôm"))
    }

    func testCoongCommitsAsVietnameseAfterVietnameseContext() {
        let session = InputSessionManager()
        session.appendContext("cồn")
        for character in "coong" { _ = session.handleCharacter(character) }
        XCTAssertEqual(session.currentOutput(), "công")

        guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected công to commit")
        }
        XCTAssertFalse(isOverride)
        XCTAssertEqual(committed, "công")
    }

    func testAmbiguousTelexEndingPrefersVietnameseWithoutEnglishContext() {
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "toots", rendered: "tốt"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "toots", context: "được và được", rendered: "tốt"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "toots", context: "I like listening to music", rendered: "tốt"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "This", context: "he is", rendered: "Thí"))
    }

    func testTelexToneBeforeFinalConsonantKeepsPlausibleVietnameseWithoutEnglishContext() {
        for (raw, rendered) in [("tuyeern", "tuyển"), ("toost", "tốt")] {
            XCTAssertFalse(
                SmartBilingualDetector.isEnglishWord(raw: raw, context: "biến thể", rendered: rendered),
                "A valid Vietnamese syllable should not be restored to \(raw)"
            )
        }

        // "tuyeern" ("tuyển") is an unambiguous Vietnamese Telex word and must not revert to raw ASCII even in English context,
        // whereas a genuine English word like "cheers" ("chế") restores in English context.
        XCTAssertFalse(
            SmartBilingualDetector.isEnglishWord(raw: "tuyeern", context: "I saw this in the latest deployment", rendered: "tuyển")
        )
        XCTAssertTrue(
            SmartBilingualDetector.isEnglishWord(raw: "cheers", context: "I saw this in the latest deployment", rendered: "chế")
        )
    }

    func testMangledEnglishWithImpossibleVietnameseSyllableShape() {
        let examples = [
            ("superadmin", "supeadmỉn"),
            ("super", "sủpe"),
            ("clever", "clẻve"),
            ("detector", "detẻcto"),
            ("tractor", "trảcto"),
            ("center", "cẻnte"),
            ("advantages", "advantáge")
        ]

        for (raw, rendered) in examples {
            XCTAssertTrue(
                SmartBilingualDetector.isEnglishWord(raw: raw, rendered: rendered),
                "Expected \(raw) to be restored from \(rendered)"
            )
        }
    }

    func testMangledEnglishWordsRestoreOnCommitButKeepValidVietnamese() {
        // With the non-plausible tone rejection fix, words where tone would produce
        // non-plausible Vietnamese now stay as raw ASCII directly (no mangling).
        // SmartBilingual override is no longer needed for these words.
        let noLongerMangledExamples = [
            "superadmin", "super", "clever", "detector", "tractor", "center", "advantages"
        ]

        for raw in noLongerMangledExamples {
            let session = InputSessionManager()
            for character in raw {
                _ = session.handleCharacter(character)
            }
            // Engine now produces raw ASCII output directly (non-plausible tone rejected)
            XCTAssertEqual(session.currentOutput(), raw,
                           "\(raw) should stay as raw ASCII (non-plausible tone rejected)")
            guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                return XCTFail("Expected \(raw) to commit")
            }
            XCTAssertEqual(committed, raw)
        }

        let vietnameseSession = InputSessionManager()
        for character in "toots" {
            _ = vietnameseSession.handleCharacter(character)
        }
        guard case let .commit(_, vietnamese, isOverride) = vietnameseSession.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected tốt to commit")
        }
        XCTAssertFalse(isOverride)
        XCTAssertEqual(vietnamese, "tốt")
    }

    func testTuyenCommitsVietnameseWhenToneKeyPrecedesCoda() {
        let session = InputSessionManager()
        for character in "tuyeern" { _ = session.handleCharacter(character) }
        XCTAssertEqual(session.currentOutput(), "tuyển")

        guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected tuyển to commit")
        }
        XCTAssertFalse(isOverride)
        XCTAssertEqual(committed, "tuyển")
    }

    func testChuongFreeToneWFormsSurviveSpaceCommit() {
        for raw in ["chuongw", "chuowng"] {
            let session = InputSessionManager()
            for character in raw {
                _ = session.handleCharacter(character)
            }
            guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
                return XCTFail("Expected \(raw) to commit")
            }
            XCTAssertFalse(isOverride, raw)
            XCTAssertEqual(committed, "chương", raw)
        }
    }

    func testTelexxRemainsEnglishAfterSpaceCommit() {
        let session = InputSessionManager()
        for character in "telexx" {
            _ = session.handleCharacter(character)
        }
        guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected telexx to commit")
        }
        XCTAssertEqual(committed, "telexx")
    }

    func testWebPrefixCommitsExactlyThreeWs() {
        let session = InputSessionManager()
        for character in "www" {
            _ = session.handleCharacter(character)
        }
        XCTAssertEqual(session.currentOutput(), "www")
        guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected www to commit")
        }
        XCTAssertFalse(isOverride)
        XCTAssertEqual(committed, "www")
    }

    func testDoubleWTypesSingleLiteralWAndSurvivesSpace() {
        // 1. Default Simple Telex: 'w' -> 'w', 'ww' -> 'ww'
        let simpleSession = InputSessionManager()
        for character in "ww" {
            _ = simpleSession.handleCharacter(character)
        }
        XCTAssertEqual(simpleSession.currentOutput(), "ww")
        guard case let .commit(_, simpleCommitted, simpleIsOverride) = simpleSession.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected literal ww to commit")
        }
        XCTAssertFalse(simpleIsOverride)
        XCTAssertEqual(simpleCommitted, "ww")

        // 2. Classic Telex (simpleTelex = false): 'w' -> 'ư', 'ww' -> 'w'
        let classicSession = InputSessionManager()
        classicSession.setSimpleTelex(false)
        for character in "ww" {
            _ = classicSession.handleCharacter(character)
        }
        XCTAssertEqual(classicSession.currentOutput(), "w")
        guard case let .commit(_, committed, isOverride) = classicSession.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected literal w to commit")
        }
        XCTAssertFalse(isOverride)
        XCTAssertEqual(committed, "w")
    }

    func testUserEnglishFormsAndRepeatedKeyEscapesCommitCanonicalWord() {
        for (raw, expected) in [("user", "user"), ("users", "users"), ("usserr", "user"), ("usserrss", "users")] {
            let session = InputSessionManager()
            for character in raw {
                _ = session.handleCharacter(character)
            }
            guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                return XCTFail("Expected \(raw) to commit")
            }
            XCTAssertEqual(committed, expected, raw)
        }
    }

    func testStructuralHeuristics() {
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "MAX_SIZE"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "/usr/local/bin"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "senprints.com"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "config.json"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "localhost:8080"))
    }

    func testWordsStartingWithDdAreNotFalselyRestoredToEnglish() {
        // Vietnamese words or incomplete syllables starting with "dd" must keep their transformed shape
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddacw", rendered: "đăc"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddac", rendered: "đac"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddacwj", rendered: "đặc"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddi", rendered: "đi"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddung", rendered: "đung"))

        // Pure consonant abbreviations like DDR (đr) with no vowels should restore to DDR
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "ddr", rendered: "đr"))
    }

    func testStrokeDConsonantAbbreviationsArePreservedInlineAndOnSpace() {
        let cases: [(raw: String, expected: String)] = [
            ("DDH", "ĐH"),
            ("DDT", "ĐT"),
            ("DDW", "ĐW"),
            ("DDQ", "ĐQ"),
            ("ddh", "đh"),
            ("ddt", "đt"),
            ("ddw", "đw"),
            ("ddq", "đq"),
            ("DDC", "ĐC"),
            ("ddc", "đc"),
            ("DDB", "ĐB"),
            ("DDK", "ĐK"),
            ("DDL", "ĐL"),
            ("DDM", "ĐM"),
            ("DDN", "ĐN"),
            ("DDP", "ĐP"),
            ("DDS", "ĐS"),
            ("DDV", "ĐV"),
            ("DDX", "ĐX"),
            ("DDG", "ĐG"),
            ("DDR", "ĐR"),
            ("SDDT", "SĐT"),
            ("sddt", "sđt"),
            ("BDDS", "BĐS"),
            ("bdds", "bđs"),
            ("HDD", "HĐ"),
            ("QDD", "QĐ"),
            ("HDDND", "HĐND"),
            ("DDHQG", "ĐHQG")
        ]

        let previousProvider = SmartBilingualDetector.spellCheckerProvider
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        defer {
            SmartBilingualDetector.spellCheckerProvider = previousProvider
            SmartBilingualDetector.resetCache()
        }

        for (raw, expected) in cases {
            XCTAssertFalse(
                SmartBilingualDetector.isInlineEnglishWord(raw: raw, rendered: expected),
                "Inline bilingual should not revert \(raw) (\(expected))"
            )
            XCTAssertFalse(
                SmartBilingualDetector.isEnglishWord(raw: raw, rendered: expected),
                "Commit bilingual should not revert \(raw) (\(expected))"
            )

            let session = InputSessionManager()
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true
            for ch in raw {
                _ = session.handleCharacter(ch)
            }
            XCTAssertEqual(session.composingWord, expected, "Composing \(raw) should produce \(expected)")
            XCTAssertFalse(
                session.shouldSelectRawEnglishOnCommit(rawWord: session.rawWord, rendered: session.composingWord),
                "Pressing Space after \(raw) (\(expected)) must not revert to raw \(raw)"
            )
        }
    }

    func testGenZTeenCodePreservation() {
        // Teen code words in Gen-Z mode should not be treated as English words (keep rendered teen code)
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "thix", rendered: "thix", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "bik", rendered: "bik", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "mun", rendered: "mún", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "fai", rendered: "fải", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddc", rendered: "đc", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ko", rendered: "ko", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ddug", rendered: "đug", genZMode: true))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "tieg", rendered: "tiếg", genZMode: true))
    }

    func testGenZEnglishWordsWithDiacriticsAreRestored() {
        let previousProvider = SmartBilingualDetector.spellCheckerProvider
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        defer {
            SmartBilingualDetector.spellCheckerProvider = previousProvider
            SmartBilingualDetector.resetCache()
        }
        // Critical regression test: In Gen-Z mode, English words that received diacritics
        // MUST still be detected as English and restored to raw keystrokes!
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "more", rendered: "mỏ", genZMode: true), "more must be restored in Gen-Z mode")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "users", rendered: "usẻ", genZMode: true), "users must be restored in Gen-Z mode")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "does", rendered: "doé", genZMode: true), "does must be restored in Gen-Z mode")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "life", rendered: "lìe", genZMode: true), "life must be restored in Gen-Z mode")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "care", rendered: "caẻ", genZMode: true), "care must be restored in Gen-Z mode")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "database", rendered: "databáe", genZMode: true), "database must be restored in Gen-Z mode")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "release", rendered: "releáe", genZMode: true), "release must be restored in Gen-Z mode")
    }

    func testCacheEvictionUnderPressure() {
        // Reset cache to a clean baseline
        SmartBilingualDetector.resetCache()
        let previousLimit = SmartBilingualDetector.maxCacheEntries
        defer {
            SmartBilingualDetector.maxCacheEntries = previousLimit
            SmartBilingualDetector.resetCache()
        }

        // Temporarily lower cache limit to 20 for deterministic fast test
        SmartBilingualDetector.maxCacheEntries = 20

        // Insert 25 unique test keys through dictionary check
        for i in 0..<25 {
            let word = "testword\(i)"
            _ = SmartBilingualDetector.isEnglishWord(raw: word)
        }

        // Verify cache capacity stayed under or at limit
        XCTAssertLessThanOrEqual(SmartBilingualDetector.cacheCount, 20)
        XCTAssertGreaterThan(SmartBilingualDetector.cacheCount, 0)

        // Verify earliest inserted keys (e.g. testword0) were evicted
        SmartBilingualDetector.lockForTesting {
            XCTAssertNil(SmartBilingualDetector.spellCheckCache["testword0"])
            // Verify newer keys exist
            XCTAssertNotNil(SmartBilingualDetector.spellCheckCache["testword24"])
        }
    }

    func testEnglishDiacriticCollisionWordsRestoredWithoutContext() {
        let testWords = [
            ("test", "tét"),
            ("toast", "toát"),
            ("turn", "tủn"),
            ("cost", "cót"),
            ("best", "bét"),
            ("list", "lít"),
            ("host", "hót"),
            ("fast", "fát"),
            ("last", "lát")
        ]
        for (raw, rendered) in testWords {
            XCTAssertTrue(
                SmartBilingualDetector.isEnglishWord(raw: raw, context: "", rendered: rendered),
                "English word '\(raw)' should be restored even without English context instead of remaining '\(rendered)'"
            )
        }
        // 'rest' -> 'rét' is a critical Vietnamese syllable path (`whitelist_safe = never`) that survives without context and restores with English context:
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "rest", context: "", rendered: "rét"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "rest", context: "the", rendered: "rét"))
    }

    func testToneEscapeSequencesAreNotInlineRestored() {
        // Repeated tone keys used to cancel diacritics in Telex should NOT trigger inline English override
        XCTAssertFalse(SmartBilingualDetector.isInlineEnglishWord(raw: "orr", rendered: "or"))
        XCTAssertFalse(SmartBilingualDetector.isInlineEnglishWord(raw: "iff", rendered: "if"))
        XCTAssertFalse(SmartBilingualDetector.isInlineEnglishWord(raw: "ass", rendered: "as"))
        XCTAssertFalse(SmartBilingualDetector.isInlineEnglishWord(raw: "err", rendered: "er"))

        // Genuine inline English words must continue to be restored inline
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "post", rendered: "pót"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "fast", rendered: "fát"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "docker", rendered: "đockẻ"))
    }

    func testReversibleAmbiguityAndExplicitEscape() {
        // Rule B: Repeated tone keys explicitly escape Telex and commit the cancelled form
        let escapeCases = [
            ("carr", "car"),
            ("cass", "cas"),
            ("giff", "gif"),
            ("sexx", "sex"),
            ("tess", "tes"),
            ("coss", "cos")
        ]
        for (raw, expected) in escapeCases {
            let session = InputSessionManager()
            for char in raw { _ = session.handleCharacter(char) }
            guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                XCTFail("Expected \(raw) to commit")
                continue
            }
            XCTAssertEqual(committed, expected, "Typing '\(raw)' should escape Telex and commit '\(expected)'")
        }

        // Rule A & Double Consonants: Genuine English words with double consonants preserve raw
        let englishDoubles = [
            ("class", "class"),
            ("pass", "pass"),
            ("boss", "boss"),
            ("less", "less"),
            ("card", "card"),
            ("case", "case"),
            ("test", "test")
        ]
        for (raw, expected) in englishDoubles {
            let session = InputSessionManager()
            for char in raw { _ = session.handleCharacter(char) }
            guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                XCTFail("Expected \(raw) to commit")
                continue
            }
            XCTAssertEqual(committed, expected, "Typing '\(raw)' should commit '\(expected)'")
        }
    }

    func testSingleWordEnglishAnchorContextRestoresWord() {
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "post", context: "the", rendered: "pót"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "list", context: "this", rendered: "lít"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "user", context: "for", rendered: "usẻ"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "test", context: "a", rendered: "tét"))
    }

    func testVietnameseAnchorContextProtectsVietnamese() {
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "toots", context: "những", rendered: "tốt"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "lams", context: "đang", rendered: "lắm"))
    }

    func testCandidateResolverIntentScoring() {
        let arbiter = SyllableCandidateResolver.shared
        let vnIntent = SyllableIntent(onset: "v", nucleus: "iê", coda: "t", tone: .dot, isValidVietnamese: true)
        let vnScore = arbiter.calculateIntentScore(lowerRaw: "vieetj", intent: vnIntent, rendered: "việt")
        XCTAssertGreaterThan(vnScore, 30)

        let engIntent = SyllableIntent(onset: "b", nucleus: "o", coda: "s", tone: .acute, isValidVietnamese: false)
        let engScore = arbiter.calculateIntentScore(lowerRaw: "boss", intent: engIntent, rendered: "bó")
        XCTAssertLessThan(engScore, 0)
    }

    func testNeutralLoanwordsDoNotHijackFollowingVietnameseSyllable() {
        // Common loanwords borrowed in Vietnamese sentences ("gui email", "check email", "tai app", "ok wifi")
        // must NOT force the subsequent Vietnamese word ("bán" = bans, "còn" = conf, "có" = cos) into English.
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "bans", context: "gui email", rendered: "bán"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "conf", context: "check email", rendered: "còn"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "cos", context: "tai app", rendered: "có"))
        XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "toots", context: "ok wifi", rendered: "tốt"))

        // However, when the loanword is preceded by an English function word ("the email", "this app"),
        // the sentence is genuinely English and the next word restores to English.
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "was", context: "the email", rendered: "ứa"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "has", context: "this app", rendered: "há"))
    }

    func testEnglishContractionsOpenEnglishContextWithStraightAndCurlyApostrophes() {
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "been", context: "I've", rendered: "bên"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "been", context: "I\u{2019}ve", rendered: "bên"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "been", context: "haven't", rendered: "bên"))
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "more", context: "don't", rendered: "mỏ"))
    }

    func testDoubleVowelEnglishCollisionWordsSupportTripleAndPostCodaEscape() {
        let escapeCases: [(raw: String, expected: String)] = [
            // Triple-vowel Telex escape (eee -> ee, ooo -> oo)
            ("seeen", "seen"),
            ("teeen", "teen"),
            ("keeen", "keen"),
            ("queeen", "queen"),
            ("beeen", "been"),
            ("peee", "pee"),
            ("reeef", "reef"),
            ("seee", "see"),
            ("beee", "bee"),
            ("treee", "tree"),
            ("greeen", "green"),
            ("rooom", "room"),
            ("tooo", "too"),
            ("mooon", "moon"),
            ("nooon", "noon"),
            ("booom", "boom"),
            ("rooof", "roof"),
            ("rooots", "roots"),
            // Post-coda / post-tone escape (sên + e -> seen, rề + e/f -> reef)
            ("seene", "seen"),
            ("teene", "teen"),
            ("keene", "keen"),
            ("queene", "queen"),
            ("beene", "been"),
            ("reefe", "reef"),
            ("reeff", "reef"),
            ("roomo", "room"),
            ("moono", "moon"),
            ("noono", "noon"),
            ("boomo", "boom"),
            ("roofo", "roof"),
            ("rooff", "roof")
        ]

        for profile in GrammarProfile.allCases {
            for inlineBilingual in [false, true] {
                for (raw, expected) in escapeCases {
                    let session = InputSessionManager()
                    session.setGrammarProfile(profile)
                    session.inlineBilingualEnabled = inlineBilingual
                    for ch in raw {
                        _ = session.handleCharacter(ch)
                    }
                    XCTAssertEqual(
                        session.currentOutput(),
                        expected,
                        "Inline output for '\(raw)' with profile=\(profile) inlineBilingual=\(inlineBilingual) should be '\(expected)'"
                    )
                    guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
                        XCTFail("Expected '\(raw)' to commit")
                        continue
                    }
                    XCTAssertFalse(isOverride, "Commit for '\(raw)' must not override '\(expected)' back to '\(raw)'")
                    XCTAssertEqual(
                        committed,
                        expected,
                        "Committed output for '\(raw)' with profile=\(profile) inlineBilingual=\(inlineBilingual) should be '\(expected)'"
                    )
                }
            }
        }
    }

    func testPostCommitBackspaceAndVowelUndoResurrectsDoubleVowelEnglish() {
        for (raw, vnWord, undoChar, expected) in [
            ("see", "sê", Character("e"), "see"),
            ("bee", "bê", Character("e"), "bee"),
            ("pee", "pê", Character("e"), "pee"),
            ("too", "tô", Character("o"), "too")
        ] {
            let session = InputSessionManager()
            for ch in raw { _ = session.handleCharacter(ch) }
            guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                XCTFail("Expected \(raw) to commit")
                continue
            }
            XCTAssertEqual(committed, vnWord)
            // First backspace deletes trailing Space and arms post-commit editing (editCaretBack = 0)
            _ = session.handleBackspace()
            // Typing the vowel again undoes the circumflex (sê + e -> see)
            _ = session.handleCharacter(undoChar)
            XCTAssertEqual(session.currentOutput(), expected)
            guard case let .commit(_, finalCommitted, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
                XCTFail("Expected \(expected) to commit")
                continue
            }
            XCTAssertFalse(isOverride)
            XCTAssertEqual(finalCommitted, expected)
        }
    }

    func testMixedVietnameseAndEnglishSentenceContextRestoresDoubleVowelEnglishWords() {
        let session = InputSessionManager()
        // Type Vietnamese words with diacritics first, then switch to English mid-sentence
        for word in ["gõ", "sên", "là", "Việt", "còn", "I", "have"] {
            session.appendContext(word)
        }
        for ch in "seen" { _ = session.handleCharacter(ch) }
        guard case let .commit(_, committedSeen, isOverrideSeen) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected seen to commit")
        }
        XCTAssertTrue(isOverrideSeen)
        XCTAssertEqual(committedSeen, "seen")

        for (context, raw) in [
            ("tôi thấy the", "teen"),
            ("cô ấy rất is", "keen"),
            ("nữ hoàng là the", "queen"),
            ("tôi đã I've", "been"),
            ("đi vệ sinh I need to", "pee"),
            ("rạn san hô the", "reef"),
            ("nhìn kìa I can", "see"),
            ("con ong là a", "bee")
        ] {
            XCTAssertTrue(
                SmartBilingualDetector.isEnglishWord(raw: raw, context: context, rendered: "sên"),
                "Expected '\(raw)' after mixed Vietnamese+English context '\(context)' to restore as English"
            )
        }
    }

    func testNarrowSlashCommandsAndVietnameseSlashCompounds() {
        let cases: [(input: String, expected: String)] = [
            ("/aws", "/aws"),
            ("/os", "/os"),
            ("/var", "/var"),
            ("/clear", "/clear"),
            ("/compact", "/compact"),
            ("/model", "/model"),
            ("--help", "--help"),
            ("anh/chij", "anh/chị"),
            ("nam/nuwx", "nam/nữ"),
            ("coj/las", "cọ/lá"),
            ("las/coj", "lá/cọ"),
            ("100W", "100W"),
            ("100w", "100w"),
            ("50W", "50W"),
            ("4K60W", "4K60W"),
            ("20W-50", "20W-50")
        ]

        for (input, expected) in cases {
            let session = InputSessionManager()
            var screen = ""
            for ch in input {
                if session.isWordBoundary(ch) {
                    let act = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    if case let .commit(bs, txt, isOverride) = act, isOverride {
                        if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                        screen += txt
                    }
                    screen.append(ch)
                } else {
                    let act = session.handleCharacter(ch)
                    if case let .replace(bs, txt) = act {
                        if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                        screen += txt
                    } else if case .passThrough = act {
                        screen.append(ch)
                    }
                }
            }
            if session.isComposing {
                let act = session.commitWord(smartBilingualEnabled: true)
                if case let .commit(bs, txt, isOverride) = act, isOverride {
                    if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                    screen += txt
                }
            }
            XCTAssertEqual(screen, expected, "Input '\(input)' expected '\(expected)', got '\(screen)'")
        }
    }

    func testStandaloneVietnameseRhymesComposeAndCommitWithoutRevertingToRaw() {
        let standardTelexRhymes: [(raw: String, expected: String)] = [
            ("uoois", "uối"),
            ("uooif", "uồi"),
            ("uooir", "uổi"),
            ("uooix", "uỗi"),
            ("uooij", "uội"),
            ("onj", "ọn"),
            ("ieengs", "iếng"),
            ("ieets", "iết"),
            ("uowngs", "ướng"),
            ("uoocs", "uốc"),
            ("uyeens", "uyến"),
            ("uyeets", "uyết"),
            ("oangs", "oáng"),
            ("uawng", "uăng")
        ]

        let flexOrderRhymes: [(raw: String, expected: String)] = [
            ("ojn", "ọn"),
            ("ojp", "ọp"),
            ("uoios", "uối"),
            ("uosio", "uối"),
            ("uangw", "uăng")
        ]

        func runWord(_ raw: String, profile: GrammarProfile, inlineBilingual: Bool) -> String {
            let session = InputSessionManager()
            session.setGrammarProfile(profile)
            session.inlineBilingualEnabled = inlineBilingual
            var screen = ""
            for ch in raw {
                let act = session.handleCharacter(ch)
                if case let .replace(bs, txt) = act {
                    if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                    screen += txt
                } else if case .passThrough = act {
                    screen.append(ch)
                }
            }
            if session.isComposing {
                let act = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
                if case let .commit(bs, txt, isOverride) = act, isOverride {
                    if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                    screen += txt
                }
            }
            return screen
        }

        for inlineBilingual in [false, true] {
            for profile in [GrammarProfile.senFlex, GrammarProfile.classic] {
                for (raw, expected) in standardTelexRhymes {
                    let actual = runWord(raw, profile: profile, inlineBilingual: inlineBilingual)
                    XCTAssertEqual(
                        actual,
                        expected,
                        "Standalone rhyme '\(raw)' (\(profile), inline=\(inlineBilingual)) expected '\(expected)', got '\(actual)'"
                    )
                }
            }

            for (raw, expected) in flexOrderRhymes {
                let actual = runWord(raw, profile: .senFlex, inlineBilingual: inlineBilingual)
                XCTAssertEqual(
                    actual,
                    expected,
                    "Flex standalone rhyme '\(raw)' (.senFlex, inline=\(inlineBilingual)) expected '\(expected)', got '\(actual)'"
                )
            }
        }

        // Non-regression: vowel-initial English words & tech acronyms must continue restoring to raw ASCII
        let protectedEnglishTokens = [
            "isp", "ips", "aus", "airfare", "ons", "isa", "url", "urls",
            "uses", "user", "ours", "ios", "aes", "art", "erp", "war", "wax"
        ]
        for token in protectedEnglishTokens {
            let actual = runWord(token, profile: .senFlex, inlineBilingual: false)
            XCTAssertEqual(
                actual,
                token,
                "Expected vowel-initial English/tech token '\(token)' to restore to raw ASCII, got '\(actual)'"
            )
        }

        // 'oops' is a single-path collision with Vietnamese 'ốp': preserves 'ốp' without context, restores 'oops' in English context
        XCTAssertEqual(runWord("oops", profile: .senFlex, inlineBilingual: false), "ốp")
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "oops", context: "I said", rendered: "ốp"))
    }

    func testAllCapsAcronymsPreserveSurroundingLanguageMomentumBilateral() {
        let previousProvider = SmartBilingualDetector.spellCheckerProvider
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        defer {
            SmartBilingualDetector.spellCheckerProvider = previousProvider
        }

        // 1. Vietnamese clauses with `.vietnamese` momentum keep `.vietnamese` after ALL-CAPS acronyms
        for vnCtx in ["team bên US", "đang ở VN", "học IT", "ngành IT", "gọi API", "làm BE", "phòng HR", "đang xem TV", "gửi CV"] {
            let state = BilingualIntentArbiter.evaluateSentenceLanguageState(vnCtx)
            XCTAssertEqual(state.momentum, .vietnamese, "Expected Vietnamese momentum for '\(vnCtx)', got \(state.momentum)")
            let arbTheme = BilingualIntentArbiter.arbitrate(raw: "theme", rendered: "thêm", context: vnCtx)
            XCTAssertEqual(arbTheme.primaryCandidate.text, "thêm", "Arbiter must preserve 'thêm' after '\(vnCtx)'")
            let arbSex = BilingualIntentArbiter.arbitrate(raw: "sex", rendered: "sẽ", context: vnCtx)
            XCTAssertEqual(arbSex.primaryCandidate.text, "sẽ", "Arbiter must preserve 'sẽ' after '\(vnCtx)'")
        }

        // Untoned ASCII Vietnamese clauses (`xem` -> `.neutral`) stay `.neutral` (never flip to `.english`) after ALL-CAPS acronyms
        for neutralVnCtx in ["xem TV", "lam BE"] {
            let state = BilingualIntentArbiter.evaluateSentenceLanguageState(neutralVnCtx)
            XCTAssertEqual(state.momentum, .neutral, "Expected neutral (non-English) momentum for '\(neutralVnCtx)', got \(state.momentum)")
            XCTAssertEqual(BilingualIntentArbiter.arbitrate(raw: "theme", rendered: "thêm", context: neutralVnCtx).primaryCandidate.text, "thêm")
            XCTAssertEqual(BilingualIntentArbiter.arbitrate(raw: "sex", rendered: "sẽ", context: neutralVnCtx).primaryCandidate.text, "sẽ")
        }

        // 2. English clauses with embedded ALL-CAPS acronyms (and Caps-Lock English prose) keep `.english` momentum
        for enCtx in ["living in the US", "the new API", "working in IT", "I will check API", "THIS IS THE", "IT IS"] {
            let state = BilingualIntentArbiter.evaluateSentenceLanguageState(enCtx)
            XCTAssertEqual(state.momentum, .english, "Expected English momentum for '\(enCtx)', got \(state.momentum)")
            let arbRest = BilingualIntentArbiter.arbitrate(raw: "rest", rendered: "rét", context: enCtx)
            XCTAssertEqual(arbRest.primaryCandidate.text, "rest", "Arbiter must prefer 'rest' after '\(enCtx)'")
        }
        XCTAssertEqual(BilingualIntentArbiter.arbitrate(raw: "rest", rendered: "rét", context: "I am").primaryCandidate.text, "rest")

        // 3. End-to-end typing across macOS (commit + inline) and iOS (`UIKitInputSessionAdapter`)
        func driveMac(_ input: String, inlineBilingual: Bool) -> String {
            let session = InputSessionManager()
            session.clearContext()
            session.macroEnabled = false
            session.setSmartBilingualEnabled(true)
            session.inlineBilingualEnabled = inlineBilingual
            var screen = ""
            for ch in input {
                if session.isWordBoundary(ch) {
                    let act = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    if case let .commit(bs, txt, true) = act {
                        if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                        screen += txt
                    }
                    screen.append(ch)
                } else {
                    let act = session.handleCharacter(ch)
                    if case let .replace(bs, txt) = act {
                        if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                        screen += txt
                    } else if case .passThrough = act {
                        screen.append(ch)
                    }
                }
            }
            return screen
        }

        final class SimpleProxy: TextDocumentProxyProtocol {
            var buffer = ""
            var documentContextBeforeInput: String? { buffer }
            var documentContextAfterInput: String? { nil }
            func insertText(_ text: String) { buffer.append(text) }
            func deleteBackward() { if !buffer.isEmpty { buffer.removeLast() } }
        }

        func driveIOS(_ input: String) -> String {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.clearContext()
            adapter.session.macroEnabled = false
            adapter.session.setSmartBilingualEnabled(true)
            let proxy = SimpleProxy()
            for ch in input {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            return proxy.buffer
        }

        let bilateralPhrases: [(raw: String, expected: String)] = [
            ("hocj IT sex ", "học IT sẽ "),
            ("hocj IT theem ", "học IT thêm "),
            ("hocj IT theme ", "học IT theme "),
            ("nganhf IT been ", "ngành IT bên "),
            ("nganhf IT moon ", "ngành IT môn "),
            ("ddang lamf BE sex ", "đang làm BE sẽ "),
            ("ddang lamf BE theem ", "đang làm BE thêm "),
            ("ddang lamf BE theme ", "đang làm BE theme "),
            ("team been USS ddang ", "team bên US đang "),
            ("team been USS sex ", "team bên US sẽ "),
            ("goij API xong ", "gọi API xong "),
            ("goij API sex ", "gọi API sẽ "),
            ("goij API theem ", "gọi API thêm "),
            ("goij API theme ", "gọi API theme "),
            // Symmetric English controls (P0.7 Section 1: `US` resolves directly as English in English context)
            ("living in the US is ", "living in the US is "),
            ("the new API rest ", "the new API rest "),
            ("working in IT theme ", "working in IT theme "),
            ("I will rest ", "I will rest "),
            ("It is rest ", "It is rest ")
        ]

        for (raw, expected) in bilateralPhrases {
            XCTAssertEqual(driveMac(raw, inlineBilingual: false), expected, "macOS commit failed for \(raw.debugDescription)")
            XCTAssertEqual(driveMac(raw, inlineBilingual: true), expected, "macOS inline failed for \(raw.debugDescription)")
            XCTAssertEqual(driveIOS(raw), expected, "iOS adapter failed for \(raw.debugDescription)")
        }
    }
}
