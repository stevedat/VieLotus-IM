import XCTest
@testable import VieLotusCore

/// Empirical characterization tests reproducing the Smart Bilingual auto-restore recovery trap
/// (`thêm → theme`, `bên → been`, `tủn → turn`) and pinning the architectural invariants and
/// Backspace counter-cases required before introducing any post-Space `UndoRecord` / `↩ Giữ “thêm”` UX.
final class AutoRestoreUndoCharacterizationTests: XCTestCase {

    private var previousSpellCheckerProvider: SpellCheckerProvider?

    override func setUp() {
        super.setUp()
        previousSpellCheckerProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = EmbeddedEnglishSpellChecker.shared
    }

    override func tearDown() {
        SmartBilingualDetector.spellCheckerProvider = previousSpellCheckerProvider
        previousSpellCheckerProvider = nil
        super.tearDown()
    }

    // MARK: - Minimal Host Simulators

    private struct MacHostBuffer {
        var text: String = ""

        mutating func applyUTF16Replace(backspaces: Int, replacement: String) {
            var units = Array(text.utf16)
            let removeCount = min(max(0, backspaces), units.count)
            if removeCount > 0 {
                units.removeLast(removeCount)
            }
            units.append(contentsOf: replacement.utf16)
            text = String(decoding: units, as: UTF16.self)
        }

        mutating func type(_ input: String, into session: InputSessionManager) -> [SessionAction] {
            var actions: [SessionAction] = []
            for ch in input {
                if session.isWordBoundary(ch) {
                    let act = session.commitWord(
                        smartBilingualEnabled: session.smartBilingualEnabled,
                        boundaryChar: ch
                    )
                    actions.append(act)
                    switch act {
                    case let .commit(bs, word, isOverride):
                        if isOverride {
                            applyUTF16Replace(backspaces: bs, replacement: word)
                        }
                    case let .replace(bs, word):
                        applyUTF16Replace(backspaces: bs, replacement: word)
                    default:
                        break
                    }
                    text.append(ch)
                } else {
                    let act = session.handleCharacter(ch)
                    actions.append(act)
                    switch act {
                    case let .replace(bs, word):
                        applyUTF16Replace(backspaces: bs, replacement: word)
                    case let .commit(bs, word, isOverride):
                        if isOverride {
                            applyUTF16Replace(backspaces: bs, replacement: word)
                        }
                    case .passThrough:
                        text.append(ch)
                    case .consumed, .reset:
                        break
                    }
                }
            }
            return actions
        }

        mutating func backspace(in session: InputSessionManager) -> SessionAction {
            let act = session.handleBackspace()
            switch act {
            case let .replace(bs, word):
                applyUTF16Replace(backspaces: bs, replacement: word)
            case .passThrough, .reset:
                if !text.isEmpty {
                    text.removeLast()
                }
            case .consumed, .commit:
                break
            }
            return act
        }
    }

    private final class MockUIKitProxy: TextDocumentProxyProtocol {
        var beforeCursor: String = ""
        var afterCursor: String = ""
        var selected: String? = nil

        var documentContextBeforeInput: String? { beforeCursor }
        var documentContextAfterInput: String? { afterCursor }
        var selectedText: String? { selected }

        func insertText(_ text: String) {
            selected = nil
            beforeCursor.append(text)
        }

        func deleteBackward() {
            if selected != nil {
                selected = nil
                return
            }
            if !beforeCursor.isEmpty {
                beforeCursor.removeLast()
            }
        }
    }

    private func makeMacSession(inlineBilingual: Bool) -> InputSessionManager {
        let session = InputSessionManager()
        session.clearContext()
        session.macroEnabled = false
        session.setInputMethod(.telex)
        session.setGrammarProfile(.senFlex)
        session.setSmartBilingualEnabled(true)
        session.inlineBilingualEnabled = inlineBilingual
        return session
    }

    private func makeUIKitAdapter() -> UIKitInputSessionAdapter {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.clearContext()
        adapter.session.macroEnabled = false
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        adapter.session.setSmartBilingualEnabled(true)
        return adapter
    }

    // MARK: - 1. macOS Commit-Mode Auto-Restore Trap & Provenance Capture

