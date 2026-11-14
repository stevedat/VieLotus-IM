import XCTest
@testable import VieLotusCore

final class MobileFastTypingTests: XCTestCase {
    private var previousProvider: SpellCheckerProvider?
    override func setUp() {
        previousProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()
    }
    override func tearDown() {
        SmartBilingualDetector.spellCheckerProvider = previousProvider
    }
    private func adapter() -> UIKitInputSessionAdapter {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setGrammarProfile(.senFlex)
        adapter.session.setGenZMode(true)
        adapter.session.setModernOrthography(true)
        adapter.smartBilingual = true
        adapter.session.macroEnabled = false
        XCTAssertTrue(adapter.session.inlineBilingualEnabled)
        return adapter
    }

    func testMobileConfigurationAgainstIndependentExpectedText() {
        for (raw, expected) in [
            ("apple meta cos ", "apple meta có "),
            ("apple meta cons ", "apple meta cón "),
            ("and cos ", "and có "),
            ("sin and cos ", "sin and cos "),
            ("pros and cons ", "pros and cons "),
            ("just ", "just "),
            ("sunworld ", "sunworld "),
            ("file.rar ", "file.rar "),
            ("coss ", "cos "),
            ("cos<ns ", "cón ")
        ] {
            let adapter = adapter()
            let proxy = MockTextDocumentProxy()
            for ch in raw {
                if ch == "<" { adapter.handleBackspace(proxy: proxy) }
                else { adapter.handleCharacter(ch, proxy: proxy) }
            }
            XCTAssertEqual(proxy.buffer, expected, raw)
        }
    }

    func testVietnameseReturnsAfterShortAndLongEnglishRuns() {
        let runs = ["apple meta", "please check the", "please check the update and review the document", "just sunworld", "the latest version of the application"]
        let words = [("cos", "có"), ("cons", "cón"), ("cosn", "cón"), ("laf", "là"), ("bans", "bán"), ("conf", "còn"),
                     ("tieengs", "tiếng"), ("vieetj", "việt"), ("dduwowcj", "được"), ("ddang", "đang")]
        for run in runs {
            for (raw, expected) in words {
                let adapter = adapter()
                let proxy = MockTextDocumentProxy()
                // Start with explicit Vietnamese, then several English words.
                for ch in "tooi ddang " + run + " " { adapter.handleCharacter(ch, proxy: proxy) }
                let prefix = proxy.buffer
                for ch in raw { adapter.handleCharacter(ch, proxy: proxy) }
                XCTAssertEqual(proxy.buffer, prefix + expected, "inline: \(run) / \(raw)")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, prefix + expected + " ", "commit: \(run) / \(raw)")
            }
        }
    }

    func testRepeatedAlternationKeepsEnglishWordsAndResumesVietnamese() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        var expectedDocument = ""
        for round in 1...12 {
            let raw = "tooi ddang " + String(repeating: "hello world software keyboard ", count: round) + "bans conf cos laf tieengs vieetj "
            for ch in raw { adapter.handleCharacter(ch, proxy: proxy) }
            expectedDocument += "tôi đang " + String(repeating: "hello world software keyboard ", count: round) + "bán còn có là tiếng việt "
            XCTAssertEqual(proxy.buffer, expectedDocument, "round=\(round)")
        }
    }

    func testGeneratedAlternationOrdersDoNotDependOnOneSentence() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        let english = ["coffee", "window", "computer", "project", "keyboard", "software", "garden", "hello", "world", "document", "review"]
        let vietnamese = [("cas", "cá"), ("taos", "táo"), ("mays", "máy"), ("tinhs", "tính"),
                          ("lamf", "làm"), ("vieecj", "việc"), ("dduwowcj", "được"), ("bans", "bán")]
        for key in "tooi " { adapter.handleCharacter(key, proxy: proxy) }
        var expected = "tôi "
        for round in 0..<24 {
            let run = (0..<((round * 7) % 17 + 1)).map { english[(round * 3 + $0 * 5) % english.count] }.joined(separator: " ") + " "
            for key in run { adapter.handleCharacter(key, proxy: proxy) }
            expected += run
            XCTAssertEqual(proxy.buffer, expected, "English run \(round)")
            let word = vietnamese[round % vietnamese.count]
            for key in word.0 { adapter.handleCharacter(key, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, expected + word.1, "Vietnamese return \(round)")
            adapter.handleCharacter(" ", proxy: proxy)
            expected += word.1 + " "
            XCTAssertEqual(proxy.buffer, expected)
        }
    }

    func testEnglishCollisionsRemainEnglishInsideMixedTyping() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        for ch in "tooi ddang best cost host list just pros and cons " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "tôi đang best cost host list just pros and cons ")
    }

    func testMixedEvidenceSurvivesLongEnglishRunButClearsWithContext() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        for ch in "tooi " + String(repeating: "hello world ", count: 40) + "bans " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertTrue(proxy.buffer.hasSuffix("bán "))
        adapter.session.clearContext()
        adapter.session.context = "please check the"
        adapter.session.reset()
        proxy.buffer = "please check the "
        for ch in "bans " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "please check the bans ")
    }

    func testMixedInputPreservesExplicitEscapeAndLiteralSelection() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        for ch in "tooi hello world coss " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "tôi hello world cos ")
        for ch in "bans" { adapter.handleCharacter(ch, proxy: proxy) }
        adapter.selectCompositionCandidate("bans", proxy: proxy)
        adapter.commitWord(proxy: proxy, suffix: " ")
        XCTAssertTrue(proxy.buffer.hasSuffix("bans "))
    }

    func testMobileToneIsDisplayedAtTheToneKeyWithoutWaitingForBoundary() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        for (key, expected) in zip("cos", ["c", "co", "có"]) {
            adapter.handleCharacter(key, proxy: proxy)
            XCTAssertEqual(proxy.buffer, expected)
        }
    }

    func testContinuousMobileLanguageSwitchesPreserveOrderAndOutput() {
        let adapter = adapter()
        let proxy = MockTextDocumentProxy()
        let raw = "apple meta cos just sunworld file.rar "
        let expected = "apple meta có just sunworld file.rar "
        for iteration in 1...30 {
            for ch in raw { adapter.handleCharacter(ch, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, String(repeating: expected, count: iteration))
        }
    }
}
