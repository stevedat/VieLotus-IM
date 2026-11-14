import XCTest
@testable import VieLotusCore

/// Golden Test Suite for **Modified 3B (3B+): Delayed Modifier Once + Semantic Saturation + Safe Literal Fallback**.
///
/// Covers all 11 policy requirements and Acceptance criteria across both macOS (`InputSessionManager`)
/// and iOS (`UIKitInputSessionAdapter`):
/// 1. Free Telex (`aam/ama -> âm`, `eem/eme -> êm`, `caan/cana -> cân`, `khieem/khieme -> khiêm`).
/// 2. Delayed modifier (`a/e/o/w`) transforms once when a valid semantic target exists.
/// 3. Once a vowel is transformed (saturated), a redundant modifier after the coda/offglide does NOT cancel circumflex/horn (`trưởng+w -> trưởngw`, `Trưởng+w -> Trưởngw`, `khiêm+e -> khiême`, `hồng+o -> hồngo`, `cửa+w -> cửaw`, `caana/canaa -> câna`).
/// 4. Contiguous Classic Escape (`aaa`, `eee`, `ooo`, `aww`, `oww`, `uww`, `ww`, `ddd`) is preserved within bounded scope.
/// 5. Valid post-coda vowel reshape (`trường+o -> truồng`, `thưởng+o -> thuổng`) remains supported and saturates afterwards (`truồng+o -> truồngo`).
/// 6. `z` only clears tone marks (`s/f/r/x/j`), never structural vowel/consonant modifiers.
/// 7. `Backspace` undoes literal fallback cleanly and restores full state when deleting and retyping.
/// 8. Zero swallowed keys, zero ghost keys, zero raw Telex leaks.
/// 9. `SmartBilingualDetector` arbitrates `cana`, `theme`, proper nouns, and English words by context, with per-keystroke intermediate state verification (`cheese`, `theme`, `meme`, `here`).
/// 10. Canonical raw inputs enforced (`khiem` without second `e` is `"khiem"`, whereas `khieem` / `khieme` forms `"khiêm"`).
/// 11. Keystroke-by-keystroke macOS + iOS parity across `Space`, `Backspace`, `z`, tone switching, and continuation.
final class ModifierPolicy3BPlusGoldenTests: XCTestCase {

    private final class GoldenProxy: TextDocumentProxyProtocol {
        var buffer: String = ""
        var documentContextBeforeInput: String? { buffer.isEmpty ? nil : buffer }
        var documentContextAfterInput: String? = nil
        var selectedText: String? = nil

        func insertText(_ text: String) {
            buffer.append(text)
        }

        func deleteBackward() {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
        }
    }

