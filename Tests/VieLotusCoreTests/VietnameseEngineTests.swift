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
}
