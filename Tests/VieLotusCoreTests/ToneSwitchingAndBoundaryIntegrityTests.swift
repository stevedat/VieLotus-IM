import XCTest
@testable import VieLotusCore

final class ToneSwitchingAndBoundaryIntegrityTests: XCTestCase {

    // MARK: - C. Per-Keystroke In-Memory Test Trace

    struct KeystrokeTraceEvent: Equatable {
        let physicalInputKey: String
        let previousSemanticState: String
        let modifierAndToneOwnership: String
        let activeModifiers: [Character]
        let supersededModifiers: [Character]
        let compositionSessionId: UInt64
        let commitReopenStatus: String
        let expectedUnicode: String
        let actualUnicode: String
        let nativeReplacementOperation: String
        let backspaceRestorationState: String
    }

    private final class TraceableProxy: TextDocumentProxyProtocol {
        var buffer: String = ""
        var contextOverride: String?? = nil
        var documentContextAfterInput: String? = nil
        private(set) var lastOperation: String = "noop"

        var documentContextBeforeInput: String? {
            if let override = contextOverride {
                return override
            }
            return buffer.isEmpty ? "" : buffer
        }

        func insertText(_ text: String) {
            buffer.append(text)
            lastOperation = "insert(\(text))"
        }

        func deleteBackward() {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            lastOperation = "deleteBackward"
        }

        func resetOperationLog() {
            lastOperation = "noop"
        }
    }

    private static func ownershipSummary(session: InputSessionManager) -> (summary: String, active: [Character], superseded: [Character]) {
        let activeVowels = session.engine.activeVowelModifiers
        let activeTone = session.engine.activeToneModifier
        var active = activeVowels
        if let activeTone {
            active.append(activeTone)
        }
        let superseded = session.engine.supersededModifiers
        let vowelDesc = activeVowels.isEmpty ? "none" : String(activeVowels)
        let toneDesc = activeTone.map { String($0) } ?? "none"
        return ("vowel:\(vowelDesc)|tone:\(toneDesc)", active, superseded)
    }

    private static func commitReopenStatus(session: InputSessionManager, key: Character, wasComposing: Bool, wasArmed: Bool) -> String {
        if key == " " {
            return wasComposing ? "committed" : "boundary-idle"
        }
        if key == "<" {
            if session.isComposing {
                return session.engine.isEditingCommittedWord ? "reopened-backspace" : "active-backspace"
            }
            if session.editCaretBack == 0 {
                return "armed-for-reopen"
            }
            return "idle-backspace"
        }
        if session.engine.isEditingCommittedWord || (wasArmed && !wasComposing && session.isComposing) {
            return "reopened"
        }
        return session.isComposing ? "active" : "idle"
    }

    /// Runs a keystroke script (where `<` represents Backspace) against the macOS adapter (`InputSessionManager`)
    /// and returns the per-keystroke trace.
    @discardableResult
    private func runMacOSTracedSequence(
        steps: [(key: Character, expectedBuffer: String)],
        profile: GrammarProfile = .senFlex,
        inlineBilingual: Bool = true
    ) -> [KeystrokeTraceEvent] {
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        session.setGrammarProfile(profile)
        session.smartBilingualEnabled = true
        session.inlineBilingualEnabled = inlineBilingual

        var buffer = ""
        var trace: [KeystrokeTraceEvent] = []

        for step in steps {
            let ch = step.key
            let prevSemantic = session.currentOutput()
            let wasComposing = session.isComposing
            let wasArmed = session.editCaretBack >= 0
            let nativeOp: String

            if ch == "<" {
                let action = session.handleBackspace()
                switch action {
                case .passThrough:
                    if !buffer.isEmpty { buffer.removeLast() }
                    nativeOp = "passThrough(deleteBackward)"
                case .reset:
                    if !buffer.isEmpty { buffer.removeLast() }
                    nativeOp = "reset(deleteBackward)"
                case let .replace(bs, text):
                    if bs > 0, buffer.count >= bs {
                        buffer.removeLast(bs)
                    } else if bs > 0 {
                        buffer.removeAll()
                    }
                    buffer.append(text)
                    nativeOp = "replace(bs:\(bs),text:\(text))"
                case .consumed, .commit:
                    nativeOp = "consumed"
                }
            } else if session.isWordBoundary(ch) {
                if session.isComposing {
                    let action = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    if case let .commit(bs, text, isOverride) = action {
                        if bs > 0, buffer.count >= bs {
                            buffer.removeLast(bs)
                        }
                        buffer.append(text)
                        buffer.append(ch)
                        nativeOp = "commit(bs:\(bs),text:\(text)\(ch),override:\(isOverride))"
                    } else {
                        buffer.append(ch)
                        nativeOp = "passThrough(\(ch))"
                    }
                } else {
                    session.resetCaret()
                    buffer.append(ch)
                    nativeOp = "passThrough(\(ch))"
                }
            } else {
                let action = session.handleCharacter(ch)
                switch action {
                case let .replace(bs, text):
                    if bs > 0, buffer.count >= bs {
                        buffer.removeLast(bs)
                    } else if bs > 0 {
                        buffer.removeAll()
                    }
                    buffer.append(text)
                    nativeOp = "replace(bs:\(bs),text:\(text))"
                case .passThrough:
                    buffer.append(ch)
                    nativeOp = "passThrough(\(ch))"
                case .consumed:
                    nativeOp = "consumed(noop)"
                case .reset:
                    nativeOp = "reset"
                case let .commit(bs, text, isOverride):
                    if bs > 0, buffer.count >= bs {
                        buffer.removeLast(bs)
                    }
                    buffer.append(text)
                    nativeOp = "commit(bs:\(bs),text:\(text),override:\(isOverride))"
                }
            }

            let ownership = Self.ownershipSummary(session: session)
            let status = Self.commitReopenStatus(session: session, key: ch, wasComposing: wasComposing, wasArmed: wasArmed)
            let bsRestore = session.engine.nextBackspaceRestorationState ?? ""
            let event = KeystrokeTraceEvent(
                physicalInputKey: ch == "<" ? "Backspace" : (ch == " " ? "Space" : String(ch)),
                previousSemanticState: prevSemantic,
                modifierAndToneOwnership: ownership.summary,
                activeModifiers: ownership.active,
                supersededModifiers: ownership.superseded,
                compositionSessionId: session.sessionGeneration,
                commitReopenStatus: status,
                expectedUnicode: step.expectedBuffer,
                actualUnicode: buffer,
                nativeReplacementOperation: nativeOp,
                backspaceRestorationState: bsRestore
            )
            trace.append(event)
            XCTAssertEqual(
                event.actualUnicode,
                event.expectedUnicode,
                "[macOS profile=\(profile)] Key '\(event.physicalInputKey)' after '\(prevSemantic)' expected '\(step.expectedBuffer)' got '\(buffer)' (raw='\(session.rawWord)', ownership='\(ownership.summary)', superseded=\(ownership.superseded))"
            )
        }
        return trace
    }

