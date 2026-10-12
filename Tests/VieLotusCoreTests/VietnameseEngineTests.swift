import XCTest
@testable import VieLotusCore

final class VietnameseEngineTests: XCTestCase {
    func testTelexBasicTransform() {
        let engine = VietnameseEngine()
        engine.inputMethod = .telex
        
        let inputs = ["t", "o", "o", "i"]
        for char in inputs {
            _ = engine.feed(Character(char))
        }
        XCTAssertEqual(engine.currentOutput(), "tôi")
    }
    
    func testVniBasicTransform() {
        let engine = VietnameseEngine()
        engine.inputMethod = .vni
        
        let inputs = ["t", "o", "i", "6"]
        for char in inputs {
            _ = engine.feed(Character(char))
        }
        XCTAssertEqual(engine.currentOutput(), "tôi")
    }
    
    func testToneCancellation() {
        let engine = VietnameseEngine()
        engine.inputMethod = .telex
        
        let inputs = ["t", "o", "a", "n", "s"]
        for char in inputs { _ = engine.feed(Character(char)) }
        XCTAssertEqual(engine.currentOutput(), "toán")
        
        // Repeating the same tone key ('s') cancels the acute tone and restores the literal key ('toans')
        _ = engine.feed("s")
        XCTAssertEqual(engine.currentOutput(), "toans")

        // In Telex, typing 'z' cancels the active diacritic back to base ('toan')
        let engineZ = VietnameseEngine()
        engineZ.inputMethod = .telex
        for char in ["t", "o", "a", "n", "s", "z"] { _ = engineZ.feed(Character(char)) }
        XCTAssertEqual(engineZ.currentOutput(), "toan")
    }

