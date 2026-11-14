import XCTest
@testable import VieLotusCore

/// Golden Test Suite for **P0.6 — Preserve Explicit Telex Escape Across Subsequent Keys**.
///
/// Verifies that once an explicit Telex/VNI cancellation (`CancelToneAndEmitLiteral` or Classic Escape)
/// has been confirmed in a composition session:
/// 1. Physical keystrokes remain intact in `rawWord` (`rawLedger`, e.g. `"turrus"`).
/// 2. Semantic escape provenance (`toneSemanticEvent`, `explicitEscapeState`, `selectionReason`) survives
///    subsequent vowels, consonants, tone keys, bilingual arbitration, `Space`, `Backspace`, and post-commit reopen.
/// 3. Candidate arbitration never falls back to full raw replay (`"turrus"`) after a confirmed semantic cancellation,
///    while preserving real English words containing doubled consonants (`"cirrus"`, `"errors"`, `"passes"`, `"current"`).
/// 4. Generalized across all tone keys (`s/f/r/x/j`), variable tone-key positions / free-order Telex,
///    VNI cancellation (`tu33us -> tu3us`), and Classic Vowel/Horn/Stroke Escape (`caaas`, `tuwwus`, `dddus`)
///    in both macOS (`InputSessionManager`) and iOS (`UIKitInputSessionAdapter`) sessions.
final class PreserveExplicitTelexEscapeTests: XCTestCase {

    private final class MockProxy: TextDocumentProxyProtocol {
        var buffer: String = ""
        var documentContextBeforeInput: String? { buffer.isEmpty ? nil : buffer }
        var documentContextAfterInput: String? = nil

        func insertText(_ text: String) {
            buffer.append(text)
        }

        func deleteBackward() {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
        }
    }

    private var previousSpellCheckerProvider: (any SpellCheckerProvider)?

    override func setUp() {
        super.setUp()
        previousSpellCheckerProvider = SmartBilingualDetector.spellCheckerProvider
    }

    override func tearDown() {
        if let previousSpellCheckerProvider {
            SmartBilingualDetector.spellCheckerProvider = previousSpellCheckerProvider
        }
        previousSpellCheckerProvider = nil
        super.tearDown()
    }

    private func applyMacAction(_ action: SessionAction, key: Character?, to buffer: inout String) {
        switch action {
        case .replace(let bs, let txt):
            if bs > 0 && bs <= buffer.count {
                buffer.removeLast(bs)
            }
            buffer.append(txt)
        case .commit(let bs, let txt, _):
            if bs > 0 && bs <= buffer.count {
                buffer.removeLast(bs)
            }
            buffer.append(txt)
            if let key {
                buffer.append(key)
            }
        case .passThrough:
            if let key {
                buffer.append(key)
            } else if !buffer.isEmpty {
                buffer.removeLast()
            }
        case .reset:
            if key == nil && !buffer.isEmpty {
                buffer.removeLast()
            }
        case .consumed:
            break
        }
    }

    // MARK: - 1. Per-Key Golden Trace of `t u r r u s` (macOS & iOS)

