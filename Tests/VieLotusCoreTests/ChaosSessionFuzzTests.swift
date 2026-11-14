import XCTest
@testable import VieLotusCore

/// Layered, deterministic, seeded fuzzing suite for `EngineBridge`, `InputSessionManager`,
/// and `UIKitInputSessionAdapter`.
///
/// Architectural guarantees:
/// - **Layer 1 (Engine)**: Pure `EngineBridge` state & UTF-16 diff exactness across Telex/VNI/SenFlex options.
/// - **Layer 2 (macOS Session + UTF-16 Host Document)**: `InputSessionManager` direct-replacement math,
///   UTF-16 surrogate safety, post-commit reopen when armed (`editCaretBack == 0`), boundary isolation
///   when disarmed (`editCaretBack != 0`), and `←`/`→` caret stepping (`stepCaretBack`/`stepCaretForward`).
/// - **Layer 3 (iOS UIKit Proxy Adapter)**: `UIKitInputSessionAdapter` against a simulated `UITextDocumentProxy`
///   with external cursor jumps, selections, backspaces, and candidate commits.
///
/// CI runs a fast fixed seed set by default; extended exploration can be run on demand via:
/// `VIELOTUS_FUZZ_SEEDS=1000 VIELOTUS_FUZZ_STEPS=400 swift test --filter ChaosSessionFuzzTests`
/// or replayed for a single seed via `VIELOTUS_FUZZ_SINGLE_SEED=0x...`.
final class ChaosSessionFuzzTests: XCTestCase {

    private var previousSpellCheckerProvider: SpellCheckerProvider?

    override func setUp() {
        super.setUp()
        previousSpellCheckerProvider = SmartBilingualDetector.spellCheckerProvider
        // Use deterministic in-memory `EmbeddedEnglishSpellChecker` so fuzz runs are fast and OS-independent.
        SmartBilingualDetector.spellCheckerProvider = EmbeddedEnglishSpellChecker.shared
    }

    override func tearDown() {
        SmartBilingualDetector.spellCheckerProvider = previousSpellCheckerProvider
        previousSpellCheckerProvider = nil
        super.tearDown()
    }

    // MARK: - Deterministic SplitMix64 PRNG

    struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextInt(_ upperBound: Int) -> Int {
            precondition(upperBound > 0)
            return Int(next() % UInt64(upperBound))
        }