    /// Drives a keystroke script through both macOS `InputSessionManager` and iOS `UIKitInputSessionAdapter`
    /// (where `"<"` = Backspace and `" "` = Space) and verifies identical on-screen text at every step.
    private func assertDualPlatformScript(
        _ steps: [(key: Character, expected: String)],
        profile: GrammarProfile = .senFlex,
        smartBilingual: Bool = true,
        inlineBilingual: Bool = false,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let macSession = InputSessionManager()
        macSession.setInputMethod(.telex)
        macSession.setGrammarProfile(profile)
        macSession.smartBilingualEnabled = smartBilingual
        macSession.inlineBilingualEnabled = inlineBilingual
        if !context.isEmpty {
            for word in context.split(whereSeparator: \.isWhitespace) {
                macSession.appendContext(String(word))
            }
        }
        var macBuffer = ""

        let iosAdapter = UIKitInputSessionAdapter()
        iosAdapter.session.setInputMethod(.telex)
        iosAdapter.session.setGrammarProfile(profile)
        iosAdapter.smartBilingual = smartBilingual
        iosAdapter.session.smartBilingualEnabled = smartBilingual
        iosAdapter.session.inlineBilingualEnabled = inlineBilingual
        let iosProxy = GoldenProxy()
        if !context.isEmpty {
            for word in context.split(whereSeparator: \.isWhitespace) {
                iosAdapter.session.appendContext(String(word))
            }
        }

        for (idx, step) in steps.enumerated() {
            if step.key == "<" {
                let action = macSession.handleBackspace()
                switch action {
                case .replace(let bs, let txt):
                    if bs > 0 && bs <= macBuffer.count {
                        macBuffer.removeLast(bs)
                    }
                    macBuffer.append(txt)
                case .reset:
                    if !macBuffer.isEmpty {
                        macBuffer.removeLast()
                    }
                case .passThrough:
                    if !macBuffer.isEmpty {
                        macBuffer.removeLast()
                    }
                case .consumed, .commit:
                    break
                }
                iosAdapter.handleBackspace(proxy: iosProxy)
            } else if macSession.isWordBoundary(step.key) {
                let action = macSession.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: step.key)
                switch action {
                case .commit(let bs, let txt, _):
                    if bs > 0 && bs <= macBuffer.count {
                        macBuffer.removeLast(bs)
                    }
                    macBuffer.append(txt)
                    macBuffer.append(step.key)
                case .passThrough:
                    macBuffer.append(step.key)
                default:
                    macBuffer.append(step.key)
                }
                iosAdapter.handleCharacter(step.key, proxy: iosProxy)
            } else {
                let action = macSession.handleCharacter(step.key)
                switch action {
                case .replace(let bs, let txt):
                    if bs > 0 && bs <= macBuffer.count {
                        macBuffer.removeLast(bs)
                    }
                    macBuffer.append(txt)
                case .passThrough:
                    macBuffer.append(step.key)
                case .consumed, .commit, .reset:
                    break
                }
                iosAdapter.handleCharacter(step.key, proxy: iosProxy)
            }

            XCTAssertEqual(
                macBuffer,
                step.expected,
                "macOS mismatch at step #\(idx + 1) ('\(step.key)') [profile=\(profile)]",
                file: file,
                line: line
            )
            XCTAssertEqual(
                iosProxy.buffer,
                step.expected,
                "iOS mismatch at step #\(idx + 1) ('\(step.key)') [profile=\(profile)]",
                file: file,
                line: line
            )
        }
    }

    // MARK: - 1, 2 & 10. Free Telex, Delayed Modifier Once & Explicit Keystroke-by-Keystroke Verification

    func testFreeTelexDelayedModifierOnceAndCanonicalKhiemInput() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // Explicit per-keystroke expectations (zero dynamic derivation)
            let scripts: [[(key: Character, expected: String)]] = [
                // Requirement 1: Free Telex (contiguous & delayed once)
                [("a", "a"), ("a", "â"), ("m", "âm")],
                [("a", "a"), ("m", "am"), ("a", "âm")],
                [("e", "e"), ("e", "ê"), ("m", "êm")],
                [("e", "e"), ("m", "em"), ("e", "êm")],
                [("c", "c"), ("a", "ca"), ("a", "câ"), ("n", "cân")],
                [("c", "c"), ("a", "ca"), ("n", "can"), ("a", "cân")],
                [("n", "n"), ("h", "nh"), ("a", "nha"), ("a", "nhâ"), ("n", "nhân")],
                [("n", "n"), ("h", "nh"), ("a", "nha"), ("n", "nhan"), ("a", "nhân")],
                [("t", "t"), ("h", "th"), ("e", "the"), ("e", "thê"), ("m", "thêm")],
                [("t", "t"), ("h", "th"), ("e", "the"), ("m", "them"), ("e", "theme"), ("f", "thềm")],
                [("t", "t"), ("r", "tr"), ("o", "tro"), ("o", "trô"), ("n", "trôn"), ("g", "trông")],
                [("t", "t"), ("r", "tr"), ("o", "tro"), ("n", "tron"), ("g", "trong"), ("o", "trông")],
                // Requirement 10: 'khiem' has only one 'e' and must remain 'khiem';
                // 'khieem' and 'khieme' are the canonical Telex inputs for 'khiêm'
                [("k", "k"), ("h", "kh"), ("i", "khi"), ("e", "khie"), ("m", "khiem")],
                [("k", "k"), ("h", "kh"), ("i", "khi"), ("e", "khie"), ("e", "khiê"), ("m", "khiêm")],
                [("k", "k"), ("h", "kh"), ("i", "khi"), ("e", "khie"), ("m", "khiem"), ("e", "khiêm")],
                // Multi-order Telex for 'trưởng' & 'Trưởng'
                [("t", "t"), ("r", "tr"), ("u", "tru"), ("o", "truo"), ("w", "trươ"), ("n", "trươn"), ("g", "trương"), ("r", "trưởng")],
                [("t", "t"), ("r", "tr"), ("u", "tru"), ("o", "truo"), ("n", "truon"), ("g", "truong"), ("w", "trương"), ("r", "trưởng")],
                [("t", "t"), ("r", "tr"), ("u", "tru"), ("w", "trư"), ("o", "trươ"), ("n", "trươn"), ("g", "trương"), ("r", "trưởng")],
                [("t", "t"), ("r", "tr"), ("u", "tru"), ("o", "truo"), ("n", "truon"), ("g", "truong"), ("r", "truỏng"), ("w", "trưởng")],
                [("t", "t"), ("r", "tr"), ("u", "tru"), ("w", "trư"), ("o", "trươ"), ("w", "trươ"), ("n", "trươn"), ("g", "trương"), ("r", "trưởng")],
                [("T", "T"), ("r", "Tr"), ("u", "Tru"), ("o", "Truo"), ("w", "Trươ"), ("n", "Trươn"), ("g", "Trương"), ("r", "Trưởng"), ("w", "Trưởngw")]
            ]

            for script in scripts {
                assertDualPlatformScript(script, profile: profile)
            }
        }
    }

    // MARK: - 3. Semantic Saturation + Safe Literal Fallback (Including Uppercase 'Trưởngw')

    func testSemanticSaturationPreventsPostCodaCancellationAndAppendsLiteral() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // Mandatory comparison cases under Policy 3B+:
            // - trưởng + w -> trưởngw
            // - Trưởng + w -> Trưởngw (U+01B0 'ư' + U+1EDF 'ở', NEVER 'Truởngw')
            // - khiêm + e -> khiême
            // - hồng + o -> hồngo
            // - cửa + w -> cửaw
            // - caana / canaa -> câna
            let saturationCases: [(raw: String, expected: String)] = [
                ("truowngrw", "trưởngw"),
                ("truongwrw", "trưởngw"),
                ("truwongrw", "trưởngw"),
                ("truongrww", "trưởngw"),
                ("truwowngrw", "trưởngw"),
                ("Truowngrw", "Trưởngw"),
                ("Truongwrw", "Trưởngw"),
                ("Truongrww", "Trưởngw"),
                ("khieeme", "khiême"),
                ("khiemee", "khiême"),
                ("Khieeme", "Khiême"),
                ("hoongfo", "hồngo"),
                ("hoonfgo", "hồngo"),
                ("hongfo", "hồng"),
                ("hongfoo", "hồngo"),
                ("Hoongfo", "Hồngo"),
                ("cuwarw", "cửaw"),
                ("cuwraw", "cửaw"),
                ("cuawrw", "cửaw"),
                ("Cuwarw", "Cửaw"),
                ("caana", "câna"),
                ("canaa", "câna"),
                ("Caana", "Câna"),
                ("aama", "âma"),
                ("amaa", "âma"),
                ("eeme", "ême"),
                ("emee", "ême"),
                ("nhaanja", "nhậna"),
                ("nhanaja", "nhậna"),
                ("tieengse", "tiếnge"),
                ("vieecje", "việce"),
                ("muoonso", "muốno"),
                ("dduowcjw", "đượcw")
            ]

            for tc in saturationCases {
                let s = InputSessionManager()
                s.setGrammarProfile(profile)
                s.smartBilingualEnabled = true
                for ch in tc.raw {
                    _ = s.handleCharacter(ch)
                }
                let output = s.currentOutput()
                XCTAssertEqual(
                    output,
                    tc.expected,
                    "macOS inline saturation for '\(tc.raw)' [profile=\(profile)]"
                )
                if tc.raw.lowercased().hasPrefix("tru") {
                    XCTAssertTrue(
                        output.lowercased().hasPrefix("trưởng"),
                        "'\(tc.raw)' must preserve both 'ư' and 'ở' in 'Trưởngw', never 'Truởngw' (got '\(output)')"
                    )
                }
                guard case let .commit(_, committed, isOverride) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    XCTFail("Expected commit for '\(tc.raw)'")
                    continue
                }
                XCTAssertEqual(
                    committed,
                    tc.expected,
                    "macOS Space commit for '\(tc.raw)' [profile=\(profile)]"
                )
                XCTAssertFalse(isOverride, "'\(tc.raw)' must not collapse to raw on Space commit")
            }
        }
    }

    // MARK: - 4. Bounded Contiguous Classic Escape

    func testContiguousClassicEscapeRemainsIntact() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // Pure Telex inline & non-bilingual commit for 'aaa -> aa', 'eee -> ee', 'ooo -> oo'
            for (raw, expected) in [("aaa", "aa"), ("eee", "ee"), ("ooo", "oo")] {
                assertDualPlatformScript([
                    (Array(raw)[0], String(Array(raw)[0])),
                    (Array(raw)[1], raw == "aaa" ? "â" : (raw == "eee" ? "ê" : "ô")),
                    (Array(raw)[2], expected),
                    (" ", expected + " ")
                ], profile: profile, smartBilingual: false)
            }

            // Contiguous classic escapes that survive both inline and under SmartBilingual commit
            let classicEscapeCases: [(raw: String, expected: String)] = [
                ("caaa", "caa"),
                ("seee", "see"),
                ("tooo", "too"),
                ("ddd", "dd"),
                ("laww", "law"),
                ("raww", "raw"),
                ("showw", "show"),
                ("loww", "low"),
                ("uww", "uw"),
                ("seeed", "seed"),
                ("toool", "tool"),
                ("lawws", "laws")
            ]

            for tc in classicEscapeCases {
                let s = InputSessionManager()
                s.setGrammarProfile(profile)
                for ch in tc.raw {
                    _ = s.handleCharacter(ch)
                }
                XCTAssertEqual(s.currentOutput(), tc.expected, "Classic escape inline for '\(tc.raw)' [profile=\(profile)]")
                guard case let .commit(_, committed, _) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    XCTFail("Expected commit for '\(tc.raw)'")
                    continue
                }
                XCTAssertEqual(committed, tc.expected, "Classic escape commit for '\(tc.raw)' [profile=\(profile)]")
            }
        }
    }

    // MARK: - 5. Post-Coda Valid Vowel Reshape Preserved & Saturated Thereafter

    func testPostCodaVowelReshapeAndSubsequentSaturation() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // trường + o -> truồng (valid mutual-exclusion reshape), then + o -> truồngo (saturated, no circumflex strip)
            assertDualPlatformScript([
                ("t", "t"),
                ("r", "tr"),
                ("u", "tru"),
                ("o", "truo"),
                ("w", "trươ"),
                ("n", "trươn"),
                ("g", "trương"),
                ("f", "trường"),
                ("o", "truồng"),
                ("o", "truồngo"),
                ("<", "truồng"),
                ("<", "trường"),
                (" ", "trường ")
            ], profile: profile)
        }
    }

    // MARK: - 6. 'z' Clears Only Tone Marks, Never Structural Diacritics

    func testZKeyClearsOnlyToneMarksAndAppendsLiterallyWhenUntoned() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // trưởng + z -> trương + z -> trươngz
            assertDualPlatformScript([
                ("t", "t"), ("r", "tr"), ("u", "tru"), ("o", "truo"), ("w", "trươ"),
                ("n", "trươn"), ("g", "trương"), ("r", "trưởng"),
                ("z", "trương"),
                ("z", "trươngz"),
                ("<", "trương"),
                ("s", "trướng")
            ], profile: profile)

            // khiếm + z -> khiêm + z -> khiêmz
            assertDualPlatformScript([
                ("k", "k"), ("h", "kh"), ("i", "khi"), ("e", "khie"), ("e", "khiê"),
                ("m", "khiêm"), ("s", "khiếm"),
                ("z", "khiêm"),
                ("z", "khiêmz"),
                ("<", "khiêm")
            ], profile: profile)
        }
    }

    // MARK: - 7, 8 & 11. Step-by-Step Backspace, Retype, Tone Change & Continuation

    func testBackspaceRestoresSaturatedWordAndAllowsRetypeAndContinuation() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // 1. trưởng + w -> trưởngw -> ⌫ -> trưởng -> + s -> trướng -> + w -> trướngw -> ⌫ -> trướng -> Space
            assertDualPlatformScript([
                ("t", "t"), ("r", "tr"), ("u", "tru"), ("o", "truo"), ("w", "trươ"),
                ("n", "trươn"), ("g", "trương"), ("r", "trưởng"),
                ("w", "trưởngw"),
                ("<", "trưởng"),
                ("s", "trướng"),
                ("w", "trướngw"),
                ("<", "trướng"),
                (" ", "trướng ")
            ], profile: profile)

            // 2. khiêm (via khieem) + e -> khiême -> + n -> khiêmen -> ⌫ -> khiême -> ⌫ -> khiêm -> Space
            assertDualPlatformScript([
                ("k", "k"), ("h", "kh"), ("i", "khi"), ("e", "khie"), ("e", "khiê"), ("m", "khiêm"),
                ("e", "khiême"),
                ("n", "khiêmen"),
                ("<", "khiême"),
                ("<", "khiêm"),
                (" ", "khiêm ")
            ], profile: profile)

            // 3. hồng + o -> hồngo -> ⌫ -> hồng -> Space -> ⌫ -> + o -> hồngo -> Space
            assertDualPlatformScript([
                ("h", "h"), ("o", "ho"), ("o", "hô"), ("n", "hôn"), ("g", "hông"), ("f", "hồng"),
                ("o", "hồngo"),
                ("<", "hồng"),
                (" ", "hồng "),
                ("<", "hồng"),
                ("o", "hồngo"),
                (" ", "hồngo ")
            ], profile: profile)

            // 4. trưởng + Space -> ⌫ -> + w -> trưởngw -> ⌫ -> trưởng -> + o -> truổng
            assertDualPlatformScript([
                ("t", "t"), ("r", "tr"), ("u", "tru"), ("o", "truo"), ("w", "trươ"),
                ("n", "trươn"), ("g", "trương"), ("r", "trưởng"),
                (" ", "trưởng "),
                ("<", "trưởng"),
                ("w", "trưởngw"),
                ("<", "trưởng"),
                ("o", "truổng"),
                (" ", "truổng ")
            ], profile: profile)

            // 5. cửa + w -> cửaw -> ⌫ -> cửa -> Space
            assertDualPlatformScript([
                ("c", "c"), ("u", "cu"), ("w", "cư"), ("a", "cưa"), ("r", "cửa"),
                ("w", "cửaw"),
                ("<", "cửa"),
                (" ", "cửa ")
            ], profile: profile)

            // 6. cân (via caan and cana) + a -> câna -> ⌫ -> cân -> + s -> cấn
            assertDualPlatformScript([
                ("c", "c"), ("a", "ca"), ("a", "câ"), ("n", "cân"),
                ("a", "câna"),
                ("<", "cân"),
                ("s", "cấn")
            ], profile: profile)

            assertDualPlatformScript([
                ("c", "c"), ("a", "ca"), ("n", "can"), ("a", "cân"),
                ("a", "câna"),
                ("<", "cân"),
                ("s", "cấn")
            ], profile: profile)
        }
    }

    // MARK: - Acceptance: Multi-Order Telex State Equivalence

    func testMultiOrderTelexProducesIdenticalContinuationBehavior() {
        let truongOrders = ["truowngr", "truongwr", "truwongr", "trwuongr", "truongrw", "truwowngr"]
        for order in truongOrders {
            let s = InputSessionManager()
            s.setGrammarProfile(.senFlex)
            for ch in order { _ = s.handleCharacter(ch) }
            XCTAssertEqual(s.currentOutput(), "trưởng", "Order '\(order)' must form 'trưởng'")

            // + w -> trưởngw
            _ = s.handleCharacter("w")
            XCTAssertEqual(s.currentOutput(), "trưởngw", "Order '\(order)' + w must form 'trưởngw'")

            // Backspace -> trưởng
            _ = s.handleBackspace()
            XCTAssertEqual(s.currentOutput(), "trưởng", "Order '\(order)' + w + Backspace must restore 'trưởng'")

            // + o -> truổng
            _ = s.handleCharacter("o")
            XCTAssertEqual(s.currentOutput(), "truổng", "Order '\(order)' + o must reshape to 'truổng'")

            // + o -> truổngo (saturated)
            _ = s.handleCharacter("o")
            XCTAssertEqual(s.currentOutput(), "truổngo", "Order '\(order)' + oo must saturate at 'truổngo'")

            // Backspace -> truổng -> + w -> trưởng -> + z -> trương
            _ = s.handleBackspace()
            XCTAssertEqual(s.currentOutput(), "truổng")
            _ = s.handleCharacter("w")
            XCTAssertEqual(s.currentOutput(), "trưởng")
            _ = s.handleCharacter("z")
            XCTAssertEqual(s.currentOutput(), "trương")
        }

        let khiemOrders = ["khieem", "khieme"]
        for order in khiemOrders {
            let s = InputSessionManager()
            s.setGrammarProfile(.senFlex)
            for ch in order { _ = s.handleCharacter(ch) }
            XCTAssertEqual(s.currentOutput(), "khiêm", "Order '\(order)' must form 'khiêm'")
            _ = s.handleCharacter("e")
            XCTAssertEqual(s.currentOutput(), "khiême", "Order '\(order)' + e must form 'khiême'")
            _ = s.handleBackspace()
            XCTAssertEqual(s.currentOutput(), "khiêm", "Order '\(order)' + e + Backspace must restore 'khiêm'")
            _ = s.handleCharacter("s")
            XCTAssertEqual(s.currentOutput(), "khiếm", "Order '\(order)' + s must form 'khiếm'")
        }

        let canOrders = ["caan", "cana"]
        for order in canOrders {
            let s = InputSessionManager()
            s.setGrammarProfile(.senFlex)
            for ch in order { _ = s.handleCharacter(ch) }
            XCTAssertEqual(s.currentOutput(), "cân", "Order '\(order)' must form 'cân'")
            _ = s.handleCharacter("a")
            XCTAssertEqual(s.currentOutput(), "câna", "Order '\(order)' + a must form 'câna'")
            _ = s.handleBackspace()
            XCTAssertEqual(s.currentOutput(), "cân", "Order '\(order)' + a + Backspace must restore 'cân'")
        }
    }

    // MARK: - 9. SmartBilingualDetector Contextual Arbitration & Keystroke-by-Keystroke Intermediate States

    func testSmartBilingualContextualArbitrationForDelayedModifierCollisions() {
        // 1. Vietnamese context or no context -> preserves Vietnamese ('cân' via 'cana', 'thêm' via 'theem')
        assertDualPlatformScript([
            ("c", "c"), ("a", "ca"), ("n", "can"), ("a", "cân"), (" ", "cân ")
        ], context: "đặt lên")

        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("e", "thê"), ("m", "thêm"), (" ", "thêm ")
        ], context: "cần")

        // 2. Known post-coda vowel English words ('theme', 'Theme', 'meme', 'gene', 'data', 'photo') stay English inline in any context
        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("m", "them"), ("e", "theme"), (" ", "theme ")
        ], context: "cần")

        assertDualPlatformScript([
            ("c", "c"), ("a", "ca"), ("n", "can"), ("a", "cân"), (" ", "cana ")
        ], context: "water into wine at")

        assertDualPlatformScript([
            ("C", "C"), ("a", "Ca"), ("n", "Can"), ("a", "Cân"), (" ", "Cana ")
        ], context: "wedding at")

        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("m", "them"), ("e", "theme"), (" ", "theme ")
        ], context: "change the")

        assertDualPlatformScript([
            ("T", "T"), ("h", "Th"), ("e", "The"), ("m", "Them"), ("e", "Theme"), (" ", "Theme ")
        ], context: "select the")
    }

    func testKeystrokeByKeystrokeBilingualIntermediateStates() {
        // Requirement 4 (Condition 4): Evaluate every keystroke of 'cheese', 'theme', 'meme', 'here'
        // 1. 'here' & 'there':
        // - 'here' ('h-e-r-e') has delayed 'e' after tone 'r' forming valid Vietnamese 'hể' ('hể hả');
        //   without English context it preserves 'hể ', and with English context Space restores 'here '.
        // - 'there' ('t-h-e-r-e'): in inlineBilingual=true, restores immediately on the 5th keystroke ('there');
        //   in inlineBilingual=false, 'r' applies Hỏi tone ('thẻ'), trailing 'e' appends ('thẻe'), and Space restores 'there '.
        assertDualPlatformScript([
            ("h", "h"), ("e", "he"), ("r", "hẻ"), ("e", "hể"), (" ", "hể ")
        ], inlineBilingual: false)
        assertDualPlatformScript([
            ("h", "h"), ("e", "he"), ("r", "hẻ"), ("e", "hể"), (" ", "here ")
        ], inlineBilingual: false, context: "come over")

        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("r", "thẻ"), ("e", "there"), (" ", "there ")
        ], inlineBilingual: true)
        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("r", "thẻ"), ("e", "thẻe"), (" ", "there ")
        ], inlineBilingual: false)

        // 2. 'cheese':
        // - Under senFlex, the 6th key ('e') resolves 'cheese' immediately to 'cheese' (non-phonotactic 'chếe' vs known English 'cheese').
        // - Under classic, the 6th key ('e') saturates 'chế' -> 'chếe' (never stripping 'ê' to 'chée'), and Space restores 'cheese '.
        assertDualPlatformScript([
            ("c", "c"), ("h", "ch"), ("e", "che"), ("e", "chê"), ("s", "chế"), ("e", "cheese"), (" ", "cheese ")
        ], profile: .senFlex, inlineBilingual: false)

        assertDualPlatformScript([
            ("c", "c"), ("h", "ch"), ("e", "che"), ("e", "chê"), ("s", "chế"), ("e", "chếe"), (" ", "cheese ")
        ], profile: .classic, inlineBilingual: false)

        // 3. 'theme' & 'meme' vs 'theem' & 'meem':
        // - Post-coda vowel English words 'theme' & 'meme' remain English inline on the 4th/5th keystroke.
        // - Adjacent vowel doubling 'theem' & 'meem' forms 'thêm' & 'mêm'.
        assertDualPlatformScript([
            ("m", "m"), ("e", "me"), ("m", "mem"), ("e", "meme"), (" ", "meme ")
        ], inlineBilingual: false, context: "send the")

        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("m", "them"), ("e", "theme"), (" ", "theme ")
        ], inlineBilingual: false, context: "in the")

        assertDualPlatformScript([
            ("t", "t"), ("h", "th"), ("e", "the"), ("e", "thê"), ("m", "thêm"), (" ", "thêm ")
        ], inlineBilingual: false, context: "cần")
    }
}
