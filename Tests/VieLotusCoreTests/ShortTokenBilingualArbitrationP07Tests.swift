import XCTest
@testable import VieLotusCore

/// Comprehensive verification suite for:
/// 1. `VieLotus P0.7 — Unified Short-Token Bilingual Arbitration` (Sections 1–7)
/// 2. Empirical `Apple Telex vs. Sen Việt (macOS)` Autocorrect-OFF worksheet parity.
final class ShortTokenBilingualArbitrationP07Tests: XCTestCase {

    private final class P07Proxy: TextDocumentProxyProtocol {
        var buffer: String = ""
        var documentContextBeforeInput: String? { buffer }
        var documentContextAfterInput: String? { nil }
        func insertText(_ text: String) { buffer.append(text) }
        func deleteBackward() {
            if !buffer.isEmpty { buffer.removeLast() }
        }
    }

    override func setUp() {
        super.setUp()
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
    }

    private func driveMacPhrase(
        _ rawPhrase: String,
        smartBilingual: Bool = true,
        inlineBilingual: Bool = true,
        policy: BilingualNoContextPolicy = .probabilisticBilingual
    ) -> String {
        let session = InputSessionManager()
        session.smartBilingualEnabled = smartBilingual
        session.inlineBilingualEnabled = inlineBilingual
        session.bilingualNoContextPolicy = policy
        session.macroEnabled = false
        var screen = ""
        for ch in rawPhrase {
            if session.isWordBoundary(ch) {
                if session.isComposing {
                    let action = session.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: ch)
                    applyMacAction(action, to: &screen)
                } else {
                    _ = session.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: ch)
                }
                screen.append(ch)
            } else {
                let action = session.handleCharacter(ch)
                applyMacAction(action, to: &screen, fallbackPassThrough: ch)
            }
        }
        return screen
    }

    private func applyMacAction(_ action: SessionAction, to screen: inout String, fallbackPassThrough: Character? = nil) {
        switch action {
        case .passThrough:
            if let ch = fallbackPassThrough { screen.append(ch) }
        case .consumed:
            break
        case let .replace(backspaces, text):
            removeTrailingUTF16(from: &screen, count: backspaces)
            screen.append(text)
        case let .commit(backspaces, text, _):
            removeTrailingUTF16(from: &screen, count: backspaces)
            screen.append(text)
        case .reset:
            screen.removeAll()
        }
    }

    private func removeTrailingUTF16(from str: inout String, count: Int) {
        guard count > 0, !str.isEmpty else { return }
        let u16 = Array(str.utf16)
        let keep = max(0, u16.count - count)
        str = String(decoding: u16.prefix(keep), as: UTF16.self)
    }

    private func driveIOSPhrase(
        _ rawPhrase: String,
        smartBilingual: Bool = true,
        policy: BilingualNoContextPolicy = .probabilisticBilingual
    ) -> String {
        let session = InputSessionManager()
        session.bilingualNoContextPolicy = policy
        session.macroEnabled = false
        let adapter = UIKitInputSessionAdapter(session: session)
        adapter.smartBilingual = smartBilingual
        let proxy = P07Proxy()
        for ch in rawPhrase {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        return proxy.buffer
    }

    func testShortLabelLanguageSwitchAcrossSharedSessionAndUIKitAdapter() {
        let cases = [
            ("apple meta cos ", "apple meta có "),
            ("apple meta cons ", "apple meta cón "),
            ("apple meta bans conf gif ", "apple meta bán còn gì "),
            ("apple meta google bans ", "apple meta google bán "),
            ("pros and cons ", "pros and cons "),
            ("apple meta cos(x) ", "apple meta cos(x) ")
        ]

        for (raw, expected) in cases {
            XCTAssertEqual(driveMacPhrase(raw), expected, raw)
            XCTAssertEqual(driveIOSPhrase(raw), expected, raw)
        }
    }

    // MARK: - Section 1: Required Short-Token Defaults, Abbreviations & Vietnamese Reachability

    func testSection1NoContextEnglishDefaultsAndAbbreviationsParity() {
        let englishDefaults = ["or", "is", "if", "as", "of", "off", "us", "are", "ajax"]
        for word in englishDefaults {
            let macInline = InputSessionManager()
            macInline.smartBilingualEnabled = true
            macInline.inlineBilingualEnabled = true
            for ch in word { _ = macInline.handleCharacter(ch) }
            XCTAssertEqual(macInline.currentOutput(), word, "macOS inline default must be English for '\(word)'")
            if case let .commit(_, committed, _) = macInline.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                XCTAssertEqual(committed, word, "macOS commit default must be English for '\(word)'")
            } else {
                XCTFail("Expected commit for '\(word)'")
            }

            // Note: In real macOS (`VieLotusIMController`, `inlineBilingual: true`) and iOS (`UIKitInputSessionAdapter`),
            // `of` auto-selects English at keystroke 2 so keystroke 3 (`f`) produces `off`.
            // In commit-only batch mode (`inlineBilingual: false`), keystroke 2 displays Vietnamese `ò`, so keystroke 3 (`f`)
            // performs Classic Tone Escape (`ò -> of`, preserving screen-truth `cancel_keep_composed`).
            let expectedCommitOnly = (word == "off") ? "of " : (word + " ")
            XCTAssertEqual(driveMacPhrase(word + " ", inlineBilingual: false), expectedCommitOnly, "macOS commit-only failed for '\(word)'")
            XCTAssertEqual(driveMacPhrase(word + " ", inlineBilingual: true), word + " ", "macOS inline phrase failed for '\(word)'")
            XCTAssertEqual(driveIOSPhrase(word + " "), word + " ", "iOS adapter failed for '\(word)'")
        }

        // `mix/mĩ` honors `whitelist_safe = never` (the current suite has 180/180 unique-path cases) in cold no-context under `.probabilisticBilingual`,
        // while defaulting to `mix` under `.experimentalFrequencyWeighted` or in English context (`"the mix "`):
        XCTAssertEqual(driveMacPhrase("mix "), "mĩ ")
        XCTAssertEqual(driveIOSPhrase("mix "), "mĩ ")
        XCTAssertEqual(driveMacPhrase("mix ", policy: .experimentalFrequencyWeighted), "mix ")
        XCTAssertEqual(driveIOSPhrase("mix ", policy: .experimentalFrequencyWeighted), "mix ")
        XCTAssertEqual(driveMacPhrase("the mix "), "the mix ")
        XCTAssertEqual(driveIOSPhrase("the mix "), "the mix ")

        // Lowercase neutral no-context preserves legitimate Vietnamese syllables for `est/ét`, `os/ó`, `ir/ỉ`, `ix/ĩ`
        let lowercaseAbbreviations: [(raw: String, vn: String)] = [
            ("est", "ét"),
            ("os", "ó"),
            ("ir", "ỉ"),
            ("ix", "ĩ")
        ]
        for (raw, expectedVN) in lowercaseAbbreviations {
            XCTAssertEqual(driveMacPhrase(raw + " "), expectedVN + " ", "macOS lowercase '\(raw)' should preserve '\(expectedVN)' without context")
            XCTAssertEqual(driveIOSPhrase(raw + " "), expectedVN + " ", "iOS lowercase '\(raw)' should preserve '\(expectedVN)' without context")
        }

        // Case-sensitive, camelCase, technical-delimiter, and English-context resolution for `est`, `os`, `ir`, `ix`
        let casedAndTechnicalCases: [(phrase: String, expected: String)] = [
            ("EST ", "EST "),
            ("OS ", "OS "),
            ("IR ", "IR "),
            ("IX ", "IX "),
            ("iOS ", "iOS "),
            ("macOS ", "macOS "),
            ("tvOS ", "tvOS "),
            ("/os ", "/os "),
            ("os() ", "os() "),
            ("running on os ", "running on os "),
            ("meeting at 5pm est ", "meeting at 5pm est "),
            ("the ir sensor ", "the ir sensor "),
            ("chapter ix is ", "chapter ix is ")
        ]
        for (phrase, expected) in casedAndTechnicalCases {
            XCTAssertEqual(driveMacPhrase(phrase), expected, "macOS technical/case failed for '\(phrase)'")
            XCTAssertEqual(driveIOSPhrase(phrase), expected, "iOS technical/case failed for '\(phrase)'")
        }
    }

    func testSection1EveryVietnameseCandidateRemainsReachable() {
        let reachableTargets: [(raw: String, vn: String, vnCollocation: String)] = [
            ("mix", "mĩ", "nước "),
            ("or", "ỏ", "thẻ "),
            ("is", "í", "cái "),
            ("if", "ì", "ầm "),
            ("as", "á", "thật "),
            ("of", "ò", "kêu "),
            ("us", "ú", "bé "),
            ("est", "ét", "hét "),
            ("os", "ó", "chữ "),
            ("ir", "ỉ", "ầm "),
            ("ix", "ĩ", "rên ")
        ]

        for item in reachableTargets {
            // Path A: Explicit candidate selection on active composition (macOS & iOS)
            let macSession = InputSessionManager()
            macSession.smartBilingualEnabled = true
            macSession.inlineBilingualEnabled = true
            for ch in item.raw { _ = macSession.handleCharacter(ch) }
            if macSession.currentOutput() != item.vn {
                let twin = BilingualIntentArbiter.bilingualTwinCandidate(
                    composingWord: macSession.currentOutput(),
                    rawWord: macSession.rawWord,
                    context: macSession.context
                )
                XCTAssertEqual(twin?.displayText.lowercased(), item.vn, "Twin suggestion must expose '\(item.vn)' for '\(item.raw)'")
                _ = macSession.selectCompositionCandidate(item.vn)
            }
            XCTAssertEqual(macSession.currentOutput(), item.vn, "macOS explicit selection failed for '\(item.vn)'")
            if case let .commit(_, committed, _) = macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                XCTAssertEqual(committed, item.vn, "macOS commit must preserve selected '\(item.vn)'")
            }

            let iosAdapter = UIKitInputSessionAdapter()
            let iosProxy = P07Proxy()
            for ch in item.raw { iosAdapter.handleCharacter(ch, proxy: iosProxy) }
            if iosProxy.buffer != item.vn {
                iosAdapter.selectCompositionCandidate(item.vn, proxy: iosProxy)
            }
            XCTAssertEqual(iosProxy.buffer, item.vn, "iOS explicit selection failed for '\(item.vn)'")
            iosAdapter.handleCharacter(" ", proxy: iosProxy)
            XCTAssertEqual(iosProxy.buffer, item.vn + " ", "iOS commit must preserve selected '\(item.vn)'")

            // Path B: Vietnamese collocation context
            let sessionWithCtx = InputSessionManager()
            sessionWithCtx.smartBilingualEnabled = true
            sessionWithCtx.inlineBilingualEnabled = true
            sessionWithCtx.context = item.vnCollocation.trimmingCharacters(in: .whitespaces)
            for ch in item.raw { _ = sessionWithCtx.handleCharacter(ch) }
            XCTAssertEqual(sessionWithCtx.currentOutput(), item.vn, "Collocation '\(item.vnCollocation)' must produce '\(item.vn)'")
            if case let .commit(_, committedCtx, _) = sessionWithCtx.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                XCTAssertEqual(committedCtx, item.vn)
            }

            // Path C: `.standardVietnameseFirst` policy
            XCTAssertEqual(
                driveMacPhrase(item.raw + " ", policy: .standardVietnameseFirst),
                item.vn + " ",
                "standardVietnameseFirst must reach '\(item.vn)'"
            )
        }

        // Path D: Free-order Telex `mxi -> mĩ`
        XCTAssertEqual(driveMacPhrase("mxi "), "mĩ ")
        XCTAssertEqual(driveIOSPhrase("mxi "), "mĩ ")
    }

    // MARK: - Section 2: Critical Escape Semantics (Provenance-Driven)

    func testSection2CriticalEscapeSemanticsDistinguishEnglishFromVietnamese() {
        // 1. `mix` auto-selected English (in English context or `.experimentalFrequencyWeighted`) -> next `x` produces `mixx`
        let autoMix = InputSessionManager()
        autoMix.smartBilingualEnabled = true
        autoMix.inlineBilingualEnabled = true
        autoMix.context = "the"
        for ch in "mix" { _ = autoMix.handleCharacter(ch) }
        XCTAssertEqual(autoMix.currentOutput(), "mix")
        XCTAssertEqual(autoMix.candidateProvenance.selectedKind, .rawLiteral)
        XCTAssertEqual(autoMix.candidateProvenance.selectionStability, .provisional)

        _ = autoMix.handleCharacter("x")
        XCTAssertEqual(autoMix.currentOutput(), "mixx")
        XCTAssertEqual(autoMix.candidateProvenance.explicitEscapeState, .literalLockedAfterSelection)
        if case let .commit(_, committedMixx, _) = autoMix.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedMixx, "mixx")
        }
        XCTAssertEqual(driveIOSPhrase("the mixx "), "the mixx ")
        XCTAssertEqual(driveIOSPhrase("mixx ", policy: .experimentalFrequencyWeighted), "mixx ")

        // 2. `mix -> mĩ` selected Vietnamese -> next `x` performs semantic tone cancellation -> `mix`
        let selectedMi = InputSessionManager()
        selectedMi.smartBilingualEnabled = true
        selectedMi.inlineBilingualEnabled = true
        for ch in "mix" { _ = selectedMi.handleCharacter(ch) }
        _ = selectedMi.selectCompositionCandidate("mĩ")
        XCTAssertEqual(selectedMi.currentOutput(), "mĩ")
        XCTAssertEqual(selectedMi.candidateProvenance.selectionStability, .explicitSelection)

        _ = selectedMi.handleCharacter("x")
        XCTAssertEqual(selectedMi.currentOutput(), "mix")
        XCTAssertEqual(selectedMi.candidateProvenance.explicitEscapeState, .semanticToneEscape)
        XCTAssertEqual(selectedMi.candidateProvenance.selectionStability, .explicitEscape)
        if case let .commit(_, committedEscapedMix, _) = selectedMi.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedEscapedMix, "mix")
        }

        let iosMi = UIKitInputSessionAdapter()
        let iosMiProxy = P07Proxy()
        for ch in "mix" { iosMi.handleCharacter(ch, proxy: iosMiProxy) }
        iosMi.selectCompositionCandidate("mĩ", proxy: iosMiProxy)
        XCTAssertEqual(iosMiProxy.buffer, "mĩ")
        iosMi.handleCharacter("x", proxy: iosMiProxy)
        XCTAssertEqual(iosMiProxy.buffer, "mix")
        iosMi.handleCharacter(" ", proxy: iosMiProxy)
        XCTAssertEqual(iosMiProxy.buffer, "mix ")

        // 3. `of` auto-selected English -> next `f` produces `off`
        let autoOf = InputSessionManager()
        autoOf.smartBilingualEnabled = true
        autoOf.inlineBilingualEnabled = true
        for ch in "of" { _ = autoOf.handleCharacter(ch) }
        XCTAssertEqual(autoOf.currentOutput(), "of")
        XCTAssertEqual(autoOf.candidateProvenance.selectedKind, .rawLiteral)
        XCTAssertEqual(autoOf.candidateProvenance.selectionStability, .provisional)

        _ = autoOf.handleCharacter("f")
        XCTAssertEqual(autoOf.currentOutput(), "off")
        XCTAssertEqual(autoOf.candidateProvenance.explicitEscapeState, .literalLockedAfterSelection)
        if case let .commit(_, committedOff, _) = autoOf.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedOff, "off")
        }
        XCTAssertEqual(driveIOSPhrase("off "), "off ")

        // 4. `ò` selected Vietnamese via `of` -> next `f` follows Classic/Semantic Tone Escape -> `of`
        let selectedOGrave = InputSessionManager()
        selectedOGrave.smartBilingualEnabled = true
        selectedOGrave.inlineBilingualEnabled = true
        for ch in "of" { _ = selectedOGrave.handleCharacter(ch) }
        _ = selectedOGrave.selectCompositionCandidate("ò")
        XCTAssertEqual(selectedOGrave.currentOutput(), "ò")
        XCTAssertEqual(selectedOGrave.candidateProvenance.selectionStability, .explicitSelection)

        _ = selectedOGrave.handleCharacter("f")
        XCTAssertEqual(selectedOGrave.currentOutput(), "of")
        XCTAssertEqual(selectedOGrave.candidateProvenance.explicitEscapeState, .semanticToneEscape)
        XCTAssertEqual(selectedOGrave.candidateProvenance.selectionStability, .explicitEscape)
        if case let .commit(_, committedEscapedOf, _) = selectedOGrave.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedEscapedOf, "of")
        }

        // Also verify Vietnamese collocation `kêu ò` + `f` -> `kêu of` (never overwritten back to `off` on commit)
        let ctxOGrave = InputSessionManager()
        ctxOGrave.smartBilingualEnabled = true
        ctxOGrave.inlineBilingualEnabled = true
        ctxOGrave.context = "kêu"
        for ch in "of" { _ = ctxOGrave.handleCharacter(ch) }
        XCTAssertEqual(ctxOGrave.currentOutput(), "ò")
        _ = ctxOGrave.handleCharacter("f")
        XCTAssertEqual(ctxOGrave.currentOutput(), "of")
        if case let .commit(_, committedCtxOf, _) = ctxOGrave.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedCtxOf, "of")
        }

        let iosOGrave = UIKitInputSessionAdapter()
        let iosOGraveProxy = P07Proxy()
        for ch in "of" { iosOGrave.handleCharacter(ch, proxy: iosOGraveProxy) }
        iosOGrave.selectCompositionCandidate("ò", proxy: iosOGraveProxy)
        XCTAssertEqual(iosOGraveProxy.buffer, "ò")
        iosOGrave.handleCharacter("f", proxy: iosOGraveProxy)
        XCTAssertEqual(iosOGraveProxy.buffer, "of")
        iosOGrave.handleCharacter(" ", proxy: iosOGraveProxy)
        XCTAssertEqual(iosOGraveProxy.buffer, "of ")
    }

    // MARK: - Section 3: Provisional vs Explicit Lock & Zero Flip Continuation

    func testSection3ProvisionalDoesNotBlockDelayedVietnameseWhileExplicitLockRespectsChoice() {
        // Provisional `or` displays `or`, then `+ m` recovers `ỏm`!
        let provisionalOr = InputSessionManager()
        provisionalOr.smartBilingualEnabled = true
        provisionalOr.inlineBilingualEnabled = true
        for ch in "or" { _ = provisionalOr.handleCharacter(ch) }
        XCTAssertEqual(provisionalOr.currentOutput(), "or")
        XCTAssertEqual(provisionalOr.candidateProvenance.selectionStability, .provisional)
        _ = provisionalOr.handleCharacter("m")
        XCTAssertEqual(provisionalOr.currentOutput(), "ỏm")
        if case let .commit(_, committedOm, _) = provisionalOr.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedOm, "ỏm")
        }
        XCTAssertEqual(driveIOSPhrase("orm "), "ỏm ")

        // Provisional `is` displays `is`, then `+ t` recovers `ít`!
        XCTAssertEqual(driveMacPhrase("ist "), "ít ")
        XCTAssertEqual(driveIOSPhrase("ist "), "ít ")

        // Provisional `OS` displays `OS`, then `+ C` recovers `ÓC`!
        XCTAssertEqual(driveMacPhrase("OSC "), "ÓC ")
        XCTAssertEqual(driveIOSPhrase("OSC "), "ÓC ")

        // Explicit `selectCompositionCandidate("or")` locks English so `+ m` produces `orm` even in Vietnamese context
        let explicitOr = InputSessionManager()
        explicitOr.smartBilingualEnabled = true
        explicitOr.inlineBilingualEnabled = true
        explicitOr.context = "làm"
        for ch in "or" { _ = explicitOr.handleCharacter(ch) }
        _ = explicitOr.selectCompositionCandidate("or")
        XCTAssertEqual(explicitOr.currentOutput(), "or")
        XCTAssertEqual(explicitOr.candidateProvenance.selectionStability, .explicitSelection)
        _ = explicitOr.handleCharacter("m")
        XCTAssertEqual(explicitOr.currentOutput(), "orm")
        if case let .commit(_, committedExplicitOrm, _) = explicitOr.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedExplicitOrm, "orm")
        }

        // English continuations from provisional short tokens must have 0 mid-word flips
        let zeroFlipContinuations = [
            "off", "offer", "office", "often",
            "issue", "island", "isolate",
            "order", "organ", "orbit", "oral",
            "use", "user", "using",
            "ask", "asked"
        ]
        for word in zeroFlipContinuations {
            let s = InputSessionManager()
            s.smartBilingualEnabled = true
            s.inlineBilingualEnabled = true
            for ch in word {
                _ = s.handleCharacter(ch)
                XCTAssertTrue(
                    s.currentOutput().unicodeScalars.allSatisfy(\.isASCII),
                    "Unexpected Vietnamese flip '\(s.currentOutput())' while typing English '\(word)'"
                )
            }
            XCTAssertEqual(s.currentOutput(), word)
            XCTAssertEqual(s.candidateProvenance.flipCount, 0, "Expected 0 flips on '\(word)'")
        }
        for word in ["mixer", "mixed", "mixing"] {
            let s = InputSessionManager()
            s.smartBilingualEnabled = true
            s.inlineBilingualEnabled = true
            s.context = "the"
            for ch in word {
                _ = s.handleCharacter(ch)
                XCTAssertTrue(s.currentOutput().unicodeScalars.allSatisfy(\.isASCII))
            }
            XCTAssertEqual(s.currentOutput(), word)
            XCTAssertEqual(s.candidateProvenance.flipCount, 0)
        }
    }

    // MARK: - Section 4: Frequency-Aware Continuous Priors

    func testSection4ContinuousVietnamesePriorDifferentiatesSyllableFrequencies() {
        let highFreqPrior = BilingualIntentArbiter.continuousVietnameseNoContextPrior(vnFreq: 9.0)
        let midFreqPrior = BilingualIntentArbiter.continuousVietnameseNoContextPrior(vnFreq: 6.5)
        let rareCliticPrior = BilingualIntentArbiter.continuousVietnameseNoContextPrior(vnFreq: 3.0)

        XCTAssertGreaterThan(highFreqPrior, midFreqPrior)
        XCTAssertGreaterThan(midFreqPrior, rareCliticPrior)

        // Single-path Vietnamese collisions (`sẽ`, `bên`, `trê`, `thí`, `mĩ`) win no-context over English (`sex`, `been`, `tree`, `this`, `mix`)
        XCTAssertFalse(BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: "sex", lowerRendered: "sẽ"))
        XCTAssertFalse(BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: "been", lowerRendered: "bên"))
        XCTAssertFalse(BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: "tree", lowerRendered: "trê"))
        XCTAssertFalse(BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: "this", lowerRendered: "thí"))
        XCTAssertFalse(BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: "mix", lowerRendered: "mĩ"))

        // High-frequency English short words (`or`, `is`, `if`, `as`, `of`, `us`) win no-context over rare standalone Vietnamese clitics/variants
        for (raw, vn) in [("or", "ỏ"), ("is", "í"), ("if", "ì"), ("as", "á"), ("of", "ò"), ("us", "ú")] {
            XCTAssertTrue(BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: raw, lowerRendered: vn))
        }
    }

    // MARK: - Section 6: Auto-Generated Length 2–5 Collision Corpus & 5 Separate Metrics

    func testSection6AutoGeneratedShortTokenCollisionCorpusAndSentences() {
        // Automatically generate length 2–5 short-token collisions from offline Vietnamese syllable inventory x English lexicon
        var generatedCollisions: [(raw: String, vn: String)] = []
        var seenRaw = Set<String>()
        for syllable in VietnameseSyllableDictionary.shared.syllables.sorted() {
            let raw = VietnameseEngine.rawKeys(for: syllable, inputMethod: .telex).lowercased()
            guard (2...5).contains(raw.count),
                  raw != syllable,
                  !seenRaw.contains(raw),
                  (EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(raw) ||
                   BilingualIntentArbiter.englishCollisionLogFrequencies[raw] != nil) else {
                continue
            }
            let verifyEngine = VietnameseEngine()
            verifyEngine.inputMethod = .telex
            guard verifyEngine.transform(Array(raw)).lowercased() == syllable else {
                continue
            }
            seenRaw.insert(raw)
            generatedCollisions.append((raw: raw, vn: syllable))
        }
        XCTAssertGreaterThan(generatedCollisions.count, 100, "Expected >100 auto-generated length 2–5 EN/VN collisions")

        var englishCorruptionCount = 0
        var vietnameseUnreachableCount = 0
        var wrongEscapeCount = 0
        var unintentionalRawReplayCount = 0
        var unintendedCandidateFlipCount = 0

        for pair in generatedCollisions {
            // Generic English prose is insufficient domain evidence for lowercase cos.
            let expectedInProse = pair.raw == "cos" ? pair.vn : pair.raw
            // 1. Prefix, English-context typing, Space, punctuation, Backspace & retype
            let enSession = InputSessionManager()
            enSession.smartBilingualEnabled = true
            enSession.inlineBilingualEnabled = true
            enSession.context = "please check the"
            for ch in pair.raw {
                _ = enSession.handleCharacter(ch)
            }
            // Backspace last char and retype
            if let lastChar = pair.raw.last {
                _ = enSession.handleBackspace()
                _ = enSession.handleCharacter(lastChar)
            }
            if case let .commit(_, committedEN, _) = enSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                if committedEN != expectedInProse && !BilingualIntentArbiter.isVietnameseClauseStarter(rendered: pair.vn, lowerRaw: pair.raw) {
                    englishCorruptionCount += 1
                    XCTFail("English-context commit corrupted '\(pair.raw)' -> '\(committedEN)' (vn='\(pair.vn)')")
                }
            }

            // Punctuation commit in English context
            let punctOut = driveMacPhrase("please check the \(pair.raw).")
            if punctOut != "please check the \(expectedInProse)." &&
               !BilingualIntentArbiter.isVietnameseClauseStarter(rendered: pair.vn, lowerRaw: pair.raw) {
                englishCorruptionCount += 1
                XCTFail("English-context punctuation corrupted '\(pair.raw)' -> '\(punctOut)'")
            }

            // 2. Vietnamese reachability (either direct no-context Vietnamese OR explicit candidate selection)
            let vnSession = InputSessionManager()
            vnSession.smartBilingualEnabled = true
            vnSession.inlineBilingualEnabled = true
            for ch in pair.raw { _ = vnSession.handleCharacter(ch) }
            if vnSession.currentOutput() != pair.vn {
                _ = vnSession.selectCompositionCandidate(pair.vn)
            }
            if case let .commit(_, committedVN, _) = vnSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                if committedVN != pair.vn {
                    vietnameseUnreachableCount += 1
                }
            }

            // 3. Tone escape & raw-replay audit on tone-bearing collisions
            if let lastKey = pair.raw.last, "sfrxj".contains(lastKey), VietnameseSyllableDictionary.hasToneMark(pair.vn) {
                // When explicitly selected as English literal, repeating tone key must append literally (`raw + lastKey`)
                let litSession = InputSessionManager()
                litSession.smartBilingualEnabled = true
                litSession.inlineBilingualEnabled = true
                for ch in pair.raw { _ = litSession.handleCharacter(ch) }
                _ = litSession.selectCompositionCandidate(pair.raw)
                _ = litSession.handleCharacter(lastKey)
                let expectedLiteral = pair.raw + String(lastKey)
                if litSession.currentOutput() != expectedLiteral {
                    wrongEscapeCount += 1
                }
                if litSession.candidateProvenance.flipCount > 1 {
                    unintendedCandidateFlipCount += 1
                }

                // When explicitly selected as Vietnamese, repeating adjacent final tone key must escape tone without duplicating key
                let escSession = InputSessionManager()
                escSession.smartBilingualEnabled = true
                escSession.inlineBilingualEnabled = true
                for ch in pair.raw { _ = escSession.handleCharacter(ch) }
                _ = escSession.selectCompositionCandidate(pair.vn)
                _ = escSession.handleCharacter(lastKey)
                let escapedOut = escSession.currentOutput()
                if VietnameseSyllableDictionary.hasToneMark(escapedOut) {
                    wrongEscapeCount += 1
                }
                if case let .commit(_, committedEsc, _) = escSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                    if committedEsc != escapedOut {
                        unintentionalRawReplayCount += 1
                    }
                }
            }
        }

        // Full sentences: English, Vietnamese, Mixed-language, and Technical/Code
        let corpusSentences: [(raw: String, expected: String)] = [
            // Pure English sentences with short-token collisions
            ("if it is off or out of order mix it ", "if it is off or out of order mix it "),
            ("are you with us or as fast as ajax ", "are you with us or as fast as ajax "),
            // Pure Vietnamese sentences
            ("chaof buooir sangs hoom nay trowif ddepj quas ", "chào buổi sáng hôm nay trời đẹp quá "),
            ("nuowcs mix vaf chaau as coong ngheej cao ", "nước mĩ và châu á công nghệ cao "),
            // Mixed bilingual sentences
            ("Chaof buooir sangs! Good morning! ", "Chào buổi sáng! Good morning! "),
            ("app nayf chayj treen iOS vaf macOS raats muowtj ", "app này chạy trên iOS và macOS rất mượt "),
            // Technical & code contexts
            ("if (os == nil || isOff) ", "if (os == nil || isOff) "),
            ("fetch(/api/ajax) ", "fetch(/api/ajax) ")
        ]
        for (raw, expected) in corpusSentences {
            let macOut = driveMacPhrase(raw)
            let iosOut = driveIOSPhrase(raw)
            if macOut != expected { englishCorruptionCount += 1 }
            if iosOut != expected { englishCorruptionCount += 1 }
            XCTAssertEqual(macOut, expected, "macOS sentence mismatch for '\(raw)'")
            XCTAssertEqual(iosOut, expected, "iOS sentence mismatch for '\(raw)'")
        }

        print(
            "P0.7_COLLISION_CORPUS_METRICS: collisions=\(generatedCollisions.count) " +
            "en_corruption=\(englishCorruptionCount) vn_unreachable=\(vietnameseUnreachableCount) " +
            "wrong_escape=\(wrongEscapeCount) raw_replay=\(unintentionalRawReplayCount) " +
            "unintended_flip=\(unintendedCandidateFlipCount)"
        )
        XCTAssertEqual(englishCorruptionCount, 0, "English corruption count must be 0")
        XCTAssertEqual(vietnameseUnreachableCount, 0, "Vietnamese unreachable count must be 0")
        XCTAssertEqual(wrongEscapeCount, 0, "Wrong escape count must be 0")
        XCTAssertEqual(unintentionalRawReplayCount, 0, "Unintentional raw replay count must be 0")
        XCTAssertEqual(unintendedCandidateFlipCount, 0, "Unintended candidate flip count must be 0")
    }

    // MARK: - Empirical Worksheet Parity: Apple Telex vs. Sen Việt (macOS, Autocorrect OFF)

    func testEmpiricalAppleTelexVsSenVietWorksheetParity() {
        // Table 1 Row 1: `m -> mi -> mĩ -> mĩi -> mĩi␣` (when Vietnamese `mĩ` is active)
        let t1r1PureTelex = driveMacPhrase("mixi ", smartBilingual: false)
        XCTAssertEqual(t1r1PureTelex, "mĩi ")

        let t1r1SelectedVN = InputSessionManager()
        t1r1SelectedVN.smartBilingualEnabled = true
        t1r1SelectedVN.inlineBilingualEnabled = true
        for ch in "mix" { _ = t1r1SelectedVN.handleCharacter(ch) }
        _ = t1r1SelectedVN.selectCompositionCandidate("mĩ")
        _ = t1r1SelectedVN.handleCharacter("i")
        XCTAssertEqual(t1r1SelectedVN.currentOutput(), "mĩi")
        if case let .commit(_, committedMii, _) = t1r1SelectedVN.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedMii, "mĩi")
        }

        // Table 1 Row 2: `m -> mi -> mĩ -> mix -> mixi -> mixi␣` (MUST NOT raw-replay `mixxi␣`)
        XCTAssertEqual(driveMacPhrase("mixxi ", smartBilingual: false), "mixi ")
        XCTAssertEqual(driveMacPhrase("mixxi ", policy: .standardVietnameseFirst), "mixi ")
        let t1r2SelectedVN = InputSessionManager()
        t1r2SelectedVN.smartBilingualEnabled = true
        t1r2SelectedVN.inlineBilingualEnabled = true
        for ch in "mix" { _ = t1r2SelectedVN.handleCharacter(ch) }
        _ = t1r2SelectedVN.selectCompositionCandidate("mĩ")
        _ = t1r2SelectedVN.handleCharacter("x")
        XCTAssertEqual(t1r2SelectedVN.currentOutput(), "mix")
        _ = t1r2SelectedVN.handleCharacter("i")
        XCTAssertEqual(t1r2SelectedVN.currentOutput(), "mixi")
        if case let .commit(_, committedMixi, _) = t1r2SelectedVN.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(committedMixi, "mixi", "Escaped 'mix' + 'i' must commit 'mixi', never 'mixxi'")
        }

        // Table 1 Row 3: `a -> â -> âo -> âoo -> âoo␣` (`aaoo␣`)
        let t1r3 = InputSessionManager()
        t1r3.smartBilingualEnabled = true
        t1r3.inlineBilingualEnabled = true
        var traceT1R3: [String] = []
        for ch in "aaoo" {
            _ = t1r3.handleCharacter(ch)
            traceT1R3.append(t1r3.currentOutput())
        }
        XCTAssertEqual(traceT1R3, ["a", "â", "âo", "âoo"])
        XCTAssertEqual(driveMacPhrase("aaoo "), "âoo ")
        XCTAssertEqual(driveIOSPhrase("aaoo "), "âoo ")

        // Table 1 Row 4: `o -> ô -> ôa -> ôaa -> ôaa␣` (`ooaa␣`)
        let t1r4 = InputSessionManager()
        t1r4.smartBilingualEnabled = true
        t1r4.inlineBilingualEnabled = true
        var traceT1R4: [String] = []
        for ch in "ooaa" {
            _ = t1r4.handleCharacter(ch)
            traceT1R4.append(t1r4.currentOutput())
        }
        XCTAssertEqual(traceT1R4, ["o", "ô", "ôa", "ôaa"])
        XCTAssertEqual(driveMacPhrase("ooaa "), "ôaa ")
        XCTAssertEqual(driveIOSPhrase("ooaa "), "ôaa ")

        // Table 2 Row 1: `e -> ê -> êa -> êaa` (`eeaa` / `eeaa␣`)
        let t2r1 = InputSessionManager()
        t2r1.smartBilingualEnabled = true
        t2r1.inlineBilingualEnabled = true
        var traceT2R1: [String] = []
        for ch in "eeaa" {
            _ = t2r1.handleCharacter(ch)
            traceT2R1.append(t2r1.currentOutput())
        }
        XCTAssertEqual(traceT2R1, ["e", "ê", "êa", "êaa"])
        XCTAssertEqual(driveMacPhrase("eeaa "), "êaa ")
        XCTAssertEqual(driveIOSPhrase("eeaa "), "êaa ")

        // Table 2 Row 2: `u -> ư -> uw -> uwu -> uwuw -> uwuw␣` (`uwwuw␣`)
        let t2r2 = InputSessionManager()
        t2r2.smartBilingualEnabled = true
        t2r2.inlineBilingualEnabled = true
        var traceT2R2: [String] = []
        for ch in "uwwuw" {
            _ = t2r2.handleCharacter(ch)
            traceT2R2.append(t2r2.currentOutput())
        }
        XCTAssertEqual(traceT2R2, ["u", "ư", "uw", "uwu", "uwuw"])
        XCTAssertEqual(driveMacPhrase("uwwuw "), "uwuw ")
        XCTAssertEqual(driveIOSPhrase("uwwuw "), "uwuw ")

        // Table 2 Row 3: `aweeoo␣ -> ăeeoo␣` (provisional `awe` at char 3 recovers `ăee -> ăeeo -> ăeeoo␣`)
        XCTAssertEqual(driveMacPhrase("aweeoo "), "ăeeoo ")
        XCTAssertEqual(driveIOSPhrase("aweeoo "), "ăeeoo ")

        // Table 2 Row 4 & Table 3 Row 1: Intentional Policy 3B+ Semantic Saturation (`ajaa␣ -> ậa␣`, `ejee␣ -> ệe␣`)
        XCTAssertEqual(driveMacPhrase("ajaa "), "ậa ")
        XCTAssertEqual(driveMacPhrase("ejee "), "ệe ")

        // Table 3 Row 2: `i -> ị -> ij -> iji -> iji␣` (`ijji␣`)
        let t3r2 = InputSessionManager()
        t3r2.smartBilingualEnabled = true
        t3r2.inlineBilingualEnabled = true
        var traceT3R2: [String] = []
        for ch in "ijji" {
            _ = t3r2.handleCharacter(ch)
            traceT3R2.append(t3r2.currentOutput())
        }
        XCTAssertEqual(traceT3R2, ["i", "ị", "ij", "iji"])
        XCTAssertEqual(driveMacPhrase("ijji "), "iji ")
        XCTAssertEqual(driveIOSPhrase("ijji "), "iji ")

        // Table 3 Rows 3 & 4 (Post-commit Space + Backspace + Re-append on `ejee` / `ệe` and `ijji` / `iji`):
        let iosPostCommitE = UIKitInputSessionAdapter()
        let iosPostProxyE = P07Proxy()
        for ch in "ejee " { iosPostCommitE.handleCharacter(ch, proxy: iosPostProxyE) }
        XCTAssertEqual(iosPostProxyE.buffer, "ệe ")
        iosPostCommitE.handleBackspace(proxy: iosPostProxyE) // delete trailing space -> `ệe` armed
        iosPostCommitE.handleCharacter("e", proxy: iosPostProxyE) // append `e` -> `ệee`
        XCTAssertEqual(iosPostProxyE.buffer, "ệee")
        iosPostCommitE.handleCharacter(" ", proxy: iosPostProxyE)
        XCTAssertEqual(iosPostProxyE.buffer, "ệee ")

        let iosPostCommit = UIKitInputSessionAdapter()
        let iosPostProxy = P07Proxy()
        for ch in "ijji " { iosPostCommit.handleCharacter(ch, proxy: iosPostProxy) }
        XCTAssertEqual(iosPostProxy.buffer, "iji ")
        iosPostCommit.handleBackspace(proxy: iosPostProxy) // delete trailing space -> `iji` armed
        iosPostCommit.handleCharacter("i", proxy: iosPostProxy) // append `i` -> `ijii`
        iosPostCommit.handleCharacter(" ", proxy: iosPostProxy)
        XCTAssertEqual(iosPostProxy.buffer, "ijii ")

        // Table 4 (`ậ -> âj` / `ẩ -> âr` + all modified vowels):
        let modifiedVowelToneEscapes: [(raw: String, trace: [String], expected: String)] = [
            ("aajj", ["a", "â", "ậ", "âj"], "âj"),
            ("aarr", ["a", "â", "ẩ", "âr"], "âr"),
            ("awjj", ["a", "ă", "ặ", "ăj"], "ăj"),
            ("eejj", ["e", "ê", "ệ", "êj"], "êj"),
            ("oojj", ["o", "ô", "ộ", "ôj"], "ôj"),
            ("owjj", ["o", "ơ", "ợ", "ơj"], "ơj"),
            ("uwjj", ["u", "ư", "ự", "ưj"], "ưj")
        ]
        for item in modifiedVowelToneEscapes {
            let sess = InputSessionManager()
            sess.smartBilingualEnabled = true
            sess.inlineBilingualEnabled = true
            var trace: [String] = []
            for ch in item.raw {
                _ = sess.handleCharacter(ch)
                trace.append(sess.currentOutput())
            }
            XCTAssertEqual(trace, item.trace, "Trace mismatch for '\(item.raw)'")
            XCTAssertEqual(driveMacPhrase(item.raw), item.expected, "macOS inline mismatch for '\(item.raw)'")
            XCTAssertEqual(driveMacPhrase(item.raw + " "), item.expected + " ", "macOS space commit mismatch for '\(item.raw)'")
            XCTAssertEqual(driveIOSPhrase(item.raw), item.expected, "iOS inline mismatch for '\(item.raw)'")
            XCTAssertEqual(driveIOSPhrase(item.raw + " "), item.expected + " ", "iOS space commit mismatch for '\(item.raw)'")
        }

        // Table 4 Rows 3 & 4 (Post-commit Space + Backspace + Thêm on `âr` / `âj`):
        let iosPostCommitAj = UIKitInputSessionAdapter()
        let iosPostProxyAj = P07Proxy()
        for ch in "aajj " { iosPostCommitAj.handleCharacter(ch, proxy: iosPostProxyAj) }
        XCTAssertEqual(iosPostProxyAj.buffer, "âj ")
        iosPostCommitAj.handleBackspace(proxy: iosPostProxyAj) // delete trailing space -> `âj` armed
        iosPostCommitAj.handleCharacter("j", proxy: iosPostProxyAj)
        XCTAssertEqual(iosPostProxyAj.buffer, "âjj")
        iosPostCommitAj.handleCharacter(" ", proxy: iosPostProxyAj)
        XCTAssertEqual(iosPostProxyAj.buffer, "âjj ")

        // Table 5 (`à -> afa`, `assa -> asa`, `axxa -> axa`, `ojjo -> ojo` with MacSpellChecker active):
        let macSpell = MacSpellChecker()
        XCTAssertFalse(macSpell.isWordInEnglishDictionary("affa"), "MacSpellChecker must not treat 'affa' as an English word")
        XCTAssertFalse(macSpell.isWordInEnglishDictionary("eeff"), "MacSpellChecker must not treat 'eeff' as an English word")
        XCTAssertFalse(macSpell.isWordInEnglishDictionary("ooff"), "MacSpellChecker must not treat 'ooff' as an English word")
        XCTAssertTrue(macSpell.isWordInEnglishDictionary("iffy"), "MacSpellChecker must preserve real English word 'iffy'")

        let table5Cases: [(raw: String, trace: [String], expected: String)] = [
            ("affa", ["a", "à", "af", "afa"], "afa"),
            ("assa", ["a", "as", "as", "asa"], "asa"),
            ("axxa", ["a", "ã", "ax", "axa"], "axa"),
            ("ojjo", ["o", "ọ", "oj", "ojo"], "ojo")
        ]
        for item in table5Cases {
            let sess = InputSessionManager()
            sess.smartBilingualEnabled = true
            sess.inlineBilingualEnabled = true
            var trace: [String] = []
            for ch in item.raw {
                _ = sess.handleCharacter(ch)
                trace.append(sess.currentOutput())
            }
            XCTAssertEqual(trace, item.trace, "Trace mismatch for '\(item.raw)'")
            XCTAssertEqual(driveMacPhrase(item.raw), item.expected, "macOS inline mismatch for '\(item.raw)'")
            XCTAssertEqual(driveMacPhrase(item.raw + " "), item.expected + " ", "macOS space commit mismatch for '\(item.raw)'")
            XCTAssertEqual(driveIOSPhrase(item.raw), item.expected, "iOS inline mismatch for '\(item.raw)'")
            XCTAssertEqual(driveIOSPhrase(item.raw + " "), item.expected + " ", "iOS space commit mismatch for '\(item.raw)'")
        }

        // Table 5 Post-commit Space + Backspace + Thêm (`af ⌫a -> afa`, `af ⌫a␣ -> afa␣`):
        let iosPostCommitAf = UIKitInputSessionAdapter()
        let iosPostProxyAf = P07Proxy()
        for ch in "aff " { iosPostCommitAf.handleCharacter(ch, proxy: iosPostProxyAf) }
        XCTAssertEqual(iosPostProxyAf.buffer, "af ")
        iosPostCommitAf.handleBackspace(proxy: iosPostProxyAf) // delete trailing space -> `af` armed
        iosPostCommitAf.handleCharacter("a", proxy: iosPostProxyAf) // append `a` -> `afa`
        XCTAssertEqual(iosPostProxyAf.buffer, "afa")
        iosPostCommitAf.handleCharacter(" ", proxy: iosPostProxyAf)
        XCTAssertEqual(iosPostProxyAf.buffer, "afa ")
    }
}