        mutating func choose<T>(_ array: [T]) -> T {
            array[nextInt(array.count)]
        }
    }

    // MARK: - Fuzz Operations & Shrinker

    enum FuzzOp: Equatable, CustomStringConvertible {
        case char(Character)
        case literalChar(Character)
        case wordToken(String)
        case boundary(Character)
        case passiveEmojiOrNFD(String)
        case backspace
        case caretLeft
        case caretRight
        case caretJump(Int)
        case selectRange(Int)
        case reset

        var description: String {
            switch self {
            case .char(let c): return "char(\(String(c).debugDescription))"
            case .literalChar(let c): return "lit(\(String(c).debugDescription))"
            case .wordToken(let w): return "word(\(w.debugDescription))"
            case .boundary(let b): return "bound(\(String(b).debugDescription))"
            case .passiveEmojiOrNFD(let s): return "utf16(\(s.debugDescription))"
            case .backspace: return "BS"
            case .caretLeft: return "LEFT"
            case .caretRight: return "RIGHT"
            case .caretJump(let pos): return "JUMP(\(pos))"
            case .selectRange(let len): return "SEL(\(len))"
            case .reset: return "RESET"
            }
        }
    }

    private static let fuzzAlphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let telexHotKeys: [Character] = Array("sfrxjwaeodSFRXJWAEODtnchnguyi")
    private static let boundaries: [Character] = [" ", " ", " ", ",", ".", "/", "-", "\n"]
    private static let utf16StressPayloads: [String] = ["😀", "🇻🇳", "👍🏽", "e\u{0301}", "a\u{0302}\u{0301}"]
    private static let bilingualFragments: [String] = [
        "toans", "vieetj", "nguwowif", "thuowng", "sex", "theme", "been", "tree",
        "super", "book", "is", "IT", "API", "US", "canhf", "sexx", "ddi", "bus"
    ]

    private static func configuredSeeds(defaultCount: Int = 32) -> [UInt64] {
        let env = ProcessInfo.processInfo.environment
        if let single = env["VIELOTUS_FUZZ_SINGLE_SEED"] {
            let clean = single.hasPrefix("0x") ? String(single.dropFirst(2)) : single
            if let parsed = UInt64(clean, radix: single.hasPrefix("0x") ? 16 : 10) {
                return [parsed]
            }
        }
        let count = env["VIELOTUS_FUZZ_SEEDS"].flatMap(Int.init) ?? defaultCount
        var rng = SplitMix64(seed: 0x5649_454C_4F54_5553) // "VIELOTUS"
        return (0..<max(1, count)).map { _ in rng.next() }
    }

    private static func configuredSteps(defaultSteps: Int = 220) -> Int {
        let env = ProcessInfo.processInfo.environment
        return max(10, env["VIELOTUS_FUZZ_STEPS"].flatMap(Int.init) ?? defaultSteps)
    }

    /// Delta-debugging trace shrinker: reduces a failing `[FuzzOp]` sequence to a minimal reproducer.
    private static func shrinkTrace(_ ops: [FuzzOp], reproducesFailure: ([FuzzOp]) -> String?) -> (ops: [FuzzOp], failure: String) {
        var current = ops
        var lastMessage = reproducesFailure(current) ?? "unknown failure"

        // 1. Binary prefix truncation first (fastest way to trim trailing noise)
        var hi = current.count
        while hi > 1 {
            let prefixCandidate = Array(current.prefix(hi - 1))
            if let msg = reproducesFailure(prefixCandidate) {
                current = prefixCandidate
                lastMessage = msg
                hi = current.count
            } else {
                break
            }
        }

        // 2. Chunk / single-element deletion pass
        var chunkSize = max(1, current.count / 2)
        while chunkSize >= 1 {
            var idx = 0
            while idx < current.count && current.count > 1 {
                let end = min(current.count, idx + chunkSize)
                var candidate = current
                candidate.removeSubrange(idx..<end)
                if !candidate.isEmpty, let msg = reproducesFailure(candidate) {
                    current = candidate
                    lastMessage = msg
                } else {
                    idx += chunkSize
                }
            }
            if chunkSize == 1 { break }
            chunkSize /= 2
        }
        return (current, lastMessage)
    }

    // MARK: - Simulated UTF-16 Host Document Model (macOS Direct Replacement)

    struct FuzzUTF16Error: Error {
        let message: String
    }

    struct SimulatedUTF16Document {
        private(set) var utf16: [UInt16] = []
        private(set) var cursorUTF16: Int = 0

        private static func isHighSurrogate(_ u: UInt16) -> Bool { (0xD800...0xDBFF).contains(u) }
        private static func isLowSurrogate(_ u: UInt16) -> Bool { (0xDC00...0xDFFF).contains(u) }

        /// Validates that `offset` is within `[0, utf16.count]` and does not split a UTF-16 surrogate pair.
        func validateBoundary(_ offset: Int) -> String? {
            guard offset >= 0 && offset <= utf16.count else {
                return "UTF-16 offset \(offset) out of bounds [0, \(utf16.count)]"
            }
            if offset > 0 && offset < utf16.count &&
               Self.isHighSurrogate(utf16[offset - 1]) &&
               Self.isLowSurrogate(utf16[offset]) {
                return "UTF-16 offset \(offset) splits surrogate pair (\(String(format: "0x%04X 0x%04X", utf16[offset - 1], utf16[offset])))"
            }
            return nil
        }

        /// Decodes `[0..<cursorUTF16]` strictly, failing if any unpaired surrogate exists.
        func strictBeforeCursorString() -> Result<String, FuzzUTF16Error> {
            if let err = validateBoundary(cursorUTF16) {
                return .failure(FuzzUTF16Error(message: err))
            }
            return Self.strictDecodeUTF16(Array(utf16[0..<cursorUTF16]))
        }

        func strictFullString() -> Result<String, FuzzUTF16Error> {
            Self.strictDecodeUTF16(utf16)
        }

        private static func strictDecodeUTF16(_ units: [UInt16]) -> Result<String, FuzzUTF16Error> {
            var scalars: [UnicodeScalar] = []
            scalars.reserveCapacity(units.count)
            var decoder = UTF16()
            var iter = units.makeIterator()
            while true {
                switch decoder.decode(&iter) {
                case .scalarValue(let s):
                    scalars.append(s)
                case .emptyInput:
                    return .success(String(String.UnicodeScalarView(scalars)))
                case .error:
                    return .failure(FuzzUTF16Error(message: "Invalid/unpaired UTF-16 sequence in document buffer"))
                }
            }
        }

        /// Applies an IME direct-replacement `(backspacesUTF16, text)` at `cursorUTF16`.
        mutating func applyIMEReplace(backspacesUTF16: Int, text: String) -> String? {
            guard backspacesUTF16 >= 0 else {
                return "Negative backspaces (\(backspacesUTF16))"
            }
            guard backspacesUTF16 <= cursorUTF16 else {
                return "Backspace underflow: requested \(backspacesUTF16) UTF-16 units, only \(cursorUTF16) before cursor"
            }
            let start = cursorUTF16 - backspacesUTF16
            if let err = validateBoundary(start) {
                return "Replacement start boundary invalid: \(err)"
            }
            let replacementUnits = Array(text.utf16)
            utf16.replaceSubrange(start..<cursorUTF16, with: replacementUnits)
            cursorUTF16 = start + replacementUnits.count
            if case .failure(let err) = strictFullString() {
                return err.message
            }
            return nil
        }

        mutating func insertHostText(_ text: String) -> String? {
            applyIMEReplace(backspacesUTF16: 0, text: text)
        }

        /// Simulates native host Backspace (deletes 1 extended grapheme cluster `Character` before cursor).
        mutating func deleteOneCharacterBackward() -> (deleted: Bool, error: String?) {
            guard cursorUTF16 > 0 else { return (false, nil) }
            switch strictBeforeCursorString() {
            case .failure(let err):
                return (false, err.message)
            case .success(let before):
                guard let lastChar = before.last else { return (false, nil) }
                let width = lastChar.utf16.count
                let err = applyIMEReplace(backspacesUTF16: width, text: "")
                return (true, err)
            }
        }

        /// Simulates native host `←` (steps cursor back by 1 extended grapheme cluster `Character`).
        mutating func moveCaretLeftOneCharacter() -> (moved: Bool, error: String?) {
            guard cursorUTF16 > 0 else { return (false, nil) }
            switch strictBeforeCursorString() {
            case .failure(let err):
                return (false, err.message)
            case .success(let before):
                guard let lastChar = before.last else { return (false, nil) }
                let nextCursor = cursorUTF16 - lastChar.utf16.count
                if let err = validateBoundary(nextCursor) { return (false, err) }
                cursorUTF16 = nextCursor
                return (true, nil)
            }
        }

        /// Simulates native host `→` (steps cursor forward by 1 extended grapheme cluster `Character`).
        mutating func moveCaretRightOneCharacter() -> (moved: Bool, error: String?) {
            guard cursorUTF16 < utf16.count else { return (false, nil) }
            switch Self.strictDecodeUTF16(Array(utf16[cursorUTF16..<utf16.count])) {
            case .failure(let err):
                return (false, err.message)
            case .success(let after):
                guard let firstChar = after.first else { return (false, nil) }
                let nextCursor = cursorUTF16 + firstChar.utf16.count
                if let err = validateBoundary(nextCursor) { return (false, err) }
                cursorUTF16 = nextCursor
                return (true, nil)
            }
        }

        /// Moves cursor to a valid `Character` boundary indexed by `hint`.
        mutating func jumpCaret(hint: Int) -> String? {
            switch strictFullString() {
            case .failure(let err):
                return err.message
            case .success(let full):
                var boundaries: [Int] = [0]
                var acc = 0
                for ch in full {
                    acc += ch.utf16.count
                    boundaries.append(acc)
                }
                cursorUTF16 = boundaries[abs(hint) % boundaries.count]
                return validateBoundary(cursorUTF16)
            }
        }
    }

    // MARK: - Layer 1: Pure Engine State & UTF-16 Diff Fuzzing

    private static func generateEngineOps(seed: UInt64, count: Int) -> [FuzzOp] {
        var rng = SplitMix64(seed: seed)
        var ops: [FuzzOp] = []
        ops.reserveCapacity(count)
        for _ in 0..<count {
            switch rng.nextInt(100) {
            case 0..<45:
                ops.append(.char(rng.choose(telexHotKeys)))
            case 45..<70:
                ops.append(.char(rng.choose(fuzzAlphabet)))
            case 70..<76:
                ops.append(.literalChar(rng.choose(telexHotKeys)))
            case 76..<90:
                ops.append(.backspace)
            case 90..<95:
                ops.append(.boundary(" "))
            default:
                ops.append(.reset)
            }
        }
        return ops
    }

    private static func runLayer1EngineTrace(
        _ ops: [FuzzOp],
        method: InputMethodType,
        profile: GrammarProfile,
        simpleTelex: Bool,
        genZMode: Bool,
        relaxedCoda: Bool,
        backspaceStyle: BackspaceStyle
    ) -> (error: String?, transcript: [String]) {
        let engine = EngineBridge()
        engine.setInputMethod(method)
        engine.setGrammarProfile(profile)
        engine.setSimpleTelex(simpleTelex)
        engine.setGenZMode(genZMode)
        engine.setRelaxedCoda(relaxedCoda)
        engine.setBackspaceStyle(backspaceStyle)

        var doc = SimulatedUTF16Document()
        var transcript: [String] = []
        transcript.reserveCapacity(ops.count)

        for (stepIdx, op) in ops.enumerated() {
            switch op {
            case .char(let ch):
                if let diff = engine.feed(ch) {
                    if let err = doc.applyIMEReplace(backspacesUTF16: diff.backspaces, text: diff.suffix) {
                        return ("Step \(stepIdx) (\(op)): \(err)", transcript)
                    }
                } else {
                    if let err = doc.insertHostText(String(ch)) {
                        return ("Step \(stepIdx) (\(op)): \(err)", transcript)
                    }
                }
            case .literalChar(let ch):
                if let diff = engine.feedLiteral(ch) {
                    if let err = doc.applyIMEReplace(backspacesUTF16: diff.backspaces, text: diff.suffix) {
                        return ("Step \(stepIdx) (\(op)): \(err)", transcript)
                    }
                }
            case .backspace:
                if engine.isComposing {
                    if let diff = engine.backspace() {
                        if let err = doc.applyIMEReplace(backspacesUTF16: diff.backspaces, text: diff.suffix) {
                            return ("Step \(stepIdx) (\(op)): \(err)", transcript)
                        }
                    } else {
                        let (_, err) = doc.deleteOneCharacterBackward()
                        if let err { return ("Step \(stepIdx) (\(op)): \(err)", transcript) }
                    }
                } else {
                    doc = SimulatedUTF16Document()
                }
            case .boundary:
                if engine.isComposing {
                    let out = engine.currentOutput()
                    let raw = engine.rawString()
                    engine.commitWord(raw: raw.isEmpty ? out : raw, rendered: out)
                }
                if engine.isComposing || !engine.rawString().isEmpty || !engine.currentOutput().isEmpty {
                    return ("Step \(stepIdx) (\(op)): commitWord leaked composing state", transcript)
                }
                doc = SimulatedUTF16Document()
            case .reset:
                engine.reset()
                if engine.isComposing || !engine.rawString().isEmpty || !engine.currentOutput().isEmpty {
                    return ("Step \(stepIdx) (\(op)): reset leaked state", transcript)
                }
                doc = SimulatedUTF16Document()
            default:
                break
            }

            if engine.isComposing != (!engine.rawString().isEmpty) {
                return ("Step \(stepIdx) (\(op)): isComposing=\(engine.isComposing) mismatches rawString=\(engine.rawString().debugDescription)", transcript)
            }
            if engine.isComposing {
                switch doc.strictFullString() {
                case .failure(let err):
                    return ("Step \(stepIdx) (\(op)): \(err.message)", transcript)
                case .success(let screenWord):
                    if screenWord != engine.currentOutput() {
                        return ("Step \(stepIdx) (\(op)): UTF-16 diff drift: screen=\(screenWord.debugDescription) != engine.currentOutput()=\(engine.currentOutput().debugDescription)", transcript)
                    }
                }
            }
            transcript.append(engine.currentOutput())
        }
        return (nil, transcript)
    }

    func testLayer1EngineUTF16AndLifecycleInvariants() {
        let seeds = Self.configuredSeeds()
        let steps = Self.configuredSteps()

        for (idx, seed) in seeds.enumerated() {
            let method: InputMethodType = (idx % 3 == 2) ? .vni : .telex
            let profile: GrammarProfile = GrammarProfile.allCases[idx % GrammarProfile.allCases.count]
            let simple = (idx % 5 == 1)
            let genZ = (idx % 4 == 1)
            let relaxed = (idx % 3 == 1)
            let bsStyle: BackspaceStyle = (idx % 2 == 0) ? .appleSemantic : .gboardCharacter

            let ops = Self.generateEngineOps(seed: seed, count: steps)
            let firstRun = Self.runLayer1EngineTrace(
                ops,
                method: method,
                profile: profile,
                simpleTelex: simple,
                genZMode: genZ,
                relaxedCoda: relaxed,
                backspaceStyle: bsStyle
            )
            if firstRun.error != nil {
                let shrunk = Self.shrinkTrace(ops) {
                    Self.runLayer1EngineTrace(
                        $0,
                        method: method,
                        profile: profile,
                        simpleTelex: simple,
                        genZMode: genZ,
                        relaxedCoda: relaxed,
                        backspaceStyle: bsStyle
                    ).error
                }
                XCTFail(
                    """
                    Layer 1 Engine Fuzz Failure!
                    Reproduce with: VIELOTUS_FUZZ_SINGLE_SEED=\(String(format: "0x%016llX", seed)) swift test --filter ChaosSessionFuzzTests
                    Config: method=\(method), profile=\(profile), simple=\(simple), genZ=\(genZ), relaxed=\(relaxed), bs=\(bsStyle)
                    Error: \(shrunk.failure)
                    Minimal trace (\(shrunk.ops.count) ops): \(shrunk.ops)
                    """
                )
                return
            }

            // Determinism check on first 4 seeds
            if idx < 4 {
                let replay = Self.runLayer1EngineTrace(
                    ops,
                    method: method,
                    profile: profile,
                    simpleTelex: simple,
                    genZMode: genZ,
                    relaxedCoda: relaxed,
                    backspaceStyle: bsStyle
                )
                XCTAssertEqual(firstRun.transcript, replay.transcript, "Engine replay diverged for seed \(String(format: "0x%016llX", seed))")
            }
        }
    }

    // MARK: - Layer 2: macOS InputSessionManager + UTF-16 Host Document & Caret Stepping

    private static func generateSessionOps(seed: UInt64, count: Int) -> [FuzzOp] {
        var rng = SplitMix64(seed: seed)
        var ops: [FuzzOp] = []
        ops.reserveCapacity(count)
        for _ in 0..<count {
            switch rng.nextInt(100) {
            case 0..<32:
                ops.append(.char(rng.choose(telexHotKeys)))
            case 32..<48:
                ops.append(.char(rng.choose(fuzzAlphabet)))
            case 48..<60:
                ops.append(.wordToken(rng.choose(bilingualFragments)))
            case 60..<74:
                ops.append(.boundary(rng.choose(boundaries)))
            case 74..<86:
                ops.append(.backspace)
            case 86..<91:
                ops.append(.caretLeft)
            case 91..<95:
                ops.append(.caretRight)
            case 95..<98:
                ops.append(.caretJump(rng.nextInt(64)))
            default:
                ops.append(.passiveEmojiOrNFD(rng.choose(utf16StressPayloads)))
            }
        }
        return ops
    }

    private static func runLayer2MacSessionTrace(
        _ ops: [FuzzOp],
        method: InputMethodType,
        inlineBilingual: Bool,
        smartBilingual: Bool
    ) -> String? {
        let session = InputSessionManager()
        session.clearContext()
        session.macroEnabled = false
        session.setInputMethod(method)
        session.setGrammarProfile(.senFlex)
        session.setSmartBilingualEnabled(smartBilingual)
        session.inlineBilingualEnabled = inlineBilingual

        var doc = SimulatedUTF16Document()

        func feedSingleChar(_ ch: Character, stepLabel: String) -> String? {
            if session.isWordBoundary(ch) {
                let action = session.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: ch)
                switch action {
                case let .commit(bs, text, isOverride):
                    if isOverride {
                        if let err = doc.applyIMEReplace(backspacesUTF16: bs, text: text) {
                            return "\(stepLabel): commit override error: \(err)"
                        }
                    }
                case let .replace(bs, text):
                    if let err = doc.applyIMEReplace(backspacesUTF16: bs, text: text) {
                        return "\(stepLabel): boundary replace error: \(err)"
                    }
                default:
                    break
                }
                if let err = doc.insertHostText(String(ch)) {
                    return "\(stepLabel): boundary insert error: \(err)"
                }
                return nil
            }

            let wasDisarmedIdle = !session.isComposing &&
                session.editCaretBack < 0 &&
                session.activeDotPrefix == nil &&
                session.pendingDotPrefix == nil

            let action = session.handleCharacter(ch)
            switch action {
            case let .replace(bs, text):
                if wasDisarmedIdle && bs > 0 {
                    return "\(stepLabel): disarmed idle handleCharacter(\(ch)) requested non-zero backspaces=\(bs)"
                }
                if let err = doc.applyIMEReplace(backspacesUTF16: bs, text: text) {
                    return "\(stepLabel): replace(\(bs), \(text.debugDescription)) error: \(err)"
                }
            case let .commit(bs, text, isOverride):
                if isOverride {
                    if let err = doc.applyIMEReplace(backspacesUTF16: bs, text: text) {
                        return "\(stepLabel): commit(\(bs), \(text.debugDescription)) error: \(err)"
                    }
                }
            case .passThrough:
                if let err = doc.insertHostText(String(ch)) {
                    return "\(stepLabel): passThrough insert error: \(err)"
                }
            case .consumed, .reset:
                break
            }
            return nil
        }

        for (stepIdx, op) in ops.enumerated() {
            let label = "Step \(stepIdx) (\(op))"
            switch op {
            case .char(let ch):
                if let err = feedSingleChar(ch, stepLabel: label) { return err }
            case .wordToken(let token):
                for ch in token {
                    if let err = feedSingleChar(ch, stepLabel: "\(label)[\(ch)]") { return err }
                }
            case .boundary(let b):
                if let err = feedSingleChar(b, stepLabel: label) { return err }
            case .passiveEmojiOrNFD(let payload):
                if session.isComposing {
                    let act = session.commitWord(smartBilingualEnabled: smartBilingual, boundaryChar: " ")
                    if case let .commit(bs, txt, true) = act {
                        if let err = doc.applyIMEReplace(backspacesUTF16: bs, text: txt) { return "\(label): \(err)" }
                    }
                    _ = doc.insertHostText(" ")
                }
                session.resetCaret()
                session.engine.clearHistory()
                if let err = doc.insertHostText(payload) { return "\(label): \(err)" }
            case .backspace:
                let wasDisarmedIdle = !session.isComposing && session.editCaretBack != 0
                let action = session.handleBackspace()
                switch action {
                case let .replace(bs, text):
                    if wasDisarmedIdle {
                        return "\(label): disarmed handleBackspace() unexpectedly returned .replace(\(bs), \(text.debugDescription))"
                    }
                    if let err = doc.applyIMEReplace(backspacesUTF16: bs, text: text) {
                        return "\(label): backspace replace(\(bs), \(text.debugDescription)) error: \(err)"
                    }
                case .passThrough, .reset:
                    let (deleted, err) = doc.deleteOneCharacterBackward()
                    if let err { return "\(label): host backspace error: \(err)" }
                    if !deleted {
                        // Pressing backspace at offset 0: session must not stay armed for reopen
                        if session.editCaretBack == 0 {
                            session.resetCaret()
                        }
                    }
                case .consumed, .commit:
                    break
                }
            case .caretLeft:
                let (moved, err) = doc.moveCaretLeftOneCharacter()
                if let err { return "\(label): \(err)" }
                if moved {
                    session.stepCaretBack()
                } else {
                    session.reset()
                    session.engine.clearHistory()
                }
            case .caretRight:
                let (moved, err) = doc.moveCaretRightOneCharacter()
                if let err { return "\(label): \(err)" }
                if moved {
                    session.stepCaretForward()
                } else {
                    session.reset()
                    session.engine.clearHistory()
                }
            case .caretJump(let hint):
                session.reset()
                session.engine.clearHistory()
                if let err = doc.jumpCaret(hint: hint) { return "\(label): \(err)" }
            default:
                break
            }

            // Invariant A: Document UTF-16 buffer & cursor boundary remain strictly valid
            let beforeString: String
            switch doc.strictBeforeCursorString() {
            case .failure(let err):
                return "\(label): invalid UTF-16 before cursor: \(err.message)"
            case .success(let s):
                beforeString = s
            }

            // Invariant B: Whenever composing, the text immediately before cursor MUST end with `session.currentOutput()`
            if session.isComposing {
                let active = session.currentOutput()
                if active.isEmpty {
                    return "\(label): session.isComposing is true while currentOutput() is empty"
                }
                let activeUTF16 = Array(active.utf16)
                let beforeUTF16 = Array(doc.utf16[0..<doc.cursorUTF16])
                if beforeUTF16.count < activeUTF16.count ||
                   Array(beforeUTF16.suffix(activeUTF16.count)) != activeUTF16 {
                    return "\(label): active composition desync! beforeCursor=\(beforeString.debugDescription) does not end with currentOutput()=\(active.debugDescription) (rawWord=\(session.rawWord.debugDescription))"
                }
            }
        }
        return nil
    }

    func testLayer2MacSessionUTF16DocumentModelAndCaretChaos() {
        let seeds = Self.configuredSeeds()
        let steps = Self.configuredSteps()

        for (idx, seed) in seeds.enumerated() {
            let method: InputMethodType = (idx % 4 == 3) ? .vni : .telex
            let inlineBilingual = (idx % 2 == 1)
            let smartBilingual = (idx % 5 != 4)

            let ops = Self.generateSessionOps(seed: seed, count: steps)
            if Self.runLayer2MacSessionTrace(
                ops,
                method: method,
                inlineBilingual: inlineBilingual,
                smartBilingual: smartBilingual
            ) != nil {
                let shrunk = Self.shrinkTrace(ops) {
                    Self.runLayer2MacSessionTrace(
                        $0,
                        method: method,
                        inlineBilingual: inlineBilingual,
                        smartBilingual: smartBilingual
                    )
                }
                XCTFail(
                    """
                    Layer 2 macOS UTF-16 Document Fuzz Failure!
                    Reproduce with: VIELOTUS_FUZZ_SINGLE_SEED=\(String(format: "0x%016llX", seed)) swift test --filter ChaosSessionFuzzTests
                    Config: method=\(method), inlineBilingual=\(inlineBilingual), smartBilingual=\(smartBilingual)
                    Error: \(shrunk.failure)
                    Minimal trace (\(shrunk.ops.count) ops): \(shrunk.ops)
                    """
                )
                return
            }
        }
    }

    /// Targeted regression test for `←` (`stepCaretBack`) then `→` (`stepCaretForward`) round-trip
    /// when `inlineBilingualEnabled == true` (`composingWord != engine.currentOutput()`, e.g. `"super"` vs `"sủpe"`),
    /// and for NFD decomposed vowel replacement on iOS `UIKitInputSessionAdapter` (`"se\u{0301}"` + `"f"` -> `"sè"`).
    func testCaretBackForwardRoundTripPreservesDisplayedInlineBilingualWordOnReopen() {
        let session = InputSessionManager()
        session.clearContext()
        session.macroEnabled = false
        session.setInputMethod(.telex)
        session.setGrammarProfile(.senFlex)
        session.setSmartBilingualEnabled(true)
        session.inlineBilingualEnabled = true

        var doc = SimulatedUTF16Document()
        for ch in "super" {
            let action = session.handleCharacter(ch)
            if case let .replace(bs, text) = action {
                XCTAssertNil(doc.applyIMEReplace(backspacesUTF16: bs, text: text))
            } else if case .passThrough = action {
                XCTAssertNil(doc.insertHostText(String(ch)))
            }
        }
        XCTAssertEqual(try? doc.strictFullString().get(), "super")

        // Press ← then → back to the end of "super", then Backspace once
        _ = doc.moveCaretLeftOneCharacter()
        session.stepCaretBack()
        _ = doc.moveCaretRightOneCharacter()
        session.stepCaretForward()

        let bsAction = session.handleBackspace()
        switch bsAction {
        case let .replace(bs, text):
            XCTAssertNil(doc.applyIMEReplace(backspacesUTF16: bs, text: text))
        case .passThrough, .reset:
            _ = doc.deleteOneCharacterBackward()
        default:
            break
        }
        XCTAssertEqual(
            try? doc.strictFullString().get(),
            "supe",
            "← then → then Backspace on inline-bilingual 'super' must delete 1 trailing char ('supe'), never corrupt to 'ssủp'"
        )

        // Minimal 5-op reproducer discovered by Layer 3 fuzzer (seed 0x10E72FB42BF8F79F):
        // NFD decomposed vowel in proxy ("se\u{0301}") + tone key "f" must replace only the vowel ("sè"), never swallow "s".
        let nfdTrace: [FuzzOp] = [.char("s"), .char("E"), .caretJump(1), .passiveEmojiOrNFD("e\u{0301}"), .char("f")]
        if let err = Self.runLayer3UIKitTrace(nfdTrace, method: .telex) {
            XCTFail("Layer 3 NFD decomposed replacement regression: \(err)")
        }
    }

    // MARK: - Layer 3: iOS UIKitInputSessionAdapter + Simulated UITextDocumentProxy

    private final class SimulatedUIKitProxy: TextDocumentProxyProtocol {
        var beforeCursor: String = ""
        var afterCursor: String = ""
        var selected: String? = nil

        var documentContextBeforeInput: String? { beforeCursor }
        var documentContextAfterInput: String? { afterCursor }
        var selectedText: String? { selected }

        func insertText(_ text: String) {
            if selected != nil {
                selected = nil
            }
            beforeCursor.append(text)
        }

        func deleteBackward() {
            if selected != nil {
                selected = nil
                return
            }
            guard !beforeCursor.isEmpty else { return }
            beforeCursor.removeLast()
        }

        func moveCursor(hint: Int) {
            let full = beforeCursor + (selected ?? "") + afterCursor
            selected = nil
            let chars = Array(full)
            guard !chars.isEmpty else {
                beforeCursor = ""
                afterCursor = ""
                return
            }
            let split = abs(hint) % (chars.count + 1)
            beforeCursor = String(chars[0..<split])
            afterCursor = String(chars[split..<chars.count])
        }

        func selectTrailing(maxChars: Int) {
            guard !beforeCursor.isEmpty, maxChars > 0 else { return }
            let chars = Array(beforeCursor)
            let take = min(chars.count, maxChars)
            beforeCursor = String(chars.dropLast(take))
            selected = String(chars.suffix(take))
        }
    }

    private static func generateUIKitOps(seed: UInt64, count: Int) -> [FuzzOp] {
        var rng = SplitMix64(seed: seed)
        var ops: [FuzzOp] = []
        ops.reserveCapacity(count)
        for _ in 0..<count {
            switch rng.nextInt(100) {
            case 0..<35:
                ops.append(.char(rng.choose(telexHotKeys)))
            case 35..<50:
                ops.append(.char(rng.choose(fuzzAlphabet)))
            case 50..<62:
                ops.append(.wordToken(rng.choose(bilingualFragments)))
            case 62..<67:
                ops.append(.literalChar(rng.choose(telexHotKeys)))
            case 67..<80:
                ops.append(.boundary(rng.choose(boundaries)))
            case 80..<91:
                ops.append(.backspace)
            case 91..<96:
                ops.append(.caretJump(rng.nextInt(64)))
            case 96..<98:
                ops.append(.selectRange(1 + rng.nextInt(5)))
            default:
                ops.append(.passiveEmojiOrNFD(rng.choose(utf16StressPayloads)))
            }
        }
        return ops
    }

    private static func runLayer3UIKitTrace(_ ops: [FuzzOp], method: InputMethodType) -> String? {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.clearContext()
        adapter.session.macroEnabled = false
        adapter.session.setInputMethod(method)
        adapter.session.setGrammarProfile(.senFlex)
        adapter.session.setSmartBilingualEnabled(true)

        let proxy = SimulatedUIKitProxy()

        for (stepIdx, op) in ops.enumerated() {
            let label = "Step \(stepIdx) (\(op))"
            switch op {
            case .char(let ch):
                adapter.handleCharacter(ch, proxy: proxy)
            case .literalChar(let ch):
                adapter.handleLiteralCharacter(ch, proxy: proxy)
            case .wordToken(let token):
                for ch in token {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
            case .boundary(let b):
                adapter.handleCharacter(b, proxy: proxy)
            case .backspace:
                adapter.handleBackspace(proxy: proxy)
            case .caretJump(let hint):
                proxy.moveCursor(hint: hint)
                adapter.handleExternalTextChange(proxy: proxy)
            case .selectRange(let len):
                proxy.selectTrailing(maxChars: len)
                adapter.handleExternalTextChange(proxy: proxy)
            case .passiveEmojiOrNFD(let payload):
                if adapter.session.isComposing {
                    adapter.commitWord(proxy: proxy, suffix: " ")
                }
                proxy.insertText(payload)
                adapter.handleExternalTextChange(proxy: proxy)
            default:
                break
            }

            if adapter.session.isComposing && proxy.selected == nil {
                let active = adapter.session.currentOutput()
                if active.isEmpty {
                    return "\(label): adapter.session.isComposing is true while currentOutput() is empty"
                }
                if !proxy.beforeCursor.hasSuffix(active) {
                    return "\(label): UIKit proxy desync! beforeCursor=\(proxy.beforeCursor.debugDescription) does not end with currentOutput()=\(active.debugDescription) (rawWord=\(adapter.session.rawWord.debugDescription))"
                }
            }
        }
        return nil
    }

    func testLayer3UIKitAdapterProxyModelAndExternalCursorJumps() {
        let seeds = Self.configuredSeeds()
        let steps = Self.configuredSteps()

        for (idx, seed) in seeds.enumerated() {
            let method: InputMethodType = (idx % 4 == 3) ? .vni : .telex
            let ops = Self.generateUIKitOps(seed: seed, count: steps)
            if Self.runLayer3UIKitTrace(ops, method: method) != nil {
                let shrunk = Self.shrinkTrace(ops) {
                    Self.runLayer3UIKitTrace($0, method: method)
                }
                XCTFail(
                    """
                    Layer 3 UIKit Adapter Fuzz Failure!
                    Reproduce with: VIELOTUS_FUZZ_SINGLE_SEED=\(String(format: "0x%016llX", seed)) swift test --filter ChaosSessionFuzzTests
                    Config: method=\(method)
                    Error: \(shrunk.failure)
                    Minimal trace (\(shrunk.ops.count) ops): \(shrunk.ops)
                    """
                )
                return
            }
        }
    }

    // =========================================================================
    // LAYER 4: BEHAVIORAL & SLIP-RECOVERY SCORECARD (INDEPENDENT GROUND-TRUTH ORACLE)
    // =========================================================================

    enum SlipKind: String, CaseIterable {
        case typo = "typo"
        case backIntoWord = "back-into-word"
        case cursorTrip = "cursor-trip"
        case strayPunct = "stray-punct"
        case midWordClick = "mid-word-click"
        case editElsewhere = "edit-elsewhere"
    }

    struct ScorecardHostDoc {
        var text: String = ""

        mutating func apply(_ action: SessionAction, fallbackChar: Character?) {
            switch action {
            case .replace(let bs, let replacement):
                if bs > 0 {
                    var rem = bs
                    var idx = text.endIndex
                    while rem > 0 && idx > text.startIndex {
                        idx = text.index(before: idx)
                        rem -= text[idx].utf16.count
                    }
                    text.removeSubrange(idx..<text.endIndex)
                }
                text.append(replacement)
            case .commit(let bs, let committed, _):
                if bs > 0 {
                    var rem = bs
                    var idx = text.endIndex
                    while rem > 0 && idx > text.startIndex {
                        idx = text.index(before: idx)
                        rem -= text[idx].utf16.count
                    }
                    text.removeSubrange(idx..<text.endIndex)
                }
                text.append(committed)
                if let ch = fallbackChar {
                    text.append(ch)
                }
            case .passThrough, .reset:
                if let ch = fallbackChar {
                    text.append(ch)
                } else if !text.isEmpty {
                    text.removeLast()
                }
            case .consumed:
                break
            }
        }
    }

    struct ConversationalWordSpec {
        let rawKeys: String
        let expectedWord: String
        let postSpaceToneSwap: (toneKey: Character, expectedSwapped: String)?

        init(_ rawKeys: String, _ expectedWord: String, postSpaceToneSwap: (Character, String)? = nil) {
            self.rawKeys = rawKeys
            self.expectedWord = expectedWord
            self.postSpaceToneSwap = postSpaceToneSwap
        }
    }

    static let conversationalCorpus: [[ConversationalWordSpec]] = [
        [
            .init("Hoom", "Hôm"),
            .init("nay", "nay"),
            .init("team", "team"),
            .init("mifnh", "mình", postSpaceToneSwap: ("s", "mính")),
            .init("deploy", "deploy"),
            .init("banr", "bản", postSpaceToneSwap: ("s", "bán")),
            .init("build", "build"),
            .init("mowis", "mới", postSpaceToneSwap: ("f", "mời")),
            .init("leen", "lên"),
            .init("server", "server")
        ],
        [
            .init("Neesu", "Nếu"),
            .init("code", "code"),
            .init("bij", "bị", postSpaceToneSwap: ("s", "bí")),
            .init("bug", "bug"),
            .init("thif", "thì", postSpaceToneSwap: ("s", "thí")),
            .init("check", "check"),
            .init("log", "log"),
            .init("truwowsc", "trước"),
            .init("nhas", "nhá", postSpaceToneSwap: ("f", "nhà"))
        ],
        [
            .init("Anh", "Anh"),
            .init("guwir", "gửi"),
            .init("file", "file"),
            .init("baos", "báo", postSpaceToneSwap: ("f", "bào")),
            .init("caos", "cáo", postSpaceToneSwap: ("f", "cào")),
            .init("vafo", "vào"),
            .init("group", "group"),
            .init("chat", "chat"),
            .init("cho", "cho"),
            .init("em", "em")
        ]
    ]

    func testBehavioralAndSlipRecoveryScorecardWithIndependentOracle() {
        let prevProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = prevProvider }

        let prevMacro = MacroEngine.shared.isEnabled
        MacroEngine.shared.isEnabled = false
        defer { MacroEngine.shared.isEnabled = prevMacro }

        var cleanPassed = 0
        var cleanTotal = 0
        var badEdits = 0
        var extraRetypeKeystrokes = 0
        var slipPassed: [SlipKind: Int] = [:]
        var slipTotal: [SlipKind: Int] = [:]
        for kind in SlipKind.allCases {
            slipPassed[kind] = 0
            slipTotal[kind] = 0
        }

        // 1. Clean conversational accuracy against independent ground-truth oracle
        for sentence in Self.conversationalCorpus {
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(.senFlex)
            session.setSmartBilingualEnabled(true)
            session.inlineBilingualEnabled = true
            var doc = ScorecardHostDoc()

            for spec in sentence {
                let guardPrefix = doc.text
                for ch in spec.rawKeys {
                    let act = session.handleCharacter(ch)
                    doc.apply(act, fallbackChar: ch)
                    if !doc.text.hasPrefix(guardPrefix) {
                        badEdits += 1
                    }
                }
                let commitAct = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
                doc.apply(commitAct, fallbackChar: " ")
                if !doc.text.hasPrefix(guardPrefix) {
                    badEdits += 1
                }
                let expectedPrefix = guardPrefix + spec.expectedWord + " "
                cleanTotal += 1
                if doc.text == expectedPrefix {
                    cleanPassed += 1
                } else {
                    extraRetypeKeystrokes += spec.rawKeys.count + 1
                    doc.text = expectedPrefix
                }
            }
        }

        // 2. Slip-recovery suite per category with prefix text-safety guard (`badEdits == 0`)
        for sentence in Self.conversationalCorpus {
            for (wordIdx, spec) in sentence.enumerated() where spec.rawKeys.count >= 3 {
                for kind in SlipKind.allCases {
                    if kind == .backIntoWord && spec.postSpaceToneSwap == nil {
                        continue
                    }
                    let session = InputSessionManager()
                    session.setInputMethod(.telex)
                    session.setGrammarProfile(.senFlex)
                    session.setSmartBilingualEnabled(true)
                    session.inlineBilingualEnabled = true
                    var doc = ScorecardHostDoc()

                    // Prime preceding words in sentence cleanly
                    for prevIdx in 0..<wordIdx {
                        let prev = sentence[prevIdx]
                        for ch in prev.rawKeys {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")
                    }

                    let guardPrefix = doc.text
                    let splitIdx = (kind == .strayPunct) ? min(2, max(1, spec.rawKeys.count / 2)) : max(1, spec.rawKeys.count / 2)
                    let firstHalf = String(spec.rawKeys.prefix(splitIdx))
                    let secondHalf = String(spec.rawKeys.dropFirst(splitIdx))

                    var expectedAfterSlip = guardPrefix + spec.expectedWord + " "

                    switch kind {
                    case .typo:
                        for ch in firstHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        // Inject non-modifier typo 'q' then Backspace
                        doc.apply(session.handleCharacter("q"), fallbackChar: "q")
                        doc.apply(session.handleBackspace(), fallbackChar: nil)
                        if !doc.text.hasPrefix(guardPrefix) { badEdits += 1 }
                        for ch in secondHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")

                    case .backIntoWord:
                        guard let swap = spec.postSpaceToneSwap else { continue }
                        for ch in spec.rawKeys {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")
                        // Backspace the trailing space to reopen the committed word, then apply tone swap
                        doc.apply(session.handleBackspace(), fallbackChar: nil)
                        if !doc.text.hasPrefix(guardPrefix) { badEdits += 1 }
                        doc.apply(session.handleCharacter(swap.toneKey), fallbackChar: swap.toneKey)
                        if !doc.text.hasPrefix(guardPrefix) { badEdits += 1 }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")
                        expectedAfterSlip = guardPrefix + swap.expectedSwapped + " "

                    case .cursorTrip:
                        for ch in spec.rawKeys {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        session.stepCaretBack()
                        session.stepCaretForward()
                        if !doc.text.hasPrefix(guardPrefix) { badEdits += 1 }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")

                    case .strayPunct:
                        for ch in firstHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        // Stray comma commits prefix, then Backspace deletes comma and re-arms prefix
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: ","), fallbackChar: ",")
                        doc.apply(session.handleBackspace(), fallbackChar: nil)
                        if !doc.text.hasPrefix(guardPrefix) { badEdits += 1 }
                        for ch in secondHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")

                    case .midWordClick:
                        for ch in firstHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        let currentPrefix = String(doc.text.dropFirst(guardPrefix.count))
                        session.reset()
                        session.setCompositionPrefix(currentPrefix)
                        for ch in secondHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")

                    case .editElsewhere:
                        for ch in firstHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        let savedPrefix = String(doc.text.dropFirst(guardPrefix.count))
                        session.reset()
                        session.editCaretBack = InputSessionManager.caretDisarmed
                        // Simulate editing elsewhere and returning to the word tail
                        session.setCompositionPrefix(savedPrefix)
                        for ch in secondHalf {
                            doc.apply(session.handleCharacter(ch), fallbackChar: ch)
                        }
                        doc.apply(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ")
                    }

                    if !doc.text.hasPrefix(guardPrefix) {
                        badEdits += 1
                    }
                    slipTotal[kind, default: 0] += 1
                    if doc.text == expectedAfterSlip {
                        slipPassed[kind, default: 0] += 1
                    } else {
                        extraRetypeKeystrokes += spec.rawKeys.count + 1
                    }
                }
            }
        }

        XCTAssertEqual(badEdits, 0, "Prefix text-safety guard violated: engine modified text prior to active/armed word boundary")
        XCTAssertEqual(cleanPassed, cleanTotal, "Conversational clean accuracy against independent ground-truth oracle must be 100%")
        XCTAssertEqual(extraRetypeKeystrokes, 0, "Zero manual retype keystrokes expected on conversational slip-recovery suite")
        for kind in SlipKind.allCases {
            let passed = slipPassed[kind] ?? 0
            let total = slipTotal[kind] ?? 0
            XCTAssertGreaterThan(total, 0)
            XCTAssertEqual(passed, total, "Slip category '\(kind.rawValue)' failed (\(passed)/\(total))")
        }
    }
}