    func testPerKeyTraceAndProvenanceOfTurrusAcrossProfilesAndPlatforms() {
        struct ExpectedStep {
            let key: Character
            let rawLedger: String
            let engineOutput: String
            let selectedCandidate: String
            let toneSemanticEvent: ToneModifierSemanticEvent?
            let explicitEscapeState: ExplicitEscapeKind
            let selectionReason: CandidateSelectionReason
            let hostOutput: String
        }

        let expectedSteps: [ExpectedStep] = [
            ExpectedStep(
                key: "t",
                rawLedger: "t",
                engineOutput: "t",
                selectedCandidate: "t",
                toneSemanticEvent: nil,
                explicitEscapeState: .none,
                selectionReason: .asciiPassThrough,
                hostOutput: "t"
            ),
            ExpectedStep(
                key: "u",
                rawLedger: "tu",
                engineOutput: "tu",
                selectedCandidate: "tu",
                toneSemanticEvent: nil,
                explicitEscapeState: .none,
                selectionReason: .asciiPassThrough,
                hostOutput: "tu"
            ),
            ExpectedStep(
                key: "r",
                rawLedger: "tur",
                engineOutput: "tủ",
                selectedCandidate: "tủ",
                toneSemanticEvent: .applyTone,
                explicitEscapeState: .none,
                selectionReason: .vietnameseComposition,
                hostOutput: "tủ"
            ),
            ExpectedStep(
                key: "r",
                rawLedger: "turr",
                engineOutput: "tur",
                selectedCandidate: "tur",
                toneSemanticEvent: .cancelToneAndEmitLiteral,
                explicitEscapeState: .semanticToneEscape,
                selectionReason: .explicitTelexEscape,
                hostOutput: "tur"
            ),
            ExpectedStep(
                key: "u",
                rawLedger: "turru",
                engineOutput: "turu",
                selectedCandidate: "turu",
                toneSemanticEvent: nil,
                explicitEscapeState: .semanticToneEscape,
                selectionReason: .explicitTelexEscape,
                hostOutput: "turu"
            ),
            ExpectedStep(
                key: "s",
                rawLedger: "turrus",
                engineOutput: "turus",
                selectedCandidate: "turus",
                toneSemanticEvent: nil,
                explicitEscapeState: .semanticToneEscape,
                selectionReason: .explicitTelexEscape,
                hostOutput: "turus"
            )
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for inlineBilingual in [false, true] {
                let macSession = InputSessionManager()
                macSession.setInputMethod(.telex)
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = inlineBilingual
                var macHost = ""

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setInputMethod(.telex)
                iosAdapter.session.setGrammarProfile(profile)
                iosAdapter.smartBilingual = true
                iosAdapter.session.inlineBilingualEnabled = inlineBilingual
                let iosProxy = MockProxy()

                for (idx, step) in expectedSteps.enumerated() {
                    let action = macSession.handleCharacter(step.key)
                    applyMacAction(action, key: step.key, to: &macHost)
                    iosAdapter.handleCharacter(step.key, proxy: iosProxy)

                    let prov = macSession.candidateProvenance
                    let ctx = "[profile=\(profile), inline=\(inlineBilingual), step=\(idx + 1) '\(step.key)']"
                    XCTAssertEqual(macSession.rawWord, step.rawLedger, "macOS rawLedger \(ctx)")
                    XCTAssertEqual(macSession.engine.currentOutput(), step.engineOutput, "macOS engineOutput \(ctx)")
                    XCTAssertEqual(prov.selectedCandidate, step.selectedCandidate, "macOS selectedCandidate \(ctx)")
                    XCTAssertEqual(prov.toneSemanticEvent, step.toneSemanticEvent, "macOS toneSemanticEvent \(ctx)")
                    XCTAssertEqual(prov.explicitEscapeState, step.explicitEscapeState, "macOS explicitEscapeState \(ctx)")
                    XCTAssertEqual(prov.selectionReason, step.selectionReason, "macOS selectionReason \(ctx)")
                    XCTAssertEqual(macHost, step.hostOutput, "macOS hostOutput \(ctx)")

                    let iosProv = iosAdapter.session.candidateProvenance
                    XCTAssertEqual(iosAdapter.session.rawWord, step.rawLedger, "iOS rawLedger \(ctx)")
                    XCTAssertEqual(iosProv.selectedCandidate, step.selectedCandidate, "iOS selectedCandidate \(ctx)")
                    XCTAssertEqual(iosProv.toneSemanticEvent, step.toneSemanticEvent, "iOS toneSemanticEvent \(ctx)")
                    XCTAssertEqual(iosProv.explicitEscapeState, step.explicitEscapeState, "iOS explicitEscapeState \(ctx)")
                    XCTAssertEqual(iosProv.selectionReason, step.selectionReason, "iOS selectionReason \(ctx)")
                    XCTAssertEqual(iosProxy.buffer, step.hostOutput, "iOS hostOutput \(ctx)")
                }

                // Commit via Space: must preserve `"turus "` and `.semanticToneEscape` in `lastCommittedProvenance`
                let commitAction = macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
                applyMacAction(commitAction, key: " ", to: &macHost)
                iosAdapter.handleCharacter(" ", proxy: iosProxy)

                XCTAssertEqual(macHost, "turus ", "macOS Space commit [profile=\(profile)]")
                XCTAssertEqual(iosProxy.buffer, "turus ", "iOS Space commit [profile=\(profile)]")
                XCTAssertEqual(macSession.lastCommittedProvenance.rawCandidate, "turrus")
                XCTAssertEqual(macSession.lastCommittedProvenance.selectedCandidate, "turus")
                XCTAssertEqual(macSession.lastCommittedProvenance.explicitEscapeState, .semanticToneEscape)
                XCTAssertEqual(macSession.lastCommittedProvenance.selectionReason, .explicitTelexEscape)
            }
        }
    }

    // MARK: - 2. Distinct Trajectory of `turus` (Single `r`, No Double `r`)

    func testSingleRTurusHasDistinctLedgerAndBehaviorFromDoubleRTurrus() {
        let macSession = InputSessionManager()
        macSession.setGrammarProfile(.senFlex)
        macSession.smartBilingualEnabled = true
        macSession.inlineBilingualEnabled = false
        var macHost = ""

        // t -> tu -> tủ -> tủu -> túu, then Space -> "turus " (raw restore of invalid VN syllable without escape)
        let inlineExpected: [(Character, String, String)] = [
            ("t", "t", "t"),
            ("u", "tu", "tu"),
            ("r", "tur", "tủ"),
            ("u", "turu", "tủu"),
            ("s", "turus", "túu")
        ]
        for (ch, expectedRaw, expectedHost) in inlineExpected {
            let act = macSession.handleCharacter(ch)
            applyMacAction(act, key: ch, to: &macHost)
            XCTAssertEqual(macSession.rawWord, expectedRaw)
            XCTAssertEqual(macHost, expectedHost)
            XCTAssertEqual(macSession.candidateProvenance.explicitEscapeState, .none)
        }

        let commitAct = macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
        applyMacAction(commitAct, key: " ", to: &macHost)
        XCTAssertEqual(macHost, "turus ")
        XCTAssertEqual(macSession.lastCommittedProvenance.rawCandidate, "turus")
        XCTAssertEqual(macSession.lastCommittedProvenance.explicitEscapeState, .none)
    }

    // MARK: - 3. Backspace & Post-Commit (`Space + Backspace`) Integrity on `turrus`

    func testTurrusBackspaceAndPostCommitReopenNeverReplayRawTurrus() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let macSession = InputSessionManager()
            macSession.setGrammarProfile(profile)
            macSession.smartBilingualEnabled = true
            macSession.inlineBilingualEnabled = true
            var macHost = ""

            let iosAdapter = UIKitInputSessionAdapter()
            iosAdapter.session.setGrammarProfile(profile)
            iosAdapter.smartBilingual = true
            let iosProxy = MockProxy()

