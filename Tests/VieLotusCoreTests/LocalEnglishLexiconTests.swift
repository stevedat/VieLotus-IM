import XCTest
@testable import VieLotusCore

final class LocalEnglishLexiconTests: XCTestCase {
    func testBundledLexiconRecognizesEnglishAndRejectsTelexFragments() {
        let lexicon = LocalEnglishLexicon.shared
        XCTAssertTrue(lexicon.isLoaded, "SCOWL resource must be present in the product bundle")
        for word in ["apple", "just", "trust", "file"] {
            XCTAssertTrue(lexicon.contains(word), word)
        }
        for word in ["tiee", "vieetj", "dunwgf"] {
            XCTAssertFalse(lexicon.contains(word), word)
        }
    }

    private final class Proxy: TextDocumentProxyProtocol {
        var buffer = ""
        var documentContextBeforeInput: String? { buffer }
        var documentContextAfterInput: String? { nil }
        func insertText(_ text: String) { buffer += text }
        func deleteBackward() { if !buffer.isEmpty { buffer.removeLast() } }
    }

    func testOfflineProviderPreservesMobileBilingualPhrases() {
        let previous = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = previous }
        for (raw, expected) in [
            ("apple meta cos ", "apple meta có "),
            ("apple meta cons ", "apple meta cón "),
            ("apple meta laf ", "apple meta là "),
            ("just ", "just "),
            ("and cos ", "and có "),
            ("you and cos ", "you and có "),
            ("sin cos ", "sin cos "),
            ("pros cons ", "pros cons "),
            ("sunworld ", "sunworld "),
            ("Sunworld ", "Sunworld "),
            ("sunflower ", "sunflower "),
            ("sin and cos ", "sin and cos "),
            ("sin apple and cos ", "sin apple and có "),
            ("pros and cos ", "pros and có "),
            ("and cos(x) ", "and cos(x) "),
            ("apple meta sunworld ", "apple meta sunworld "),
            ("file.rar ", "file.rar "),
            ("file.rar next ", "file.rar next "),
            ("file.rar rar ", "file.rar rả "),
            ("rar ", "rả "),
            ("file.tar ", "file.tar "),
            ("file.zip ", "file.zip "),
            ("pros and cons ", "pros and cons "),
            ("convert it to rar file ", "convert it to rar file ")
        ] {
            let session = InputSessionManager()
            session.macroEnabled = false
            let adapter = UIKitInputSessionAdapter(session: session)
            adapter.smartBilingual = true
            let proxy = Proxy()
            for ch in raw { adapter.handleCharacter(ch, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, expected, raw)
        }
    }

    func testDotSuffixSurvivesSpaceDeletionAndRecommit() {
        let previous = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = previous }
        let session = InputSessionManager()
        session.macroEnabled = false
        let adapter = UIKitInputSessionAdapter(session: session)
        adapter.smartBilingual = true
        let proxy = Proxy()
        for ch in "file.rar " { adapter.handleCharacter(ch, proxy: proxy) }
        adapter.handleBackspace(proxy: proxy)
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "file.rar ")
    }

    func testLocalCompletionCorrectionAndCasing() {
        let lexicon = LocalEnglishLexicon.shared
        XCTAssertEqual(lexicon.candidates(for: "teh").first?.insertionText, "the")
        let candidates = lexicon.candidates(for: "Trus")
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.insertionText.hasPrefix("Trus") })
        XCTAssertLessThanOrEqual(candidates.count, 2)
        for word in ["có", "file.rar", "HTTP", "OpenAI", "", "a", String(repeating: "x", count: 33)] {
            XCTAssertTrue(lexicon.candidates(for: word).isEmpty)
        }
    }

    func testResolveVieLotusCoreSupportsPublicPackageBundleName() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VieLotusBundleResolve-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appResources = tempRoot
            .appendingPathComponent("VieLotusIM.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let bundleURL = appResources.appendingPathComponent("VieLotusIM_VieLotusCore.bundle", isDirectory: true)
        let bundleResources = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleResources, withIntermediateDirectories: true)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>org.vielotus.VieLotusCore.resources</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """
        try infoPlist.write(
            to: bundleURL.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        try "apple\njust\ntrust\n".write(
            to: bundleResources.appendingPathComponent("scowl-en.txt"),
            atomically: true,
            encoding: .utf8
        )

        let resolved = Bundle.resolveVieLotusCore(
            in: [appResources],
            fallbackBundles: [],
            sourceResourcesURL: nil
        )
        XCTAssertEqual(resolved.bundleURL.standardizedFileURL, bundleURL.standardizedFileURL)
        XCTAssertNotNil(resolved.url(forResource: "scowl-en", withExtension: "txt"))
    }
}