    func testToneKeyCanAppearBeforeFinalConsonant() {
        for input in ["toost", "toots"] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), "tốt", input)
        }
    }

    func testFreeToneWProducesChuongInEitherPosition() {
        for input in ["chuongw", "chuowng"] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), "chương", input)
        }
    }

    func testTripleWAtWordStartIsLiteralWebPrefix() {
        for (input, expected) in [("w", "ư"), ("ww", "w"), ("www", "www"), ("wwww", "wwww")] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), expected, input)
        }
    }

    func testRepeatedToneKeysCanEscapeEnglishSAndR() {
        for (input, expected) in [("usserr", "user"), ("usserrss", "users")] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), expected, input)
        }
    }

    func testBackspaceRecomputesCompositionFromRemainingRawKeys() {
        let session = InputSessionManager()
        for character in "ddoois" {
            _ = session.handleCharacter(character)
        }
        XCTAssertEqual(session.currentOutput(), "đối")

        var outputs: [String] = []
        for _ in 0..<6 {
            _ = session.handleBackspace()
            outputs.append(session.currentOutput())
        }
        XCTAssertEqual(outputs, ["đôi", "đô", "đo", "đ", "d", ""])
    }

    func testBackspaceThatChangesNoVisibleTextKeepsCompositionActive() {
        let session = InputSessionManager()
        for character in "assz" {
            _ = session.handleCharacter(character)
        }
        XCTAssertEqual(session.currentOutput(), "as")

        let action = session.handleBackspace()
        guard case let .replace(backspaces, text) = action else {
            return XCTFail("Expected the consumed z key to be removed")
        }
        XCTAssertEqual(backspaces, 0)
        XCTAssertEqual(text, "")
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.rawWord, "ass")
        XCTAssertEqual(session.currentOutput(), "as")

        _ = session.handleBackspace()
        XCTAssertEqual(session.currentOutput(), "á")
    }

    func testWordCommitOnNewlineWithoutSpaceInInputSessionManager() {
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        for char in "vieejt" {
            _ = session.handleCharacter(char)
        }
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "việt")
        
        // Simulate Shift+Enter / Return (\n) boundary
        XCTAssertTrue(session.isWordBoundary("\n"))
        let action = session.commitWord(smartBilingualEnabled: true)
        guard case let .commit(_, text, isOverride) = action else {
            return XCTFail("Expected commit action on newline")
        }
        XCTAssertEqual(text, "việt")
        XCTAssertFalse(isOverride)
        XCTAssertFalse(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "")
    }

    func testEnglishWordRestoreOnNewlineWithoutSpace() {
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        for char in "there" {
            _ = session.handleCharacter(char)
        }
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "thẻe")
        
        // Simulate Shift+Enter / Return (\n) boundary
        XCTAssertTrue(session.isWordBoundary("\n"))
        let action = session.commitWord(smartBilingualEnabled: true)
        guard case let .commit(_, text, isOverride) = action else {
            return XCTFail("Expected commit action on newline")
        }
        XCTAssertEqual(text, "there")
        XCTAssertTrue(isOverride)
        XCTAssertFalse(session.isComposing)
    }

    func testVniWordCommitOnNewlineWithoutSpace() {
        let session = InputSessionManager()
        session.setInputMethod(.vni)
        for char in "viet65" {
            _ = session.handleCharacter(char)
        }
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "việt")
        
        XCTAssertTrue(session.isWordBoundary("\n"))
        let action = session.commitWord(smartBilingualEnabled: true)
        guard case let .commit(_, text, isOverride) = action else {
            return XCTFail("Expected commit action on newline")
        }
        XCTAssertEqual(text, "việt")
        XCTAssertFalse(isOverride)
        XCTAssertFalse(session.isComposing)
    }

    func testPartialDeletionPrefixRetentionAndResumeComposition() {
        // Test case 1: "đổi" deleted back to "đ", then typing "uocwj" -> "được"
        let engine1 = VietnameseEngine()
        engine1.setCompositionPrefix("đ")
        XCTAssertEqual(engine1.currentOutput(), "đ")
        for char in "uocwj" {
            _ = engine1.feed(char)
        }
        XCTAssertEqual(engine1.currentOutput(), "được")

        // Test case 2: "trường" deleted back to "tr", then typing "uowngr" -> "trưởng"
        let engine2 = VietnameseEngine()
        engine2.setCompositionPrefix("tr")
        XCTAssertEqual(engine2.currentOutput(), "tr")
        for char in "uowngr" {
            _ = engine2.feed(char)
        }
        XCTAssertEqual(engine2.currentOutput(), "trưởng")

        // Test case 3: "những" deleted back to "nh", then typing "unwg" -> "nhưng"
        let engine3 = VietnameseEngine()
        engine3.setCompositionPrefix("nh")
        XCTAssertEqual(engine3.currentOutput(), "nh")
        for char in "unwg" {
            _ = engine3.feed(char)
        }
        XCTAssertEqual(engine3.currentOutput(), "nhưng")

        // Test case 4: "thể" deleted back to "th", then typing "ieenf" -> "thiền"
        let engine4 = VietnameseEngine()
        engine4.setCompositionPrefix("th")
        XCTAssertEqual(engine4.currentOutput(), "th")
        for char in "ieenf" {
            _ = engine4.feed(char)
        }
        XCTAssertEqual(engine4.currentOutput(), "thiền")

        // Test case 5: "thụ" deleted back to "th", then typing "ungx" -> "thũng"
        let engine5 = VietnameseEngine()
        engine5.setCompositionPrefix("th")
        XCTAssertEqual(engine5.currentOutput(), "th")
        for char in "ungx" {
            _ = engine5.feed(char)
        }
        XCTAssertEqual(engine5.currentOutput(), "thũng")
    }

    func testRawKeysForVietnamesePrefixes() {
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "đ", inputMethod: .telex), "dd")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "đ", inputMethod: .vni), "d9")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "tr", inputMethod: .telex), "tr")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "nh", inputMethod: .telex), "nh")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "th", inputMethod: .telex), "th")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "toá", inputMethod: .telex), "toas")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "toá", inputMethod: .vni), "toa1")
    }
}