    func testMacCommitModeAutoRestoreLoopAndProvenanceCapture() {
        let session = makeMacSession(inlineBilingual: false)
        var host = MacHostBuffer()

        _ = host.type("working in IT ", into: session)
        XCTAssertEqual(host.text, "working in IT ")

        // Before Space, commit-mode displays the Vietnamese syllable "hể" for delayed-modifier collision "here"
        _ = host.type("here", into: session)
        XCTAssertEqual(host.text, "working in IT hể")

        // Pressing Space triggers Smart Bilingual override ("hể" -> "here")
        let spaceActions = host.type(" ", into: session)
        XCTAssertEqual(host.text, "working in IT here ")
        XCTAssertEqual(spaceActions.last, .commit(backspaces: 2, text: "here", isOverride: true))

        // Provenance captures both sides of the auto-restore decision
        let prov = session.lastCommittedProvenance
        XCTAssertEqual(prov.rawCandidate, "here")
        XCTAssertEqual(prov.vietnameseCandidate, "hể")
        XCTAssertEqual(prov.selectedCandidate, "here")
        XCTAssertEqual(prov.selectedKind, .rawLiteral)
        XCTAssertEqual(prov.explicitEscapeState, .none)

        // Recovery attempt 1: Backspace x2 ("here " -> "her") + retype "e " loops right back to "here "
        _ = host.backspace(in: session) // deletes trailing Space -> arms editCaretBack == 0
        XCTAssertEqual(host.text, "working in IT here")
        _ = host.backspace(in: session) // reopens committed word and deletes trailing 'e'
        XCTAssertEqual(host.text, "working in IT her")
        // Note empirical finding: post-commit handleBackspace() does not pop recentWords,
        // so session.context currently retains the committed "here" token.
        XCTAssertTrue(session.context.hasSuffix("here"), "Expected current context characterization: \(session.context)")

        _ = host.type("e ", into: session)
        XCTAssertEqual(
            host.text,
            "working in IT here ",
            "Retyping 'e ' after Backspace x2 currently re-triggers auto-restore to 'here '"
        )

        // Recovery attempt 2: Delete entire word (Backspace x5) and retype "here " also loops back to "here "
        for _ in 0..<5 {
            _ = host.backspace(in: session)
        }
        XCTAssertEqual(host.text, "working in IT ")
        _ = host.type("here ", into: session)
        XCTAssertEqual(host.text, "working in IT here ")

        // Recovery attempt 3: Pressing extra 'e' ("heree ") under SenFlex yields "hểe ", still NOT "hể ";
        // and for single-path collisions like "been" ("bên"), even adjacent-vowel Telex has NO alternative spelling!
        for _ in 0..<5 {
            _ = host.backspace(in: session)
        }
        _ = host.type("heree ", into: session)
        XCTAssertEqual(host.text, "working in IT hểe ")
        XCTAssertNotEqual(host.text, "working in IT hể ")

        let singlePathSession = makeMacSession(inlineBilingual: false)
        var singlePathHost = MacHostBuffer()
        _ = singlePathHost.type("he is been ", into: singlePathSession)
        XCTAssertEqual(singlePathHost.text, "he is been ")
        XCTAssertEqual(singlePathSession.lastCommittedProvenance.vietnameseCandidate, "bên")
        XCTAssertEqual(singlePathSession.lastCommittedProvenance.selectedCandidate, "been")
    }

    // MARK: - 2. Inline Bilingual & iOS UIKit Adapter: `isOverride == false` vs `lastCommittedProvenance`