    /// Runs the exact same keystroke script against the iOS adapter (`UIKitInputSessionAdapter`)
    /// and returns the per-keystroke trace.
    @discardableResult
    private func runIOSTracedSequence(
        steps: [(key: Character, expectedBuffer: String)],
        profile: GrammarProfile = .senFlex
    ) -> [KeystrokeTraceEvent] {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(profile)
        let proxy = TraceableProxy()
        var trace: [KeystrokeTraceEvent] = []

        for step in steps {
            let ch = step.key
            let prevSemantic = adapter.session.currentOutput()
            let wasComposing = adapter.session.isComposing
            let wasArmed = adapter.session.editCaretBack >= 0
            let beforeBuffer = proxy.buffer
            proxy.resetOperationLog()

            if ch == "<" {
                adapter.handleBackspace(proxy: proxy)
            } else {
                adapter.handleCharacter(ch, proxy: proxy)
            }

            let afterBuffer = proxy.buffer
            let ownership = Self.ownershipSummary(session: adapter.session)
            let status = Self.commitReopenStatus(session: adapter.session, key: ch, wasComposing: wasComposing, wasArmed: wasArmed)
            let bsRestore = adapter.session.engine.nextBackspaceRestorationState ?? ""
            let nativeOp = "\(proxy.lastOperation)[\(beforeBuffer)->\(afterBuffer)]"

            let event = KeystrokeTraceEvent(
                physicalInputKey: ch == "<" ? "Backspace" : (ch == " " ? "Space" : String(ch)),
                previousSemanticState: prevSemantic,
                modifierAndToneOwnership: ownership.summary,
                activeModifiers: ownership.active,
                supersededModifiers: ownership.superseded,
                compositionSessionId: adapter.session.sessionGeneration,
                commitReopenStatus: status,
                expectedUnicode: step.expectedBuffer,
                actualUnicode: afterBuffer,
                nativeReplacementOperation: nativeOp,
                backspaceRestorationState: bsRestore
            )
            trace.append(event)
            XCTAssertEqual(
                event.actualUnicode,
                event.expectedUnicode,
                "[iOS profile=\(profile)] Key '\(event.physicalInputKey)' after '\(prevSemantic)' expected '\(step.expectedBuffer)' got '\(afterBuffer)' (raw='\(adapter.session.rawWord)', ownership='\(ownership.summary)', superseded=\(ownership.superseded))"
            )
        }
        return trace
    }

    private func assertDualAdapterSequence(
        _ steps: [(key: Character, expectedBuffer: String)],
        profiles: [GrammarProfile] = [.classic, .smartHybrid, .senFlex]
    ) {
        for profile in profiles {
            let macTrace = runMacOSTracedSequence(steps: steps, profile: profile)
            let iosTrace = runIOSTracedSequence(steps: steps, profile: profile)
            XCTAssertEqual(macTrace.count, steps.count)
            XCTAssertEqual(iosTrace.count, steps.count)
            for idx in 0..<steps.count {
                XCTAssertEqual(macTrace[idx].actualUnicode, iosTrace[idx].actualUnicode)
                XCTAssertEqual(macTrace[idx].activeModifiers, iosTrace[idx].activeModifiers)
                XCTAssertEqual(macTrace[idx].supersededModifiers, iosTrace[idx].supersededModifiers)
            }
        }
    }

    // MARK: - B.1 Late Vowel Modifiers (masa -> mấ, maja -> mậ, mafa -> mầ, mara -> mẩ, maxa -> mẫ)

    func testLateVowelModifiersAndReversibleBackspace() {
        let lateCases: [(toneKey: Character, toned: String, circumflexed: String)] = [
            ("s", "má", "mấ"),
            ("j", "mạ", "mậ"),
            ("f", "mà", "mầ"),
            ("r", "mả", "mẩ"),
            ("x", "mã", "mẫ")
        ]

        for tc in lateCases {
            // 1. Active composition + reversible Backspace (mấ -> má -> ma -> m -> "") + retype + Space commit
            let steps: [(key: Character, expectedBuffer: String)] = [
                ("m", "m"),
                ("a", "ma"),
                (tc.toneKey, tc.toned),
                ("a", tc.circumflexed),
                ("<", tc.toned),
                ("a", tc.circumflexed),
                ("<", tc.toned),
                ("<", "ma"),
                ("<", "m"),
                ("<", ""),
                ("m", "m"),
                ("a", "ma"),
                (tc.toneKey, tc.toned),
                ("a", tc.circumflexed),
                (" ", tc.circumflexed + " ")
            ]
            assertDualAdapterSequence(steps)

            // Verify trace fields on the late vowel step (`+a`)
            let trace = runMacOSTracedSequence(steps: Array(steps.prefix(4)))
            let lateStep = trace[3]
            XCTAssertEqual(lateStep.physicalInputKey, "a")
            XCTAssertEqual(lateStep.previousSemanticState, tc.toned)
            XCTAssertEqual(lateStep.actualUnicode, tc.circumflexed)
            XCTAssertEqual(lateStep.activeModifiers, ["a", tc.toneKey])
            XCTAssertEqual(lateStep.backspaceRestorationState, tc.toned)
        }
    }

    // MARK: - B.2 Repeated Tone Switching (masfj -> mạ, masfjs -> má)

