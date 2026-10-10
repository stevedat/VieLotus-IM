import XCTest
@testable import VieLotusCore

final class MacroEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MacroEngine.shared.resetToDefaults()
        MacroEngine.shared.isEnabled = true
    }

    func testDefaultMacroLookups() {
        let engine = MacroEngine.shared
        XCTAssertEqual(engine.lookup(word: "vn"), "Việt Nam")
        XCTAssertEqual(engine.lookup(word: "sg"), "Sài Gòn")
        XCTAssertEqual(engine.lookup(word: "hn"), "Hà Nội")
        XCTAssertEqual(engine.lookup(word: "dc"), "được")
        XCTAssertEqual(engine.lookup(word: "ko"), "không")
        XCTAssertEqual(engine.lookup(word: "vs"), "với")
        XCTAssertEqual(engine.lookup(word: "ng"), "người")
    }

    func testCasePreservation() {
        let engine = MacroEngine.shared
        // All uppercase
        XCTAssertEqual(engine.lookup(word: "VN"), "VIỆT NAM")
        XCTAssertEqual(engine.lookup(word: "SG"), "SÀI GÒN")

        // Titlecase (Capital first letter)
        XCTAssertEqual(engine.lookup(word: "Vn"), "Việt Nam")
        XCTAssertEqual(engine.lookup(word: "Sg"), "Sài Gòn")

        // Lowercase
        XCTAssertEqual(engine.lookup(word: "vn"), "Việt Nam")
    }

    func testAddAndRemoveCustomMacro() {
        let engine = MacroEngine.shared
        XCTAssertNil(engine.lookup(word: "agl"))

        engine.setMacro(key: "agl", value: "Apple Global Logistics")
        XCTAssertEqual(engine.lookup(word: "agl"), "Apple Global Logistics")
        XCTAssertEqual(engine.lookup(word: "AGL"), "APPLE GLOBAL LOGISTICS")

        engine.removeMacro(key: "agl")
        XCTAssertNil(engine.lookup(word: "agl"))
    }

    func testDisabledMacroReturnsNil() {
        let engine = MacroEngine.shared
        XCTAssertNotNil(engine.lookup(word: "vn"))

        engine.isEnabled = false
        XCTAssertNil(engine.lookup(word: "vn"))
        XCTAssertNil(engine.lookup(word: "VN"))
    }

    func testJSONExportAndImport() throws {
        let engine = MacroEngine(initialMacros: [
            "t1": "Test One",
            "t2": "Test Two"
        ])

        let data = try engine.exportJSON()
        XCTAssertFalse(data.isEmpty)

        let newEngine = MacroEngine(initialMacros: [:])
        XCTAssertNil(newEngine.lookup(word: "t1"))

        try newEngine.importJSON(data: data)
        XCTAssertEqual(newEngine.lookup(word: "t1"), "Test One")
        XCTAssertEqual(newEngine.lookup(word: "t2"), "Test Two")
    }

    func testInputSessionManagerMacroCommit() {
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        session.macroEnabled = true

        // Type "v" "n"
        _ = session.handleCharacter("v")
        _ = session.handleCharacter("n")
        XCTAssertTrue(session.isComposing)

        // Commit word with macro enabled
        let action = session.commitWord(smartBilingualEnabled: true)
        if case .commit(let backspaces, let text, let isOverride) = action {
            XCTAssertEqual(text, "Việt Nam")
            XCTAssertEqual(backspaces, 2)
            XCTAssertTrue(isOverride)
        } else {
            XCTFail("Expected .commit action, got \(action)")
        }

        // Test uppercase "V" "N"
        _ = session.handleCharacter("V")
        _ = session.handleCharacter("N")
        let actionUpper = session.commitWord(smartBilingualEnabled: true)
        if case .commit(let backspaces, let text, let isOverride) = actionUpper {
            XCTAssertEqual(text, "VIỆT NAM")
            XCTAssertEqual(backspaces, 2)
            XCTAssertTrue(isOverride)
        } else {
            XCTFail("Expected .commit action, got \(actionUpper)")
        }

        // Test when macro disabled
        session.macroEnabled = false
        _ = session.handleCharacter("v")
        _ = session.handleCharacter("n")
        let actionDisabled = session.commitWord(smartBilingualEnabled: true)
        if case .commit(_, let text, _) = actionDisabled {
            XCTAssertEqual(text, "vn")
        } else {
            XCTFail("Expected .commit action, got \(actionDisabled)")
        }
    }
}