    func testInlineBilingualAndUIKitAdapterRecordProvenanceEvenWhenCommitIsOverrideIsFalse() {
        // A. macOS Inline-Bilingual Session (`inlineBilingualEnabled = true`)
        let inlineSession = makeMacSession(inlineBilingual: true)
        var inlineHost = MacHostBuffer()

        _ = inlineHost.type("working in IT here", into: inlineSession)
        // Inline arbitration already flipped composingWord to "here" BEFORE Space!
        XCTAssertEqual(inlineHost.text, "working in IT here")
        XCTAssertEqual(inlineSession.composingWord, "here")

        let commitActions = inlineHost.type(" ", into: inlineSession)
        XCTAssertEqual(inlineHost.text, "working in IT here ")
        // CRITICAL FINDING FOR FUTURE UndoRecord DESIGN:
        // Because composingWord was already "here" inline, commitWord reports `isOverride == false`!
        // Therefore UndoRecord MUST inspect `lastCommittedProvenance`, never `isOverride` alone.
        XCTAssertEqual(commitActions.last, .commit(backspaces: 4, text: "here", isOverride: false))
        XCTAssertEqual(inlineSession.lastCommittedProvenance.vietnameseCandidate, "hể")
        XCTAssertEqual(inlineSession.lastCommittedProvenance.selectedCandidate, "here")
        XCTAssertEqual(inlineSession.lastCommittedProvenance.selectedKind, .rawLiteral)
        XCTAssertEqual(inlineSession.lastCommittedProvenance.explicitEscapeState, .none)

        // B. iOS UIKitInputSessionAdapter (`here`, `been`, and no-context `turn`)
        let adapter = makeUIKitAdapter()
        let proxy = MockUIKitProxy()

        for ch in "working in IT here " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.beforeCursor, "working in IT here ")
        XCTAssertEqual(adapter.session.lastCommittedProvenance.vietnameseCandidate, "hể")
        XCTAssertEqual(adapter.session.lastCommittedProvenance.selectedCandidate, "here")
        XCTAssertEqual(adapter.session.lastCommittedProvenance.selectedKind, .rawLiteral)