    func testRepeatedToneSwitchingNeverAccumulatesHistoricalModifiers() {
        // masfj -> mạ within one active composition
        let masfjSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("a", "ma"),
            ("s", "má"),
            ("f", "mà"),
            ("j", "mạ")
        ]
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let macTrace = runMacOSTracedSequence(steps: masfjSteps, profile: profile)
            let iosTrace = runIOSTracedSequence(steps: masfjSteps, profile: profile)
            XCTAssertEqual(macTrace.last?.actualUnicode, "mạ")
            XCTAssertEqual(macTrace.last?.activeModifiers, ["j"])
            XCTAssertEqual(macTrace.last?.supersededModifiers, ["s", "f"])
            XCTAssertEqual(macTrace.last?.backspaceRestorationState, "ma")
            XCTAssertEqual(iosTrace.last?.actualUnicode, "mạ")
            XCTAssertEqual(iosTrace.last?.activeModifiers, ["j"])
            XCTAssertEqual(iosTrace.last?.supersededModifiers, ["s", "f"])
        }

        // masfjs -> má, followed by late vowel modifier (+a -> mấ), z tone-clear (-> mâ), and Backspace
        let masfjsSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("a", "ma"),
            ("s", "má"),
            ("f", "mà"),
            ("j", "mạ"),
            ("s", "má"),
            ("a", "mấ"),
            ("z", "mâ"),
            ("<", "mấ"),
            ("<", "má"),
            ("<", "ma"),
            ("<", "m"),
            ("<", "")
        ]
        assertDualAdapterSequence(masfjsSteps)
    }

    // MARK: - B.3 Space Boundary & Reopen Policy (majza reproduction & prevention)

    func testSpaceBoundaryPreventsMajzaLeakageAndHonorsVerifiedReopenPolicy() {
        // 1. maj + Space + z + a + Space -> preserves committed "mạ" and treats "za" as a separate token
        let separateTokenSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("a", "ma"),
            ("j", "mạ"),
            (" ", "mạ "),
            ("z", "mạ z"),
            ("a", "mạ za"),
            (" ", "mạ za ")
        ]
        assertDualAdapterSequence(separateTokenSteps)

        // 2. Direct active composition: maj + z + a -> "mạ" -> "ma" -> "mâ" (never "majza")
        let directMajzaSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("a", "ma"),
            ("j", "mạ"),
            ("z", "ma"),
            ("a", "mâ"),
            (" ", "mâ ")
        ]
        assertDualAdapterSequence(directMajzaSteps)

        // 3. Reopen after Space deletion with verified host context:
        // maj + Space + Backspace + z + a -> "mạ" -> "mạ " -> "mạ" -> "ma" -> "mâ" (never "majza")
        let reopenedMajzaSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("a", "ma"),
            ("j", "mạ"),
            (" ", "mạ "),
            ("<", "mạ"),
            ("z", "ma"),
            ("a", "mâ"),
            (" ", "mâ ")
        ]
        assertDualAdapterSequence(reopenedMajzaSteps)

        // 4. Reopen after Space deletion + late vowel modifier:
        // maj + Space + Backspace + a -> "mậ"
        let reopenedLateVowelSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("a", "ma"),
            ("j", "mạ"),
            (" ", "mạ "),
            ("<", "mạ"),
            ("a", "mậ"),
            (" ", "mậ ")
        ]
        assertDualAdapterSequence(reopenedLateVowelSteps)

        // 5. Unverified host context policy: if host context is nil or cursor moved after Space deletion,
        // reopen must be disarmed so committed "mạ" is never mutated and "za" is typed literally.
        let adapter = UIKitInputSessionAdapter()
        let proxy = TraceableProxy()
        for ch in "maj " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "mạ ")
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "mạ")

        // Simulate host returning nil documentContextBeforeInput (unverified context) outside XPC shadow window
        proxy.contextOverride = .some(nil)
        adapter.handleExternalTextChange(proxy: proxy)
        XCTAssertEqual(adapter.session.editCaretBack, InputSessionManager.caretDisarmed)

        proxy.contextOverride = nil
        proxy.buffer = "mạ "
        adapter.handleCharacter("z", proxy: proxy)
        adapter.handleCharacter("a", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "mạ za", "Unverified host context must not reopen or corrupt committed word")
    }

    // MARK: - B.4 Complex Words & Reported Failures (cairfs, mẹ/mè/mẻ/mẽ/mế/mệ, cá/cà/cả/cã/cạ, cải/cài/cái/cãi/cại)

    func testComplexWordsAndCairfsReproduction() {
        // 1. Reproduce reported failure `cairfs` and verify cải -> cài -> cái -> cãi -> cại + z + Backspace + Space
        let cairfsSteps: [(key: Character, expectedBuffer: String)] = [
            ("c", "c"),
            ("a", "ca"),
            ("i", "cai"),
            ("r", "cải"),
            ("f", "cài"),
            ("s", "cái"),
            ("x", "cãi"),
            ("j", "cại"),
            ("s", "cái"),
            ("z", "cai"),
            ("<", "cái"),
            ("<", "cai"),
            ("r", "cải"),
            ("f", "cài"),
            ("s", "cái"),
            (" ", "cái "),
            ("<", "cái"),
            ("r", "cải"),
            (" ", "cải ")
        ]
        assertDualAdapterSequence(cairfsSteps)

        // 2. Family: mẹ, mè, mẻ, mẽ, mế, mệ (tone switching + late circumflex 'e' + 'z' tone-only cancellation)
        let meSteps: [(key: Character, expectedBuffer: String)] = [
            ("m", "m"),
            ("e", "me"),
            ("j", "mẹ"),
            ("f", "mè"),
            ("r", "mẻ"),
            ("x", "mẽ"),
            ("s", "mé"),
            ("e", "mế"),
            ("j", "mệ"),
            ("f", "mề"),
            ("r", "mể"),
            ("x", "mễ"),
            ("s", "mế"),
            ("z", "mê"), // 'z' cancels tone only, preserving circumflex 'ê'
            ("j", "mệ"),
            ("<", "mê"),
            ("<", "me"),
            ("j", "mẹ"),
            ("e", "mệ"),
            ("<", "mẹ"), // Backspace reverses late vowel modifier 'e' -> 'mẹ'
            (" ", "mẹ ")
        ]
        assertDualAdapterSequence(meSteps)

        // 3. Family: cá, cà, cả, cã, cạ (repeated tone switching + late vowel modifier + reopen)
        let caSteps: [(key: Character, expectedBuffer: String)] = [
            ("c", "c"),
            ("a", "ca"),
            ("s", "cá"),
            ("f", "cà"),
            ("r", "cả"),
            ("x", "cã"),
            ("j", "cạ"),
            ("s", "cá"),
            ("z", "ca"),
            ("<", "cá"),
            (" ", "cá "),
            ("<", "cá"),
            ("f", "cà"),
            ("r", "cả"),
            ("x", "cã"),
            ("j", "cạ"),
            (" ", "cạ ")
        ]
        assertDualAdapterSequence(caSteps)
    }

    // MARK: - A.8 & A.10 Tone-Only 'z' Cancellation & Invalid Transformation Rejection

    func testZToneOnlyCancellationPreservesVowelModifiersAndStrokeD() {
        // 'độ' + 'z' -> 'đô', 'được' + 'z' -> 'đươc', 'mẫ' + 'z' -> 'mâ', 'mặ' + 'z' -> 'mă'
        let zCases: [[(key: Character, expectedBuffer: String)]] = [
            [
                ("d", "d"), ("d", "đ"), ("o", "đo"), ("o", "đô"), ("j", "độ"),
                ("z", "đô"), ("s", "đố"), ("z", "đô"), (" ", "đô ")
            ],
            [
                ("d", "d"), ("d", "đ"), ("u", "đu"), ("o", "đuo"), ("w", "đươ"), ("c", "đươc"), ("j", "được"),
                ("z", "đươc"), ("s", "đước"), ("j", "được"), ("z", "đươc"), (" ", "đươc ")
            ],
            [
                ("m", "m"), ("a", "ma"), ("w", "mă"), ("j", "mặ"), ("s", "mắ"),
                ("z", "mă"), ("n", "măn"), ("s", "mắn"), ("z", "măn"), (" ", "măn ")
            ]
        ]
        for zc in zCases {
            assertDualAdapterSequence(zc)
        }
    }

    func testFocusChangeAndCursorMovementIsolationAcrossAdapters() {
        let adapter = UIKitInputSessionAdapter()
        let proxy = TraceableProxy()

        // Type 'masfj' -> 'mạ'
        for ch in "masfj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "mạ")
        let gen1 = adapter.session.sessionGeneration

        // Simulate focus change / cursor move to a new text field
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        XCTAssertFalse(adapter.session.isComposing)
        XCTAssertNotEqual(adapter.session.sessionGeneration, gen1)

        // Typing 'za' in the new context must never leak previous composition modifiers
        for ch in "za " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "za ")
    }

    // MARK: - P0 Word Boundary, Adjacent Digit/Punctuation Context & Double-Space Auto-Period

    func testP0WordBoundaryDigitAndDotContextRegression() {
        // 1. Keystroke-by-keystroke verification (no Space required to transform!) across both InputSessionManager and UIKitInputSessionAdapter
        let keystrokeSequences: [[(key: Character, expectedBuffer: String)]] = [
            // 'haf' -> 'hà'
            [("h", "h"), ("a", "ha"), ("f", "hà")],
            // 'Haf' -> 'Hà'
            [("H", "H"), ("a", "Ha"), ("f", "Hà")],
            // 'haf.' -> 'hà.'
            [("h", "h"), ("a", "ha"), ("f", "hà"), (".", "hà.")],
            // 'Haf.' -> 'Hà.'
            [("H", "H"), ("a", "Ha"), ("f", "Hà"), (".", "Hà.")],
            // '.haf' -> '.hà'
            [(".", "."), ("h", ".h"), ("a", ".ha"), ("f", ".hà")],
            // '0979haf' -> '0979hà'
            [("0", "0"), ("9", "09"), ("7", "097"), ("9", "0979"), ("h", "0979h"), ("a", "0979ha"), ("f", "0979hà")],
            // 'haf0979' -> 'hà0979'
            [("h", "h"), ("a", "ha"), ("f", "hà"), ("0", "hà0"), ("9", "hà09"), ("7", "hà097"), ("9", "hà0979")],
            // '0979haf haf0979' -> '0979hà hà0979'
            [
                ("0", "0"), ("9", "09"), ("7", "097"), ("9", "0979"),
                ("h", "0979h"), ("a", "0979ha"), ("f", "0979hà"),
                (" ", "0979hà "),
                ("h", "0979hà h"), ("a", "0979hà ha"), ("f", "0979hà hà"),
                ("0", "0979hà hà0"), ("9", "0979hà hà09"), ("7", "0979hà hà097"), ("9", "0979hà hà0979")
            ],
            // Backspace & re-type inside digit/dot contexts
            [
                ("0", "0"), ("9", "09"), ("7", "097"), ("9", "0979"),
                ("h", "0979h"), ("a", "0979ha"), ("f", "0979hà"),
                ("<", "0979ha"), ("s", "0979há"), ("f", "0979hà"), (".", "0979hà."),
                ("<", "0979hà")
            ],
            // Stale dot-prefix isolation on intervening space, double-dot, or Backspace:
            // 'haf. com' -> 'hà. com' (never 'hhaf.com')
            [
                ("h", "h"), ("a", "ha"), ("f", "hà"), (".", "hà."),
                (" ", "hà. "), ("c", "hà. c"), ("o", "hà. co"), ("m", "hà. com")
            ],
            // 'haf..com' -> 'hà..com' (never 'hhaf.com')
            [
                ("h", "h"), ("a", "ha"), ("f", "hà"), (".", "hà."),
                (".", "hà.."), ("c", "hà..c"), ("o", "hà..co"), ("m", "hà..com")
            ],
            // 'os. path' -> 'ó. path'
            [
                ("o", "o"), ("s", "ó"), (".", "ó."),
                (" ", "ó. "), ("p", "ó. p"), ("a", "ó. pa"), ("t", "ó. pat"), ("h", "ó. path")
            ],
            // 'os..path' -> 'ó..path'
            [
                ("o", "o"), ("s", "ó"), (".", "ó."),
                (".", "ó.."), ("p", "ó..p"), ("a", "ó..pa"), ("t", "ó..pat"), ("h", "ó..path")
            ],
            // 'haf.x< com' -> 'hà. com'
            [
                ("h", "h"), ("a", "ha"), ("f", "hà"), (".", "hà."),
                ("x", "hà.x"), ("<", "hà."), (" ", "hà. "), ("c", "hà. c"), ("o", "hà. co"), ("m", "hà. com")
            ],
            // 'haf.x<<com' -> 'hàcom'
            [
                ("h", "h"), ("a", "ha"), ("f", "hà"), (".", "hà."),
                ("x", "hà.x"), ("<", "hà."), ("<", "hà"), ("c", "hàc"), ("o", "hàco"), ("m", "hàcom")
            ],
            // 'haf.x<com' -> 'haf.com'
            [
                ("h", "h"), ("a", "ha"), ("f", "hà"), (".", "hà."),
                ("x", "hà.x"), ("<", "hà."), ("c", "hà.c"), ("o", "hà.co"), ("m", "haf.com")
            ]
        ]

        for seq in keystrokeSequences {
            assertDualAdapterSequence(seq)
        }

        // 2. Distinguish directly typed '.' from double-space auto-period shortcut ('applyDoubleSpacePeriodShortcut')
        let adapter = UIKitInputSessionAdapter()
        let proxy = TraceableProxy()
        for ch in "Haf" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "Hà")
        // First space commits 'Hà '
        adapter.commitWord(proxy: proxy, suffix: " ")
        XCTAssertEqual(proxy.buffer, "Hà ")
        // Second space triggers double-space period shortcut -> 'Hà. '
        adapter.applyDoubleSpacePeriodShortcut(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hà. ")
        XCTAssertEqual(adapter.session.editCaretBack, InputSessionManager.caretDisarmed)
        // Subsequent Vietnamese word after double-space period transforms immediately
        for ch in "haf" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "Hà. hà")

        // 3. Preserve URLs, emails, dotted modules/domains, code identifiers, and alphanumeric tokens
        let preservedCases: [(input: String, expected: String)] = [
            ("os.path", "os.path"),
            ("haf.com", "haf.com"),
            ("haf.com.vn", "haf.com.vn"),
            ("haf.co.uk", "haf.co.uk"),
            ("vielotus.vn", "vielotus.vn"),
            ("https://api.senprints.com/mcp", "https://api.senprints.com/mcp"),
            ("www.google.com", "www.google.com"),
            ("user@example.com", "user@example.com"),
            ("is_valid", "is_valid"),
            ("v2.0", "v2.0"),
            ("a1s", "a1s"),
            ("x2f", "x2f")
        ]
        for tc in preservedCases {
            let pAdapter = UIKitInputSessionAdapter()
            let pProxy = TraceableProxy()
            for ch in tc.input {
                pAdapter.handleCharacter(ch, proxy: pProxy)
            }
            if pAdapter.session.isComposing {
                pAdapter.commitWord(proxy: pProxy)
            }
            XCTAssertEqual(pProxy.buffer, tc.expected, "Preserved token '\(tc.input)' must remain '\(tc.expected)'")
        }
    }

    // MARK: - Trailing 'd' / 'dd' Scope & Replay-Safe Backspace Verification

    func testTrailingDDScopePreservesCompletedSyllableAndRawLedger() {
        let cases: [(stemRaw: String, stemExpected: String, after1D: String, after2D: String, after3D: String, afterSemanticBs: String, retypeKey: Character)] = [
            ("dduocjw", "được", "dược", "dượcđ", "dượcdd", "đươc", "j"),
            ("ddungs", "đúng", "dúng", "dúngđ", "dúngdd", "đung", "s"),
            ("ddas", "đá", "dá", "dáđ", "dádd", "đa", "s")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for tc in cases {
                let session = InputSessionManager()
                session.setGrammarProfile(profile)
                session.smartBilingualEnabled = true
                session.inlineBilingualEnabled = true

                for ch in tc.stemRaw {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(session.currentOutput(), tc.stemExpected, "profile=\(profile): stem '\(tc.stemRaw)'")

                // 1st trailing 'd' cancels initial 'đ' -> 'd' ("được" -> "dược")
                _ = session.handleCharacter("d")
                XCTAssertEqual(session.currentOutput(), tc.after1D, "profile=\(profile): +1 'd' on '\(tc.stemRaw)'")

                // 2nd trailing 'd' forms trailing 'đ' while keeping initial 'd' ("dượcđ", matching Apple Telex iOS)
                _ = session.handleCharacter("d")
                XCTAssertEqual(session.currentOutput(), tc.after2D, "profile=\(profile): +2 'd' on '\(tc.stemRaw)'")
                XCTAssertEqual(session.rawWord, tc.stemRaw + "dd")

                // 3rd trailing 'd' cancels trailing 'đ' -> 'dd' ("dượcdd", matching Apple Telex & Gboard)
                _ = session.handleCharacter("d")
                XCTAssertEqual(session.currentOutput(), tc.after3D, "profile=\(profile): +3 'd' on '\(tc.stemRaw)'")
                XCTAssertEqual(session.rawWord, tc.stemRaw + "ddd")

                // Backspace chain: "dượcdd" -> "dượcđ" -> "dược" -> "được" -> "đươc"
                _ = session.handleBackspace()
                XCTAssertEqual(session.currentOutput(), tc.after2D, "profile=\(profile): Backspace 1 from '\(tc.after3D)'")
                _ = session.handleBackspace()
                XCTAssertEqual(session.currentOutput(), tc.after1D, "profile=\(profile): Backspace 2 from '\(tc.after2D)'")
                _ = session.handleBackspace()
                XCTAssertEqual(session.currentOutput(), tc.stemExpected, "profile=\(profile): Backspace 3 restores '\(tc.stemExpected)'")
                _ = session.handleBackspace()
                XCTAssertEqual(session.currentOutput(), tc.afterSemanticBs, "profile=\(profile): Backspace 4 strips tone")
                _ = session.handleCharacter(tc.retypeKey)
                XCTAssertEqual(session.currentOutput(), tc.stemExpected, "profile=\(profile): re-typing tone restores '\(tc.stemExpected)'")

                // Verify Space commit on 2nd 'd' ("dượcđ") and 3rd 'd' ("dượcdd") never reverts to raw ASCII
                for (suffix, expectedCommitted) in [("dd", tc.after2D), ("ddd", tc.after3D)] {
                    let s2 = InputSessionManager()
                    s2.setGrammarProfile(profile)
                    s2.smartBilingualEnabled = true
                    s2.inlineBilingualEnabled = true
                    for ch in (tc.stemRaw + suffix) {
                        _ = s2.handleCharacter(ch)
                    }
                    XCTAssertEqual(s2.currentOutput(), expectedCommitted)
                    guard case let .commit(_, committedText, isOverride) = s2.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                        return XCTFail("Expected commit for '\(tc.stemRaw + suffix)'")
                    }
                    XCTAssertEqual(committedText, expectedCommitted, "profile=\(profile): commit of '\(tc.stemRaw + suffix)' must preserve '\(expectedCommitted)'")
                    XCTAssertFalse(isOverride)
                }
            }
        }
    }

    func testDuongAllKeystrokeOrdersAndNeverRawCollapseOnMacOSAndIOS() {
        let duongOrders = [
            "dduowngf",
            "dduongwf",
            "dduongfw",
            "dduwongf",
            "dduwowngf",
            "dudowngf",
            "duowngdf",
            "duowngfd",
            "duongwdf",
            "duongwfd",
            "duwongdf",
            "duwongfd",
            "duongdwf",
            "duongdfw",
            "duongfdw"
        ]

        let antiRawCollapseCases: [(raw: String, expected: String)] = [
            ("duowngd", "đương"),
            ("duwongd", "đương"),
            ("duongdw", "đương"),
            ("duowngdf", "đường"),
            ("duowngfd", "đường"),
            ("duwongdf", "đường"),
            ("duwongfd", "đường"),
            ("duongdwf", "đường"),
            ("duongdfw", "đường"),
            ("duongfdw", "đường"),
            ("duowngdfd", "dường"),
            ("duowngdfdd", "dườngđ"),
            ("duowngdfddd", "dườngdd"),
            ("duowngfdd", "dường"),
            ("duowngfddd", "dườngđ"),
            ("duowngfdddd", "dườngdd"),
            ("dduowngdfd", "đường"),
            ("dduowngdfdd", "dường"),
            ("dduowngdfddd", "dườngđ"),
            ("dduowngffd", "đươngfd"),
            ("dduowngffdd", "đươngfdd"),
            ("dduowngffddd", "đươngfddd"),
            ("dduowngffw", "đươngfw"),
            ("dduowngddff", "dươngđff"),
            ("dduowngfddf", "dườngđf"),
            ("duowngfdu", "đườngu"),
            ("duowngfddu", "dườngu"),
            ("duowngfdddu", "dườngđu"),
            ("duowngdfdu", "dườngu"),
            ("duocwjd", "được"),
            ("duocdwj", "được"),
            ("duodcwj", "được"),
            ("dudocwj", "được"),
            ("duocwjdu", "đượcu"),
            ("duocwjddu", "dượcu"),
            ("duocwjdddu", "dượcđu"),
            ("duocdwjdu", "dượcu"),
            ("duodcwjdu", "dượcu"),
            ("dudocwjdu", "dượcu")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for order in duongOrders {
                // 1. macOS InputSessionManager
                let session = InputSessionManager()
                session.setGrammarProfile(profile)
                session.smartBilingualEnabled = true
                session.inlineBilingualEnabled = true
                for ch in order {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(session.composingWord, "đường", "macOS profile=\(profile) order='\(order)' must compose 'đường'")

                // Pressing 'd' on "đường" cancels initial 'đ' -> 'd' ("dường"), never "dươngdfd" or "dươngfđ"
                _ = session.handleCharacter("d")
                XCTAssertEqual(session.composingWord, "dường", "macOS profile=\(profile) order='\(order)' + d must produce 'dường'")

                // Pressing 'd' again forms "dườngđ"
                _ = session.handleCharacter("d")
                XCTAssertEqual(session.composingWord, "dườngđ", "macOS profile=\(profile) order='\(order)' + dd must produce 'dườngđ'")

                // Pressing 'd' a 3rd time forms "dườngdd"
                _ = session.handleCharacter("d")
                XCTAssertEqual(session.composingWord, "dườngdd", "macOS profile=\(profile) order='\(order)' + ddd must produce 'dườngdd'")

                // Backspace x3 restores "dườngđ" -> "dường" -> "đường"
                _ = session.handleBackspace()
                XCTAssertEqual(session.composingWord, "dườngđ", "macOS profile=\(profile) order='\(order)' Backspace 1")
                _ = session.handleBackspace()
                XCTAssertEqual(session.composingWord, "dường", "macOS profile=\(profile) order='\(order)' Backspace 2")
                _ = session.handleBackspace()
                XCTAssertEqual(session.composingWord, "đường", "macOS profile=\(profile) order='\(order)' Backspace 3")

                // 2. iOS UIKitInputSessionAdapter
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setGrammarProfile(profile)
                adapter.session.smartBilingualEnabled = true
                adapter.session.inlineBilingualEnabled = true
                let proxy = TraceableProxy()
                for ch in order {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "đường", "iOS profile=\(profile) order='\(order)' must compose 'đường'")
                adapter.handleCharacter("d", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "dường", "iOS profile=\(profile) order='\(order)' + d must produce 'dường'")
                adapter.handleCharacter("d", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "dườngđ", "iOS profile=\(profile) order='\(order)' + dd must produce 'dườngđ'")
                adapter.handleCharacter("d", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "dườngdd", "iOS profile=\(profile) order='\(order)' + ddd must produce 'dườngdd'")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "dườngđ", "iOS profile=\(profile) order='\(order)' Backspace 1")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "dường", "iOS profile=\(profile) order='\(order)' Backspace 2")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "đường", "iOS profile=\(profile) order='\(order)' Backspace 3")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "đường ", "iOS profile=\(profile) order='\(order)' Space commit")
            }

            for tc in antiRawCollapseCases {
                let session = InputSessionManager()
                session.setGrammarProfile(profile)
                session.smartBilingualEnabled = true
                session.inlineBilingualEnabled = true
                for ch in tc.raw {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(session.composingWord, tc.expected, "macOS profile=\(profile) raw='\(tc.raw)' inline")
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(tc.raw)'")
                }
                XCTAssertEqual(committedText, tc.expected, "macOS profile=\(profile) raw='\(tc.raw)' commit")
                XCTAssertFalse(isOverride, "macOS profile=\(profile) raw='\(tc.raw)' must never revert to raw ASCII")

                let adapter = UIKitInputSessionAdapter()
                adapter.session.setGrammarProfile(profile)
                adapter.session.smartBilingualEnabled = true
                adapter.session.inlineBilingualEnabled = true
                let proxy = TraceableProxy()
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, tc.expected, "iOS profile=\(profile) raw='\(tc.raw)' inline")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expected + " ", "iOS profile=\(profile) raw='\(tc.raw)' commit")
            }
        }
    }

    func testDuocAllKeystrokeOrdersAndPostCodaContinuationIntegrity() {
        let universalDuocOrders = [
            "dduowcj",
            "dduocwj",
            "dduocjw",
            "dduwocj",
            "dduwowcj",
            "duocwjd",
            "duocjwd",
            "duowcjd",
            "duwocjd",
            "duowcdj",
            "dudowcj",
            "duodcwj"
        ]
        let flexOnlyDuocOrders = [
            "dduowjc",
            "ddwuocj"
        ]

        let literalSingleChars: [Character] = [
            "a", "b", "c", "e", "f", "g", "h", "i", "k", "l",
            "m", "n", "p", "q", "r", "t", "u", "v", "x", "y"
        ]

        let multiCharSuffixExpectations: [(suffix: String, expected: String)] = [
            ("a", "đượca"),
            ("aa", "đượcaa"),
            ("aaa", "đượcaaa"),
            ("aau", "đượcaau"),
            ("ae", "đượcae"),
            ("an", "đượcan"),
            ("e", "đượce"),
            ("ee", "đượcee"),
            ("eee", "đượceee"),
            ("ees", "đượcees"),
            ("eu", "đượceu"),
            ("u", "đượcu"),
            ("uu", "đượcuu"),
            ("sh", "đướch"),
            ("sa", "đướca"),
            ("saa", "đướcaa"),
            ("z", "đươc"),
            ("zb", "đươcb"),
            ("zbs", "đươcbs"),
            ("za", "đươca"),
            ("zas", "đươcas"),
            ("zno", "đươcno"),
            ("zz", "đươcz"),
            ("zzs", "đươczs"),
            ("w", "đượcw"),
            ("wa", "đượcwa"),
            ("waa", "đượcwaa"),
            ("wo", "đượcwo"),
            ("woo", "đượcwoo"),
            ("wooo", "đượcwooo"),
            ("d", "dược"),
            ("da", "dượca"),
            ("daa", "dượcaa"),
            ("dan", "dượcan"),
            ("du", "dượcu"),
            ("db", "dượcb"),
            ("dz", "dươc"),
            ("dzb", "dươcb"),
            ("dzw", "dươcw"),
            ("dwz", "dượcwz"),
            ("od", "duộc"),
            ("odz", "duôc"),
            ("odzb", "duôcb")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let activeOrders = profile == .classic ? universalDuocOrders : (universalDuocOrders + flexOnlyDuocOrders)
            for order in activeOrders {
                // 1. Verify every non-modifier single character appends literally as "được<c>" and survives Space commit
                for c1 in literalSingleChars {
                    let s = InputSessionManager()
                    s.setGrammarProfile(profile)
                    s.smartBilingualEnabled = true
                    s.inlineBilingualEnabled = true
                    for ch in order { _ = s.handleCharacter(ch) }
                    XCTAssertEqual(s.currentOutput(), "được", "profile=\(profile) order=\(order)")
                    _ = s.handleCharacter(c1)
                    let expected1 = "được\(c1)"
                    XCTAssertEqual(s.currentOutput(), expected1, "profile=\(profile) order=\(order) +\(c1) inline")
                    guard case let .commit(_, committed1, isOverride1) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                        return XCTFail("Expected commit for \(order)+\(c1)")
                    }
                    XCTAssertEqual(committed1, expected1, "profile=\(profile) order=\(order) +\(c1) commit")
                    XCTAssertFalse(isOverride1)
                }

                // 2. Verify multi-char continuations on both macOS InputSessionManager and iOS UIKitInputSessionAdapter
                for tc in multiCharSuffixExpectations {
                    let s = InputSessionManager()
                    s.setGrammarProfile(profile)
                    s.smartBilingualEnabled = true
                    s.inlineBilingualEnabled = true
                    for ch in (order + tc.suffix) {
                        _ = s.handleCharacter(ch)
                    }
                    XCTAssertEqual(s.currentOutput(), tc.expected, "macOS profile=\(profile) order=\(order) suffix='\(tc.suffix)' inline")
                    guard case let .commit(_, committed, isOverride) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                        return XCTFail("Expected commit for \(order)+\(tc.suffix)")
                    }
                    XCTAssertEqual(committed, tc.expected, "macOS profile=\(profile) order=\(order) suffix='\(tc.suffix)' commit")
                    XCTAssertFalse(isOverride, "macOS profile=\(profile) order=\(order) suffix='\(tc.suffix)' must never revert to raw ASCII")

                    let adapter = UIKitInputSessionAdapter()
                    adapter.session.setGrammarProfile(profile)
                    adapter.session.smartBilingualEnabled = true
                    adapter.session.inlineBilingualEnabled = true
                    let proxy = TraceableProxy()
                    for ch in (order + tc.suffix) {
                        adapter.handleCharacter(ch, proxy: proxy)
                    }
                    XCTAssertEqual(proxy.buffer, tc.expected, "iOS profile=\(profile) order=\(order) suffix='\(tc.suffix)' inline")
                    adapter.handleCharacter(" ", proxy: proxy)
                    XCTAssertEqual(proxy.buffer, tc.expected + " ", "iOS profile=\(profile) order=\(order) suffix='\(tc.suffix)' commit")
                }
            }

            // 3. Adjacent double-tone 'jj' escape on canonical "dduowcj" + continuations ("j", "ja", "jaa", "jss")
            for (suffix, expected) in [("j", "đươcj"), ("ja", "đươcja"), ("jaa", "đươcjaa"), ("jss", "đươcjss")] {
                let s = InputSessionManager()
                s.setGrammarProfile(profile)
                s.smartBilingualEnabled = true
                s.inlineBilingualEnabled = true
                for ch in ("dduowcj" + suffix) {
                    _ = s.handleCharacter(ch)
                }
                XCTAssertEqual(s.currentOutput(), expected, "profile=\(profile) dduowcj+\(suffix) inline")
                guard case let .commit(_, committed, isOverride) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for dduowcj+\(suffix)")
                }
                XCTAssertEqual(committed, expected, "profile=\(profile) dduowcj+\(suffix) commit")
                XCTAssertFalse(isOverride)
            }
        }
    }

    func testOffglideAndOpenSyllablePostContinuationNeverCollapsesToRaw() {
        // Step-by-step traces for "nếu" + "eu" (neeuseu -> nếueu), "chiều" + "eu" (chieeufeu -> chiềueu),
        // and "điều" + "eu" (ddieeufeu -> điềueu) including Backspace recovery and Space commit.
        let neeuseuSteps: [(key: Character, expectedBuffer: String)] = [
            ("n", "n"),
            ("e", "ne"),
            ("e", "nê"),
            ("u", "nêu"),
            ("s", "nếu"),
            ("e", "nếue"),
            ("u", "nếueu"),
            ("<", "nếue"),
            ("<", "nếu"),
            ("e", "nếue"),
            ("u", "nếueu"),
            (" ", "nếueu ")
        ]
        assertDualAdapterSequence(neeuseuSteps)

        let chieeufeuSteps: [(key: Character, expectedBuffer: String)] = [
            ("c", "c"),
            ("h", "ch"),
            ("i", "chi"),
            ("e", "chie"),
            ("e", "chiê"),
            ("u", "chiêu"),
            ("f", "chiều"),
            ("e", "chiềue"),
            ("u", "chiềueu"),
            ("<", "chiềue"),
            ("<", "chiều"),
            ("e", "chiềue"),
            ("u", "chiềueu"),
            (" ", "chiềueu ")
        ]
        assertDualAdapterSequence(chieeufeuSteps)

        let ddieeufeuSteps: [(key: Character, expectedBuffer: String)] = [
            ("d", "d"),
            ("d", "đ"),
            ("i", "đi"),
            ("e", "đie"),
            ("e", "điê"),
            ("u", "điêu"),
            ("f", "điều"),
            ("e", "điềue"),
            ("u", "điềueu"),
            ("<", "điềue"),
            ("<", "điều"),
            ("e", "điềue"),
            ("u", "điềueu"),
            (" ", "điềueu ")
        ]
        assertDualAdapterSequence(ddieeufeuSteps)

        let continuationCases: [(raw: String, expected: String)] = [
            ("neeuse", "nếue"),
            ("neeuseu", "nếueu"),
            ("neeuseeu", "nếueeu"),
            ("neeusu", "nếuu"),
            ("neeusb", "nếub"),
            ("chieeufe", "chiềue"),
            ("chieeufeu", "chiềueu"),
            ("chieeufeeu", "chiềueeu"),
            ("chieeufu", "chiềuu"),
            ("chieeufb", "chiềub"),
            ("ddieeufe", "điềue"),
            ("ddieeufeu", "điềueu"),
            ("ddieeufeeu", "điềueeu"),
            ("ddieeufu", "điềuu"),
            ("ddieeufb", "điềub"),
            ("nhieeufe", "nhiềue"),
            ("nhieeufeu", "nhiềueu"),
            ("nhieeufu", "nhiềuu"),
            ("nguowifeu", "ngườieu"),
            ("nguowifb", "ngườib"),
            ("tooiseu", "tốieu"),
            ("tuooireu", "tuổieu"),
            ("ddaaufeu", "đầueu"),
            ("ddaayseu", "đấyeu"),
            ("mowiseu", "mớieu"),
            ("cuwareu", "cửaeu"),
            ("cuwarb", "cửab")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for tc in continuationCases {
                let s = InputSessionManager()
                s.setGrammarProfile(profile)
                s.smartBilingualEnabled = true
                s.inlineBilingualEnabled = true
                for ch in tc.raw {
                    _ = s.handleCharacter(ch)
                }
                XCTAssertEqual(s.currentOutput(), tc.expected, "macOS profile=\(profile) raw='\(tc.raw)' inline")
                XCTAssertNotEqual(s.currentOutput(), tc.raw, "macOS profile=\(profile) raw='\(tc.raw)' must never collapse to raw")
                guard case let .commit(_, committed, isOverride) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(tc.raw)'")
                }
                XCTAssertEqual(committed, tc.expected, "macOS profile=\(profile) raw='\(tc.raw)' commit")
                XCTAssertFalse(isOverride, "macOS profile=\(profile) raw='\(tc.raw)' must never revert to raw on commit")

                let adapter = UIKitInputSessionAdapter()
                adapter.session.setGrammarProfile(profile)
                adapter.session.smartBilingualEnabled = true
                adapter.session.inlineBilingualEnabled = true
                let proxy = TraceableProxy()
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, tc.expected, "iOS profile=\(profile) raw='\(tc.raw)' inline")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expected + " ", "iOS profile=\(profile) raw='\(tc.raw)' commit")
            }
        }
    }

    func testArrDoubleTapToneEscapeProducesAr() {
        let cases: [(raw: String, expected: String)] = [
            ("ar", "ả"),
            ("arr", "ar"),
            ("Arr", "Ar"),
            ("ARR", "AR"),
            ("arrr", "arr"),
            ("er", "ẻ"),
            ("err", "er"),
            ("or", "ỏ"),
            ("orr", "or")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for tc in cases {
                let s = InputSessionManager()
                s.setGrammarProfile(profile)
                s.smartBilingualEnabled = true
                s.inlineBilingualEnabled = true
                s.bilingualNoContextPolicy = .standardVietnameseFirst
                for ch in tc.raw {
                    _ = s.handleCharacter(ch)
                }
                XCTAssertEqual(s.currentOutput(), tc.expected, "macOS profile=\(profile) raw='\(tc.raw)' inline")
                guard case let .commit(_, committed, _) = s.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(tc.raw)'")
                }
                XCTAssertEqual(committed, tc.expected, "macOS profile=\(profile) raw='\(tc.raw)' commit")
            }

            // Code delimiter boundary (`[`) still restores `arr[i]` in code
            let codeSession = InputSessionManager()
            codeSession.setGrammarProfile(profile)
            codeSession.smartBilingualEnabled = true
            codeSession.inlineBilingualEnabled = true
            for ch in "arr" {
                _ = codeSession.handleCharacter(ch)
            }
            guard case let .commit(_, codeCommitted, isOverride) = codeSession.commitWord(smartBilingualEnabled: true, boundaryChar: "[") else {
                return XCTFail("Expected commit for 'arr['")
            }
            XCTAssertTrue(isOverride)
            XCTAssertEqual(codeCommitted, "arr")
        }
    }
}
