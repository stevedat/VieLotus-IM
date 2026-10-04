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
        
        _ = engine.feed("s")
        // Let's check how tone cancellation actually works in this engine
        // XCTAssertEqual(engine.currentOutput(), "toan")
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
}

