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

        // Test transformed macro keys: "ddc" -> "đc" -> "được"
        session.macroEnabled = true
        _ = session.handleCharacter("d")
        _ = session.handleCharacter("d")
        _ = session.handleCharacter("c")
        let actionDdc = session.commitWord(smartBilingualEnabled: true)
        if case .commit(let backspaces, let text, let isOverride) = actionDdc {
            XCTAssertEqual(text, "được")
            XCTAssertEqual(backspaces, 2)
            XCTAssertTrue(isOverride)
        } else {
            XCTFail("Expected .commit action for ddc -> được, got \(actionDdc)")
        }

        // Test "sddt" -> "sđt" -> "số điện thoại"
        _ = session.handleCharacter("s")
        _ = session.handleCharacter("d")
        _ = session.handleCharacter("d")
        _ = session.handleCharacter("t")
        let actionSddt = session.commitWord(smartBilingualEnabled: true)
        if case .commit(let backspaces, let text, let isOverride) = actionSddt {
            XCTAssertEqual(text, "số điện thoại")
            XCTAssertEqual(backspaces, 3)
            XCTAssertTrue(isOverride)
        } else {
            XCTFail("Expected .commit action for sddt -> số điện thoại, got \(actionSddt)")
        }
    }

    func testMacroEntriesSortedList() {
        let engine = MacroEngine(initialMacros: [
            "hn": "Hà Nội",
            "sg": "Sài Gòn",
            "abc": "ABC Group"
        ])
        let entries = engine.getMacroEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].key, "abc")
        XCTAssertEqual(entries[0].value, "ABC Group")
        XCTAssertEqual(entries[1].key, "hn")
        XCTAssertEqual(entries[2].key, "sg")
    }

    func testSaveAndLoadDiskPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFileURL = tempDir.appendingPathComponent("macros.json")

        let engine1 = MacroEngine(initialMacros: [
            "hn": "Hà Nội",
            "sg": "Sài Gòn"
        ], storageURL: tempFileURL, autoSaveToDisk: false)

        try engine1.saveToDisk(url: tempFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        let engine2 = MacroEngine(initialMacros: [:], storageURL: tempFileURL, autoSaveToDisk: false)
        XCTAssertNil(engine2.lookup(word: "hn"))
        let loaded = engine2.loadFromDisk(url: tempFileURL)
        XCTAssertTrue(loaded)
        XCTAssertEqual(engine2.lookup(word: "hn"), "Hà Nội")
        XCTAssertEqual(engine2.lookup(word: "sg"), "Sài Gòn")
    }

    func testAutoSaveOnSetAndRemove() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFileURL = tempDir.appendingPathComponent("macros.json")

        let engine = MacroEngine(initialMacros: [:], storageURL: tempFileURL, autoSaveToDisk: true)
        engine.setMacro(key: "dn", value: "Đà Nẵng")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        let reader = MacroEngine(initialMacros: [:], storageURL: tempFileURL, autoSaveToDisk: false)
        XCTAssertTrue(reader.loadFromDisk())
        XCTAssertEqual(reader.lookup(word: "dn"), "Đà Nẵng")

        engine.removeMacro(key: "dn")
        XCTAssertTrue(reader.loadFromDisk())
        XCTAssertNil(reader.lookup(word: "dn"))
    }

    func testReloadFromDiskIfChanged() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFileURL = tempDir.appendingPathComponent("macros.json")

        let engine = MacroEngine(initialMacros: ["k1": "v1"], storageURL: tempFileURL, autoSaveToDisk: false)
        try engine.saveToDisk(url: tempFileURL)
        engine.loadFromDisk(url: tempFileURL)

        // No change yet
        XCTAssertFalse(engine.reloadFromDiskIfChanged(url: tempFileURL))

        // Modify the file externally
        Thread.sleep(forTimeInterval: 0.05)
        let modifiedJSON = "{\"k1\":\"v1_updated\",\"k2\":\"v2\"}".data(using: .utf8)!
        try modifiedJSON.write(to: tempFileURL, options: .atomic)

        // Now reload should detect mtime change and succeed
        XCTAssertTrue(engine.reloadFromDiskIfChanged(url: tempFileURL))
        XCTAssertEqual(engine.lookup(word: "k1"), "v1_updated")
        XCTAssertEqual(engine.lookup(word: "k2"), "v2")
    }

    func testImportJSONReplaceAll() throws {
        let engine = MacroEngine(initialMacros: [
            "old": "Old Word",
            "keep": "Keep Word"
        ])
        let newData = "{\"new\":\"New Word\"}".data(using: .utf8)!
        try engine.importJSON(data: newData, replaceAll: true)

        XCTAssertNil(engine.lookup(word: "old"))
        XCTAssertNil(engine.lookup(word: "keep"))
        XCTAssertEqual(engine.lookup(word: "new"), "New Word")
    }

    func testNotificationPostedOnMacroChange() {
        let expectation = expectation(description: "macrosDidChangeNotification posted")
        let token = NotificationCenter.default.addObserver(
            forName: MacroEngine.macrosDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let engine = MacroEngine(initialMacros: [:], autoSaveToDisk: false)
        engine.setMacro(key: "test", value: "Value")

        wait(for: [expectation], timeout: 1.0)
    }
}