            for ch in "turrus" {
                applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                iosAdapter.handleCharacter(ch, proxy: iosProxy)
            }
            XCTAssertEqual(macHost, "turus")
            XCTAssertEqual(iosProxy.buffer, "turus")

            // 1. In-composition Backspace steps back cleanly (`turus -> turu -> tur`) while preserving `.semanticToneEscape`
            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "turu")
            XCTAssertEqual(iosProxy.buffer, "turu")
            XCTAssertEqual(macSession.candidateProvenance.explicitEscapeState, .semanticToneEscape)

            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "tur")
            XCTAssertEqual(iosProxy.buffer, "tur")
            XCTAssertEqual(macSession.candidateProvenance.explicitEscapeState, .semanticToneEscape)

            // Re-typing `u`, `s` from `"tur"` must produce `"turu"` -> `"turus"` (never `"turrus"` or `"túru"`)
            for (ch, exp) in [(Character("u"), "turu"), (Character("s"), "turus")] {
                applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                iosAdapter.handleCharacter(ch, proxy: iosProxy)
                XCTAssertEqual(macHost, exp)
                XCTAssertEqual(iosProxy.buffer, exp)
                XCTAssertEqual(macSession.candidateProvenance.explicitEscapeState, .semanticToneEscape)
            }

            // 2. `turrus + Space + Backspace` (deletes trailing space -> `"turus"`), then another Backspace (`"turu"`), then `s` (`"turus"`)
            applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
            iosAdapter.handleCharacter(" ", proxy: iosProxy)
            XCTAssertEqual(macHost, "turus ")
            XCTAssertEqual(iosProxy.buffer, "turus ")

            // First Backspace removes trailing Space; screen stays `"turus"`, never `"turrus"`
            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "turus")
            XCTAssertEqual(iosProxy.buffer, "turus")

            // Second Backspace steps into `"turu"` (preserving escaped ledger `"turru"`), and typing `'s'` yields `"turus"`
            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "turu")
            XCTAssertEqual(iosProxy.buffer, "turu")
            XCTAssertEqual(macSession.candidateProvenance.explicitEscapeState, .semanticToneEscape)

            applyMacAction(macSession.handleCharacter("s"), key: "s", to: &macHost)
            iosAdapter.handleCharacter("s", proxy: iosProxy)
            XCTAssertEqual(macHost, "turus")
            XCTAssertEqual(iosProxy.buffer, "turus")
            XCTAssertFalse(macHost.contains("turrus"))
            XCTAssertFalse(iosProxy.buffer.contains("turrus"))
        }
    }

    // MARK: - 4. `turr` Followed by Further Tone Keys (`turrs`, `turrf`, `turrx`, `turrj`, `turrz`)

    func testTurrFollowedByAnotherToneKeyRemainsLiteralAfterEscape() {
        let cases: [(raw: String, expected: String)] = [
            ("tur", "tủ"),
            ("turr", "tur"),
            ("turrs", "turs"),
            ("turrf", "turf"),
            ("turrx", "turx"),
            ("turrj", "turj"),
            ("turrz", "turz")
        ]
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for tc in cases {
                let s = InputSessionManager()
                s.setGrammarProfile(profile)
                s.smartBilingualEnabled = true
                s.inlineBilingualEnabled = true
                var host = ""
                for ch in tc.raw {
                    applyMacAction(s.handleCharacter(ch), key: ch, to: &host)
                }
                XCTAssertEqual(host, tc.expected, "Inline '\(tc.raw)' [profile=\(profile)]")
                applyMacAction(s.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &host)
                XCTAssertEqual(host, tc.expected + " ", "Committed '\(tc.raw)' [profile=\(profile)]")
            }
        }
    }

    // MARK: - 5. Generalization Across All Tone Keys (`s/f/r/x/j`), Free-Order Telex, VNI & Classic Escape

    func testGeneralizedEscapePreservationAcrossAllToneKeysFreeOrderVNIAndClassicEscape() {
        let telexEscapeCases: [(raw: String, expected: String)] = [
            // All 5 tone keys on open plain-vowel stems + vowel + tone key
            ("tussus", "tusus"),
            ("tuffus", "tufus"),
            ("turrus", "turus"),
            ("tuxxus", "tuxus"),
            ("tujjus", "tujus"),
            // Single-vowel open stems
            ("arrus", "arus"),
            ("ussus", "usus"),
            // Open diphthong & free-order Telex tone cancellation
            ("tairrus", "tairus"),
            ("tarirus", "tairus"),
            // Closed-coda contiguous & free-order Telex tone cancellation (including multi-vowel continuation)
            ("canhffus", "canhfus"),
            ("cafnhfus", "canhfus"),
            ("canhffuas", "canhfuas"),
            ("hoongffus", "hôngfus"),
            ("hoonfgfus", "hôngfus"),
            // Classic triple-vowel, double-horn (single & compound vowel clusters), and triple-stroke escapes followed by vowel + tone key
            ("caaas", "caas"),
            ("caaaos", "caaos"),
            ("teeeus", "teeus"),
            ("tooous", "toous"),
            ("tuwwus", "tuwus"),
            ("tawwus", "tawus"),
            ("towwus", "towus"),
            ("tuoww", "tuow"),
            ("tuowwus", "tuowus"),
            ("uoww", "uow"),
            ("uowwus", "uowus"),
            ("muaww", "muaw"),
            ("muawwus", "muawus"),
            ("uaww", "uaw"),
            ("cuuww", "cuuw"),
            ("cuuwwus", "cuuwus"),
            ("hoaww", "hoaw"),
            ("hoawwus", "hoawus"),
            ("huouww", "huouw"),
            ("huouwwus", "huouwus"),
            ("dddus", "ddus"),
            // Uppercase / mixed-case preservation
            ("Turrus", "Turus"),
            ("TURRUS", "TURUS"),
            ("TuRRuS", "TuRuS"),
            ("CANHFFUS", "CANHFUS"),
            ("Tuowwus", "Tuowus"),
            ("TUOWWUS", "TUOWUS")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for tc in telexEscapeCases {
                let macSession = InputSessionManager()
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macHost = ""

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setGrammarProfile(profile)
                iosAdapter.smartBilingual = true
                let iosProxy = MockProxy()

                for ch in tc.raw {
                    applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                    iosAdapter.handleCharacter(ch, proxy: iosProxy)
                }
                XCTAssertEqual(macHost, tc.expected, "macOS inline '\(tc.raw)' [profile=\(profile)]")
                XCTAssertEqual(iosProxy.buffer, tc.expected, "iOS inline '\(tc.raw)' [profile=\(profile)]")
                XCTAssertEqual(macSession.rawWord, tc.raw, "rawLedger must keep all physical keys for '\(tc.raw)'")
                XCTAssertNotEqual(macSession.candidateProvenance.explicitEscapeState, .none, "Escape state must survive for '\(tc.raw)'")

                applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
                iosAdapter.handleCharacter(" ", proxy: iosProxy)
                XCTAssertEqual(macHost, tc.expected + " ", "macOS commit '\(tc.raw)' [profile=\(profile)]")
                XCTAssertEqual(iosProxy.buffer, tc.expected + " ", "iOS commit '\(tc.raw)' [profile=\(profile)]")
            }
        }

        // VNI cancellation generalization: `tu33us -> tu3us`, `ca11us -> ca1us`, `to66us -> to6us`, `tu77us -> tu7us`
        let vniEscapeCases: [(raw: String, expected: String)] = [
            ("tu33us", "tu3us"),
            ("tu33u1", "tu3u1"),
            ("ca11us", "ca1us"),
            ("to66u1", "to6u1"),
            ("tu77u1", "tu7u1")
        ]
        for tc in vniEscapeCases {
            let vniSession = InputSessionManager()
            vniSession.setInputMethod(.vni)
            vniSession.smartBilingualEnabled = true
            vniSession.inlineBilingualEnabled = true
            var host = ""
            for ch in tc.raw {
                applyMacAction(vniSession.handleCharacter(ch), key: ch, to: &host)
            }
            XCTAssertEqual(host, tc.expected, "VNI inline '\(tc.raw)'")
            XCTAssertEqual(vniSession.rawWord, tc.raw, "VNI rawLedger must retain all physical keys for '\(tc.raw)'")
            applyMacAction(vniSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &host)
            XCTAssertEqual(host, tc.expected + " ", "VNI commit '\(tc.raw)'")
        }

        // Real English words with doubled consonants (`rr`, `ss`, `ff`) and acronyms (`usps`) must STILL restore to English under both Embedded & macOS spell-checkers!
        let englishWords = ["cirrus", "errors", "terrors", "mirrors", "passes", "current", "office", "coffee", "buffer", "offsetof", "usps", "USPS"]
        var providers: [any SpellCheckerProvider] = [EmbeddedEnglishSpellChecker.shared]
        #if os(macOS)
        providers.append(MacSpellChecker())
        #endif
        for provider in providers {
            SmartBilingualDetector.spellCheckerProvider = provider
            for word in englishWords {
                let s = InputSessionManager()
                s.setGrammarProfile(.senFlex)
                s.smartBilingualEnabled = true
                s.inlineBilingualEnabled = true
                var host = ""
                for ch in word {
                    applyMacAction(s.handleCharacter(ch), key: ch, to: &host)
                }
                applyMacAction(s.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &host)
                XCTAssertEqual(host, word + " ", "Real English word '\(word)' must still restore to raw English")
            }
        }
    }

    // MARK: - 6. Independent Test Case for `trươngfu` / `trườngu` (Separated from `tủ -> turus`)

    func testIndependentTruongFuAndTruongFFuCases() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // 1. `truowngffu`: repeated `f` cancels Huyền tone and emits literal `f` -> `"trươngfu"`
            let sEscaped = InputSessionManager()
            sEscaped.setGrammarProfile(profile)
            sEscaped.smartBilingualEnabled = true
            var hostEscaped = ""
            for ch in "truowngffu" {
                applyMacAction(sEscaped.handleCharacter(ch), key: ch, to: &hostEscaped)
            }
            XCTAssertEqual(hostEscaped, "trươngfu")
            applyMacAction(sEscaped.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &hostEscaped)
            XCTAssertEqual(hostEscaped, "trươngfu ")

            // 2. `truowngfu`: single `f` keeps `"trường"` and overflows `'u'` literally -> `"trườngu"`
            let sOverflow = InputSessionManager()
            sOverflow.setGrammarProfile(profile)
            sOverflow.smartBilingualEnabled = true
            var hostOverflow = ""
            for ch in "truowngfu" {
                applyMacAction(sOverflow.handleCharacter(ch), key: ch, to: &hostOverflow)
            }
            XCTAssertEqual(hostOverflow, "trườngu")
            applyMacAction(sOverflow.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &hostOverflow)
            XCTAssertEqual(hostOverflow, "trườngu ")
        }
    }

    // MARK: - 7. Compound Horn Escape (`tuowwus`, `uowwus`, `muawwus`) Step-by-Step, Backspace & Post-Commit Reopen

    func testCompoundHornEscapeStepByStepBackspaceAndPostCommitReopen() {
        let traceSteps: [(key: Character, expectedRaw: String, expectedScreen: String)] = [
            ("t", "t", "t"),
            ("u", "tu", "tu"),
            ("o", "tuo", "tuo"),
            ("w", "tuow", "tươ"),
            ("w", "tuoww", "tuow"),
            ("u", "tuowwu", "tuowu"),
            ("s", "tuowwus", "tuowus")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let macSession = InputSessionManager()
            macSession.setGrammarProfile(profile)
            macSession.smartBilingualEnabled = true
            macSession.inlineBilingualEnabled = true
            var macHost = ""

            let iosAdapter = UIKitInputSessionAdapter()
            iosAdapter.session.setGrammarProfile(profile)
            iosAdapter.smartBilingual = true
            let iosProxy = MockProxy()

            for step in traceSteps {
                applyMacAction(macSession.handleCharacter(step.key), key: step.key, to: &macHost)
                iosAdapter.handleCharacter(step.key, proxy: iosProxy)
                XCTAssertEqual(macSession.rawWord, step.expectedRaw, "rawWord mismatch at '\(step.key)' [profile=\(profile)]")
                XCTAssertEqual(macHost, step.expectedScreen, "macOS screen mismatch at '\(step.key)' [profile=\(profile)]")
                XCTAssertEqual(iosProxy.buffer, step.expectedScreen, "iOS screen mismatch at '\(step.key)' [profile=\(profile)]")
            }

            // In-composition Backspace: `tuowus -> tuowu -> tuow`, then re-type `u`, `s` -> `tuowus`
            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "tuowu")
            XCTAssertEqual(iosProxy.buffer, "tuowu")

            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "tuow")
            XCTAssertEqual(iosProxy.buffer, "tuow")

            for (ch, exp) in [(Character("u"), "tuowu"), (Character("s"), "tuowus")] {
                applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                iosAdapter.handleCharacter(ch, proxy: iosProxy)
                XCTAssertEqual(macHost, exp)
                XCTAssertEqual(iosProxy.buffer, exp)
            }

            // Space commit + Backspace reopen + Backspace + `'s'` -> must stay `"tuowus"`, never `"tuowwus"`
            applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
            iosAdapter.handleCharacter(" ", proxy: iosProxy)
            XCTAssertEqual(macHost, "tuowus ")
            XCTAssertEqual(iosProxy.buffer, "tuowus ")

            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "tuowus")
            XCTAssertEqual(iosProxy.buffer, "tuowus")

            applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
            iosAdapter.handleBackspace(proxy: iosProxy)
            XCTAssertEqual(macHost, "tuowu")
            XCTAssertEqual(iosProxy.buffer, "tuowu")

            applyMacAction(macSession.handleCharacter("s"), key: "s", to: &macHost)
            iosAdapter.handleCharacter("s", proxy: iosProxy)
            XCTAssertEqual(macHost, "tuowus")
            XCTAssertEqual(iosProxy.buffer, "tuowus")
        }
    }

    // MARK: - 7. Open/Offglide Toned Vietnamese Same-Base-Vowel Extension (`tủ → tủu`)

    func testOpenSyllableSameVowelExtensionFourScenarioMatrixAndParity() {
        // 1. Verify all 4 scenarios in VieLotusLab's TelexComparisonSimulator match Apple Telex 100%
        let rows = TelexComparisonSimulator.buildFourScenarioMatrix(
            baseRawWord: "tur",
            extraKey: "u",
            simulateAppleAutocorrect: false
        )
        XCTAssertEqual(rows.count, 4)
        let expectedFinals = ["tủu", "tủu ", "tủu", "tủu "]
        let expectedChains = [
            ["t", "tu", "tủ", "tủu"],
            ["t", "tu", "tủ", "tủu", "tủu "],
            ["t", "tu", "tủ", "tủ ", "tủ", "tủu"],
            ["t", "tu", "tủ", "tủ ", "tủ", "tủu", "tủu "]
        ]
        for idx in 0..<4 {
            XCTAssertEqual(rows[idx].appleTelexOutput, expectedFinals[idx], "Apple final mismatch at row \(idx + 1)")
            XCTAssertEqual(rows[idx].vieLotusOutput, expectedFinals[idx], "Sen Việt final mismatch at row \(idx + 1)")
            XCTAssertEqual(rows[idx].steps.map(\.appleTelexOutput), expectedChains[idx], "Apple chain mismatch at row \(idx + 1)")
            XCTAssertEqual(rows[idx].steps.map(\.vieLotusOutput), expectedChains[idx], "Sen Việt chain mismatch at row \(idx + 1)")
            XCTAssertEqual(rows[idx].deltaKind, .identical, "Row \(idx + 1) must match Apple Telex 100%")
        }

        // 2. Verify macOS (InputSessionManager) & iOS (UIKitInputSessionAdapter) across all grammar profiles
        let vnExtensionCases: [(raw: String, expectedCommitted: String)] = [
            ("turu", "tủu "),
            ("turuu", "tủuu "),
            ("nguru", "ngủu "),
            ("gifi", "gìi "),
            ("ddiri", "đỉi "),
            ("chiji", "chịi "),
            ("kyfy", "kỳy "),
            ("maisi", "máii "),
            ("trowfii", "trờii "),
            ("cuwsuu", "cứuu ")
        ]
        let englishRestoreCases: [(raw: String, expectedCommitted: String)] = [
            ("guru", "guru "),
            ("cheese", "cheese "),
            ("fiji", "fiji "),
            ("ascii", "ascii "),
            ("wifi", "wifi "),
            ("kijiji", "kijiji "),
            ("visit", "visit "),
            ("visits", "visits ")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // 2a. In-composition Backspace on `t u r u`: `tủu -> tủ -> tu -> t`
            do {
                let macSession = InputSessionManager()
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macHost = ""

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setGrammarProfile(profile)
                iosAdapter.smartBilingual = true
                let iosProxy = MockProxy()

                for (ch, exp) in [(Character("t"), "t"), (Character("u"), "tu"), (Character("r"), "tủ"), (Character("u"), "tủu")] {
                    applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                    iosAdapter.handleCharacter(ch, proxy: iosProxy)
                    XCTAssertEqual(macHost, exp, "macOS inline mismatch for '\(ch)' [profile=\(profile)]")
                    XCTAssertEqual(iosProxy.buffer, exp, "iOS inline mismatch for '\(ch)' [profile=\(profile)]")
                }

                for expAfterBs in ["tủ", "tu", "t", ""] {
                    applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
                    iosAdapter.handleBackspace(proxy: iosProxy)
                    XCTAssertEqual(macHost, expAfterBs, "macOS backspace mismatch [profile=\(profile)]")
                    XCTAssertEqual(iosProxy.buffer, expAfterBs, "iOS backspace mismatch [profile=\(profile)]")
                }
            }

            // 2b. Scenarios 3 & 4 (`t u r ␣ ⌫ u ␣` -> `tủu `)
            do {
                let macSession = InputSessionManager()
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macHost = ""

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setGrammarProfile(profile)
                iosAdapter.smartBilingual = true
                let iosProxy = MockProxy()

                for ch in "tur" {
                    applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                    iosAdapter.handleCharacter(ch, proxy: iosProxy)
                }
                applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
                iosAdapter.handleCharacter(" ", proxy: iosProxy)
                XCTAssertEqual(macHost, "tủ ")
                XCTAssertEqual(iosProxy.buffer, "tủ ")

                applyMacAction(macSession.handleBackspace(), key: nil, to: &macHost)
                iosAdapter.handleBackspace(proxy: iosProxy)
                XCTAssertEqual(macHost, "tủ")
                XCTAssertEqual(iosProxy.buffer, "tủ")

                applyMacAction(macSession.handleCharacter("u"), key: "u", to: &macHost)
                iosAdapter.handleCharacter("u", proxy: iosProxy)
                XCTAssertEqual(macHost, "tủu")
                XCTAssertEqual(iosProxy.buffer, "tủu")

                applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
                iosAdapter.handleCharacter(" ", proxy: iosProxy)
                XCTAssertEqual(macHost, "tủu ")
                XCTAssertEqual(iosProxy.buffer, "tủu ")
            }

            // 2c. Vietnamese open/offglide vowel lengthening preservation
            for tc in vnExtensionCases {
                let macSession = InputSessionManager()
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macHost = ""

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setGrammarProfile(profile)
                iosAdapter.smartBilingual = true
                let iosProxy = MockProxy()

                for ch in tc.raw {
                    applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                    iosAdapter.handleCharacter(ch, proxy: iosProxy)
                }
                applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
                iosAdapter.handleCharacter(" ", proxy: iosProxy)

                XCTAssertEqual(macHost, tc.expectedCommitted, "macOS VN vowel extension mismatch for '\(tc.raw)' [profile=\(profile)]")
                XCTAssertEqual(iosProxy.buffer, tc.expectedCommitted, "iOS VN vowel extension mismatch for '\(tc.raw)' [profile=\(profile)]")
            }

            // 2d. Real English words must still restore raw cleanly
            for tc in englishRestoreCases {
                let macSession = InputSessionManager()
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macHost = ""

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setGrammarProfile(profile)
                iosAdapter.smartBilingual = true
                let iosProxy = MockProxy()

                for ch in tc.raw {
                    applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                    iosAdapter.handleCharacter(ch, proxy: iosProxy)
                }
                applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " "), key: " ", to: &macHost)
                iosAdapter.handleCharacter(" ", proxy: iosProxy)

                XCTAssertEqual(macHost, tc.expectedCommitted, "macOS English restore mismatch for '\(tc.raw)' [profile=\(profile)]")
                XCTAssertEqual(iosProxy.buffer, tc.expectedCommitted, "iOS English restore mismatch for '\(tc.raw)' [profile=\(profile)]")
            }
        }
    }

    func testDoubledKeyProvenanceContractAndDeltaMatrix() {
        let prevProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = prevProvider }

        let prevMacro = MacroEngine.shared.isEnabled
        MacroEngine.shared.isEnabled = false
        defer { MacroEngine.shared.isEnabled = prevMacro }

        func driveClause(
            _ rawClause: String,
            genZMode: Bool = false,
            simpleTelex: Bool = true
        ) -> String {
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(.senFlex)
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true
            session.setGenZMode(genZMode)
            session.setSimpleTelex(simpleTelex)
            var buffer = ""
            for ch in rawClause {
                if session.isWordBoundary(ch) {
                    applyMacAction(
                        session.commitWord(smartBilingualEnabled: true, genZMode: genZMode, boundaryChar: ch),
                        key: ch,
                        to: &buffer
                    )
                } else {
                    applyMacAction(session.handleCharacter(ch), key: ch, to: &buffer)
                }
            }
            if session.isComposing {
                applyMacAction(
                    session.commitWord(smartBilingualEnabled: true, genZMode: genZMode, boundaryChar: nil),
                    key: nil,
                    to: &buffer
                )
            }
            return buffer
        }

        // 1. Doubled-Key Provenance Contract:
        //    - Explicit Telex escape from Vietnamese (`mĩ + x -> mix`, `tủ + r + u + s -> turus`, standalone `ẻ + r -> er`)
        //    - Intentional doubled key when English is already provisional in English context (`the mixx -> the mixx`, `to err -> to err`)
        //    - Code identifiers with underscores (`foo_barr`, `my_varr`)
        //    - English dictionary words with doubled consonants (`terrible`, `boss`, `less`, `cirrus`, `ASUS`)
        XCTAssertEqual(driveClause("mixx "), "mix ")
        XCTAssertEqual(driveClause("turrus "), "turus ")
        XCTAssertEqual(driveClause("err "), "er ")
        XCTAssertEqual(driveClause("the mixx "), "the mixx ")
        XCTAssertEqual(driveClause("to err "), "to err ")
        XCTAssertEqual(driveClause("foo_barr "), "foo_barr ")
        XCTAssertEqual(driveClause("my_varr "), "my_varr ")
        XCTAssertEqual(driveClause("terrible boss less cirrus ASUS "), "terrible boss less cirrus ASUS ")

        // 2. Teencode & Z/W/F/J Delta Matrix (`genZMode = true` vs English `zero`, `zoom`, `zone`):
        XCTAssertEqual(driveClause("zaayj dzoo zui zer goif thiks uwfk ", genZMode: true), "zậy dzô zui zẻ gòi thík ừk ")
        XCTAssertEqual(driveClause("zero zoom zone ", genZMode: true), "zero zoom zone ")

        // 3. Digit-Prefixed Vietnamese & Technical Unit Delta Matrix (`simpleTelex = true` and `false`):
        for simple in [true, false] {
            XCTAssertEqual(
                driveClause("5trawm 100tyr 4tuooir 1cais 65w 100W ", simpleTelex: simple),
                "5trăm 100tỷ 4tuổi 1cái 65w 100W ",
                "Digit-prefixed delta matrix failed for simpleTelex=\(simple)"
            )
        }

        // 4. Capitalized `DD` Delta Matrix (`DDaf Nawngx -> Đà Nẵng`, `DDR -> ĐR`, `ddr -> ddr`, `DDoS -> DDoS`, `ddos -> đó`):
        XCTAssertEqual(driveClause("DDaf Nawngx "), "Đà Nẵng ")
        XCTAssertEqual(driveClause("DDR "), "ĐR ")
        XCTAssertEqual(driveClause("ddr "), "ddr ")
        XCTAssertEqual(driveClause("DDoS "), "DDoS ")
        XCTAssertEqual(driveClause("ddos "), "đó ")
    }

    func testAlternateTelexKeyOrdersEnglishCompoundsAndCrossBoundaryBackspace() {
        let prevProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = prevProvider }

        let prevMacro = MacroEngine.shared.isEnabled
        MacroEngine.shared.isEnabled = false
        defer { MacroEngine.shared.isEnabled = prevMacro }

        func driveWithBackspaceTokens(_ spec: String) -> String {
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(.senFlex)
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true
            var buffer = ""
            var i = spec.startIndex
            while i < spec.endIndex {
                if spec[i...].hasPrefix("{BS}") {
                    i = spec.index(i, offsetBy: 4)
                    let action = session.handleBackspace()
                    applyMacAction(action, key: nil, to: &buffer)
                    continue
                }
                let ch = spec[i]
                i = spec.index(after: i)
                if session.isWordBoundary(ch) {
                    applyMacAction(
                        session.commitWord(smartBilingualEnabled: true, genZMode: false, boundaryChar: ch),
                        key: ch,
                        to: &buffer
                    )
                } else {
                    applyMacAction(session.handleCharacter(ch), key: ch, to: &buffer)
                }
            }
            if session.isComposing {
                applyMacAction(
                    session.commitWord(smartBilingualEnabled: true, genZMode: false, boundaryChar: nil),
                    key: nil,
                    to: &buffer
                )
            }
            return buffer
        }

        // 1. Alternate Telex key-order invariants (including words whose initial consonant matches the tone key `s/f/r/x/j`
        //    or whose raw spelling splits into 3-letter English tokens like `chi + seem`, `thu + ana`, `cho + air`):
        let alternateOrderCases: [(raw: String, expected: String)] = [
            ("suwowngs ", "sướng "),
            ("suowngs ", "sướng "),
            ("suonwgs ", "sướng "),
            ("suongws ", "sướng "),
            ("rooif ", "rồi "),
            ("chiseem ok ", "chiếm ok "),
            ("chiseen ok ", "chiến ok "),
            ("thuana ok ", "thuân ok "),
            ("duoiso ok ", "duối ok "),
            ("beenhs ok ", "bếnh ok "),
            ("chinhs ok ", "chính ok "),
            ("thoair ok ", "thoải ok "),
            ("dieeng ok ", "diêng ok "),
        ]
        for tc in alternateOrderCases {
            XCTAssertEqual(
                driveWithBackspaceTokens(tc.raw),
                tc.expected,
                "Alternate Telex key-order invariant failed for '\(tc.raw)'"
            )
        }

        // 2. Compound English words, plural compounds (`webhooks`, `dashboards`), and alphanumeric compounds (`dashboard1`, `window1`):
        let compoundCases: [(raw: String, expected: String)] = [
            ("testgen ok ", "testgen ok "),
            ("airdrop ok ", "airdrop ok "),
            ("webhook ok ", "webhook ok "),
            ("webhooks ok ", "webhooks ok "),
            ("dashboard ok ", "dashboard ok "),
            ("dashboards ok ", "dashboards ok "),
            ("dashboard1 ok ", "dashboard1 ok "),
            ("window1 ok ", "window1 ok "),
            ("markdown ok ", "markdown ok "),
            ("textarea ok ", "textarea ok "),
            ("wireframe ok ", "wireframe ok "),
            ("confusing ok ", "confusing ok "),
            ("imagegen ok ", "imagegen ok "),
            ("screenshot ok ", "screenshot ok "),
            ("username ok ", "username ok "),
            ("filename ok ", "filename ok "),
            ("filenames ok ", "filenames ok "),
            ("keyboard ok ", "keyboard ok "),
        ]
        for tc in compoundCases {
            XCTAssertEqual(
                driveWithBackspaceTokens(tc.raw),
                tc.expected,
                "English compound invariant failed for '\(tc.raw)'"
            )
        }

        // 3. Cross-boundary backspace & reopen invariants (no word swallowing when backing past a space):
        let backspaceCases: [(raw: String, expected: String)] = [
            ("animat ed{BS}{BS}{BS}ed ok ", "animated ok "),
            ("hello ok{BS}{BS}{BS}world ok ", "helloworld ok "),
            ("ddoongf{BS} ok ", "đông ok "),
            ("ddoongf{BS}s ok ", "đống ok "),
            ("ddoongf{BS}{BS}s ok ", "đóng ok "),
            ("ddoongf {BS}{BS}s ok ", "đốn ok "),
            ("toi an com{BS}{BS}{BS}{BS}{BS}{BS}xyz ok ", "toi xyz ok "),
        ]
        for tc in backspaceCases {
            XCTAssertEqual(
                driveWithBackspaceTokens(tc.raw),
                tc.expected,
                "Cross-boundary backspace invariant failed for '\(tc.raw)'"
            )
        }
    }

    func testUbuntuLabMixedCaseSubwordsAndPostDigitParity() {
        let cases: [(raw: String, expected: String)] = [
            ("12trieeuj ", "12triệu "),
            ("123Haf ", "123Hà "),
            ("1haf ", "1hà "),
            ("1gox ", "1gõ "),
            ("hafGo ", "hàGo "),
            ("DdatSteve ", "ĐatSteve "),
            ("DdatjSteve ", "ĐạtSteve "),
            ("SteveDdatj ", "SteveĐạt "),
            ("TPDdatj ", "TPĐạt "),
            ("VNHaf ", "VNHà "),
            ("TPDDaay ", "TPĐây "),
            ("TPDdatSteve ", "TPĐatSteve "),
            ("TestCase ", "TestCase "),
            ("UseCase ", "UseCase "),
            ("HTTPPost ", "HTTPPost "),
            ("URLSession ", "URLSession "),
            ("runTest ", "runTest "),
            ("getList ", "getList "),
            ("setHost ", "setHost "),
            ("hasMore ", "hasMore "),
            ("turnOff ", "turnOff "),
            ("isOpen ", "isOpen "),
            ("iOS ", "iOS "),
            ("macOS ", "macOS "),
            ("tvOS ", "tvOS "),
            ("DDoS ", "DDoS "),
            ("SaaS ", "SaaS "),
            ("TuRRuS ", "TuRuS "),
            ("ddAAy ", "đÂy "),
            ("DDaay ", "Đây "),
            (
                "thuwr gox 123Haf 1haf 1gox gox12 .haf ...thuwr -haf haf-- 12trieeuj TPDdatj tp-ddatj Ddattp Ddat12 haf123 Ddatj123 Ahf hafGo DdatSteve DdatjSteve SteveDdatj ",
                "thử gõ 123Hà 1hà 1gõ gõ12 .hà ...thử -hà hà-- 12triệu TPĐạt tp-đạt Đattp Đat12 hà123 Đạt123 Ahf hàGo ĐatSteve ĐạtSteve SteveĐạt "
            ),
        ]

        for tc in cases {
            let macSession = InputSessionManager()
            macSession.smartBilingualEnabled = true
            macSession.inlineBilingualEnabled = true
            var macHost = ""

            let iosAdapter = UIKitInputSessionAdapter()
            iosAdapter.smartBilingual = true
            let iosProxy = MockProxy()

            for ch in tc.raw {
                if macSession.isWordBoundary(ch) {
                    applyMacAction(macSession.commitWord(smartBilingualEnabled: true, boundaryChar: ch), key: ch, to: &macHost)
                } else {
                    applyMacAction(macSession.handleCharacter(ch), key: ch, to: &macHost)
                }
                iosAdapter.handleCharacter(ch, proxy: iosProxy)
            }
            XCTAssertEqual(macHost, tc.expected, "macOS InputSessionManager failed for '\(tc.raw)'")
            XCTAssertEqual(iosProxy.buffer, tc.expected, "iOS UIKitInputSessionAdapter failed for '\(tc.raw)'")
        }
    }
}
