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
        XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "coong", context: "the latest deployment", rendered: "công"))
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

        XCTAssertTrue(
            SmartBilingualDetector.isEnglishWord(raw: "tuyeern", context: "I saw this in the latest deployment", rendered: "tuyển")
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
        let examples = [
            ("superadmin", "supeadmỉn"),
            ("super", "sủpe"),
            ("clever", "clẻve"),
            ("detector", "detẻcto"),
            ("tractor", "trảcto"),
            ("center", "cẻnte"),
            ("advantages", "advantáge")
        ]

        for (raw, expectedRendered) in examples {
            let session = InputSessionManager()
            for character in raw {
                _ = session.handleCharacter(character)
            }
            XCTAssertEqual(session.currentOutput(), expectedRendered)
            guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
                return XCTFail("Expected \(raw) to commit")
            }
            XCTAssertTrue(isOverride)
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
        let session = InputSessionManager()
        for character in "ww" {
            _ = session.handleCharacter(character)
        }
        XCTAssertEqual(session.currentOutput(), "w")
        guard case let .commit(_, committed, isOverride) = session.commitWord(smartBilingualEnabled: true) else {
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
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
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
            ("last", "lát"),
            ("rest", "rét")
        ]
        for (raw, rendered) in testWords {
            XCTAssertTrue(
                SmartBilingualDetector.isEnglishWord(raw: raw, context: "", rendered: rendered),
                "English word '\(raw)' should be restored even without English context instead of remaining '\(rendered)'"
            )
        }
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
}