        // Backspace x2 + "e " on iOS also loops back to "here "
        adapter.handleBackspace(proxy: proxy)
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.beforeCursor, "working in IT her")
        adapter.handleCharacter("e", proxy: proxy)
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.beforeCursor, "working in IT here ")

        // `he is been ` (intending "bên")
        let beenAdapter = makeUIKitAdapter()
        let beenProxy = MockUIKitProxy()
        for ch in "he is been " {
            beenAdapter.handleCharacter(ch, proxy: beenProxy)
        }
        XCTAssertEqual(beenProxy.beforeCursor, "he is been ")
        XCTAssertEqual(beenAdapter.session.lastCommittedProvenance.vietnameseCandidate, "bên")
        XCTAssertEqual(beenAdapter.session.lastCommittedProvenance.selectedCandidate, "been")

        // No-context lexical restore `turn ` (non-existent VN syllable "tủn" -> "turn")
        let turnAdapter = makeUIKitAdapter()
        let turnProxy = MockUIKitProxy()
        for ch in "turn " {
            turnAdapter.handleCharacter(ch, proxy: turnProxy)
        }
        XCTAssertEqual(turnProxy.beforeCursor, "turn ")
        XCTAssertEqual(turnAdapter.session.lastCommittedProvenance.vietnameseCandidate, "tủn")
        XCTAssertEqual(turnAdapter.session.lastCommittedProvenance.selectedCandidate, "turn")
    }

    // MARK: - 3. Pre-Space Explicit Candidate Selection Works Today (Gap Is Specifically Post-Space)

    func testUIKitExplicitVietnameseCandidateCommitBeforeSpace() {
        let adapter = makeUIKitAdapter()
        let proxy = MockUIKitProxy()

        for ch in "working in IT here" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        // Inline display chose "here", while candidateProvenance preserves Vietnamese twin "hể"
        XCTAssertEqual(proxy.beforeCursor, "working in IT here")
        XCTAssertEqual(adapter.session.candidateProvenance.selectedCandidate, "here")
        XCTAssertEqual(adapter.session.candidateProvenance.vietnameseCandidate, "hể")

        // Tapping "hể" on the iOS candidate bar BEFORE Space commits "hể " cleanly
        adapter.commitCandidate("hể", proxy: proxy, trailingSpace: true)
        XCTAssertEqual(proxy.beforeCursor, "working in IT hể ")
    }

    // MARK: - 4. Counter-Cases Showing Why Unconditional "2nd Backspace = Undo" Is Unsafe as Default

    func testBackspaceCounterCasesPunctuationAndRapidDeletionRemainPredictable() {
        // Counter-case A: Typing "working in IT theme ", pressing Backspace once to remove Space,
        // and inserting "," MUST produce "working in IT theme,".
        do {
            let session = makeMacSession(inlineBilingual: false)
            var host = MacHostBuffer()
            _ = host.type("working in IT theme ", into: session)
            _ = host.backspace(in: session)
            _ = host.type(",", into: session)
            XCTAssertEqual(host.text, "working in IT theme,")

            let adapter = makeUIKitAdapter()
            let proxy = MockUIKitProxy()
            for ch in "working in IT theme " {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            adapter.handleBackspace(proxy: proxy)
            adapter.handleCharacter(",", proxy: proxy)
            XCTAssertEqual(proxy.beforeCursor, "working in IT theme,")
        }

        // Counter-case B: Pressing/holding Backspace 2..6 times after "working in IT theme "
        // must delete characters monotonically without unexpectedly mutating "theme" into "thêm".
        do {
            let adapter = makeUIKitAdapter()
            let proxy = MockUIKitProxy()
            for ch in "working in IT theme " {
                adapter.handleCharacter(ch, proxy: proxy)
            }

            let expectedSteps = [
                "working in IT theme",
                "working in IT them",
                "working in IT the",
                "working in IT th",
                "working in IT t",
                "working in IT "
            ]
            for expected in expectedSteps {
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.beforeCursor, expected)
            }
        }
    }

    // MARK: - 5. Live 3-Scenario Playground Drills End-to-End Verification (Telex & VNI)

    func testPlaygroundThreeScenarioDrillsMatchUIKitAdapterExactOutput() {
        let telexDrills: [(input: String, expected: String)] = [
            // Scenario 1: Tiếng Việt (Telex)
            ("truowngr", "trưởng"),
            ("rrung rrinh", "rủng rỉnh"),
            ("tooisz", "tôi"),
            ("canhff", "canhf"),
            // Scenario 2: Câu trộn Anh–Việt (Telex) & đối xứng từ tiếng Anh phổ biến có 'ee'/'oo'
            ("treen", "trên"),
            ("check status treen website", "check status trên website"),
            ("guiwr file update cho nhoms", "gửi file update cho nhóm"),
            ("window user restore", "window user restore"),
            ("check the green tree", "check the green tree"),
            ("I have been", "I have been"),
            ("in the room", "in the room"),
            // Scenario 3: Mã nguồn & URL
            ("github.com/user.vn", "github.com/user.vn"),
            ("/compact config.json", "/compact config.json"),
            ("npm run watch", "npm run watch")
        ]

        let providers: [(name: String, provider: SpellCheckerProvider)] = [
            ("EmbeddedEnglishSpellChecker", EmbeddedEnglishSpellChecker.shared),
            ("MacSpellChecker", MacSpellChecker())
        ]

        for (providerName, provider) in providers {
            SmartBilingualDetector.spellCheckerProvider = provider

            for drill in telexDrills {
                // 1. iOS UIKitInputSessionAdapter
                let adapter = makeUIKitAdapter()
                let proxy = MockUIKitProxy()
                for ch in drill.input {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(
                    proxy.beforeCursor,
                    drill.expected,
                    "[\(providerName) / UIKit] Telex drill \(drill.input.debugDescription) must produce \(drill.expected.debugDescription)"
                )

                // 2. macOS InputSessionManager (both commit-mode and inline-bilingual mode)
                for inlineMode in [false, true] {
                    let macSession = makeMacSession(inlineBilingual: inlineMode)
                    var macHost = MacHostBuffer()
                    _ = macHost.type(drill.input, into: macSession)
                    if macSession.isComposing {
                        let commitAct = macSession.commitWord(smartBilingualEnabled: macSession.smartBilingualEnabled)
                        if case let .commit(bs, word, isOverride) = commitAct, isOverride {
                            macHost.applyUTF16Replace(backspaces: bs, replacement: word)
                        }
                    }
                    XCTAssertEqual(
                        macHost.text,
                        drill.expected,
                        "[\(providerName) / macOS inline=\(inlineMode)] Telex drill \(drill.input.debugDescription) must produce \(drill.expected.debugDescription)"
                    )
                }
            }
        }

        let vniDrills: [(input: String, expected: String)] = [
            // Scenario 1: Tiếng Việt (VNI)
            ("truo7ng3", "trưởng"),
            ("vie65t nam", "việt nam"),
            ("to6i10", "tôi"),
            ("canh22", "canh2"),
            // Scenario 2: Câu trộn Anh–Việt (VNI)
            ("check status tre6n website", "check status trên website"),
            ("gu7i3 file update cho nhom1", "gửi file update cho nhóm")
        ]

        for drill in vniDrills {
            let adapter = makeUIKitAdapter()
            adapter.session.setInputMethod(.vni)
            let proxy = MockUIKitProxy()
            for ch in drill.input {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(
                proxy.beforeCursor,
                drill.expected,
                "VNI Playground drill \(drill.input.debugDescription) must produce \(drill.expected.debugDescription)"
            )
        }
    }
}
