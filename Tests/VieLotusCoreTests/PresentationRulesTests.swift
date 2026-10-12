import XCTest
@testable import VieLotusCore

/// Covers the data-driven per-app presentation rules (`typing-modes.yml`): parsing,
/// bundle-id matching, precedence against user choices and the built-in heuristic.
final class PresentationRulesTests: XCTestCase {

    override func tearDown() {
        ClientAdapter.setPresentationRules(.empty)
        super.tearDown()
    }

    // MARK: - Parsing

    func testParserHandlesCommentsBlankLinesAndTrailingComments() {
        let text = """
        # a whole-line comment
        \t
        com.apple.preview: directReplacement   # trailing comment
        com.example.app: markedText
        """
        let rules = PresentationRulesParser.parse(text).rules
        XCTAssertEqual(rules.map(\.key), ["com.apple.preview", "com.example.app"])
        XCTAssertEqual(rules.map(\.preference), [.directReplacement, .markedText])
    }

    func testParserLowercasesKeysAndAcceptsQuotedValues() {
        let rules = PresentationRulesParser.parse("Com.Microsoft.Excel: \"markedText\"").rules
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].key, "com.microsoft.excel")
        XCTAssertEqual(rules[0].preference, .markedText)
    }

    func testParserIgnoresMalformedLinesInsteadOfFailing() {
        // A hand-edited rule file must never be able to take the input method down.
        let text = """
        no-colon-here
        : markedText
        com.example.a: notAMode
        com.example.b: markedText
        """
        let rules = PresentationRulesParser.parse(text).rules
        XCTAssertEqual(rules.map(\.key), ["com.example.b"])
    }

    func testShippedRuleFileParsesToAnEmptyRuleSet() {
        // The repository ships no active rules on purpose: an active rule is only added
        // when the built-in heuristic is known to guess wrong for a specific app.
        // The file is located through VieLotusCore's own search paths, because
        // Bundle.module inside a test target resolves to the test bundle, not the library.
        let shipped = PresentationRulesLoader.searchPaths().filter { $0.path.contains("VieLotusIM_VieLotusCore.bundle") }
        guard let url = shipped.first ?? PresentationRulesLoader.searchPaths().last else {
            return XCTFail("typing-modes.yml is missing from every loader search path")
        }
        let text = try? String(contentsOf: url, encoding: .utf8)
        XCTAssertNotNil(text, "Could not read \(url.path)")
        XCTAssertTrue(PresentationRulesParser.parse(text ?? "").isEmpty,
                      "The shipped typing-modes.yml must not change behaviour for any app")
    }

    // MARK: - Matching

    func testMatcherSupportsExactSubstringPrefixAndSuffixKeys() {
        func matches(_ key: String, _ bundleID: String) -> Bool {
            PresentationRule(key: key, preference: .markedText).matches(bundleID.lowercased())
        }

        XCTAssertTrue(matches("com.apple.preview", "com.apple.preview"))
        XCTAssertFalse(matches("com.apple.preview", "com.apple.previewer"))

        XCTAssertTrue(matches("*ghostty*", "com.mitchellh.ghostty"))
        XCTAssertFalse(matches("*ghostty*", "com.apple.terminal"))

        XCTAssertTrue(matches("com.microsoft.*", "com.microsoft.excel"))
        XCTAssertFalse(matches("com.microsoft.*", "com.apple.excel"))

        XCTAssertTrue(matches("*.slack", "com.tinyspeck.slack"))
        XCTAssertFalse(matches("*.slack", "com.slack.extra"))
        XCTAssertTrue(matches("*.slack", "com.slack.enterprise.slack"))
        XCTAssertTrue(matches("com.*.terminal", "com.terminal.app.terminal"))
        XCTAssertTrue(matches("com.*.terminal", "com.apple.terminal"))
        XCTAssertFalse(matches("com.*.terminal", "com.apple.terminal.extra"))
    }

    func testFirstMatchingRuleWins() {
        let set = PresentationRulesParser.parse("""
        com.example.specific: passthrough
        com.example.*: markedText
        """)
        XCTAssertEqual(set.preference(forBundleIdentifier: "com.example.specific"), .passthrough)
        XCTAssertEqual(set.preference(forBundleIdentifier: "com.example.other"), .markedText)
    }

    func testEmptyRuleSetAndNilBundleIDReturnNoPreference() {
        XCTAssertNil(PresentationRuleSet.empty.preference(forBundleIdentifier: "com.apple.preview"))
        XCTAssertNil(PresentationRuleSet(rules: [
            PresentationRule(key: "*preview", preference: .markedText)
        ]).preference(forBundleIdentifier: nil))
    }

    // MARK: - Precedence inside ClientAdapter

    func testDataRuleOverridesBuiltInHeuristic() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.apple.terminal: markedText"))

        // The heuristic maps a terminal to .terminalDirect when that option is enabled;
        // the data rule must win over it.
        let mode = ClientAdapter.presentationMode(
            for: .terminal,
            bundleIdentifier: "com.apple.terminal",
            terminalDirectEnabled: true
        )
        XCTAssertEqual(mode, .markedText)
    }

    func testUserPerAppOverrideBeatsDataRule() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.example.app: markedText"))

        let mode = ClientAdapter.presentationMode(
            for: .standardAppKit,
            bundleIdentifier: "com.example.app",
            appOverrides: ["com.example.app": .passthrough]
        )
        XCTAssertEqual(mode, .passthrough)
    }

    func testGlobalPreferenceBeatsDataRule() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.example.app: markedText"))

        let mode = ClientAdapter.presentationMode(
            for: .standardAppKit,
            bundleIdentifier: "com.example.app",
            preference: .directReplacement
        )
        XCTAssertEqual(mode, .directReplacement)
    }

    func testAutomaticDataRuleFallsThroughToHeuristic() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.google.chrome: automatic"))

        let mode = ClientAdapter.presentationMode(
            for: .chromium,
            bundleIdentifier: "com.google.chrome"
        )
        XCTAssertEqual(mode, .markedText, "Chromium must still use marked text when the rule says automatic")
    }

    func testUnmatchedBundleIDStillUsesHeuristic() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.example.app: passthrough"))

        let mode = ClientAdapter.presentationMode(
            for: .standardAppKit,
            bundleIdentifier: "com.apple.TextEdit"
        )
        XCTAssertEqual(mode, .directReplacement)
    }

    // MARK: - Dynamic fallback interaction

    func testPinnedDataRuleDisablesDynamicMarkedTextFallback() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.example.pinned: directReplacement"))

        XCTAssertFalse(ClientAdapter.allowsDynamicMarkedTextFallback(
            bundleIdentifier: "com.example.pinned",
            preference: .automatic,
            appOverrides: [:]
        ))
        XCTAssertTrue(ClientAdapter.allowsDynamicMarkedTextFallback(
            bundleIdentifier: "com.example.unpinned",
            preference: .automatic,
            appOverrides: [:]
        ))
    }

    func testAutomaticDataRuleLeavesDynamicFallbackEnabled() {
        ClientAdapter.setPresentationRules(PresentationRulesParser.parse("com.example.app: automatic"))

        XCTAssertTrue(ClientAdapter.allowsDynamicMarkedTextFallback(
            bundleIdentifier: "com.example.app",
            preference: .automatic,
            appOverrides: [:]
        ))
    }

    // MARK: - Loader

    func testLoaderFindsTheShippedResourceAndReloadIsIdempotent() {
        XCTAssertFalse(PresentationRulesLoader.searchPaths().isEmpty)

        // Reloading must be stable. Which file wins depends on the machine — a user copy
        // in Application Support legitimately outranks the shipped one — so this asserts
        // determinism, not emptiness.
        let first = ClientAdapter.reloadPresentationRules()
        let second = ClientAdapter.reloadPresentationRules()
        XCTAssertEqual(first, second)
        XCTAssertEqual(ClientAdapter.presentationRules, second)
    }
}
