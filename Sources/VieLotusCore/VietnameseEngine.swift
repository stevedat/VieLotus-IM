import Foundation

// MARK: - Vietnamese Orthography Types

internal enum VietnameseTone: Int, CaseIterable, Sendable {
    case none = 0
    case acute = 1   // Sắc
    case grave = 2   // Huyền
    case hook = 3    // Hỏi
    case tilde = 4   // Ngã
    case dot = 5     // Nặng
}

/// Semantic classification of a Telex tone key (`s`, `f`, `r`, `x`, `j`, `z`) relative to active syllable state (P0.2).
public enum ToneModifierSemanticEvent: Equatable, Sendable {
    /// Applies a tone to an untoned vowel nucleus (`canh + f -> cành`).
    case applyTone
    /// Replaces an existing active tone with a different tone (`cành + r -> cảnh`).
    case replaceTone
    /// Clears the active tone via `z` without emitting a literal character (`cành + z -> canh`).
    case clearToneZ
    /// Cancels the currently active tone when the same tone key is pressed again and emits one literal character (`cành + f -> canhf`, `cảnh + r -> canhr`).
    case cancelToneAndEmitLiteral
    /// Idempotent post-coda tone-then-vowel-reshape (`congror -> cổngr`).
    case idempotentPostReshapeTone
}

internal enum VowelModification: Sendable {
    case none
    case circumflex  // â, ê, ô
    case horn        // ơ, ư
    case breve       // ă
}

// MARK: - VietnameseEngine: Pure Swift Native Vietnamese Engine

/// Ultra-fast, zero-FFI, memory-safe pure Swift Vietnamese phonetic engine.
/// Provides deterministic Finite State Machine (FSM) syllable parsing,
/// modern & traditional tone placement, Telex & VNI input methods,
/// w-modifiers, case preservation, and post-commit editing ring buffer.
internal final class VietnameseEngine: @unchecked Sendable {

    // MARK: - Configuration

    internal var inputMethod: InputMethodType = .telex {
        didSet {
            if inputMethod != oldValue {
                reset()
                clearHistory()
            }
        }
    }
    internal var grammarProfile: GrammarProfile = .senFlex
    internal var modernOrthography: Bool = true
    internal var relaxedCoda: Bool = false
    internal var quickTelex: Bool = false
    internal var quickStart: Bool = false
    internal var genZMode: Bool = false
    internal var simpleTelex: Bool = true
    internal var backspaceStyle: BackspaceStyle = .appleSemantic

    // MARK: - Internal Syllable State

    /// Raw keystrokes entered for current composing syllable
    private var rawChars: [Character] = []
    private var cachedRawString: String = ""
    /// Incremental O(1) bitmask over `rawChars`:
    /// - bits 0..7: 2-bit saturating counts for `d`, `a`, `e`, `o`
    /// - bit 8 (`0x0100`): set if `rawChars` contains any Telex modifier (`s, f, r, x, j, z, w`, non-ASCII, or >= 2 of `d, a, e, o`)
    /// - bit 9 (`0x0200`): set if `rawChars` contains any VNI digit (`0..9`) or non-ASCII
    internal private(set) var rawFastMask: UInt16 = 0

    /// Zero-heap bounded keystroke buffer with provenance tracking (capacity 32)
    internal private(set) var keystrokeBuffer = BoundedKeystrokeBuffer()

    /// Current rendered output of the active word
    private var renderedOutput: String = ""
    /// Incremental O(1) flag indicating whether `renderedOutput` consists strictly of ASCII bytes (`< 128`).
    internal private(set) var renderedOutputIsASCII: Bool = true

    /// History of committed words for post-commit editing (ring buffer)
    /// Stores (rawChars, renderedOutput) pairs
    private var committedHistory: [(raw: [Character], rendered: String)] = []
    private static let maxHistoryCount = 20
    internal private(set) var isEditingCommittedWord: Bool = false
    private var isCharacterDeletingCommittedWord: Bool = false
    private var lastCommittedIsDirectToken: Bool = false
    internal private(set) var supersededModifiers: [Character] = []

    private struct CompositionSnapshot {
        let rawChars: [Character]
        let renderedOutput: String
        let isLiteralOrCancellationStep: Bool
        let isExplicitLiteralLock: Bool
        let supersededModifiers: [Character]
        let toneSemanticEvent: ToneModifierSemanticEvent?
        let hasConfirmedSemanticEscape: Bool

        init(
            rawChars: [Character],
            renderedOutput: String,
            isLiteralOrCancellationStep: Bool,
            isExplicitLiteralLock: Bool = false,
            supersededModifiers: [Character] = [],
            toneSemanticEvent: ToneModifierSemanticEvent? = nil,
            hasConfirmedSemanticEscape: Bool = false
        ) {
            self.rawChars = rawChars
            self.renderedOutput = renderedOutput
            self.isLiteralOrCancellationStep = isLiteralOrCancellationStep
            self.isExplicitLiteralLock = isExplicitLiteralLock
            self.supersededModifiers = supersededModifiers
            self.toneSemanticEvent = toneSemanticEvent
            self.hasConfirmedSemanticEscape = hasConfirmedSemanticEscape
        }
    }

    private var compositionHistory: [CompositionSnapshot] = []

    /// When enabled, incoming ASCII characters are appended literally without Telex/VNI transformation.
    internal var literalOverrideEnabled: Bool = false

    /// Indicates whether the most recent `feed(_:)` call was rejected as a no-op by the Strict Vietnamese Guard.
    internal private(set) var lastFeedWasRejectedNoOp: Bool = false
    internal private(set) var lastPostCommitEditTransaction: PostCommitEditTransaction? = nil
    /// Semantic tone event produced by the most recent keystroke in the active composition (P0.6).
    internal private(set) var lastToneSemanticEvent: ToneModifierSemanticEvent? = nil
    /// True once an explicit tone/modifier cancellation (`CancelToneAndEmitLiteral`) has been confirmed in the active composition (P0.6).
    internal private(set) var hasConfirmedSemanticEscapeInComposition: Bool = false
    private var lastAttemptedKey: Character? = nil

    internal var isComposing: Bool {
        return !rawChars.isEmpty
    }

    internal var lastCommittedWord: String? {
        return committedHistory.last?.rendered
    }

    internal var lastCommittedRaw: String? {
        return committedHistory.last.map { String($0.raw) }
    }

    internal var activeToneModifier: Character? {
        Self.extractActiveToneModifier(from: renderedOutput, inputMethod: inputMethod)
    }

    internal var activeVowelModifiers: [Character] {
        Self.extractActiveVowelModifiers(from: renderedOutput, inputMethod: inputMethod)
    }

    internal var nextBackspaceRestorationState: String? {
        guard !rawChars.isEmpty else { return nil }
        let previousOutput = renderedOutput
        guard !previousOutput.isEmpty else { return nil }
        if backspaceStyle == .gboardCharacter {
            return String(previousOutput.dropLast())
        }
        if !isCharacterDeletingCommittedWord,
           compositionHistory.count >= 2,
           let lastSnap = compositionHistory.last,
           lastSnap.isLiteralOrCancellationStep {
            return compositionHistory[compositionHistory.count - 2].renderedOutput
        }
        if isCharacterDeletingCommittedWord {
            return String(previousOutput.dropLast())
        }
        let isTwoCharWInitial = rawChars.count == 2 && Character(rawChars[0].lowercased()) == "w"
        if !isEditingCommittedWord && !isTwoCharWInitial && previousOutput.lowercased() == String(rawChars).lowercased() && rawChars.count == previousOutput.count && transform(rawChars) == previousOutput {
            let dropped = Array(rawChars.dropLast())
            return dropped.isEmpty ? "" : transform(dropped)
        }
        if !previousOutput.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return Self.applySemanticBackspace(to: previousOutput)
        }
        return String(previousOutput.dropLast())
    }

    internal init() {}

    // MARK: - Public Control API

    internal func reset() {
        rawChars.removeAll(keepingCapacity: true)
        cachedRawString = ""
        rawFastMask = 0
        keystrokeBuffer.reset()
        renderedOutput = ""
        renderedOutputIsASCII = true
        isEditingCommittedWord = false
        isCharacterDeletingCommittedWord = false
        lastFeedWasRejectedNoOp = false
        lastToneSemanticEvent = nil
        hasConfirmedSemanticEscapeInComposition = false
        lastAttemptedKey = nil
        supersededModifiers.removeAll(keepingCapacity: true)
        compositionHistory.removeAll(keepingCapacity: true)
    }

    internal func currentOutput() -> String {
        return renderedOutput
    }

    internal func rawString() -> String {
        return cachedRawString
    }

    @inline(__always)
    private static func advanceFastMask(_ mask: UInt16, with ch: Character) -> UInt16 {
        guard let ascii = ch.asciiValue else {
            return mask | 0x0300
        }
        if ascii >= 0x30 && ascii <= 0x39 {
            return mask | 0x0200
        }
        let lower = ascii | 0x20
        switch lower {
        case 0x73, 0x66, 0x72, 0x78, 0x6A, 0x7A, 0x77: // s, f, r, x, j, z, w
            return mask | 0x0100
        case 0x64: // d (bits 0..1)
            let c = mask & 0x0003
            return c >= 1 ? (mask | 0x0103) : (mask | 0x0001)
        case 0x61: // a (bits 2..3)
            let c = (mask >> 2) & 0x0003
            return c >= 1 ? (mask | 0x010C) : (mask | 0x0004)
        case 0x65: // e (bits 4..5)
            let c = (mask >> 4) & 0x0003
            return c >= 1 ? (mask | 0x0130) : (mask | 0x0010)
        case 0x6F: // o (bits 6..7)
            let c = (mask >> 6) & 0x0003
            return c >= 1 ? (mask | 0x01C0) : (mask | 0x0040)
        default:
            return mask
        }
    }

    @inline(__always)
    private static func computeFastMask(for chars: [Character]) -> UInt16 {
        var mask: UInt16 = 0
        for c in chars {
            mask = advanceFastMask(mask, with: c)
        }
        return mask
    }

    @inline(__always)
    private func appendRawChar(_ ch: Character) {
        rawChars.append(ch)
        cachedRawString.append(ch)
        rawFastMask = Self.advanceFastMask(rawFastMask, with: ch)
    }

    @inline(__always)
    private func setRawChars(_ newRaw: [Character]) {
        rawChars = newRaw
        cachedRawString = String(newRaw)
        rawFastMask = Self.computeFastMask(for: newRaw)
    }

    @inline(__always)
    private func setRenderedOutput(_ newOutput: String, isKnownASCII: Bool? = nil) {
        renderedOutput = newOutput
        renderedOutputIsASCII = isKnownASCII ?? newOutput.utf8.allSatisfy({ $0 < 128 })
    }

    // MARK: - Prefix & Re-composition API

    /// Converts a rendered Vietnamese string into canonical raw keystrokes according to the input method.
    internal static func rawKeys(for text: String, inputMethod: InputMethodType) -> String {
        var raw = ""
        var toneKey: Character? = nil
        let isVni = inputMethod == .vni

        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x0111: // đ
                raw.append(isVni ? "d9" : "dd")
            case 0x0110: // Đ
                raw.append(isVni ? "D9" : "DD")
            case 0x0300: // grave (huyền)
                toneKey = isVni ? "2" : "f"
            case 0x0301: // acute (sắc)
                toneKey = isVni ? "1" : "s"
            case 0x0303: // tilde (ngã)
                toneKey = isVni ? "4" : "x"
            case 0x0309: // hook above (hỏi)
                toneKey = isVni ? "3" : "r"
            case 0x0323: // dot below (nặng)
                toneKey = isVni ? "5" : "j"
            case 0x0302: // circumflex (â, ê, ô)
                if isVni {
                    raw.append("6")
                } else if let last = raw.last {
                    raw.append(last)
                }
            case 0x0306: // breve (ă)
                raw.append(isVni ? "8" : "w")
            case 0x031B: // horn (ơ, ư)
                let lowerRaw = raw.lowercased()
                if !isVni && lowerRaw.hasSuffix("uwo") {
                    let oChar = raw.removeLast()
                    _ = raw.removeLast() // remove redundant 'w' on preceding 'ư' in 'ươ' diphthong
                    raw.append(oChar)
                    raw.append("w")
                } else if isVni && lowerRaw.hasSuffix("u7o") {
                    let oChar = raw.removeLast()
                    _ = raw.removeLast() // remove redundant '7' on preceding 'ư' in 'ươ' diphthong
                    raw.append(oChar)
                    raw.append("7")
                } else {
                    raw.append(isVni ? "7" : "w")
                }
            default:
                raw.append(String(scalar))
            }
        }
        if let toneKey {
            raw.append(toneKey)
        }
        return raw
    }

    internal static func extractActiveToneModifier(from text: String, inputMethod: InputMethodType) -> Character? {
        if text.unicodeScalars.allSatisfy(\.isASCII) { return nil }
        let isVni = inputMethod == .vni
        for ch in text {
            switch ch.lowercased() {
            case "à", "ằ", "ầ", "è", "ề", "ì", "ò", "ồ", "ờ", "ù", "ừ", "ỳ":
                return isVni ? "2" : "f"
            case "á", "ắ", "ấ", "é", "ế", "í", "ó", "ố", "ớ", "ú", "ứ", "ý":
                return isVni ? "1" : "s"
            case "ã", "ẵ", "ẫ", "ẽ", "ễ", "ĩ", "õ", "ỗ", "ỡ", "ũ", "ữ", "ỹ":
                return isVni ? "4" : "x"
            case "ả", "ẳ", "ẩ", "ẻ", "ể", "ỉ", "ỏ", "ổ", "ở", "ủ", "ử", "ỷ":
                return isVni ? "3" : "r"
            case "ạ", "ặ", "ậ", "ẹ", "ệ", "ị", "ọ", "ộ", "ợ", "ụ", "ự", "ỵ":
                return isVni ? "5" : "j"
            default:
                break
            }
        }
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0300: return isVni ? "2" : "f"
            case 0x0301: return isVni ? "1" : "s"
            case 0x0303: return isVni ? "4" : "x"
            case 0x0309: return isVni ? "3" : "r"
            case 0x0323: return isVni ? "5" : "j"
            default: break
            }
        }
        return nil
    }

    internal static func extractActiveVowelModifiers(from text: String, inputMethod: InputMethodType) -> [Character] {
        var mods: [Character] = []
        let isVni = inputMethod == .vni
        var lastBase: Character? = nil
        var hadHornOnU = false
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x0111, 0x0110:
                mods.append(isVni ? "9" : "d")
                lastBase = "d"
            case 0x0302:
                if isVni {
                    mods.append("6")
                } else if let base = lastBase {
                    mods.append(Character(base.lowercased()))
                }
            case 0x0306:
                mods.append(isVni ? "8" : "w")
            case 0x031B:
                if lastBase?.lowercased() == "u" {
                    hadHornOnU = true
                    mods.append(isVni ? "7" : "w")
                } else if lastBase?.lowercased() == "o" && hadHornOnU {
                    // Shared horn across 'ươ' diphthong
                } else {
                    mods.append(isVni ? "7" : "w")
                }
            case 0x0300, 0x0301, 0x0303, 0x0309, 0x0323:
                break
            default:
                if scalar.properties.isAlphabetic {
                    lastBase = Character(scalar)
                }
            }
        }
        return mods
    }

    internal static func extractSemanticTransformations(from text: String, inputMethod: InputMethodType) -> [String] {
        if text.unicodeScalars.allSatisfy(\.isASCII) { return [] }
        var transforms: [String] = []
        let isVni = inputMethod == .vni
        var toneTransform: String? = nil
        for ch in text {
            let lower = ch.lowercased()
            switch lower {
            case "đ":
                transforms.append(isVni ? "d9->đ" : "dd->đ")
            case "ă", "ắ", "ằ", "ẳ", "ẵ", "ặ":
                transforms.append(isVni ? "a8->ă" : "aw->ă")
            case "â", "ấ", "ầ", "ẩ", "ẫ", "ậ":
                transforms.append(isVni ? "a6->â" : "aa->â")
            case "ê", "ế", "ề", "ể", "ễ", "ệ":
                transforms.append(isVni ? "e6->ê" : "ee->ê")
            case "ô", "ố", "ồ", "ổ", "ỗ", "ộ":
                transforms.append(isVni ? "o6->ô" : "oo->ô")
            case "ơ", "ớ", "ờ", "ở", "ỡ", "ợ":
                transforms.append(isVni ? "o7->ơ" : "ow->ơ")
            case "ư", "ứ", "ừ", "ử", "ữ", "ự":
                transforms.append(isVni ? "u7->ư" : "uw->ư")
            default:
                break
            }
            switch lower {
            case "à", "ằ", "ầ", "è", "ề", "ì", "ò", "ồ", "ờ", "ù", "ừ", "ỳ":
                toneTransform = isVni ? "2->grave" : "f->grave"
            case "á", "ắ", "ấ", "é", "ế", "í", "ó", "ố", "ớ", "ú", "ứ", "ý":
                toneTransform = isVni ? "1->acute" : "s->acute"
            case "ã", "ẵ", "ẫ", "ẽ", "ễ", "ĩ", "õ", "ỗ", "ỡ", "ũ", "ữ", "ỹ":
                toneTransform = isVni ? "4->tilde" : "x->tilde"
            case "ả", "ẳ", "ẩ", "ẻ", "ể", "ỉ", "ỏ", "ổ", "ở", "ủ", "ử", "ỷ":
                toneTransform = isVni ? "3->hook" : "r->hook"
            case "ạ", "ặ", "ậ", "ẹ", "ệ", "ị", "ọ", "ộ", "ợ", "ụ", "ự", "ỵ":
                toneTransform = isVni ? "5->dot" : "j->dot"
            default:
                break
            }
        }
        if let toneTransform {
            transforms.append(toneTransform)
        }
        return transforms
    }

    internal static func extractLiteralSuffix(from rendered: String, raw: String, relaxedCoda: Bool = false, genZMode: Bool = false) -> String {
        guard rendered.count >= 2, let lastChar = rendered.last, lastChar.isASCII else { return "" }
        let lowerRendered = rendered.lowercased()
        if !rendered.unicodeScalars.allSatisfy({ $0.isASCII }) {
            if VietnameseSyllableDictionary.shared.hasStrictSyllablePrefix(lowerRendered) ||
               VietnameseSyllableDictionary.shared.isValidSyllable(lowerRendered) ||
               VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lowerRendered, genZMode: genZMode) ||
               VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(lowerRendered, relaxedCoda: relaxedCoda, genZMode: genZMode) {
                return ""
            }
            let chars = Array(rendered)
            for idx in stride(from: chars.count - 1, through: 1, by: -1) {
                let prefix = String(chars[0..<idx])
                if VietnameseSyllableDictionary.shared.isValidSyllable(prefix.lowercased()) ||
                   VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(prefix.lowercased(), relaxedCoda: relaxedCoda, genZMode: genZMode) {
                    return String(chars[idx...])
                }
            }
            return ""
        }
        if raw.count >= 3 && SmartBilingualDetector.hasSemanticToneEscape(lowerRaw: raw.lowercased(), lowerRendered: lowerRendered) {
            let toneKeys: Set<Character> = ["s", "f", "r", "x", "j"]
            let chars = Array(rendered)
            for splitIdx in stride(from: chars.count - 1, through: 1, by: -1) {
                let ch = Character(chars[splitIdx].lowercased())
                guard toneKeys.contains(ch) else { continue }
                let stem = String(chars[0..<splitIdx]).lowercased()
                if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stem) ||
                   VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(stem) ||
                   VietnameseSyllableDictionary.shared.isValidOpenBrevePrefix(stem) ||
                   (stem.count >= 2 && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(stem)) {
                    return String(chars[splitIdx...])
                }
            }
        }
        return ""
    }

    private static func hasConfirmedEscapeInState(
        rawChars: [Character],
        renderedOutput: String,
        inputMethod: InputMethodType
    ) -> Bool {
        guard !VietnameseSyllableDictionary.hasToneMark(renderedOutput) else { return false }
        let rawStr = String(rawChars)
        guard rawStr.lowercased() != renderedOutput.lowercased() else { return false }
        if inputMethod == .vni {
            return SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: rawStr, rendered: renderedOutput)
        }
        return SmartBilingualDetector.hasSemanticToneEscape(
            lowerRaw: rawStr.lowercased(),
            lowerRendered: renderedOutput.lowercased()
        ) || SmartBilingualDetector.isExplicitTelexEscape(
            raw: rawStr,
            rendered: renderedOutput
        )
    }

    private static func isPlausibleEnglishTwoToneCluster(
        rawChars: [Character],
        prevTone: Character,
        newTone: Character
    ) -> Bool {
        guard rawChars.count >= 3 else { return false }
        let pair = String([prevTone, newTone]).lowercased()
        let beforePrev = Character(rawChars[rawChars.count - 3].lowercased())
        switch pair {
        case "rs":
            return true
        case "rf":
            return beforePrev == "a" || beforePrev == "e" || beforePrev == "o" || beforePrev == "u"
        case "fr":
            return beforePrev == "n" || beforePrev == "a" || beforePrev == "e"
        case "sf":
            return beforePrev == "n" || beforePrev == "i"
        case "sr":
            return beforePrev == "i" || beforePrev == "u"
        case "xf":
            return beforePrev == "o"
        default:
            return false
        }
    }

    /// Re-initializes composition state with an existing prefix already rendered on screen.
    internal func setCompositionPrefix(_ text: String) {
        let raw = VietnameseEngine.rawKeys(for: text, inputMethod: inputMethod)
        reset()
        for ch in raw {
            _ = feed(ch)
        }
        // Preserve the exact on-screen Unicode scalar representation (e.g. NFD pasted from APFS/PDF)
        // so the subsequent feed/backspace diff computes the exact UTF-16 backspace count on screen.
        setRenderedOutput(text)
    }

    // MARK: - Core Feed / Edit / Commit API

    /// Feeds a single character literally into the active composition without Telex/VNI transformation.
    /// Locks the active composition into literal append mode until Backspace pops the literal steps or the word commits.
    internal func feedLiteral(_ ch: Character) -> (backspaces: Int, suffix: String)? {
        guard ch.isASCII else {
            if isComposing {
                _ = commit()
            }
            return (0, String(ch))
        }
        isEditingCommittedWord = false
        isCharacterDeletingCommittedWord = false
        lastFeedWasRejectedNoOp = false
        lastToneSemanticEvent = nil
        let previousOutput = renderedOutput
        let prevIsASCII = renderedOutputIsASCII
        appendRawChar(ch)
        keystrokeBuffer.append(ch)
        let newOutput = previousOutput + String(ch)
        compositionHistory.append(
            CompositionSnapshot(
                rawChars: rawChars,
                renderedOutput: newOutput,
                isLiteralOrCancellationStep: true,
                isExplicitLiteralLock: true,
                toneSemanticEvent: nil,
                hasConfirmedSemanticEscape: hasConfirmedSemanticEscapeInComposition
            )
        )
        setRenderedOutput(newOutput, isKnownASCII: prevIsASCII)
        return calculateDiff(oldStr: previousOutput, newStr: newOutput, appendedChar: ch)
    }

    /// Synchronizes the internal rendered output to `text` and locks the active composition into literal mode
    /// when `InputSessionManager` prevents a fake Telex escape on an already-literal English token (e.g. `fee -> feee`).
    internal func forceLiteralOutput(_ text: String) {
        setRenderedOutput(text)
        lastToneSemanticEvent = nil
        hasConfirmedSemanticEscapeInComposition = false
        if !compositionHistory.isEmpty {
            let lastSnap = compositionHistory.removeLast()
            compositionHistory.append(
                CompositionSnapshot(
                    rawChars: lastSnap.rawChars,
                    renderedOutput: text,
                    isLiteralOrCancellationStep: true,
                    isExplicitLiteralLock: true,
                    supersededModifiers: lastSnap.supersededModifiers,
                    toneSemanticEvent: nil,
                    hasConfirmedSemanticEscape: false
                )
            )
        }
    }

    /// Feeds a single character into the engine.
    /// Returns (backspaces, suffix) diff if the on-screen text needs transformation,
    /// or returns (0, String(ch)) if it passes through, or nil if rejected.
    internal var isExplicitlyLiteralLocked: Bool {
        literalOverrideEnabled || compositionHistory.last?.isExplicitLiteralLock == true
    }

    internal func feed(_ ch: Character) -> (backspaces: Int, suffix: String)? {
        guard ch.isASCII else {
            // Non-ASCII characters commit previous composition and pass through
            if isComposing {
                _ = commit()
            }
            return (0, String(ch))
        }
        if literalOverrideEnabled || compositionHistory.last?.isExplicitLiteralLock == true {
            return feedLiteral(ch)
        }

        let wasEditingCommitted = isEditingCommittedWord
        let prevAttemptedKey = lastAttemptedKey
        lastAttemptedKey = ch
        isEditingCommittedWord = false
        isCharacterDeletingCommittedWord = false
        lastFeedWasRejectedNoOp = false
        let previousOutput = renderedOutput
        let prevIsASCII = renderedOutputIsASCII
        if inputMethod == .vni &&
           prevIsASCII &&
           (rawFastMask & 0x0200) == 0 &&
           !ch.isNumber &&
           compositionHistory.last?.isLiteralOrCancellationStep != true {
            appendRawChar(ch)
            keystrokeBuffer.append(ch)
            if !ch.isLetter && !ch.isNumber {
                hasConfirmedSemanticEscapeInComposition = false
            }
            lastToneSemanticEvent = nil
            let newOutput = previousOutput + String(ch)
            compositionHistory.append(
                CompositionSnapshot(
                    rawChars: rawChars,
                    renderedOutput: newOutput,
                    isLiteralOrCancellationStep: false,
                    isExplicitLiteralLock: false,
                    supersededModifiers: supersededModifiers,
                    toneSemanticEvent: nil,
                    hasConfirmedSemanticEscape: hasConfirmedSemanticEscapeInComposition
                )
            )
            setRenderedOutput(newOutput, isKnownASCII: true)
            return (0, String(ch))
        }
        let lowerCh = ch.lowercased()
        if inputMethod == .telex &&
           !previousOutput.isEmpty &&
           !prevIsASCII &&
           (lowerCh == "s" || lowerCh == "f" || lowerCh == "r" || lowerCh == "x" || lowerCh == "j") &&
           rawChars.last?.lowercased() == lowerCh &&
           prevAttemptedKey?.lowercased() != lowerCh &&
           (VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(previousOutput, relaxedCoda: relaxedCoda, genZMode: genZMode) ||
            VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(previousOutput)) {
            return feedLiteral(ch)
        }
        appendRawChar(ch)
        keystrokeBuffer.append(ch)

        if inputMethod == .telex &&
           prevIsASCII &&
           (rawFastMask & 0x0100) == 0 &&
           compositionHistory.last?.isLiteralOrCancellationStep != true {
            if !ch.isLetter && !ch.isNumber {
                hasConfirmedSemanticEscapeInComposition = false
            }
            lastToneSemanticEvent = nil
            let fastOutput = previousOutput + String(ch)
            compositionHistory.append(
                CompositionSnapshot(
                    rawChars: rawChars,
                    renderedOutput: fastOutput,
                    isLiteralOrCancellationStep: false,
                    isExplicitLiteralLock: false,
                    supersededModifiers: supersededModifiers,
                    toneSemanticEvent: nil,
                    hasConfirmedSemanticEscape: hasConfirmedSemanticEscapeInComposition
                )
            )
            setRenderedOutput(fastOutput, isKnownASCII: true)
            return (0, String(ch))
        }

        let isToneOrZKey = (inputMethod == .telex && (lowerCh == "s" || lowerCh == "f" || lowerCh == "r" || lowerCh == "x" || lowerCh == "j" || lowerCh == "z")) ||
            (inputMethod == .vni && (lowerCh == "1" || lowerCh == "2" || lowerCh == "3" || lowerCh == "4" || lowerCh == "5" || lowerCh == "0"))
        let isVowelOrHornKey = (lowerCh == "a" || lowerCh == "e" || lowerCh == "o" || lowerCh == "w")
        let lowerPrevUntoned = (!previousOutput.isEmpty && (isToneOrZKey || isVowelOrHornKey))
            ? (prevIsASCII ? previousOutput.lowercased() : VietnameseSyllableDictionary.stripToneMarks(previousOutput.lowercased()))
            : ""
        let isCompoundHornSecondW =
            !prevIsASCII &&
            inputMethod == .telex &&
            lowerCh == "w" &&
            rawChars.count >= 3 &&
            Character(rawChars[rawChars.count - 2].lowercased()) != "w" &&
            lowerPrevUntoned.hasSuffix("ươ") &&
            rawChars.dropLast().filter({ $0.lowercased() == "w" }).count == 1
        if isCompoundHornSecondW {
            let canonicalRaw = Array(Self.rawKeys(for: previousOutput, inputMethod: inputMethod))
            setRawChars(canonicalRaw)
            keystrokeBuffer.reset()
            for c in canonicalRaw { keystrokeBuffer.append(c) }
            if !compositionHistory.isEmpty {
                let lastSnap = compositionHistory.removeLast()
                compositionHistory.append(
                    CompositionSnapshot(
                        rawChars: canonicalRaw,
                        renderedOutput: lastSnap.renderedOutput,
                        isLiteralOrCancellationStep: lastSnap.isLiteralOrCancellationStep,
                        isExplicitLiteralLock: lastSnap.isExplicitLiteralLock,
                        supersededModifiers: lastSnap.supersededModifiers,
                        toneSemanticEvent: lastSnap.toneSemanticEvent,
                        hasConfirmedSemanticEscape: lastSnap.hasConfirmedSemanticEscape
                    )
                )
            }
            lastToneSemanticEvent = nil
            return (0, "")
        }

        let newOutput = transform(rawChars)
        if prevIsASCII &&
           newOutput.utf8.allSatisfy({ $0 < 128 }) &&
           newOutput == previousOutput + String(ch) &&
           compositionHistory.last?.isLiteralOrCancellationStep != true {
            if !ch.isLetter && !ch.isNumber {
                hasConfirmedSemanticEscapeInComposition = false
            }
            lastToneSemanticEvent = nil
            compositionHistory.append(
                CompositionSnapshot(
                    rawChars: rawChars,
                    renderedOutput: newOutput,
                    isLiteralOrCancellationStep: false,
                    isExplicitLiteralLock: false,
                    supersededModifiers: supersededModifiers,
                    toneSemanticEvent: nil,
                    hasConfirmedSemanticEscape: hasConfirmedSemanticEscapeInComposition
                )
            )
            setRenderedOutput(newOutput, isKnownASCII: true)
            return (0, String(ch))
        }
        if !previousOutput.isEmpty &&
           newOutput == previousOutput &&
           !prevIsASCII &&
           (VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(previousOutput, relaxedCoda: relaxedCoda, genZMode: genZMode) ||
            VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(previousOutput)) &&
           !SmartBilingualDetector.isKnownEnglishWord(String(rawChars).lowercased()) {
            setRawChars(Array(rawChars.dropLast()))
            keystrokeBuffer.popLast()
            return feedLiteral(ch)
        }

        let lowerNewUntoned = (isToneOrZKey || isVowelOrHornKey) ? VietnameseSyllableDictionary.stripToneMarks(newOutput.lowercased()) : ""
        let prevToneMod = isToneOrZKey ? Self.extractActiveToneModifier(from: previousOutput, inputMethod: inputMethod) : nil
        let newToneMod = isToneOrZKey ? Self.extractActiveToneModifier(from: newOutput, inputMethod: inputMethod) : nil
        let isToneClearZ =
            lowerCh == "z" &&
            !previousOutput.isEmpty &&
            previousOutput != newOutput &&
            !newOutput.lowercased().hasSuffix("z") &&
            VietnameseSyllableDictionary.hasToneMark(previousOutput) &&
            !VietnameseSyllableDictionary.hasToneMark(newOutput) &&
            newOutput.lowercased() == lowerPrevUntoned &&
            VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(previousOutput)
        let isMutualExclusionVowelReshape =
            ((lowerCh == "o" && lowerPrevUntoned.contains("ơ")) ||
             (lowerCh == "w" && (lowerPrevUntoned.contains("ô") || lowerPrevUntoned.contains("â")))) &&
            previousOutput != newOutput &&
            previousOutput.count == newOutput.count &&
            !newOutput.lowercased().hasSuffix(lowerCh) &&
            !newOutput.unicodeScalars.allSatisfy({ $0.isASCII }) &&
            VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newOutput)
        let isLateVowelModification =
            (lowerCh == "a" || lowerCh == "e" || lowerCh == "o" || lowerCh == "w") &&
            !previousOutput.isEmpty &&
            previousOutput != newOutput &&
            previousOutput.count == newOutput.count &&
            !newOutput.lowercased().hasSuffix(lowerCh) &&
            !lowerPrevUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            lowerNewUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            VietnameseSyllableDictionary.hasToneMark(previousOutput) &&
            VietnameseSyllableDictionary.hasToneMark(newOutput) &&
            (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newOutput) ||
             VietnameseSyllableDictionary.shared.isValidOpenBrevePrefix(lowerNewUntoned, genZMode: genZMode))
        let isVowelShapeCancellation =
            (lowerCh == "a" || lowerCh == "e" || lowerCh == "o" || lowerCh == "w") &&
            !previousOutput.isEmpty &&
            previousOutput != newOutput &&
            previousOutput.count == newOutput.count &&
            !newOutput.lowercased().hasSuffix(lowerCh) &&
            lowerPrevUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            !lowerNewUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(previousOutput) ||
             (!VietnameseSyllableDictionary.hasToneMark(previousOutput) &&
              VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(previousOutput)))
        let isReversibleLateVowelStep = (isLateVowelModification &&
            (previousOutput.last.map({ Self.isVietnameseVowel($0) }) ?? false)) || isVowelShapeCancellation
        let isStrokeCancellation =
            lowerCh == "d" &&
            !previousOutput.isEmpty &&
            previousOutput.first?.lowercased() == "đ" &&
            newOutput.first?.lowercased() == "d" &&
            previousOutput.dropFirst() == newOutput.dropFirst()
        let isToneReplacement =
            (lowerCh == "s" || lowerCh == "f" || lowerCh == "r" || lowerCh == "x" || lowerCh == "j") &&
            !previousOutput.isEmpty &&
            previousOutput != newOutput &&
            prevToneMod != nil &&
            newToneMod != nil &&
            prevToneMod != newToneMod &&
            lowerPrevUntoned == lowerNewUntoned &&
            VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(newOutput, relaxedCoda: relaxedCoda, genZMode: genZMode)

        let isAdjacentToneSwitch = isToneReplacement &&
            rawChars.count >= 3 &&
            prevToneMod != nil &&
            Character(rawChars[rawChars.count - 2].lowercased()) == prevToneMod &&
            !(rawChars.count >= 4 && rawChars.dropLast(2).contains(where: { ["s", "f", "r", "x", "j"].contains($0.lowercased()) }))
        if isToneClearZ, let prevToneMod {
            supersededModifiers.append(prevToneMod)
            supersededModifiers.append("z")
        } else if isAdjacentToneSwitch, let prevToneMod {
            supersededModifiers.append(prevToneMod)
        }

        let isAdjacentToneClearZ: Bool = {
            guard isToneClearZ else { return false }
            if !newOutput.unicodeScalars.allSatisfy({ $0.isASCII }) {
                return true
            }
            guard rawChars.count >= 3, let prevToneMod else { return false }
            let adj = Character(rawChars[rawChars.count - 2].lowercased()) == prevToneMod
            let isErzCluster = prevToneMod == "r" &&
                supersededModifiers.count <= 2 &&
                Character(rawChars[rawChars.count - 3].lowercased()) == "e"
            return adj && !isErzCluster
        }()

        let shouldCanonicalizeToneReplacement = isAdjacentToneSwitch &&
            !rawChars.contains(where: { $0.isUppercase }) &&
            rawChars.first?.lowercased() != "w" && (
                supersededModifiers.count >= 2 ||
                !Self.isPlausibleEnglishTwoToneCluster(rawChars: rawChars, prevTone: prevToneMod!, newTone: Character(lowerCh))
            )

        // P0.2: Semantic Tone Escape & Canonical Return (`CancelToneAndEmitLiteral`)
        // When a repeated tone key cancels the currently active tone and emits a single literal tone key
        // (`canhf + f -> canhf`, `cafnh + f -> canhf`, `canhr + r -> canhr`, `canhfr + r -> canhr`, `hoongf + f -> hôngf`),
        // canonicalize the underlying raw key sequence from the untoned syllable so that:
        // 1) Multi-order Telex inputs (`canhf` vs `cafnh`) share identical canonical state,
        // 2) Subsequent characters (`+ aa`) remain in explicit literal escape without re-parsing or raw replay (`canhfaa`),
        // 3) Backspace steps cleanly (`canhfaa -> canhfa -> canhf -> canh`).
        let isSemanticToneEscapeCancel: Bool = {
            guard inputMethod == .telex,
                  ["s", "f", "r", "x", "j"].contains(lowerCh),
                  !previousOutput.isEmpty,
                  let prevToneMod,
                  prevToneMod == Character(lowerCh),
                  newToneMod == nil,
                  newOutput.lowercased() == lowerPrevUntoned + lowerCh else {
                return false
            }
            guard VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(previousOutput, relaxedCoda: relaxedCoda, genZMode: genZMode) ||
                  VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnameseRhyme(previousOutput) ||
                  VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(previousOutput) else {
                return false
            }
            let lowerFullRaw = String(rawChars).lowercased()
            return !SmartBilingualDetector.isKnownEnglishWord(lowerFullRaw)
        }()

        let isVNICancellationAndLiteralEmit: Bool = {
            guard inputMethod == .vni,
                  ch.isNumber,
                  !previousOutput.isEmpty,
                  newOutput.last == ch,
                  newOutput.lowercased() != (previousOutput + String(ch)).lowercased() else {
                return false
            }
            return true
        }()
        let isVNIToneClearOrReshape: Bool = {
            guard inputMethod == .vni,
                  ch.isNumber,
                  !previousOutput.isEmpty,
                  previousOutput != newOutput,
                  !newOutput.hasSuffix(String(ch)) else {
                return false
            }
            if ch == "0" && VietnameseSyllableDictionary.hasToneMark(previousOutput) && !VietnameseSyllableDictionary.hasToneMark(newOutput) {
                return true
            }
            return VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newOutput)
        }()

        let isTelexRepeatedToneCancelRaw =
            inputMethod == .telex &&
            ["s", "f", "r", "x", "j"].contains(lowerCh) &&
            !previousOutput.isEmpty &&
            prevToneMod == Character(lowerCh) &&
            newToneMod == nil &&
            newOutput.lowercased() == lowerPrevUntoned + lowerCh
        let toneEvent: ToneModifierSemanticEvent? = {
            if isSemanticToneEscapeCancel || isTelexRepeatedToneCancelRaw ||
               (isVNICancellationAndLiteralEmit && ["1", "2", "3", "4", "5"].contains(lowerCh)) {
                return .cancelToneAndEmitLiteral
            }
            if isToneClearZ ||
               (inputMethod == .vni && ch == "0" && VietnameseSyllableDictionary.hasToneMark(previousOutput) && !VietnameseSyllableDictionary.hasToneMark(newOutput)) {
                return .clearToneZ
            }
            if isToneReplacement ||
               (inputMethod == .vni && ["1", "2", "3", "4", "5"].contains(lowerCh) && prevToneMod != nil && newToneMod != nil && prevToneMod != newToneMod) {
                return .replaceTone
            }
            if !hasConfirmedSemanticEscapeInComposition &&
               inputMethod == .telex &&
               ["s", "f", "r", "x", "j"].contains(lowerCh) &&
               prevToneMod != nil &&
               newToneMod == prevToneMod &&
               previousOutput == newOutput {
                return .idempotentPostReshapeTone
            }
            if !hasConfirmedSemanticEscapeInComposition &&
               ((inputMethod == .telex && ["s", "f", "r", "x", "j"].contains(lowerCh)) ||
                (inputMethod == .vni && ["1", "2", "3", "4", "5"].contains(lowerCh))) &&
               prevToneMod == nil &&
               newToneMod != nil {
                return .applyTone
            }
            return nil
        }()

        if !ch.isLetter && !ch.isNumber {
            hasConfirmedSemanticEscapeInComposition = false
        } else if isSemanticToneEscapeCancel || isVNICancellationAndLiteralEmit {
            hasConfirmedSemanticEscapeInComposition = true
        }
        lastToneSemanticEvent = toneEvent

        if isSemanticToneEscapeCancel {
            let untonedPreviousOutput = String(previousOutput.map { Self.addToneToVowel($0, tone: .none) })
            let untonedCanonicalRaw = Array(Self.rawKeys(for: untonedPreviousOutput, inputMethod: inputMethod))
            if !compositionHistory.isEmpty {
                compositionHistory[compositionHistory.count - 1] = CompositionSnapshot(
                    rawChars: untonedCanonicalRaw,
                    renderedOutput: untonedPreviousOutput,
                    isLiteralOrCancellationStep: false,
                    supersededModifiers: supersededModifiers
                )
            }
        } else if isVNICancellationAndLiteralEmit {
            let priorCanonicalRaw = Array(Self.rawKeys(for: previousOutput, inputMethod: .vni))
            if !compositionHistory.isEmpty {
                compositionHistory[compositionHistory.count - 1] = CompositionSnapshot(
                    rawChars: priorCanonicalRaw,
                    renderedOutput: previousOutput,
                    isLiteralOrCancellationStep: false,
                    supersededModifiers: supersededModifiers
                )
            }
            if transform(rawChars) != newOutput {
                let stemOutput = String(newOutput.dropLast())
                let canonicalStemRaw = Array(Self.rawKeys(for: stemOutput, inputMethod: .vni)) + [ch]
                setRawChars(canonicalStemRaw)
                keystrokeBuffer.reset()
                for c in canonicalStemRaw { keystrokeBuffer.append(c) }
            }
        } else if isVNIToneClearOrReshape {
            let canonicalRaw = Array(Self.rawKeys(for: newOutput, inputMethod: .vni))
            setRawChars(canonicalRaw)
            keystrokeBuffer.reset()
            for c in canonicalRaw { keystrokeBuffer.append(c) }
        } else if inputMethod == .telex && (isAdjacentToneClearZ || isMutualExclusionVowelReshape || shouldCanonicalizeToneReplacement) {
            let canonicalRaw = Array(Self.rawKeys(for: newOutput, inputMethod: inputMethod))
            setRawChars(canonicalRaw)
            keystrokeBuffer.reset()
            for c in canonicalRaw { keystrokeBuffer.append(c) }
        }
        let isPostToneEscapeLiteralFollowup =
            compositionHistory.last?.isLiteralOrCancellationStep == true &&
            !previousOutput.isEmpty &&
            newOutput.lowercased() == previousOutput.lowercased() + lowerCh &&
            !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(newOutput, relaxedCoda: relaxedCoda, genZMode: genZMode)
        let isLiteralModifierFallbackOnComposed =
            (lowerCh == "z" || lowerCh == "w" || lowerCh == "a" || lowerCh == "e" || lowerCh == "o" ||
             lowerCh == "u" || lowerCh == "i" || lowerCh == "y") &&
            !previousOutput.isEmpty &&
            newOutput.lowercased() == previousOutput.lowercased() + lowerCh &&
            (compositionHistory.last?.isLiteralOrCancellationStep == true ||
             (!prevIsASCII &&
              !VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newOutput) &&
              !VietnameseSyllableDictionary.shared.hasUntonedPrefix(newOutput, preserveVowelShape: true, relaxedCoda: relaxedCoda, genZMode: genZMode)))
        let newIsASCII = newOutput.utf8.allSatisfy({ $0 < 128 })
        let isLiteralOrCancel = (!previousOutput.isEmpty &&
            !newIsASCII &&
            !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(newOutput, relaxedCoda: relaxedCoda, genZMode: genZMode)) ||
            isLiteralModifierFallbackOnComposed ||
            isSemanticToneEscapeCancel ||
            isVNICancellationAndLiteralEmit ||
            isPostToneEscapeLiteralFollowup
        compositionHistory.append(
            CompositionSnapshot(
                rawChars: rawChars,
                renderedOutput: newOutput,
                isLiteralOrCancellationStep: isLiteralOrCancel || ((isToneClearZ || isVNIToneClearOrReshape || isMutualExclusionVowelReshape || isReversibleLateVowelStep || isStrokeCancellation) && !wasEditingCommitted),
                isExplicitLiteralLock: isVNICancellationAndLiteralEmit,
                supersededModifiers: supersededModifiers,
                toneSemanticEvent: toneEvent,
                hasConfirmedSemanticEscape: hasConfirmedSemanticEscapeInComposition
            )
        )
        setRenderedOutput(newOutput, isKnownASCII: newIsASCII)

        // Calculate diff between previousOutput and newOutput
        return calculateDiff(oldStr: previousOutput, newStr: newOutput, appendedChar: ch)
    }

    /// Handles backspace keypress during composition by reversing the active semantic or literal composition step.
    internal func backspace(displayedAsRaw: Bool = false) -> (backspaces: Int, suffix: String)? {
        guard !rawChars.isEmpty else { return nil }
        let previousOutput = renderedOutput
        if !displayedAsRaw,
           backspaceStyle == .appleSemantic,
           !isCharacterDeletingCommittedWord,
           compositionHistory.count >= 2,
           let lastSnap = compositionHistory.last,
           lastSnap.isLiteralOrCancellationStep {
            compositionHistory.removeLast()
            let restored = compositionHistory.last!
            setRawChars(restored.rawChars)
            keystrokeBuffer.reset()
            for c in restored.rawChars { keystrokeBuffer.append(c) }
            setRenderedOutput(restored.renderedOutput)
            supersededModifiers = restored.supersededModifiers
            lastToneSemanticEvent = restored.toneSemanticEvent
            hasConfirmedSemanticEscapeInComposition = restored.hasConfirmedSemanticEscape
            lastAttemptedKey = rawChars.last
            if isEditingCommittedWord && !committedHistory.isEmpty {
                committedHistory[committedHistory.count - 1] = (raw: restored.rawChars, rendered: restored.renderedOutput)
            }
            return calculateDiff(oldStr: previousOutput, newStr: restored.renderedOutput, appendedChar: nil)
        }
        if displayedAsRaw {
            let previousRaw = cachedRawString
            setRawChars(Array(rawChars.dropLast()))
            keystrokeBuffer.popLast()
            if !compositionHistory.isEmpty {
                compositionHistory.removeLast()
            }
            if rawChars.isEmpty {
                if isEditingCommittedWord && !committedHistory.isEmpty {
                    committedHistory.removeLast()
                }
                reset()
                return (previousRaw.utf16.count, "")
            }
            let newOutput = transform(rawChars)
            setRenderedOutput(newOutput)
            lastToneSemanticEvent = compositionHistory.last?.toneSemanticEvent
            hasConfirmedSemanticEscapeInComposition = false
            lastAttemptedKey = rawChars.last
            if isEditingCommittedWord && !committedHistory.isEmpty {
                committedHistory[committedHistory.count - 1] = (raw: rawChars, rendered: newOutput)
            }
            return (1, "")
        }
        guard !previousOutput.isEmpty else {
            if isEditingCommittedWord && !committedHistory.isEmpty {
                committedHistory.removeLast()
            }
            reset()
            return nil
        }

        // 1. If the user is deleting a previously committed word character-by-character via Backspace,
        // or if Gboard-style fast character deletion is active (V1 Section 2.C: `được -> đượ -> đư -> đ -> ∅`):
        if isCharacterDeletingCommittedWord || backspaceStyle == .gboardCharacter {
            let shortened = String(previousOutput.dropLast())
            if shortened.isEmpty {
                if isEditingCommittedWord && !committedHistory.isEmpty {
                    committedHistory.removeLast()
                }
                reset()
                return (previousOutput.utf16.count, "")
            }
            let preserveExplicitLiteralLock =
                !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(shortened, relaxedCoda: relaxedCoda, genZMode: genZMode) &&
                !shortened.allSatisfy(\.isASCII) &&
                compositionHistory.last?.isExplicitLiteralLock == true
            let droppedRaw = Array(rawChars.dropLast())
            let rawCopy: [Character]
            if preserveExplicitLiteralLock || (shortened.unicodeScalars.allSatisfy({ $0.isASCII }) && transform(Array(shortened)) == shortened) {
                rawCopy = Array(shortened)
            } else if !droppedRaw.isEmpty && transform(droppedRaw) == shortened {
                rawCopy = droppedRaw
            } else {
                rawCopy = Array(Self.rawKeys(for: shortened, inputMethod: inputMethod))
            }
            setRawChars(rawCopy)
            keystrokeBuffer.reset()
            for c in rawCopy { keystrokeBuffer.append(c) }
            setRenderedOutput(shortened)
            supersededModifiers.removeAll(keepingCapacity: true)
            let reopenedEscape = Self.hasConfirmedEscapeInState(rawChars: rawCopy, renderedOutput: shortened, inputMethod: inputMethod)
            lastToneSemanticEvent = nil
            hasConfirmedSemanticEscapeInComposition = reopenedEscape
            lastAttemptedKey = rawChars.last
            compositionHistory = [
                CompositionSnapshot(
                    rawChars: rawCopy,
                    renderedOutput: shortened,
                    isLiteralOrCancellationStep: false,
                    isExplicitLiteralLock: preserveExplicitLiteralLock,
                    hasConfirmedSemanticEscape: reopenedEscape
                )
            ]
            if isEditingCommittedWord && !committedHistory.isEmpty {
                committedHistory[committedHistory.count - 1] = (raw: rawCopy, rendered: shortened)
            }
            return calculateDiff(oldStr: previousOutput, newStr: shortened, appendedChar: nil)
        }

        // 2. If the last keystroke was a literal suffix or modifier-cancellation step (e.g. "truòngwf" -> "truòngw" -> "trường"),
        // pop the snapshot stack to restore the exact prior composition state.
        if compositionHistory.count >= 2,
           let lastSnap = compositionHistory.last,
           lastSnap.isLiteralOrCancellationStep {
            compositionHistory.removeLast()
            let restored = compositionHistory.last!
            setRawChars(restored.rawChars)
            keystrokeBuffer.reset()
            for c in restored.rawChars { keystrokeBuffer.append(c) }
            setRenderedOutput(restored.renderedOutput)
            supersededModifiers = restored.supersededModifiers
            lastToneSemanticEvent = restored.toneSemanticEvent
            hasConfirmedSemanticEscapeInComposition = restored.hasConfirmedSemanticEscape
            lastAttemptedKey = rawChars.last
            if isEditingCommittedWord && !committedHistory.isEmpty {
                committedHistory[committedHistory.count - 1] = (raw: restored.rawChars, rendered: restored.renderedOutput)
            }
            return calculateDiff(oldStr: previousOutput, newStr: restored.renderedOutput, appendedChar: nil)
        }

        // 3. If the word on screen was raw untransformed ASCII during active composition (e.g. "crash" -> "cras" in SEN Flex),
        // dropping the last raw keystroke lets the arbiter re-evaluate the shorter prefix.
        let isTwoCharWInitial = rawChars.count == 2 && Character(rawChars[0].lowercased()) == "w"
        if !isEditingCommittedWord && !isTwoCharWInitial && previousOutput.lowercased() == cachedRawString.lowercased() && rawChars.count == previousOutput.count && transform(rawChars) == previousOutput {
            setRawChars(Array(rawChars.dropLast()))
            keystrokeBuffer.popLast()
            if !compositionHistory.isEmpty {
                compositionHistory.removeLast()
            }
            if rawChars.isEmpty {
                reset()
                return (previousOutput.utf16.count, "")
            }
            let newOutput = transform(rawChars)
            setRenderedOutput(newOutput)
            lastToneSemanticEvent = compositionHistory.last?.toneSemanticEvent
            hasConfirmedSemanticEscapeInComposition = compositionHistory.last?.hasConfirmedSemanticEscape ??
                Self.hasConfirmedEscapeInState(rawChars: rawChars, renderedOutput: newOutput, inputMethod: inputMethod)
            lastAttemptedKey = rawChars.last
            return calculateDiff(oldStr: previousOutput, newStr: newOutput, appendedChar: nil)
        }

        // 4. Canonical Semantic Backspace for active composed syllables (or character drop for escaped ASCII):
        let shortened: String
        if !renderedOutputIsASCII {
            shortened = Self.applySemanticBackspace(to: previousOutput)
        } else {
            shortened = String(previousOutput.dropLast())
        }

        if shortened.isEmpty {
            if isEditingCommittedWord && !committedHistory.isEmpty {
                committedHistory.removeLast()
            }
            reset()
            return (previousOutput.utf16.count, "")
        }

        let droppedRaw = Array(rawChars.dropLast())
        let rawCopy: [Character]
        if shortened.unicodeScalars.allSatisfy({ $0.isASCII }) && transform(Array(shortened)) == shortened {
            rawCopy = Array(shortened)
        } else if !droppedRaw.isEmpty && (transform(droppedRaw) == shortened || (droppedRaw.count == 1 && Character(droppedRaw[0].lowercased()) == "w" && shortened.lowercased() == "w")) {
            rawCopy = droppedRaw
        } else {
            rawCopy = Array(Self.rawKeys(for: shortened, inputMethod: inputMethod))
        }
        setRawChars(rawCopy)
        keystrokeBuffer.reset()
        for c in rawCopy { keystrokeBuffer.append(c) }
        setRenderedOutput(shortened)
        supersededModifiers.removeAll(keepingCapacity: true)
        let reopenedEscape = Self.hasConfirmedEscapeInState(rawChars: rawCopy, renderedOutput: shortened, inputMethod: inputMethod)
        lastToneSemanticEvent = nil
        hasConfirmedSemanticEscapeInComposition = reopenedEscape
        lastAttemptedKey = rawChars.last
        compositionHistory = [
            CompositionSnapshot(
                rawChars: rawCopy,
                renderedOutput: shortened,
                isLiteralOrCancellationStep: false,
                hasConfirmedSemanticEscape: reopenedEscape
            )
        ]
        if isEditingCommittedWord && !committedHistory.isEmpty {
            committedHistory[committedHistory.count - 1] = (raw: rawCopy, rendered: shortened)
        }
        return calculateDiff(oldStr: previousOutput, newStr: shortened, appendedChar: nil)
    }

    /// Applies deterministic keystroke-aware semantic Backspace to a composed Vietnamese string:
    /// 1. Strip tone mark if present (`đúng -> đung`, `được -> đươc`, `trường -> trương`).
    /// 2. Else strip vowel shape modifier if present (`đươc -> đuoc`, `trương -> truong`, `đôi -> đoi`).
    /// 3. Else if length > 1, delete last character (`đung -> đun`, `đuoc -> đuo -> đu -> đ`).
    /// 4. Else if single `đ`/`Đ`, strip stroke modifier (`đ -> d`, `Đ -> D`).
    /// 5. Else delete last character to empty.
    private static func applySemanticBackspace(to text: String) -> String {
        guard !text.isEmpty else { return "" }

        if VietnameseSyllableDictionary.hasToneMark(text) {
            return String(text.map { addToneToVowel($0, tone: .none) })
        }

        // If `text` has literal overflow characters appended after a modified vowel (e.g. `hôngfaa -> hôngfa -> hôngf -> hông`),
        // delete the trailing literal character first before stripping the vowel shape modifier.
        if text.count > 1 &&
           !VietnameseSyllableDictionary.shared.isValidUntonedSyllable(text) &&
           !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(text) {
            return String(text.dropLast())
        }

        let shapeResetMap: [Character: Character] = [
            "ă": "a", "Ă": "A",
            "â": "a", "Â": "A",
            "ê": "e", "Ê": "E",
            "ô": "o", "Ô": "O",
            "ơ": "o", "Ơ": "O",
            "ư": "u", "Ư": "U"
        ]
        if text.contains(where: { shapeResetMap[$0] != nil }) {
            return String(text.map { shapeResetMap[$0] ?? $0 })
        }

        if text.count > 1 {
            return String(text.dropLast())
        }

        if text == "đ" {
            return "d"
        }
        if text == "Đ" {
            return "D"
        }

        return ""
    }

    /// Commits active composition into word history.
    internal func commit() -> (backspaces: Int, suffix: String)? {
        guard isComposing else { return nil }
        let output = renderedOutput
        let canonicalRaw = canonicalizeCommittedRaw(rawChars: rawChars, rendered: output)
        lastCommittedIsDirectToken = false
        if isEditingCommittedWord && !committedHistory.isEmpty {
            committedHistory[committedHistory.count - 1] = (raw: canonicalRaw, rendered: output)
        } else {
            committedHistory.append((raw: canonicalRaw, rendered: output))
            if committedHistory.count > Self.maxHistoryCount {
                committedHistory.removeFirst()
            }
        }
        reset()
        return (0, "")
    }

    /// Commits a specific word pair into word history (used by InputSessionManager/Controller).
    #if VIELOTUS_OPEN_CORE_MACOS
    internal func commitWord(raw: String, rendered: String) {
        let canonicalRaw = canonicalizeCommittedRaw(rawChars: Array(raw), rendered: rendered)
        lastCommittedIsDirectToken = false
        if isEditingCommittedWord && !committedHistory.isEmpty {
            committedHistory[committedHistory.count - 1] = (raw: canonicalRaw, rendered: rendered)
        } else {
            committedHistory.append((raw: canonicalRaw, rendered: rendered))
            if committedHistory.count > Self.maxHistoryCount {
                committedHistory.removeFirst()
            }
        }
        reset()
    }
    #else
    internal func commitWord(raw: String, rendered: String, isOfficialSuggestion: Bool = false) {
        let canonicalRaw = (isOfficialSuggestion && rendered.allSatisfy(\.isASCII))
            ? Array(rendered)
            : canonicalizeCommittedRaw(rawChars: Array(raw), rendered: rendered)
        lastCommittedIsDirectToken = isOfficialSuggestion
        if isEditingCommittedWord && !committedHistory.isEmpty {
            committedHistory[committedHistory.count - 1] = (raw: canonicalRaw, rendered: rendered)
        } else {
            committedHistory.append((raw: canonicalRaw, rendered: rendered))
            if committedHistory.count > Self.maxHistoryCount {
                committedHistory.removeFirst()
            }
        }
        reset()
    }
    #endif

    private func canonicalizeCommittedRaw(rawChars: [Character], rendered: String) -> [Character] {
        guard !rendered.isEmpty,
              rendered.lowercased() != String(rawChars).lowercased() else {
            return rawChars
        }
        if inputMethod == .vni {
            if !rendered.allSatisfy(\.isASCII),
               (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(rendered) ||
                VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(rendered, relaxedCoda: relaxedCoda, genZMode: genZMode)) {
                return Array(Self.rawKeys(for: rendered, inputMethod: .vni))
            }
            if let last = rendered.last, last.isNumber {
                var idx = rendered.endIndex
                while idx > rendered.startIndex && rendered[rendered.index(before: idx)].isNumber {
                    idx = rendered.index(before: idx)
                }
                let stem = String(rendered[..<idx])
                let digitSuffix = Array(rendered[idx...])
                if !stem.isEmpty {
                    return Array(Self.rawKeys(for: stem, inputMethod: .vni)) + digitSuffix
                }
            }
            return rawChars
        }
        guard inputMethod == .telex else {
            return rawChars
        }
        if !rendered.allSatisfy(\.isASCII),
           VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(rendered) {
            return Array(Self.rawKeys(for: rendered, inputMethod: inputMethod))
        }
        guard Self.hasPreVowelModifierTrigger(rawChars) else {
            return rawChars
        }
        if !rendered.allSatisfy(\.isASCII) {
            return Array(Self.rawKeys(for: rendered, inputMethod: inputMethod))
        }
        if let last = rawChars.last,
           ["s", "f", "r", "x", "j", "w"].contains(Character(last.lowercased())),
           rendered.lowercased().hasSuffix(String(last).lowercased()),
           rendered.count + 1 == rawChars.count {
            return Array(rendered) + [last]
        }
        return Array(rendered)
    }

    /// Clears committed word history when cursor context is invalidated.
    internal func clearHistory() {
        committedHistory.removeAll(keepingCapacity: true)
        lastCommittedIsDirectToken = false
        lastPostCommitEditTransaction = nil
    }

    /// Post-commit editing (LabanKey-style / Apple-style word resurrection).
    /// Caret back index into the committed text (0 = end of newest word).
    internal func editAt(caretBack: Int, char: Character) -> (backspaces: Int, suffix: String)? {
        lastPostCommitEditTransaction = nil
        guard caretBack == 0 else { return nil }
        guard let lastEntry = committedHistory.last else { return nil }
        let lastWord = lastEntry.rendered
        if lastCommittedIsDirectToken && lastWord.allSatisfy(\.isASCII) {
            return nil
        }
        if inputMethod == .vni && !char.isNumber {
            return nil
        }
        let baseCanonicalRaw: [Character]
        if inputMethod == .vni && !lastWord.allSatisfy(\.isASCII) &&
           (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(lastWord) ||
            VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(lastWord, relaxedCoda: relaxedCoda, genZMode: genZMode)) {
            baseCanonicalRaw = Array(Self.rawKeys(for: lastWord, inputMethod: .vni))
        } else {
            baseCanonicalRaw = lastEntry.raw
        }
        var rawCopy = baseCanonicalRaw
        guard !rawCopy.isEmpty else { return nil }

        if inputMethod == .telex && char.lowercased() == "d" {
            let isTripleD = rawCopy.count >= 3 &&
                rawCopy[0].lowercased() == "d" &&
                rawCopy[1].lowercased() == "d" &&
                rawCopy[2].lowercased() == "d"
            if !isTripleD && rawCopy.count >= 2 &&
               rawCopy[0].lowercased() == "d" &&
               rawCopy[1].lowercased() == "d" {
                rawCopy.removeFirst()
            } else if rawCopy[0].lowercased() == "d" {
                rawCopy.insert(rawCopy[0], at: 0)
            } else {
                rawCopy.append(char)
            }
        } else if inputMethod == .telex && (char.lowercased() == "a" || char.lowercased() == "e" || char.lowercased() == "o") && VietnameseSyllableDictionary.hasToneMark(lastWord) {
            let lowerChar = char.lowercased()
            let toneKeys: Set<String> = ["s", "f", "r", "x", "j"]
            var toneStart = rawCopy.count
            while toneStart > 0 && toneKeys.contains(rawCopy[toneStart - 1].lowercased()) {
                toneStart -= 1
            }
            if toneStart < rawCopy.count && toneStart > 0 && rawCopy[toneStart - 1].lowercased() == lowerChar {
                rawCopy.insert(char, at: toneStart)
            } else {
                rawCopy.append(char)
            }
        } else {
            // Append new raw character to raw chars
            rawCopy.append(char)
        }

        let newWord = transform(rawCopy)
        guard newWord != lastWord else { return nil }
        let lowerChar = char.lowercased()
        let isToneOrDKey = (inputMethod == .telex && ["s", "f", "r", "x", "j", "z", "d"].contains(lowerChar)) ||
            (inputMethod == .vni && ["0", "1", "2", "3", "4", "5", "9"].contains(lowerChar))
        let isVNICancellationAndLiteralEmit = inputMethod == .vni &&
            char.isNumber &&
            newWord.last == char &&
            newWord.lowercased() != (lastWord + String(char)).lowercased()
        let isExplicitVowelEscape = (inputMethod == .telex && ["a", "e", "o", "w"].contains(lowerChar) &&
            (SmartBilingualDetector.isExplicitTelexEscape(raw: String(rawCopy), rendered: newWord) ||
             SyllableCandidateResolver.isPostCodaModifierUndoOrExtension(lowerRaw: String(rawCopy).lowercased(), rendered: newWord))) ||
            isVNICancellationAndLiteralEmit
        let merelyAppended = newWord.lowercased() == (lastWord + String(char)).lowercased()
        let revertedToUnescapedRaw = newWord.lowercased() == String(rawCopy).lowercased() &&
            !SyllableCandidateResolver.isEnglishCollision(newWord.lowercased()) &&
            !isVNICancellationAndLiteralEmit
        let isPlausibleModifiedContinuation = !merelyAppended &&
            VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(newWord, relaxedCoda: relaxedCoda, genZMode: genZMode)
        if !lastWord.allSatisfy(\.isASCII) &&
           !VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newWord) &&
           !isPlausibleModifiedContinuation {
            let isClearKey = (inputMethod == .telex && lowerChar == "z") || (inputMethod == .vni && lowerChar == "0")
            if (!isToneOrDKey && !isExplicitVowelEscape) || (merelyAppended && !isExplicitVowelEscape && !isClearKey) || revertedToUnescapedRaw {
                return nil
            }
        } else if inputMethod == .vni && lastWord.allSatisfy(\.isASCII) && merelyAppended && !isExplicitVowelEscape {
            return nil
        }

        let lowerPrevUntoned = VietnameseSyllableDictionary.stripToneMarks(lastWord.lowercased())
        let lowerNewUntoned = VietnameseSyllableDictionary.stripToneMarks(newWord.lowercased())
        let prevToneMod = Self.extractActiveToneModifier(from: lastWord, inputMethod: inputMethod)
        let newToneMod = Self.extractActiveToneModifier(from: newWord, inputMethod: inputMethod)
        let isToneClearZ =
            ((inputMethod == .telex && lowerChar == "z" && !newWord.lowercased().hasSuffix("z")) ||
             (inputMethod == .vni && lowerChar == "0" && !newWord.lowercased().hasSuffix("0"))) &&
            VietnameseSyllableDictionary.hasToneMark(lastWord) &&
            !VietnameseSyllableDictionary.hasToneMark(newWord) &&
            newWord.lowercased() == lowerPrevUntoned &&
            VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(lastWord)
        let isMutualExclusionVowelReshape =
            ((inputMethod == .telex && ((lowerChar == "o" && lowerPrevUntoned.contains("ơ")) ||
                                        (lowerChar == "w" && (lowerPrevUntoned.contains("ô") || lowerPrevUntoned.contains("â"))))) ||
             (inputMethod == .vni && ((lowerChar == "6" && (lowerPrevUntoned.contains("ơ") || lowerPrevUntoned.contains("ă"))) ||
                                      (lowerChar == "7" && lowerPrevUntoned.contains("ô")) ||
                                      (lowerChar == "8" && lowerPrevUntoned.contains("â"))))) &&
            lastWord.count == newWord.count &&
            !newWord.lowercased().hasSuffix(lowerChar) &&
            !newWord.unicodeScalars.allSatisfy({ $0.isASCII }) &&
            VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newWord)
        let isLateVowelModification =
            ((inputMethod == .telex && (lowerChar == "a" || lowerChar == "e" || lowerChar == "o" || lowerChar == "w")) ||
             (inputMethod == .vni && (lowerChar == "6" || lowerChar == "7" || lowerChar == "8"))) &&
            lastWord != newWord &&
            lastWord.count == newWord.count &&
            !newWord.lowercased().hasSuffix(lowerChar) &&
            !lowerPrevUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            lowerNewUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            VietnameseSyllableDictionary.hasToneMark(lastWord) &&
            VietnameseSyllableDictionary.hasToneMark(newWord) &&
            (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newWord) ||
             VietnameseSyllableDictionary.shared.isValidOpenBrevePrefix(lowerNewUntoned, genZMode: genZMode))
        let isVowelShapeCancellation =
            ((inputMethod == .telex && (lowerChar == "a" || lowerChar == "e" || lowerChar == "o" || lowerChar == "w")) ||
             (inputMethod == .vni && (lowerChar == "6" || lowerChar == "7" || lowerChar == "8"))) &&
            lastWord != newWord &&
            lastWord.count == newWord.count &&
            !newWord.lowercased().hasSuffix(lowerChar) &&
            lowerPrevUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            !lowerNewUntoned.contains(where: { "ăâêôơư".contains($0) }) &&
            (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(lastWord) ||
             (!VietnameseSyllableDictionary.hasToneMark(lastWord) &&
              VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(lastWord)))
        let isToneReplacement =
            ((inputMethod == .telex && (lowerChar == "s" || lowerChar == "f" || lowerChar == "r" || lowerChar == "x" || lowerChar == "j")) ||
             (inputMethod == .vni && (lowerChar == "1" || lowerChar == "2" || lowerChar == "3" || lowerChar == "4" || lowerChar == "5"))) &&
            lastWord != newWord &&
            prevToneMod != nil &&
            newToneMod != nil &&
            prevToneMod != newToneMod &&
            lowerPrevUntoned == lowerNewUntoned &&
            VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(newWord, relaxedCoda: relaxedCoda, genZMode: genZMode)

        supersededModifiers.removeAll(keepingCapacity: true)
        if isToneClearZ, let prevToneMod {
            supersededModifiers.append(prevToneMod)
            supersededModifiers.append(inputMethod == .vni ? "0" : "z")
        } else if isToneReplacement, let prevToneMod {
            supersededModifiers.append(prevToneMod)
        }

        let shouldCanonicalizeToneReplacement = isToneReplacement && (
            inputMethod == .vni ||
            !lowerPrevUntoned.unicodeScalars.allSatisfy({ $0.isASCII }) ||
            !Self.isPlausibleEnglishTwoToneCluster(rawChars: rawCopy, prevTone: prevToneMod!, newTone: Character(lowerChar))
        )

        if isVNICancellationAndLiteralEmit {
            let stemOutput = String(newWord.dropLast())
            rawCopy = Array(Self.rawKeys(for: stemOutput, inputMethod: .vni)) + [char]
        } else if (inputMethod == .telex || inputMethod == .vni) && (isToneClearZ || isMutualExclusionVowelReshape || isLateVowelModification || shouldCanonicalizeToneReplacement) {
            rawCopy = Array(Self.rawKeys(for: newWord, inputMethod: inputMethod))
        } else if inputMethod == .vni && VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(newWord) {
            rawCopy = Array(Self.rawKeys(for: newWord, inputMethod: .vni))
        }

        let decisionKind: PostCommitEditDecisionKind = {
            if isToneClearZ { return .toneCancellationClear }
            if isToneReplacement { return .toneReplacement }
            if isMutualExclusionVowelReshape { return .vowelShapeReshape }
            if isVowelShapeCancellation { return .vowelShapeCancellation }
            if isVNICancellationAndLiteralEmit {
                if ["1", "2", "3", "4", "5"].contains(lowerChar) {
                    return .toneCancellationEmitLiteral
                } else if lowerChar == "9" {
                    return .strokeCancellation
                } else {
                    return .vowelShapeCancellation
                }
            }
            if lowerChar == "d" || lowerChar == "9" {
                return lastWord.lowercased().hasPrefix("đ") ? .strokeCancellation : .strokeModification
            }
            if ["s", "f", "r", "x", "j", "1", "2", "3", "4", "5"].contains(lowerChar) {
                return newWord.lowercased().hasSuffix(lowerChar) ? .toneCancellationEmitLiteral : .toneModification
            }
            return .vowelShapeModification
        }()

        // Update history and re-arm composition session
        committedHistory.removeLast()
        committedHistory.append((raw: rawCopy, rendered: newWord))
        setRawChars(rawCopy)
        keystrokeBuffer.reset()
        for c in rawCopy { keystrokeBuffer.append(c) }
        setRenderedOutput(newWord)
        isEditingCommittedWord = true
        isCharacterDeletingCommittedWord = false
        let priorHasEscape = Self.hasConfirmedEscapeInState(rawChars: baseCanonicalRaw, renderedOutput: lastWord, inputMethod: inputMethod)
        let newHasEscape = decisionKind == .toneCancellationEmitLiteral ||
            isVNICancellationAndLiteralEmit ||
            Self.hasConfirmedEscapeInState(rawChars: rawCopy, renderedOutput: newWord, inputMethod: inputMethod)
        let editToneEvent: ToneModifierSemanticEvent? = {
            switch decisionKind {
            case .toneCancellationEmitLiteral: return .cancelToneAndEmitLiteral
            case .toneCancellationClear: return .clearToneZ
            case .toneReplacement: return .replaceTone
            case .toneModification: return !newHasEscape ? .applyTone : nil
            default: return nil
            }
        }()
        lastToneSemanticEvent = editToneEvent
        hasConfirmedSemanticEscapeInComposition = newHasEscape
        let isReversibleLateVowelStep = (isLateVowelModification && (lastWord.last.map({ Self.isVietnameseVowel($0) }) ?? false)) || isVowelShapeCancellation
        let isLiteralOrCancel = (!renderedOutputIsASCII &&
            !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(newWord, relaxedCoda: relaxedCoda, genZMode: genZMode)) ||
            isVNICancellationAndLiteralEmit
        compositionHistory = [
            CompositionSnapshot(
                rawChars: baseCanonicalRaw,
                renderedOutput: lastWord,
                isLiteralOrCancellationStep: false,
                supersededModifiers: [],
                hasConfirmedSemanticEscape: priorHasEscape
            ),
            CompositionSnapshot(
                rawChars: rawCopy,
                renderedOutput: newWord,
                isLiteralOrCancellationStep: isLiteralOrCancel || isToneClearZ || isReversibleLateVowelStep,
                isExplicitLiteralLock: isVNICancellationAndLiteralEmit,
                supersededModifiers: supersededModifiers,
                toneSemanticEvent: editToneEvent,
                hasConfirmedSemanticEscape: newHasEscape
            )
        ]

        let backspaces = lastWord.utf16.count
        lastPostCommitEditTransaction = PostCommitEditTransaction(
            inputMethod: inputMethod,
            triggerKey: char,
            priorRenderedWord: lastWord,
            priorCanonicalRaw: String(baseCanonicalRaw),
            resultingRenderedWord: newWord,
            resultingCanonicalRaw: String(rawCopy),
            decisionKind: decisionKind,
            utf16Backspaces: backspaces,
            replacementSuffix: newWord,
            isLiteralLockedAfterEdit: isVNICancellationAndLiteralEmit
        )
        return (backspaces, newWord)
    }

    /// Steps back one character into the committed word when user presses Backspace while armed
    internal func editBackspaceAt(caretBack: Int) -> (backspaces: Int, suffix: String)? {
        guard caretBack == 0 else { return nil }
        guard let lastEntry = committedHistory.last else { return nil }
        let lastWord = lastEntry.rendered
        guard !lastWord.isEmpty else { return nil }
        let wasOfficialSuggestion = lastCommittedIsDirectToken

        let shortenedWord = String(lastWord.dropLast())
        committedHistory.removeLast()

        if shortenedWord.isEmpty {
            lastCommittedIsDirectToken = false
            reset()
            return (lastWord.utf16.count, "")
        }

        let droppedRaw = Array(lastEntry.raw.dropLast())
        let rawCopy: [Character]
        if wasOfficialSuggestion {
            rawCopy = Array(shortenedWord)
        } else if !droppedRaw.isEmpty && transform(droppedRaw) == shortenedWord {
            rawCopy = droppedRaw
        } else {
            rawCopy = Array(VietnameseEngine.rawKeys(for: shortenedWord, inputMethod: inputMethod))
        }
        committedHistory.append((raw: rawCopy, rendered: shortenedWord))
        setRawChars(rawCopy)
        keystrokeBuffer.reset()
        for c in rawCopy { keystrokeBuffer.append(c) }
        setRenderedOutput(shortenedWord)
        supersededModifiers.removeAll(keepingCapacity: true)
        let reopenedEscape = Self.hasConfirmedEscapeInState(rawChars: rawCopy, renderedOutput: shortenedWord, inputMethod: inputMethod)
        lastToneSemanticEvent = nil
        hasConfirmedSemanticEscapeInComposition = reopenedEscape
        lastAttemptedKey = rawChars.last
        lastCommittedIsDirectToken = false
        isEditingCommittedWord = true
        isCharacterDeletingCommittedWord = true
        compositionHistory = [
            CompositionSnapshot(
                rawChars: rawCopy,
                renderedOutput: shortenedWord,
                isLiteralOrCancellationStep: false,
                isExplicitLiteralLock: false,
                hasConfirmedSemanticEscape: reopenedEscape
            )
        ]

        let backspaces = lastWord.utf16.count
        return (backspaces, shortenedWord)
    }

    // MARK: - Diff Calculation

    private func calculateDiff(oldStr: String, newStr: String, appendedChar: Character?) -> (backspaces: Int, suffix: String) {
        if oldStr.isEmpty {
            return (0, newStr)
        }
        if oldStr == newStr && oldStr.unicodeScalars.elementsEqual(newStr.unicodeScalars) {
            return (0, "")
        }

        // Zero-allocation common prefix search via String.Index, requiring scalar-exact
        // equivalence so NFD grapheme clusters on screen are never mistaken for NFC clusters
        // with a different UTF-16 code-unit length.
        var oldIdx = oldStr.startIndex
        var newIdx = newStr.startIndex
        while oldIdx < oldStr.endIndex && newIdx < newStr.endIndex &&
              oldStr[oldIdx] == newStr[newIdx] &&
              oldStr[oldIdx].unicodeScalars.elementsEqual(newStr[newIdx].unicodeScalars) {
            oldIdx = oldStr.index(after: oldIdx)
            newIdx = newStr.index(after: newIdx)
        }

        let deletedSlice = oldStr[oldIdx...]
        let backspacesUTF16 = deletedSlice.utf16.count
        let suffix = String(newStr[newIdx...])
        return (backspacesUTF16, suffix)
    }

    // MARK: - Vietnamese Phonetic Transformation (FSM)

    internal func transform(_ chars: [Character]) -> String {
        guard !chars.isEmpty else { return "" }

        let lowerRaw = String(chars).lowercased()

        // Non-Vietnamese initials: 'f', 'j', 'z' cannot start a Vietnamese syllable
        if let first = lowerRaw.first, (first == "f" || first == "j" || first == "z") && !genZMode {
            return String(chars)
        }

        if inputMethod == .vni {
            return transformVNI(chars)
        } else {
            // Simple Telex default: standalone 'w' or repeated 'w' ("w", "ww", "www", ...) remains literal 'w...' (not 'ư' or swallowed)
            if simpleTelex && chars.allSatisfy({ $0.lowercased() == "w" }) {
                return String(chars)
            }

            // Gen-Z 'w'-initial syllables where 'w' stands for 'qu' (e.g. was/wsa -> wá, war/wra -> wả, waf/wfa -> wà, waayj/wayaj -> wậy)
            if genZMode, let wResolved = Self.transformGenZInitialWIfApplicable(
                chars,
                profile: grammarProfile,
                modernOrthography: modernOrthography,
                relaxedCoda: relaxedCoda,
                simpleTelex: simpleTelex
            ) {
                return wResolved.rendered
            }

            // Phonotactically impossible Vietnamese 'w'-initial words in Telex (e.g. "we", "wi", "wh", "wo", "wy", "wri", "wat", "wan")
            // resolve immediately to raw ASCII on the 2nd/3rd keystroke while preserving "ww" -> "w", "wa" -> "ưa", "wu" -> "ưu", "ws"/"wr" -> "ứ"/"ử".
            if Self.isEnglishWInitial(chars) || SmartBilingualDetector.isPostCodaCircumflexEnglishWord(lowerRaw) {
                return String(chars)
            }

            let rendered: String
            if grammarProfile == .classic {
                rendered = transformTelex(chars)
            } else if grammarProfile == .senFlex {
                // Dual-Path Routing (SEN VIỆT Hybrid):
                // Fast Path: pure classic patterns run fast incremental FSM
                // Flex Path: pre-vowel, infix, or English collisions run Modifier Intent Solver
                if !Self.hasFlexPathTriggers(chars, genZMode: genZMode) {
                    rendered = transformTelex(chars)
                } else {
                    let parsed = InputGrammarParser.shared.parse(
                        chars,
                        profile: grammarProfile,
                        modernOrthography: modernOrthography,
                        relaxedCoda: relaxedCoda,
                        genZMode: genZMode,
                        simpleTelex: simpleTelex
                    )
                    rendered = parsed.rendered
                }
            } else {
                let parsed = InputGrammarParser.shared.parse(
                    chars,
                    profile: grammarProfile,
                    modernOrthography: modernOrthography,
                    relaxedCoda: relaxedCoda,
                    genZMode: genZMode,
                    simpleTelex: simpleTelex
                )
                rendered = parsed.rendered
            }

            if genZMode, let first = lowerRaw.first, (first == "f" || first == "j" || first == "z"),
               rendered.lowercased() != lowerRaw,
               !Self.isValidGenZInitialTransformation(rendered: rendered, raw: lowerRaw) {
                return String(chars)
            }
            return rendered
        }
    }

    /// Returns true when a `w`-initial keystroke sequence is phonotactically impossible
    /// as a Vietnamese `ư...` word and should immediately render as literal `w...` inline.
    internal static func isEnglishWInitial(_ chars: [Character]) -> Bool {
        guard chars.count >= 2 else { return false }
        guard Character(chars[0].lowercased()) == "w" else { return false }
        let c1 = Character(chars[1].lowercased())
        // "ww..." is handled by double/triple-w escape rules (ww -> w, www -> www)
        if c1 == "w" { return false }

        let toneKeys: Set<Character> = ["s", "f", "r", "x", "j", "z"]

        // 1. "w" + tone key(s) only (e.g. "ws" -> "ứ", "wr" -> "ử", "wsf" -> "ừ")
        //    If followed by any non-tone letter (e.g. "wri" in "write", "wro" in "wrong", "wra" in "wrap"), it is English.
        if toneKeys.contains(c1) {
            for idx in 2..<chars.count {
                let ch = Character(chars[idx].lowercased())
                if !toneKeys.contains(ch) {
                    return true
                }
            }
            return false
        }

        // 2. "wa" and "wu" (2-char) stay literal English "wa"/"wu" (type "uwa"/"uaw" for "ưa", "uwu"/"uuw" for "ưu").
        //    3+ char "was", "wars", "wus" have optional tone keys only; any non-tone letter at index >= 2
        //    (e.g. "wat", "wan", "wal", "way", "wai", "warm", "ward") is English.
        if c1 == "a" || c1 == "u" {
            if chars.count == 2 {
                return true
            }
            for idx in 2..<chars.count {
                let ch = Character(chars[idx].lowercased())
                if !toneKeys.contains(ch) {
                    return true
                }
            }
            return false
        }

        // 3. Any other 2nd character after "w" (e.g. "we", "wi", "wh", "wo", "wy", "wc", "wt", "wn", ...)
        //    cannot form a valid zero-onset Vietnamese "ư..." word.
        return true
    }

    /// Validates whether a transformed word starting with 'f', 'j', 'z', or 'w' in Gen-Z mode
    /// corresponds to a genuine Vietnamese teen-code syllable (where f -> ph, z -> d/v/gi/tr/r, j -> d/gi/v/tr/r, w -> qu)
    /// rather than an English word like "zebra", "folder", "format", "water", "fee", "fees", "free".
    internal static func isValidGenZInitialTransformation(rendered: String, raw: String = "") -> Bool {
        let lower = rendered.lowercased()
        guard let first = lower.first else { return false }
        let isDzOnset = lower.hasPrefix("dz")
        let remainder = isDzOnset ? String(lower.dropFirst(2)) : String(lower.dropFirst())
        guard !remainder.isEmpty else { return false }
        let untonedRemainder = VietnameseSyllableDictionary.stripToneMarks(remainder)
        // `fr-` is an English consonant cluster (`free -> frê`), never a valid Vietnamese or Gen-Z `ph-` onset.
        if first == "f" && untonedRemainder.hasPrefix("r") {
            return false
        }
        // P0.4.1 Section 2 (Grammar-aware phonotactics):
        // Do NOT treat `fê` as an absolute phonotactic impossibility when Gen-Z Mode allows `f -> ph` (`fê <-> phê`).
        // Instead, do NOT expand Gen-Z into known English words (`fee`, `fees`, `feel`, `feed`, `feet`, `zero`, `zoom`) merely because
        // a Vietnamese Gen-Z candidate could be formed.
        let effectiveRaw = raw.isEmpty ? Self.rawKeys(for: lower, inputMethod: .telex) : raw.lowercased()
        if first == "f" && untonedRemainder == "ê" {
            let isTonedNonAcute = lower == "fề" || lower == "fể" || lower == "fễ" || lower == "fệ"
            if !isTonedNonAcute && (effectiveRaw == "fee" || effectiveRaw == "fees" || SmartBilingualDetector.isKnownEnglishWord(effectiveRaw)) {
                return false
            }
        }
        if first == "z" && !isDzOnset &&
           (effectiveRaw == "zero" || effectiveRaw == "zeros" ||
            (!VietnameseSyllableDictionary.hasToneMark(lower) && SmartBilingualDetector.isKnownEnglishWord(effectiveRaw))) {
            return false
        }
        // P0.4.1 Section 2 (j-initial guard):
        // `j` as a genZ onset maps to d/gi/v/tr/r. However, j-initial English words
        // (e.g. "just"→"jút", "jerk"→"jéc") are NOT valid genZ Vietnamese expressions —
        // the rendered form starts with 'j' which is phonotactically impossible in
        // standard Vietnamese display. If the raw is a known English word, treat it as
        // English (parity with Windows kUnconditionalEnglishWords which explicitly lists
        // "just"). Gen-Z Vietnamese j-initial words like "jups"→"júp", "jowf"→"jờ" are
        // not in isKnownEnglishWord, so they are unaffected.
        if first == "j" && !isDzOnset && SmartBilingualDetector.isKnownEnglishWord(effectiveRaw) {
            return false
        }

        let candidatePrefixes: [String]
        if isDzOnset {
            candidatePrefixes = ["d", "v", "gi"]
        } else {
            switch first {
            case "f": candidatePrefixes = ["ph"]
            case "z": candidatePrefixes = ["d", "v", "gi", "tr", "r"]
            case "j": candidatePrefixes = ["d", "gi", "v", "tr", "r"]
            case "w": candidatePrefixes = ["qu"]
            default: return false
            }
        }

        let inProgressNuclei: Set<String> = [
            "ă", "ắ", "ằ", "ẳ", "ẵ", "ặ",
            "â", "ấ", "ầ", "ẩ", "ẫ", "ậ",
            "ơ", "ớ", "ờ", "ở", "ỡ", "ợ",
            "ư", "ứ", "ừ", "ử", "ữ", "ự",
            "ươ", "ướ", "ườ", "ưở", "ưỡ", "ượ", "ưo",
            "uô", "uố", "uồ", "uổ", "uỗ", "uộ",
            "iê", "iế", "iề", "iể", "iễ", "iệ",
            "yê", "yế", "yề", "yể", "yễ", "yệ"
        ]

        for prefix in candidatePrefixes {
            let candidate = prefix + remainder
            if VietnameseSyllableDictionary.shared.isValidSyllable(candidate) ||
               VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(candidate) ||
               candidate == "quã" {
                return true
            }
            if inProgressNuclei.contains(remainder) &&
               VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(candidate) {
                return true
            }
            if first != "w" {
                // Also allow teen-code coda shortcuts (-g for -ng, -k for -c, -h for -nh)
                if candidate.hasSuffix("g") && VietnameseSyllableDictionary.shared.isValidSyllable(String(candidate.dropLast()) + "ng") {
                    return true
                }
                if candidate.hasSuffix("k") && VietnameseSyllableDictionary.shared.isValidSyllable(String(candidate.dropLast()) + "c") {
                    return true
                }
                if candidate.hasSuffix("h") && VietnameseSyllableDictionary.shared.isValidSyllable(String(candidate.dropLast()) + "nh") {
                    return true
                }
            }
        }
        return false
    }

    private static let genZProbeLock = NSLock()
    private static let genZProbeEngine = VietnameseEngine()

    /// Transforms `w`-initial Gen-Z words where `w` represents `qu` (e.g. `was`/`wsa` -> `wá`,
    /// `war`/`wra` -> `wả`, `waf`/`wfa` -> `wà`, `waj`/`wja` -> `wạ`, `waayj`/`wayaj` -> `wậy`,
    /// `wans` -> `wán`, `wais` -> `wái`, `wees` -> `wế`, `wys` -> `wý`).
    /// Preserves `wa` -> `ưa`, `wu`/`wus` -> `ưu`/`ứu`, `ws`/`wr` -> `ứ`/`ử`, and English `w`-words.
    internal static func transformGenZInitialWIfApplicable(
        _ chars: [Character],
        profile: GrammarProfile,
        modernOrthography: Bool,
        relaxedCoda: Bool,
        simpleTelex: Bool
    ) -> (intent: SyllableIntent, rendered: String)? {
        guard chars.count >= 3 else { return nil }
        guard Character(chars[0].lowercased()) == "w" else { return nil }

        let effectiveChars: [Character]
        if chars.count >= 4 && Character(chars[1].lowercased()) == "w" && Character(chars[2].lowercased()) != "w" {
            effectiveChars = [chars[0]] + Array(chars.dropFirst(2))
        } else if Character(chars[1].lowercased()) != "w" {
            effectiveChars = chars
        } else {
            return nil
        }

        let lowerEffective = String(effectiveChars).lowercased()
        let c1 = Character(effectiveChars[1].lowercased())
        let toneKeys: Set<Character> = ["s", "f", "r", "x", "j", "z"]

        // Preserve 'wu' -> 'ưu'/'ứu', pure tone keys on 'ư' ('wsf' -> 'ừ'), and English 'wi-'/'wo-'/'wh-'/'wee'
        if c1 == "u" || c1 == "i" || c1 == "o" || c1 == "h" || lowerEffective == "wee" {
            return nil
        }
        guard c1 == "a" || c1 == "e" || c1 == "y" || toneKeys.contains(c1) else {
            return nil
        }
        if effectiveChars.dropFirst().allSatisfy({ toneKeys.contains(Character($0.lowercased())) }) {
            return nil
        }
        if profile == .preVowel && !toneKeys.contains(c1) && !lowerEffective.hasPrefix("waa") && !lowerEffective.hasPrefix("wee") {
            return nil
        }

        var zChars = effectiveChars
        zChars[0] = effectiveChars[0].isUppercase ? "Z" : "z"

        let zRendered: String
        var intent = SyllableIntent(rawChars: chars)
        if profile == .classic || (profile == .senFlex && !Self.hasFlexPathTriggers(zChars, genZMode: true)) {
            Self.genZProbeLock.lock()
            Self.genZProbeEngine.grammarProfile = profile
            Self.genZProbeEngine.modernOrthography = modernOrthography
            Self.genZProbeEngine.relaxedCoda = relaxedCoda
            Self.genZProbeEngine.genZMode = true
            Self.genZProbeEngine.simpleTelex = simpleTelex
            zRendered = Self.genZProbeEngine.transformTelex(zChars)
            Self.genZProbeLock.unlock()
        } else {
            let parsed = InputGrammarParser.shared.parsePreVowelOrHybrid(
                zChars,
                profile: profile,
                modernOrthography: modernOrthography,
                relaxedCoda: relaxedCoda,
                genZMode: true,
                simpleTelex: simpleTelex
            )
            zRendered = parsed.rendered
            intent = parsed.intent
        }

        guard !zRendered.isEmpty else { return nil }
        var candidateChars = Array(zRendered)
        candidateChars[0] = effectiveChars[0]
        let candidateRendered = String(candidateChars)

        guard candidateRendered.lowercased() != lowerEffective,
              !candidateRendered.unicodeScalars.allSatisfy({ $0.isASCII }),
              Self.isValidGenZInitialTransformation(rendered: candidateRendered) else {
            return nil
        }

        intent.rawChars = chars
        intent.onset = String(effectiveChars[0]).lowercased()
        intent.isValidVietnamese = true
        return (intent, candidateRendered)
    }

    /// Determines whether the keystroke stream contains pre-vowel, infix, or flexible modifier patterns
    /// requiring the FlexPath Intent Solver.
    internal static func hasFlexPathTriggers(_ chars: [Character], genZMode: Bool = false) -> Bool {
        guard chars.count >= 2 else { return false }
        let lower = String(chars).lowercased()

        // 0. English collisions in SenFlex: must run through Arbiter
        // Note: "pass" and "boss" use Fast Path so double-s Telex cancellation ("pas", "bos") works identically to Classic.
        if lower != "pass" && lower != "boss" && SyllableCandidateResolver.isEnglishCollision(lower) {
            return true
        }
        if genZMode && lower.hasPrefix("dz") {
            return true
        }

        // 1. Trailing 'w' after 'uong' or 'ong' (e.g. nsuongw, guongw)
        if lower.hasSuffix("ngw") || lower.hasSuffix("ongw") {
            return true
        }

        // 2. Infix tone in diphthong/triphthong (e.g. truowfng, truwfowng, buwsowm, muwfowi, nguwfowi, teest)
        var hasU = false
        var hasW = false
        var hasAdjacentEE = false
        var prevByte: UInt8 = 0
        for b in lower.utf8 {
            if b == 117 { hasU = true }
            else if b == 119 { hasW = true }
            else if b == 101 && prevByte == 101 { hasAdjacentEE = true }
            prevByte = b
        }
        if hasU && hasW {
            let uwPatterns = [
                "uowf", "uows", "uowr", "uowx", "uowj",
                "uwfo", "uwso", "uwro", "uwxo", "uwjo",
                "uwfa", "uwsa", "uwra", "uwxa", "uwja"
            ]
            for pattern in uwPatterns {
                if lower.contains(pattern) { return true }
            }
        }
        if hasAdjacentEE {
            let eePatterns = ["eest", "ees", "eef", "eer", "eex", "eej"]
            for pattern in eePatterns {
                if lower.contains(pattern) { return true }
            }
        }

        // 3. Pre-vowel modifier patterns ('q' + tone + 'u', "cra"/"cras", or global onset + pre-vowel modifier)
        if Self.hasPreVowelModifierTrigger(chars, genZMode: genZMode) {
            return true
        }

        return false
    }

    /// Returns true if `chars` starts with a Vietnamese pre-vowel tone or horn modifier pattern
    /// (e.g. `gxo`, `cfung`, `ssinh`, `rrinh`, `xxinh`, `ddson`, `qfua`, `gwo`, `gwuong`, `trwfuong`).
    internal static func hasPreVowelModifierTrigger(_ chars: [Character], genZMode: Bool = false) -> Bool {
        guard chars.count >= 3 else { return false }
        let lower = String(chars).lowercased()
        let lowerChars = Array(lower)
        let n = lowerChars.count

        // 1. 'q' + tone key + 'u' (e.g. qfua, qsueet, qrua)
        if lowerChars[0] == "q" && (lowerChars[1] == "s" || lowerChars[1] == "f" || lowerChars[1] == "r" || lowerChars[1] == "x" || lowerChars[1] == "j") && lowerChars[2] == "u" {
            return true
        }

        // 2. Specific "cra" / "cras" pre-vowel hook/acute forms (avoiding English cr- clusters like crops, craps, crafts)
        if lower == "cra" || lower == "cras" {
            return true
        }

        // 3. Global Vietnamese onset + pre-vowel tone/horn modifiers before a vowel or 'w'
        return Self.hasGlobalPreVowelOnsetTrigger(lower: lower, lowerChars: lowerChars, n: n, genZMode: genZMode)
    }

    /// Detects whether `lowerChars` starts with any valid Vietnamese onset followed immediately
    /// by a pre-vowel tone key (`s, f, r, x, j`) or horn modifier (`w`) before a vowel,
    /// while excluding English initial consonant clusters (`br-, cr-, dr-, gr-, kr-, pr-, chr-, phr-, thr-, ps-`).
    private static func hasGlobalPreVowelOnsetTrigger(lower: String, lowerChars: [Character], n: Int, genZMode: Bool = false) -> Bool {
        guard n >= 3 else { return false }
        // Triple-d escape ("ddd") is not a pre-vowel trigger
        if lower.hasPrefix("ddd") { return false }
        // Protect standard tech acronyms/loanwords where onset + tone matches ASCII identifier
        if lower == "rsa" || lower.hasPrefix("rsync") || lower.hasPrefix("href") || lower.hasPrefix("tsun") || lower.hasPrefix("djang") {
            return false
        }

        let onsets3 = ["ngh"]
        let onsets2 = ["ch", "dd", "gh", "gi", "kh", "ng", "nh", "ph", "qu", "th", "tr"]
        var onsets1: Set<Character> = ["b", "c", "d", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "x"]
        if genZMode {
            onsets1.formUnion(["f", "j", "z", "w"])
        }

        var onset = ""
        if n >= 4 && onsets3.contains(String(lowerChars[0..<3])) {
            onset = String(lowerChars[0..<3])
        } else if n >= 3 && onsets2.contains(String(lowerChars[0..<2])) {
            let candidate = String(lowerChars[0..<2])
            if candidate == "gi" {
                let tailVowels = lowerChars[2...].filter { isVietnameseVowel($0) }
                if tailVowels.isEmpty || tailVowels.allSatisfy({ $0 == "i" }) {
                    onset = "g"
                } else {
                    onset = candidate
                }
            } else {
                onset = candidate
            }
        } else if onsets1.contains(lowerChars[0]) {
            onset = String(lowerChars[0])
        }

        let idx = onset.count
        guard !onset.isEmpty, idx + 1 < n else { return false }

        let mod1 = lowerChars[idx]
        let next = lowerChars[idx + 1]
        let isMod1Tone = (mod1 == "s" || mod1 == "f" || mod1 == "r" || mod1 == "x" || mod1 == "j")

        // Case A: <onset> + <toneKey> + <vowel or 'w'> (e.g. rrinh, ssinh, xxinh, cfung, ddson, thrwuong, sswuong, zfwoi)
        // Exclude <consonant != 's'> + 's' + 'w' so English/CLI words like 'cswap', 'bswap', 'tswap', 'vswap' never trigger pre-vowel tone+horn.
        let isEnglishSubwordSwapCluster = (next == "w" && mod1 == "s" && onset.count == 1 && onset != "s")
        if isMod1Tone && !isEnglishSubwordSwapCluster && (isVietnameseVowel(next) || next == "w") {
            // Exclude English <Consonant> + 'r' + <Vowel> clusters (bring, create, drive, great, krill, price, chrome, phrase, three, giraffe)
            if mod1 == "r" && next != "w" {
                let englishROnsets: Set<String> = ["b", "c", "d", "g", "k", "p", "ch", "ph", "th", "gi", "h"]
                if englishROnsets.contains(onset) {
                    return false
                }
                if onset == "f" && lower != "fra" && lower != "frai" {
                    return false
                }
            }
            // Exclude English 'ps-' + <Vowel> cluster (psychology, pseudo, psalm)
            if onset == "p" && mod1 == "s" {
                return false
            }
            return true
        }

        // Case B: <onset> + 'w' + <toneKey> + <vowel> (e.g. trwfuong, thwruong, nwsuong, cwruong, swsuong)
        if mod1 == "w" && idx + 2 < n {
            let mod2 = lowerChars[idx + 1]
            let afterMod2 = lowerChars[idx + 2]
            let isMod2Tone = (mod2 == "s" || mod2 == "f" || mod2 == "r" || mod2 == "x" || mod2 == "j")
            if isMod2Tone && isVietnameseVowel(afterMod2) {
                return true
            }
        }

        // Case C: <onset> + 'w' + <'u', 'o', or 'a'> for pre-vowel horn/breve when unambiguous
        // (e.g. gwuong, gwo, cwu, trwuongf, nwuongs, thwuongr, twuong, lwuong, cwam, gwapj, zwo, zwoif)
        if mod1 == "w" && (next == "u" || next == "o" || next == "a") {
            if (onset == "g" && (next == "u" || next == "o")) || (onset == "c" && next == "u") {
                return true
            }
            if genZMode && (onset == "z" || onset == "f" || onset == "j") {
                return true
            }
            // Require at least one following char (coda, diphthong, or tone modifier) for general onsets
            guard n > idx + 2 else { return false }
            return true
        }

        return false
    }

    /// Detects post-coda / post-tone escape for English double-vowel collision words
    /// (e.g. "seene" -> "seen", "teene" -> "teen", "keene" -> "keen", "queene" -> "queen",
    /// "beene" -> "been", "reefe" / "reeff" -> "reef", "roomo" -> "room", "moono" -> "moon").
    internal static func isPostCodaEnglishDoubleVowelEscape(_ chars: [Character]) -> Bool {
        guard chars.count >= 4 else { return false }
        let lastLower = Character(chars[chars.count - 1].lowercased())
        let prefixChars = Array(chars.dropLast())
        let lowerPrefix = String(prefixChars).lowercased()
        let lowerRaw = String(chars).lowercased()

        let isVowelUndoTail: Bool = {
            switch lastLower {
            case "e":
                return lowerPrefix.contains("ee") && !lowerPrefix.hasSuffix("e")
            case "o":
                return lowerPrefix.contains("oo") && !lowerPrefix.hasSuffix("o")
            case "a":
                return lowerPrefix.contains("aa") && !lowerPrefix.hasSuffix("a")
            default:
                return false
            }
        }()
        let isToneEscapeTail: Bool = {
            guard chars.count >= 5,
                  ["s", "f", "r", "x", "j"].contains(lastLower),
                  lowerPrefix.last == lastLower else {
                return false
            }
            return lowerPrefix.contains("ee") || lowerPrefix.contains("oo") || lowerPrefix.contains("aa")
        }()

        guard isVowelUndoTail || isToneEscapeTail else { return false }
        return (EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerPrefix) ||
                SmartBilingualDetector.isKnownEnglishWord(lowerPrefix)) &&
               !EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerRaw)
    }

    // MARK: - Telex Transformation

    private func transformTelex(_ chars: [Character]) -> String {
        if Self.isPostCodaEnglishDoubleVowelEscape(chars) {
            return String(chars.dropLast())
        }
        if SmartBilingualDetector.isPostCodaCircumflexEnglishWord(String(chars).lowercased()) {
            return String(chars)
        }

        // Support transposed initial d-V-d / d-V-V-d (e.g. dodongf -> đồng, dadauf -> đầu, dedens -> đến, dudowcj / duodcwj -> được)
        if chars.count >= 4,
           Character(chars[0].lowercased()) == "d",
           Self.isVietnameseVowel(Character(chars[1].lowercased())) {
            var foundInfixDIdx: Int? = nil
            for k in 2..<min(5, chars.count - 1) {
                let cLower = Character(chars[k].lowercased())
                if cLower == "d" {
                    if Character(chars[k + 1].lowercased()) != "d" {
                        foundInfixDIdx = k
                    }
                    break
                } else if !Self.isVietnameseVowel(cLower) && cLower != "w" {
                    break
                }
            }
            if let dIdx = foundInfixDIdx,
               !SmartBilingualDetector.isKnownEnglishWord(String(chars).lowercased()) {
                var reordered = chars
                let secondD = reordered.remove(at: dIdx)
                reordered.insert(secondD, at: 1)
                let candidate = transformTelex(reordered)
                if VietnameseSyllableDictionary.shared.isValidSyllable(candidate) ||
                   VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(candidate) ||
                   SyllableCandidateResolver.isPostCodaModifierUndoOrExtension(lowerRaw: String(reordered).lowercased(), rendered: candidate) {
                    return candidate
                }
            }
        }

        // State variables
        var result: [Character] = []
        var tone: VietnameseTone = .none
        var toneEscapeActive = false
        var toneEscapeLocked = false
        var cancelledToneKey: Character? = nil
        var hornCancelled = false
        var circumflexCancelled = false
        var circumflexCancelledKey: Character? = nil
        var strokeDCancelled = false
        var postStrokeTail: [Character] = []

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            let lower = Character(ch.lowercased())
            let isAdjacentDoubleVowelAfterToneEscape = toneEscapeActive &&
                (lower == "a" || lower == "e" || lower == "o") &&
                ((i + 1 < chars.count && Character(chars[i + 1].lowercased()) == lower) ||
                 (result.last.map({ Character($0.lowercased()) == lower }) == true))
            let hasValidVnCodaStemBeforeToneEscape: Bool = {
                guard toneEscapeActive, result.count >= 3 else { return false }
                let stemBeforeEscape = String(result.dropLast())
                guard let lastStemChar = stemBeforeEscape.last,
                      ["c", "m", "n", "p", "t", "g", "h"].contains(Character(lastStemChar.lowercased())) else {
                    return false
                }
                return VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stemBeforeEscape, genZMode: genZMode)
            }()
            if !lower.isLetter {
                toneEscapeActive = false
                toneEscapeLocked = false
                cancelledToneKey = nil
            } else if (toneEscapeActive || cancelledToneKey != nil) && Self.isVietnameseVowel(lower) && !toneEscapeLocked && !(result.contains(where: { "ăâđêôơư".contains($0.lowercased()) }) || hornCancelled || circumflexCancelled || circumflexCancelledKey != nil || strokeDCancelled || isAdjacentDoubleVowelAfterToneEscape || hasValidVnCodaStemBeforeToneEscape) {
                toneEscapeActive = false
                cancelledToneKey = nil
            }
            if circumflexCancelledKey != nil && lower != circumflexCancelledKey {
                circumflexCancelledKey = nil
            }

            // Check 'dd' / 'DD' -> 'đ' / 'Đ' (only before any vowel has been formed in result, e.g. onset 'dd' or consonant abbreviation 'sddt' -> 'sđt')
            if lower == "d" && !result.contains(where: { Self.isVietnameseVowel($0) }) {
                if i + 2 < chars.count && Character(chars[i + 1].lowercased()) == "d" && Character(chars[i + 2].lowercased()) == "d" {
                    result.append(ch)
                    result.append(chars[i + 1])
                    strokeDCancelled = true
                    toneEscapeActive = true
                    toneEscapeLocked = true
                    i += 3
                    continue
                }
                if i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "d" {
                    let isUpper = ch.isUppercase
                    result.append(isUpper ? "Đ" : "đ")
                    i += 2
                    continue
                }
            }

            // Check Quick Telex shortcuts
            if quickTelex {
                if lower == "c" && i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "c" {
                    result.append(contentsOf: ch.isUppercase ? "Ch" : "ch")
                    i += 2
                    continue
                }
                if lower == "g" && i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "g" {
                    result.append(contentsOf: ch.isUppercase ? "Gi" : "gi")
                    i += 2
                    continue
                }
                if lower == "q" && i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "q" {
                    result.append(contentsOf: ch.isUppercase ? "Qu" : "qu")
                    i += 2
                    continue
                }
            }

            // Check post-coda / non-adjacent circumflex modifier (e.g. nhana -> nhân, nhanas -> nhấn, nhansa -> nhấn, theme -> thêm, trongo -> trông)
            if (lower == "a" || lower == "e" || lower == "o") && !result.isEmpty {
                if circumflexCancelledKey == lower {
                    if let lockedStem = Self.shouldLockPostCodaOverflow(
                        stemChars: result,
                        tone: tone,
                        hasHorn: false,
                        hornCancelled: hornCancelled,
                        circumflexCancelled: circumflexCancelled,
                        circumflexCancelledKey: circumflexCancelledKey,
                        strokeDCancelled: strokeDCancelled,
                        nextChar: ch,
                        remainingChars: chars[i...],
                        fullRawChars: chars,
                        modernOrthography: modernOrthography
                    ) {
                        result = lockedStem
                        result.append(contentsOf: chars[i...])
                        tone = .none
                        hornCancelled = true
                        break
                    }
                    result.append(ch)
                    i += 1
                    continue
                }
                var cachedRemainingAllowCancel: Bool? = nil
                func getRemainingAllowCancel() -> Bool {
                    if let cached = cachedRemainingAllowCancel { return cached }
                    guard i + 1 < chars.count else {
                        cachedRemainingAllowCancel = true
                        return true
                    }
                    let hasAnyToneKeyInChars = chars.contains {
                        let c = $0.lowercased()
                        return c == "s" || c == "f" || c == "r" || c == "x" || c == "j"
                    }
                    let hasCircumflexInResult = result.contains {
                        let c = $0.lowercased()
                        return c == "â" || c == "ê" || c == "ô"
                    }
                    let hasStrokeDInResult = result.first.map { $0.lowercased() == "đ" } ?? false
                    var cachedOverflowAllow: Bool? = nil
                    for idx in (i + 1)..<chars.count {
                        let c = chars[idx].lowercased()
                        if c == String(lower) {
                            // A subsequent identical vowel modifier saturates and locks the stem into literal overflow
                            cachedRemainingAllowCancel = true
                            return true
                        }
                        if (lower == "o" && c == "w") || c == "s" || c == "f" || c == "r" || c == "x" || c == "j" || (c == "z" && (hasAnyToneKeyInChars || hasCircumflexInResult)) {
                            continue
                        }
                        if ["a", "e", "o", "w"].contains(c) && (hasAnyToneKeyInChars || hasStrokeDInResult || hasCircumflexInResult) {
                            let allow: Bool
                            if let cached = cachedOverflowAllow {
                                allow = cached
                            } else {
                                let computed = !SmartBilingualDetector.isKnownEnglishWord(String(chars).lowercased())
                                cachedOverflowAllow = computed
                                allow = computed
                            }
                            if allow { continue }
                        }
                        cachedRemainingAllowCancel = false
                        return false
                    }
                    cachedRemainingAllowCancel = true
                    return true
                }
                let circumflexLower: Character = (lower == "a") ? "â" : ((lower == "e") ? "ê" : "ô")
                var postCodaHandled = false
                if !toneEscapeActive && postStrokeTail.isEmpty && result.count >= 2,
                   let lastResChar = result.last,
                   ["c", "m", "n", "p", "t", "g", "h"].contains(Character(lastResChar.lowercased())) {
                    for vIdx in stride(from: result.count - 2, through: 0, by: -1) {
                        let vLower = Character(result[vIdx].lowercased())
                        let isVUpper = result[vIdx].isUppercase
                        if vLower == circumflexLower {
                            // Policy 3B+: Semantic Saturation — once the vowel already carries a circumflex
                            // before a coda, a duplicate modifier falls through as literal instead of stripping.
                            break
                        } else if lower == "o" && (vLower == "ơ" || vLower == "o") && vIdx >= 1 && Character(result[vIdx - 1].lowercased()) == "ư" {
                            // Mutual-exclusion vowel reshape: ươ + o -> uô (e.g. trường + o -> truồng, thưởng + o -> thuổng, nước + o -> nuốc)
                            let isPrevUpper = result[vIdx - 1].isUppercase
                            result[vIdx - 1] = isPrevUpper ? "U" : "u"
                            result[vIdx] = isVUpper ? "Ô" : "ô"
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            i += 1
                            postCodaHandled = true
                            break
                        } else if lower == "o" && vLower == "ơ" && getRemainingAllowCancel() {
                            var candidateResult = result
                            candidateResult[vIdx] = isVUpper ? "Ô" : "ô"
                            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(String(candidateResult), genZMode: genZMode) {
                                result[vIdx] = candidateResult[vIdx]
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                i += 1
                                postCodaHandled = true
                                break
                            }
                        } else if lower == "a" && vLower == "ă" && getRemainingAllowCancel() {
                            var candidateResult = result
                            candidateResult[vIdx] = isVUpper ? "Â" : "â"
                            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(String(candidateResult), genZMode: genZMode) {
                                result[vIdx] = candidateResult[vIdx]
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                i += 1
                                postCodaHandled = true
                                break
                            }
                        } else if vLower == lower {
                            let transformed: Character
                            switch lower {
                            case "a": transformed = isVUpper ? "Â" : "â"
                            case "e": transformed = isVUpper ? "Ê" : "ê"
                            default: transformed = isVUpper ? "Ô" : "ô"
                            }
                            var candidateResult = result
                            candidateResult[vIdx] = transformed
                            let candidateStr = String(candidateResult)
                            let lowerFullRaw = String(chars).lowercased()
                            if (VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateStr, genZMode: genZMode) ||
                                VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(candidateStr, raw: lowerFullRaw, genZMode: genZMode) ||
                                (!lowerFullRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(candidateStr))) {
                                let allowPostCodaEnglish = !SmartBilingualDetector.isPostCodaCircumflexEnglishWord(lowerFullRaw) &&
                                    (lowerFullRaw == "cana" || !SmartBilingualDetector.isKnownEnglishWord(lowerFullRaw))
                                if allowPostCodaEnglish && getRemainingAllowCancel() {
                                    result[vIdx] = transformed
                                    i += 1
                                    postCodaHandled = true
                                    break
                                }
                            }
                        }
                    }
                } else if !toneEscapeActive && postStrokeTail.isEmpty && result.count >= 1 {
                    let lastIdx = result.count - 1
                    let lastResLower = Character(result[lastIdx].lowercased())
                    let isLastUpper = result[lastIdx].isUppercase
                    let isCompoundUO = result.count >= 2 && Character(result[result.count - 2].lowercased()) == "ư"
                    if lastResLower == circumflexLower {
                        // Policy 3B+: Non-contiguous post-tone duplicate vowel on an open circumflex syllable
                        // is saturated (contiguous aaa/eee/ooo is handled by the triple-vowel block below).
                    } else if lower == "o" && lastResLower == "ơ" && !isCompoundUO && getRemainingAllowCancel() {
                        var candidateResult = result
                        candidateResult[lastIdx] = isLastUpper ? "Ô" : "ô"
                        if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(String(candidateResult), genZMode: genZMode) {
                            result[lastIdx] = candidateResult[lastIdx]
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            i += 1
                            postCodaHandled = true
                        }
                    } else if lower == "a" && lastResLower == "ă" && getRemainingAllowCancel() {
                        var candidateResult = result
                        candidateResult[lastIdx] = isLastUpper ? "Â" : "â"
                        let checkUntoned = String(candidateResult).lowercased()
                        if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(checkUntoned, genZMode: genZMode) ||
                           VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(checkUntoned, genZMode: genZMode) {
                            result[lastIdx] = candidateResult[lastIdx]
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            i += 1
                            postCodaHandled = true
                        }
                    } else if result.count >= 2 {
                        let midIdx = result.count - 2
                        let midResLower = Character(result[midIdx].lowercased())
                        let isMidUpper = result[midIdx].isUppercase
                        let isGenZInitial = genZMode && chars.first.map({ ["f", "j", "z", "w"].contains($0.lowercased()) }) == true
                        if midResLower == circumflexLower &&
                           ((lower == "a" && (lastResLower == "u" || lastResLower == "y")) ||
                            (lower == "e" && lastResLower == "u") ||
                            (lower == "o" && lastResLower == "i")) {
                            // Policy 3B+: Offglide-closed circumflex syllable (đầu, thấy, nếu, nhiều, tuổi, tối)
                            // is saturated; duplicate modifier falls through as literal.
                        } else if getRemainingAllowCancel() && midResLower == lower &&
                                  ((isGenZInitial &&
                                    ((lower == "a" && (lastResLower == "u" || lastResLower == "y")) ||
                                     (lower == "e" && lastResLower == "u") ||
                                     (lower == "o" && lastResLower == "i"))) ||
                                   (lower == "o" && lastResLower == "i" && midIdx >= 1 &&
                                    Character(result[midIdx - 1].lowercased()) == "u" &&
                                    !SmartBilingualDetector.isKnownEnglishWord(String(chars).lowercased()))) {
                            let transformed: Character
                            switch lower {
                            case "a": transformed = isMidUpper ? "Â" : "â"
                            case "e": transformed = isMidUpper ? "Ê" : "ê"
                            default: transformed = isMidUpper ? "Ô" : "ô"
                            }
                            var candidateResult = result
                            candidateResult[midIdx] = transformed
                            let candidateStr = String(candidateResult)
                            let lowerFullRaw = String(chars).lowercased()
                            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateStr, genZMode: genZMode || isGenZInitial) ||
                               (!lowerFullRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(candidateStr)) {
                                result[midIdx] = transformed
                                i += 1
                                postCodaHandled = true
                            }
                        } else if lower == "o" && getRemainingAllowCancel() && result.count >= 3 {
                            let prevResLower = Character(result[result.count - 3].lowercased())
                            if (lastResLower == "i" || lastResLower == "u") && (midResLower == "ơ" || midResLower == "o") && prevResLower == "ư" {
                                let isPrevUpper = result[result.count - 3].isUppercase
                                result[result.count - 3] = isPrevUpper ? "U" : "u"
                                result[midIdx] = isMidUpper ? "Ô" : "ô"
                                hornCancelled = false
                                circumflexCancelled = false
                                circumflexCancelledKey = nil
                                i += 1
                                postCodaHandled = true
                            }
                        } else if lower == "o" && getRemainingAllowCancel() && lastResLower == "ơ" && midResLower == "ư" {
                            // Open diphthong ươ + o -> uô (e.g. trươ + o -> truô)
                            result[midIdx] = isMidUpper ? "U" : "u"
                            result[lastIdx] = isLastUpper ? "Ô" : "ô"
                            hornCancelled = false
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            i += 1
                            postCodaHandled = true
                        }
                    }
                }
                if !postCodaHandled && tone != .none && !toneEscapeActive &&
                   Character(result.last!.lowercased()) == lower {
                    let lowerWord = String(chars).lowercased()
                    let isCasedEnglishECollision = chars.contains(where: { $0.isUppercase }) &&
                        ["here", "there", "these", "refer", "refers", "reset", "mere", "verse"].contains(lowerWord)
                    if !isCasedEnglishECollision && lowerWord != "there" {
                        let remSlice = chars[(i + 1)...].map { $0.lowercased() }
                        let isGenZInitial = genZMode && chars.first.map({ ["f", "j", "z", "w"].contains($0.lowercased()) }) == true
                        let toneKeyStrings: Set<String> = ["s", "f", "r", "x", "j", "z"]
                        let modifierKeyStrings: Set<String> = ["a", "e", "o", "w"]
                        let stopKeyStrings = toneKeyStrings.union(modifierKeyStrings)
                        let codaSlice = remSlice.prefix(while: { !stopKeyStrings.contains($0) })
                        let afterCodaSlice = remSlice.dropFirst(codaSlice.count)
                        let coda = codaSlice.joined()
                        let afterCodaAllToneKeys: Bool = {
                            guard !afterCodaSlice.isEmpty else { return true }
                            var cachedCanOverflow: Bool? = nil
                            let allValid = afterCodaSlice.allSatisfy { tok in
                                if toneKeyStrings.contains(tok) || tok == String(lower) || tok == "w" {
                                    return true
                                }
                                if !coda.isEmpty && modifierKeyStrings.contains(tok) {
                                    if let cached = cachedCanOverflow { return cached }
                                    let computed = !SmartBilingualDetector.isKnownEnglishWord(lowerWord)
                                    cachedCanOverflow = computed
                                    return computed
                                }
                                return false
                            }
                            guard allValid else { return false }
                            return !(afterCodaSlice.first != String(lower) && afterCodaSlice.contains(String(lower)) && afterCodaSlice.contains(where: { toneKeyStrings.contains($0) }))
                        }()
                        let validLateCodas: Set<String> = (lower == "e")
                            ? ["", "c", "ch", "m", "n", "nh", "p", "t", "u"]
                            : ["", "c", "ch", "m", "n", "ng", "nh", "p", "t", "u", "y", "i", "o"]
                        let isStopCoda = ["c", "ch", "p", "t"].contains(coda)
                        let effectiveLastToneKey: String? = afterCodaSlice.last(where: { toneKeyStrings.contains($0) }) ?? {
                            switch tone {
                            case .acute: return "s"
                            case .grave: return "f"
                            case .hook: return "r"
                            case .tilde: return "x"
                            case .dot: return "j"
                            case .none: return nil
                            }
                        }()
                        let stopCodaToneValid = !isStopCoda || effectiveLastToneKey == "s" || effectiveLastToneKey == "j" || effectiveLastToneKey == "z"
                        if (afterCodaAllToneKeys && validLateCodas.contains(coda) && stopCodaToneValid) || isGenZInitial {
                            var candidateResult = result
                            let isLastUpper = candidateResult[candidateResult.count - 1].isUppercase
                            let replacement: Character
                            switch lower {
                            case "a": replacement = isLastUpper ? "Â" : "â"
                            case "e": replacement = isLastUpper ? "Ê" : "ê"
                            default: replacement = isLastUpper ? "Ô" : "ô"
                            }
                            candidateResult[candidateResult.count - 1] = replacement
                            let nonToneTail = isGenZInitial
                                ? remSlice.filter({ !toneKeyStrings.contains($0) }).joined()
                                : coda
                            let checkUntoned = String(candidateResult) + nonToneTail
                            let isValidLateCircumflex =
                                VietnameseSyllableDictionary.shared.isValidUntonedSyllable(checkUntoned, genZMode: genZMode || isGenZInitial) ||
                                (!lowerWord.hasPrefix("w") &&
                                 VietnameseSyllableDictionary.shared.isValidUntonedRhyme(checkUntoned) &&
                                 !SmartBilingualDetector.isKnownEnglishWord(lowerWord)) ||
                                (lower == "a" && nonToneTail.isEmpty && VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(checkUntoned, genZMode: genZMode || isGenZInitial))
                            if isValidLateCircumflex {
                                result[result.count - 1] = candidateResult[candidateResult.count - 1]
                                i += 1
                                postCodaHandled = true
                            }
                        }
                    }
                }
                if postCodaHandled {
                    continue
                }
                if let lockedStem = Self.shouldLockPostCodaOverflow(
                    stemChars: result,
                    tone: tone,
                    hasHorn: false,
                    hornCancelled: hornCancelled,
                    circumflexCancelled: circumflexCancelled,
                    circumflexCancelledKey: circumflexCancelledKey,
                    strokeDCancelled: strokeDCancelled,
                    nextChar: ch,
                    remainingChars: chars[i...],
                    fullRawChars: chars,
                    modernOrthography: modernOrthography
                ) {
                    result = lockedStem
                    result.append(contentsOf: chars[i...])
                    tone = .none
                    hornCancelled = true
                    break
                }
            }

            // Check vowel doubling (aa -> â, ee -> ê, oo -> ô) and triple-vowel escape (aaa -> aa, eee -> ee, ooo -> oo)
            // Vietnamese orthography never contains double ASCII vowels (aa, ee, oo).
            // Once escaped via triple vowel, clear any pending tone and consume remaining characters literally.
            // Guard: if ư/ơ is already present in result, 'a'/'e' is an offglide/overflow (e.g. uwfaaa -> ừaaa), not circumflex â/ê.
            let hornBlocksTripleCircumflex = (lower == "a" || lower == "e") && result.contains(where: {
                let c = $0.lowercased()
                return c == "ư" || c == "ơ"
            })
            if !toneEscapeActive && !hornBlocksTripleCircumflex && (lower == "a" || lower == "e" || lower == "o") && i + 2 < chars.count && Character(chars[i + 1].lowercased()) == lower && Character(chars[i + 2].lowercased()) == lower {
                result.append(ch)
                result.append(chars[i + 1])
                tone = .none
                hornCancelled = true
                i += 3
                while i < chars.count {
                    let remCh = chars[i]
                    let remLower = Character(remCh.lowercased())
                    if (remLower == "a" || remLower == "e" || remLower == "o") && i + 2 < chars.count && Character(chars[i + 1].lowercased()) == remLower && Character(chars[i + 2].lowercased()) == remLower {
                        result.append(remCh)
                        result.append(chars[i + 1])
                        i += 3
                    } else {
                        result.append(remCh)
                        i += 1
                    }
                }
                break
            }
            if !toneEscapeActive && (lower == "a" || lower == "e" || lower == "o") && i + 1 < chars.count && Character(chars[i + 1].lowercased()) == lower {
                let hasPriorCircumflexOrBreve = result.contains(where: {
                    let c = $0.lowercased()
                    return "âêôă".contains(c) || ((lower == "a" || lower == "e") && ("ư" == c || "ơ" == c))
                })
                if !hasPriorCircumflexOrBreve {
                    let transformed: Character
                    switch lower {
                    case "a": transformed = ch.isUppercase ? "Â" : "â"
                    case "e": transformed = ch.isUppercase ? "Ê" : "ê"
                    case "o": transformed = ch.isUppercase ? "Ô" : "ô"
                    default: transformed = ch
                    }
                    result.append(transformed)
                    i += 2
                    continue
                }
            }

            // Check w-modifiers (aw -> ă, ow -> ơ, uw -> ư)
            if lower == "w" {
                if hornCancelled {
                    if let lockedStem = Self.shouldLockPostCodaOverflow(
                        stemChars: result,
                        tone: tone,
                        hasHorn: false,
                        hornCancelled: hornCancelled,
                        circumflexCancelled: circumflexCancelled,
                        circumflexCancelledKey: circumflexCancelledKey,
                        strokeDCancelled: strokeDCancelled,
                        nextChar: ch,
                        remainingChars: chars[i...],
                        fullRawChars: chars,
                        modernOrthography: modernOrthography
                    ) {
                        result = lockedStem
                        result.append(contentsOf: chars[i...])
                        tone = .none
                        hornCancelled = true
                        break
                    }
                    result.append(ch)
                    i += 1
                    continue
                }
                // If w is at the beginning of the word
                if result.isEmpty {
                    if i + 2 < chars.count && Character(chars[i + 1].lowercased()) == "w" && Character(chars[i + 2].lowercased()) == "w" {
                        result.append(contentsOf: chars[i...])
                        return String(result)
                    }
                    if simpleTelex && chars.allSatisfy({ $0.lowercased() == "w" }) {
                        result.append(contentsOf: chars[i...])
                        return String(result)
                    }
                    if i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "w" {
                        // Second 'w' cancels horn modifier -> 'w'; no Vietnamese word starts with 'w', so any trailing characters are literal
                        result.append(ch)
                        if i + 2 < chars.count {
                            result.append(contentsOf: chars[(i + 2)...])
                        }
                        return String(result)
                    }
                    result.append(ch.isUppercase ? "Ư" : "ư")
                    i += 1
                    continue
                }

                let hasCircumflexReshapable = result.contains(where: { $0.lowercased() == "ô" || $0.lowercased() == "â" })
                let hasAlreadyHornedVowel = result.contains(where: { "ăơư".contains($0.lowercased()) })
                let endsWithHornableVowel: Bool = {
                    guard let lastChar = result.last else { return false }
                    let l = Character(lastChar.lowercased())
                    return l == "a" || l == "o" || l == "u"
                }()
                if !toneEscapeActive && tone == .none && endsWithHornableVowel && !hasCircumflexReshapable && !hasAlreadyHornedVowel && i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "w" {
                    result.append(ch)
                    hornCancelled = true
                    toneEscapeActive = true
                    toneEscapeLocked = true
                    i += 2
                    continue
                }
                // Free-tone W modifier: scan backwards to find the last applicable vowel
                let canModifyExistingVowel: Bool = {
                    guard !toneEscapeActive && postStrokeTail.isEmpty, let lastResChar = result.last else {
                        return false
                    }
                    return Self.isVietnameseVowel(lastResChar) ||
                        ["c", "m", "n", "p", "t", "g", "h"].contains(Character(lastResChar.lowercased()))
                }()
                var transformed = false
                if canModifyExistingVowel {
                    let hasCodaBeforeW = result.last.map { ["c", "m", "n", "p", "t", "g", "h"].contains(Character($0.lowercased())) } ?? false
                    let lowerFullRaw = String(chars).lowercased()
                    let isValidAfterCodaW: ([Character]) -> Bool = { candidate in
                        guard hasCodaBeforeW else { return true }
                        let candidateStr = String(candidate)
                        return VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateStr, genZMode: self.genZMode) ||
                            VietnameseSyllableDictionary.shared.hasUntonedPrefix(candidateStr, preserveVowelShape: true, relaxedCoda: true, genZMode: self.genZMode) ||
                            (!SmartBilingualDetector.isKnownEnglishWord(lowerFullRaw) &&
                             (VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(candidateStr, raw: lowerFullRaw, genZMode: self.genZMode) ||
                              (!lowerFullRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(candidateStr))))
                    }
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                    let lastLower = Character(result[idx].lowercased())
                    let isLastUpper = result[idx].isUppercase

                    if lastLower == "ă" || lastLower == "ư" || lastLower == "ơ" {
                        // Policy 3B+: Semantic Saturation — once the vowel already has breve/horn,
                        // a non-contiguous trailing 'w' does NOT strip the diacritic; it falls through as literal.
                        break
                    } else if lastLower == "ô" {
                        var candidateResult = result
                        if idx >= 1 {
                            let prevLower = Character(result[idx - 1].lowercased())
                            let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                            if !isAfterQ && (prevLower == "u" || prevLower == "ư") {
                                let isPrevUpper = result[idx - 1].isUppercase
                                candidateResult[idx - 1] = isPrevUpper ? "Ư" : "ư"
                            }
                        }
                        candidateResult[idx] = isLastUpper ? "Ơ" : "ơ"
                        if isValidAfterCodaW(candidateResult) {
                            result = candidateResult
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            transformed = true
                        }
                        break
                    } else if lastLower == "â" {
                        var candidateResult = result
                        candidateResult[idx] = isLastUpper ? "Ă" : "ă"
                        if isValidAfterCodaW(candidateResult) {
                            result = candidateResult
                            circumflexCancelled = false
                            circumflexCancelledKey = nil
                            transformed = true
                        }
                        break
                    } else if lastLower == "a" {
                        if idx >= 1 {
                            let prevLower = Character(result[idx - 1].lowercased())
                            if prevLower == "u" {
                                let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                                let isStandaloneLabializedBreveWithCoda =
                                    idx == 1 &&
                                    (hasCodaBeforeW ||
                                     (i + 1 < chars.count && ["c", "m", "n", "p", "t"].contains(Character(chars[i + 1].lowercased())))) &&
                                    !SmartBilingualDetector.isKnownEnglishWord(lowerFullRaw)
                                if !isAfterQ && !isStandaloneLabializedBreveWithCoda {
                                    // u a + w -> ư a
                                    let isPrevUpper = result[idx - 1].isUppercase
                                    var candidateResult = result
                                    candidateResult[idx - 1] = isPrevUpper ? "Ư" : "ư"
                                    if isValidAfterCodaW(candidateResult) {
                                        result = candidateResult
                                        transformed = true
                                    }
                                    break
                                }
                            } else if prevLower == "ư" {
                                // Policy 3B+: 'ưa' (e.g. cưa, cửa, mưa) is already horned (saturated).
                                break
                            }
                        }
                        var candidateResult = result
                        candidateResult[idx] = isLastUpper ? "Ă" : "ă"
                        if isValidAfterCodaW(candidateResult) {
                            result = candidateResult
                            transformed = true
                        }
                        break
                    } else if lastLower == "o" {
                        // Check 'uo' + 'w' -> 'ươ' or open 'ưo' + 'w' -> 'ươ'
                        if idx >= 1 {
                            let prevLower = Character(result[idx - 1].lowercased())
                            let isPrevUpper = result[idx - 1].isUppercase
                            if prevLower == "u" {
                                var candidateResult = result
                                candidateResult[idx - 1] = isPrevUpper ? "Ư" : "ư"
                                candidateResult[idx] = isLastUpper ? "Ơ" : "ơ"
                                if isValidAfterCodaW(candidateResult) {
                                    result = candidateResult
                                    transformed = true
                                }
                                break
                            } else if prevLower == "ư" {
                                if idx == result.count - 1 {
                                    result[idx] = isLastUpper ? "Ơ" : "ơ"
                                    transformed = true
                                }
                                // Policy 3B+: When 'ưo' is followed by a coda/offglide (idx < result.count - 1),
                                // it is already saturated as 'ươ'; break without stripping so 'w' appends literally.
                                break
                            }
                        }
                        var candidateResult = result
                        candidateResult[idx] = isLastUpper ? "Ơ" : "ơ"
                        if isValidAfterCodaW(candidateResult) {
                            result = candidateResult
                            transformed = true
                        }
                        break
                    } else if lastLower == "u" {
                        if idx >= 1 {
                            let prevLower = Character(result[idx - 1].lowercased())
                            if prevLower == "o" || prevLower == "ơ" {
                                // In 'uou'/'ươu', trailing 'u' is a semivowel offglide; continue scanning backward to 'o'/'ơ'
                                continue
                            }
                            let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                            if !isAfterQ {
                                if prevLower == "u" {
                                    // u u + w -> ư u (e.g. cuuw -> cưu, cuuws -> cứu, cuusw -> cứu)
                                    let isPrevUpper = result[idx - 1].isUppercase
                                    var candidateResult = result
                                    candidateResult[idx - 1] = isPrevUpper ? "Ư" : "ư"
                                    if isValidAfterCodaW(candidateResult) {
                                        result = candidateResult
                                        transformed = true
                                    }
                                    break
                                } else if prevLower == "ư" {
                                    // Policy 3B+: 'ưu' (e.g. lưu, cứu, hưu) is already horned (saturated).
                                    break
                                }
                            }
                        }
                        var candidateResult = result
                        candidateResult[idx] = isLastUpper ? "Ư" : "ư"
                        if isValidAfterCodaW(candidateResult) {
                            result = candidateResult
                            transformed = true
                        }
                        break
                    }
                    }
                }

                if transformed {
                    i += 1
                    continue
                } else {
                    if let lockedStem = Self.shouldLockPostCodaOverflow(
                        stemChars: result,
                        tone: tone,
                        hasHorn: false,
                        hornCancelled: hornCancelled,
                        circumflexCancelled: circumflexCancelled,
                        circumflexCancelledKey: circumflexCancelledKey,
                        strokeDCancelled: strokeDCancelled,
                        nextChar: ch,
                        remainingChars: chars[i...],
                        fullRawChars: chars,
                        modernOrthography: modernOrthography
                    ) {
                        result = lockedStem
                        result.append(contentsOf: chars[i...])
                        tone = .none
                        hornCancelled = true
                        break
                    }
                    // If no vowel was transformed, just append w
                    result.append(ch)
                    i += 1
                    continue
                }
            }

            // Check tone keys (s, f, r, x, j, z)
            // Tone keys only apply if we already have vowels in result and no literal 'w' cluster!
            let isToneOrGOrD = (lower == "s" || lower == "f" || lower == "r" || lower == "x" || lower == "j" || lower == "z" || lower == "g" || lower == "d")
            let hasVowels = isToneOrGOrD && !result.contains(where: { $0.lowercased() == "w" }) && result.contains { Self.isVietnameseVowel($0) }
            if hasVowels {
                if lower == "z" && tone != .none {
                    tone = .none
                    i += 1
                    continue
                }

                var toneFound: VietnameseTone? = nil
                switch lower {
                case "s": toneFound = .acute
                case "f": toneFound = .grave
                case "r": toneFound = .hook
                case "x": toneFound = .tilde
                case "j": toneFound = .dot
                default: break
                }

                if let t = toneFound {
                    let hasModifiedChar = result.contains { "ăâđêôơư".contains($0.lowercased()) }
                    let isIllegalStopCodaTone =
                        (t == .grave || t == .hook || t == .tilde) &&
                        tone != t &&
                        (tone != .none || hasModifiedChar) &&
                        Self.endsWithStopCodaAfterVowel(result)
                    if !isIllegalStopCodaTone {
                        if toneEscapeActive {
                            let hasVnStem = hasModifiedChar || hornCancelled || circumflexCancelled || circumflexCancelledKey != nil || strokeDCancelled
                            if hasVnStem || lower == cancelledToneKey {
                                result.append(ch)
                                i += 1
                                continue
                            } else if lower != cancelledToneKey {
                                cancelledToneKey = lower
                                result.append(ch)
                                if i + 1 < chars.count && Character(chars[i + 1].lowercased()) == lower {
                                    i += 2
                                } else {
                                    i += 1
                                }
                                continue
                            }
                        } else {
                            if tone == t && t != .none {
                                let isAdjacentDoubleTone = i > 0 && Character(chars[i - 1].lowercased()) == lower
                                let hasModifiedVowel = result.contains { "ăâêôơư".contains($0.lowercased()) } || hornCancelled || circumflexCancelled || circumflexCancelledKey != nil
                                let isCodaLast = result.last.map { ["c", "m", "n", "p", "t", "g", "h"].contains(Character($0.lowercased())) } ?? false
                                let isPostCodaToneThenVowelReshape = i >= 2 &&
                                    ["a", "e", "o", "w"].contains(chars[i - 1].lowercased()) &&
                                    Character(chars[i - 2].lowercased()) == lower &&
                                    isCodaLast &&
                                    hasModifiedVowel
                                if isAdjacentDoubleTone || !isPostCodaToneThenVowelReshape {
                                    // P0.2 & P0.6 CancelToneAndEmitLiteral: Repeated active tone key cancels the tone
                                    // and emits exactly one literal tone character (e.g. tur + r -> tur -> turus,
                                    // canhf + f -> canhf, cafnh + f -> canhf, hoongf + f -> hôngf, hoonfg + f -> hôngf).
                                    let stemBeforeEscape = String(result)
                                    tone = .none
                                    toneEscapeActive = true
                                    if isAdjacentDoubleTone ||
                                       hasModifiedChar ||
                                       hornCancelled ||
                                       circumflexCancelled ||
                                       circumflexCancelledKey != nil ||
                                       strokeDCancelled ||
                                       VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stemBeforeEscape, genZMode: genZMode) ||
                                       VietnameseSyllableDictionary.shared.isValidUntonedRhyme(stemBeforeEscape) ||
                                       VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(stemBeforeEscape, relaxedCoda: relaxedCoda, genZMode: genZMode) {
                                        toneEscapeLocked = true
                                    }
                                    cancelledToneKey = lower
                                    result.append(ch)
                                } else {
                                    // Post-coda tone-then-vowel-reshape followed by same tone key (e.g. congror) is idempotent
                                    tone = t
                                }
                            } else {
                                // MARK: — Non-plausible tone rejection (Bug B: double-consonant letter-drop fix)
                                // Before applying a new tone to a PURE ASCII stem for the first time,
                                // check if the resulting syllable would be plausible Vietnamese.
                                // If not, treat the tone key as a literal consonant.
                                // E.g. "monte" + s: applying sắc to "e" gives "monté" (non-plausible VN onset "mont")
                                // → treat "s" as literal → result = [m,o,n,t,e,s].
                                // For "me" + s: "mé" IS plausible → apply tone normally.
                                //
                                // Guards: Only reject when the stem is pure ASCII (no horn/circumflex/stroke-đ
                                // already applied) and no previous tone cancel/escape is active.
                                // If the stem already has Vietnamese-specific characters, the user is clearly
                                // typing Vietnamese, so we always allow the tone.
                                let lowerStem = String(result).lowercased()
                                let stemHasVnShape = result.contains { "ăâđêôơư".contains($0.lowercased()) } ||
                                                     hornCancelled || circumflexCancelled || circumflexCancelledKey != nil || strokeDCancelled
                                let stemIsValidUntonedSyllable = lowerStem == "qu" || lowerStem == "gue" ||
                                    (VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lowerStem, genZMode: genZMode) &&
                                     (!Self.endsWithStopCodaAfterVowel(result) || t == .acute || t == .dot))
                                let shouldCheckPlausibility = tone == .none && !stemHasVnShape && !stemIsValidUntonedSyllable
                                let candidateToned = shouldCheckPlausibility ? Self.applyToneToResult(result, tone: t) : nil
                                if candidateToned != nil &&
                                   !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(candidateToned!, relaxedCoda: relaxedCoda, genZMode: genZMode) &&
                                   !VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(candidateToned!) &&
                                   !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnameseRhyme(candidateToned!) {
                                    // Non-plausible: emit as literal consonant
                                    result.append(ch)
                                } else {
                                    tone = t
                                }
                            }
                            i += 1
                            continue
                        }
                    }
                }
            }

            // Relaxed coda shortcut: 'g' at end of word (or before trailing modifiers) transforms to 'ng'
            if relaxedCoda && !toneEscapeActive && lower == "g" && hasVowels,
               let lastChar = result.last, Self.isVietnameseVowel(lastChar),
               ((i + 1)..<chars.count).allSatisfy({ ["s", "f", "r", "x", "j", "z", "w", "a", "e", "o", "d"].contains(chars[$0].lowercased()) }) {
                result.append(contentsOf: ch.isUppercase ? "NG" : "ng")
                i += 1
                continue
            }

            if lower == "d" && hasVowels && !toneEscapeActive && postStrokeTail.isEmpty,
               let firstChar = result.first, Character(firstChar.lowercased()) == "đ",
               let lastChar = result.last,
               (Self.isVietnameseVowel(lastChar) || ["c", "m", "n", "p", "t", "g", "h"].contains(Character(lastChar.lowercased()))) {
                var candidateStem = result
                if !hornCancelled && circumflexCancelledKey != "o" && candidateStem.count >= 2 {
                    for idx in 0..<(candidateStem.count - 1) {
                        if Character(candidateStem[idx].lowercased()) == "ư" && Character(candidateStem[idx + 1].lowercased()) == "o" {
                            candidateStem[idx + 1] = candidateStem[idx + 1].isUppercase ? "Ơ" : "ơ"
                        }
                    }
                }
                if VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(String(candidateStem)) {
                    var dCount = 0
                    while i + dCount < chars.count && Character(chars[i + dCount].lowercased()) == "d" {
                        dCount += 1
                    }
                    let afterDIdx = i + dCount
                    if dCount == 1 {
                        result[0] = firstChar.isUppercase ? "D" : "d"
                        strokeDCancelled = true
                        i += 1
                        continue
                    } else {
                        result[0] = firstChar.isUppercase ? "D" : "d"
                        if dCount == 2 {
                            let isTailUpper = chars[i + 1].isUppercase || chars[i].isUppercase
                            postStrokeTail.append(isTailUpper ? "Đ" : "đ")
                        } else if dCount >= 3 {
                            for k in 1..<dCount {
                                postStrokeTail.append(chars[i + k])
                            }
                        }
                        if afterDIdx < chars.count {
                            postStrokeTail.append(contentsOf: chars[afterDIdx...])
                        }
                        i = chars.count
                        break
                    }
                }
            }
            if lower == "d" && hasVowels && result.count >= 3 &&
               !toneEscapeActive && !hornCancelled && !circumflexCancelled && circumflexCancelledKey == nil && postStrokeTail.isEmpty,
               let firstChar = result.first, Character(firstChar.lowercased()) == "d",
               let lastChar = result.last, ["c", "m", "n", "p", "t", "g", "h"].contains(Character(lastChar.lowercased())),
               !SmartBilingualDetector.isKnownEnglishWord(String(chars).lowercased()),
               !SmartBilingualDetector.isKnownEnglishWord(String(chars[0...i]).lowercased()) {
                var candidateResult = result
                candidateResult[0] = firstChar.isUppercase ? "Đ" : "đ"
                if candidateResult.count >= 2 {
                    for idx in 0..<(candidateResult.count - 1) {
                        if Character(candidateResult[idx].lowercased()) == "ư" && Character(candidateResult[idx + 1].lowercased()) == "o" {
                            candidateResult[idx + 1] = candidateResult[idx + 1].isUppercase ? "Ơ" : "ơ"
                        }
                    }
                }
                let candidateStr = String(candidateResult)
                let hasShapeModifierAhead = (i + 1 == chars.count) || ((i + 1)..<chars.count).contains {
                    let c = chars[$0].lowercased()
                    return c == "w" || c == "o"
                }
                if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidateStr) ||
                   (candidateStr.lowercased().hasPrefix("đuo") &&
                    hasShapeModifierAhead &&
                    VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(candidateStr)) {
                    result = candidateResult
                    i += 1
                    continue
                }
            }

            if !(lower == "a" || lower == "e" || lower == "o"),
               let lockedStem = Self.shouldLockPostCodaOverflow(
                stemChars: result,
                tone: tone,
                hasHorn: false,
                hornCancelled: hornCancelled,
                circumflexCancelled: circumflexCancelled,
                circumflexCancelledKey: circumflexCancelledKey,
                strokeDCancelled: strokeDCancelled,
                nextChar: ch,
                remainingChars: chars[i...],
                fullRawChars: chars,
                modernOrthography: modernOrthography
            ) {
                result = lockedStem
                result.append(contentsOf: chars[i...])
                tone = .none
                hornCancelled = true
                break
            }

            result.append(ch)
            i += 1
        }

        // Harmonize 'ưo' -> 'ươ' when horn was applied to 'u' before 'o' (e.g. truwongr -> trưởng, dduwocj -> được, nguwoif -> người)
        if !hornCancelled && circumflexCancelledKey != "o" && result.count >= 2 {
            for idx in 0..<(result.count - 1) {
                if Character(result[idx].lowercased()) == "ư" && Character(result[idx + 1].lowercased()) == "o" {
                    let isOUpper = result[idx + 1].isUppercase
                    result[idx + 1] = isOUpper ? "Ơ" : "ơ"
                }
            }
        }

        // Apply tone mark to the correct vowel position
        if tone != .none {
            Self.applyTone(&result, tone: tone, modern: modernOrthography)
        }
        if !postStrokeTail.isEmpty {
            result.append(contentsOf: postStrokeTail)
        }

        return String(result)
    }

    // MARK: - VNI Transformation

    private static func harmonizeVNIHornCluster(_ chars: inout [Character]) {
        guard chars.count >= 3 else { return }
        for idx in 0..<(chars.count - 2) {
            if Character(chars[idx].lowercased()) == "ư" && Character(chars[idx + 1].lowercased()) == "o" {
                let isOUpper = chars[idx + 1].isUppercase
                chars[idx + 1] = isOUpper ? "Ơ" : "ơ"
            }
        }
    }

    private func transformVNI(_ chars: [Character]) -> String {
        if !chars.contains(where: \.isNumber) {
            return String(chars)
        }
        var result: [Character] = []
        var tone: VietnameseTone = .none
        var escapeActive = false
        var hornCancelled = false

        for ch in chars {
            if escapeActive {
                result.append(ch)
                continue
            }
            if ch.isNumber {
                let hasVowels = result.contains { Self.isVietnameseVowel($0) }
                switch ch {
                case "1", "2", "3", "4", "5":
                    guard hasVowels else {
                        result.append(ch)
                        escapeActive = true
                        continue
                    }
                    let targetTone: VietnameseTone
                    switch ch {
                    case "1": targetTone = .acute
                    case "2": targetTone = .grave
                    case "3": targetTone = .hook
                    case "4": targetTone = .tilde
                    default: targetTone = .dot
                    }
                    if tone == targetTone {
                        // Repeated active tone key cancels the tone, emits the digit literally, and locks literal mode
                        tone = .none
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        result.append(ch)
                        escapeActive = true
                    } else {
                        tone = targetTone
                    }
                case "0":
                    if hasVowels && tone != .none {
                        tone = .none
                    } else {
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        result.append(ch)
                        escapeActive = true
                    }
                case "6":
                    // â, ê, ô
                    let hasExistingCircumflex = result.contains { "âêôÂÊÔ".contains($0) }
                    if hasExistingCircumflex {
                        // Repeated '6' cancels circumflex back to base vowel, preserves active tone, appends '6', and locks
                        for idx in 0..<result.count {
                            switch result[idx] {
                            case "â": result[idx] = "a"
                            case "Â": result[idx] = "A"
                            case "ê": result[idx] = "e"
                            case "Ê": result[idx] = "E"
                            case "ô": result[idx] = "o"
                            case "Ô": result[idx] = "O"
                            default: break
                            }
                        }
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                        continue
                    }
                    var transformed = false
                    if result.count >= 2 {
                        for idx in stride(from: result.count - 1, through: 1, by: -1) {
                            let lower = Character(result[idx].lowercased())
                            let prevLower = Character(result[idx - 1].lowercased())
                            if lower == "ơ" && prevLower == "ư" {
                                result[idx - 1] = result[idx - 1].isUppercase ? "U" : "u"
                                result[idx] = result[idx].isUppercase ? "Ô" : "ô"
                                transformed = true
                                break
                            }
                        }
                    }
                    if !transformed {
                        for idx in stride(from: result.count - 1, through: 0, by: -1) {
                            let lower = Character(result[idx].lowercased())
                            let upper = result[idx].isUppercase
                            if lower == "ơ" { result[idx] = upper ? "Ô" : "ô"; transformed = true; break }
                            else if lower == "ă" { result[idx] = upper ? "Â" : "â"; transformed = true; break }
                            else if lower == "a" { result[idx] = upper ? "Â" : "â"; transformed = true; break }
                            else if lower == "e" { result[idx] = upper ? "Ê" : "ê"; transformed = true; break }
                            else if lower == "o" { result[idx] = upper ? "Ô" : "ô"; transformed = true; break }
                        }
                    }
                    if !transformed {
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                    }
                case "7":
                    // ơ, ư
                    // 1. Constructive 'u7o7' sequence where '7' is typed immediately after 'ưo'
                    if result.count >= 2,
                       let lastChar = result.last,
                       Character(lastChar.lowercased()) == "o",
                       Character(result[result.count - 2].lowercased()) == "ư" {
                        result[result.count - 1] = lastChar.isUppercase ? "Ơ" : "ơ"
                        continue
                    }
                    if !hornCancelled {
                        Self.harmonizeVNIHornCluster(&result)
                    }
                    let hasExistingHorn = result.contains { "ơưƠƯ".contains($0) }
                    if hasExistingHorn {
                        // Repeated '7' cancels horn back to base vowel(s), preserves active tone, appends '7', and locks
                        for idx in 0..<result.count {
                            switch result[idx] {
                            case "ơ": result[idx] = "o"
                            case "Ơ": result[idx] = "O"
                            case "ư": result[idx] = "u"
                            case "Ư": result[idx] = "U"
                            default: break
                            }
                        }
                        hornCancelled = true
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                        continue
                    }
                    var transformed = false
                    if result.count >= 2 {
                        for idx in stride(from: result.count - 1, through: 1, by: -1) {
                            let lower = Character(result[idx].lowercased())
                            let prevLower = Character(result[idx - 1].lowercased())
                            let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                            if !isAfterQ && lower == "ô" && prevLower == "u" {
                                result[idx - 1] = result[idx - 1].isUppercase ? "Ư" : "ư"
                                result[idx] = result[idx].isUppercase ? "Ơ" : "ơ"
                                transformed = true
                                break
                            }
                        }
                    }
                    if !transformed {
                        for idx in stride(from: result.count - 1, through: 0, by: -1) {
                            let lower = Character(result[idx].lowercased())
                            let upper = result[idx].isUppercase
                            if lower == "ô" {
                                result[idx] = upper ? "Ơ" : "ơ"
                                transformed = true
                                break
                            } else if lower == "o" {
                                if idx >= 1 {
                                    let prevLower = Character(result[idx - 1].lowercased())
                                    let prevUpper = result[idx - 1].isUppercase
                                    let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                                    if !isAfterQ && prevLower == "u" {
                                        result[idx - 1] = prevUpper ? "Ư" : "ư"
                                        result[idx] = upper ? "Ơ" : "ơ"
                                        transformed = true
                                        break
                                    }
                                }
                                result[idx] = upper ? "Ơ" : "ơ"
                                transformed = true
                                break
                            } else if lower == "u" {
                                let isSingleUAfterQ = (idx >= 1 && Character(result[idx - 1].lowercased()) == "q")
                                if isSingleUAfterQ {
                                    continue
                                }
                                if idx >= 1 {
                                    let prevLower = Character(result[idx - 1].lowercased())
                                    let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                                    if !isAfterQ && prevLower == "u" {
                                        let prevUpper = result[idx - 1].isUppercase
                                        result[idx - 1] = prevUpper ? "Ư" : "ư"
                                        transformed = true
                                        break
                                    }
                                }
                                result[idx] = upper ? "Ư" : "ư"
                                transformed = true
                                break
                            }
                        }
                    }
                    if !transformed {
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                    }
                case "8":
                    // ă
                    let hasExistingBreve = result.contains { "ăĂ".contains($0) }
                    if hasExistingBreve {
                        for idx in 0..<result.count {
                            if result[idx] == "ă" { result[idx] = "a" }
                            else if result[idx] == "Ă" { result[idx] = "A" }
                        }
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                        continue
                    }
                    var transformed = false
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                        let lower = Character(result[idx].lowercased())
                        let upper = result[idx].isUppercase
                        if lower == "â" || lower == "a" {
                            result[idx] = upper ? "Ă" : "ă"
                            transformed = true
                            break
                        }
                    }
                    if !transformed {
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                    }
                case "9":
                    // đ
                    let hasExistingStroke = result.contains { "đĐ".contains($0) }
                    if hasExistingStroke {
                        for idx in 0..<result.count {
                            if result[idx] == "đ" { result[idx] = "d" }
                            else if result[idx] == "Đ" { result[idx] = "D" }
                        }
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                        continue
                    }
                    var transformed = false
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                        let lower = Character(result[idx].lowercased())
                        let upper = result[idx].isUppercase
                        if lower == "d" { result[idx] = upper ? "Đ" : "đ" ; transformed = true; break }
                    }
                    if !transformed {
                        if !hornCancelled {
                            Self.harmonizeVNIHornCluster(&result)
                        }
                        if tone != .none {
                            Self.applyTone(&result, tone: tone, modern: modernOrthography)
                            tone = .none
                        }
                        result.append(ch)
                        escapeActive = true
                    }
                default:
                    result.append(ch)
                }
            } else {
                result.append(ch)
            }
        }

        if !escapeActive && !hornCancelled {
            Self.harmonizeVNIHornCluster(&result)
        }

        if tone != .none {
            Self.applyTone(&result, tone: tone, modern: modernOrthography)
        }

        return String(result)
    }

    // MARK: - Tone Placement Algorithm

    /// Applies Vietnamese diacritic tone mark according to standard linguistic orthography.
    /// Returns the string produced by applying `tone` to the vowel(s) in `result`,
    /// without mutating `result`. Used by the non-plausible tone rejection guard
    /// to preview what the toned syllable would look like before deciding whether to apply tone.
    private static func applyToneToResult(_ result: [Character], tone: VietnameseTone) -> String? {
        guard tone != .none, !result.isEmpty else { return nil }
        var copy = result
        applyTone(&copy, tone: tone, modern: false)
        let toned = String(copy)
        // Only return if tone actually changed something
        return toned != String(result) ? toned : nil
    }

    internal static func applyTone(_ chars: inout [Character], tone: VietnameseTone, modern: Bool) {
        guard tone != .none else { return }

        // Find indices of all vowels in chars
        var vowelIndices: [Int] = []
        for (idx, ch) in chars.enumerated() {
            if isVietnameseVowel(ch) {
                vowelIndices.append(idx)
            }
        }

        // If a single trailing vowel was appended after the coda of a valid untoned Vietnamese syllable
        // (e.g. "nhana", "nhene", "meme", "mongo", "thuôngo", "truôngo", "thươngu", "tiengo", "vieco"),
        // exclude that trailing vowel from nucleus tone placement so the tone lands on the syllable's true nucleus.
        if vowelIndices.count >= 2,
           let lastV = vowelIndices.last,
           lastV == chars.count - 1,
           (lastV > vowelIndices[vowelIndices.count - 2] + 1 ||
            (vowelIndices.count >= 3 && !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(String(chars)))),
           (VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(String(chars.dropLast())) ||
            VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(String(chars.dropLast()), genZMode: true)) {
            vowelIndices.removeLast()
        }

        guard !vowelIndices.isEmpty else { return }

        let validCodaChars: Set<Character> = ["c", "m", "n", "p", "t", "g", "h"]

        // Determine target vowel index
        let targetIndex: Int

        if vowelIndices.count == 1 {
            targetIndex = vowelIndices[0]
        } else if vowelIndices.count == 2 {
            let firstVowel = Character(chars[vowelIndices[0]].lowercased())
            let secondVowel = Character(chars[vowelIndices[1]].lowercased())
            let isFallingOffglide =
                secondVowel == "u" || (secondVowel == "o" && firstVowel != "u") ||
                (secondVowel == "i" && firstVowel != "u") ||
                (secondVowel == "y" && firstVowel != "u")
            let trailingIsValidCoda = hasValidCoda(after: vowelIndices[1], in: chars, validCodaChars: validCodaChars)
            let hasCoda = trailingIsValidCoda && !isFallingOffglide

            // Special initial digraphs: 'qu-' and 'gi-'
            // In 'qu', 'u' is part of initial consonant cluster (labialized), not nucleus
            if vowelIndices[0] > 0 && Character(chars[vowelIndices[0] - 1].lowercased()) == "q" && firstVowel == "u" {
                targetIndex = vowelIndices[1]
            }
            // In 'gi', if followed by another vowel (e.g. 'già', 'gió'), 'i' is initial
            else if vowelIndices[0] > 0 && Character(chars[vowelIndices[0] - 1].lowercased()) == "g" && firstVowel == "i" && vowelIndices.count > 1 {
                targetIndex = vowelIndices[1]
            }
            // Diphthongs with coda: tone goes to second vowel (e.g. "tiến", "hoàn", "hoạch")
            else if hasCoda {
                targetIndex = vowelIndices[1]
            }
            // Open diphthongs without coda
            else {
                let pair = "\(firstVowel)\(secondVowel)"
                // Modern orthography: oa, oe, uy -> tone on second vowel
                if pair == "oa" || pair == "oe" || pair == "uy" || pair == "uê" {
                    targetIndex = modern ? vowelIndices[1] : vowelIndices[0]
                } else if pair == "iê" || pair == "yê" || pair == "uô" || pair == "ươ" || pair == "ưo" || pair == "uơ" {
                    targetIndex = vowelIndices[1]
                } else {
                    // All other diphthongs without coda (ai, ao, au, ay, ây, eo, êu, ia, oi, ôi, ơi, ua, ui, ưa, ưi, ưu)
                    // Tone goes to first vowel: mái, báo, cấu, mấy, kéo, nếu, mía, tối, mới, múa, túi, mứa, cứu
                    targetIndex = vowelIndices[0]
                }
            }
        } else {
            // 3 or more vowels (e.g. "người", "khuỷu", "ngoại", "quỳnh")
            let lastVowelIdx = vowelIndices.last!
            let hasCoda = hasValidCoda(after: lastVowelIdx, in: chars, validCodaChars: validCodaChars)

            if hasCoda {
                // With coda consonant: tone goes to the LAST vowel (nearest to coda = nucleus)
                // e.g. "nguyễn" = [n,g,u,y,ê,n] → vowels u,y,ê → tone on ê (last vowel)
                targetIndex = vowelIndices.last!
            } else {
                // Without coda: check if last vowel is a glide (i, u, y after nucleus)
                let lastVowelLower = chars[lastVowelIdx].lowercased()
                let isLastGlide = lastVowelLower == "i" || lastVowelLower == "y" || lastVowelLower == "u"

                if isLastGlide && vowelIndices.count >= 2 {
                    // Last vowel is a glide → tone on penultimate (the nucleus)
                    // e.g. "người" → ư,ơ,i → tone on ơ (penultimate)
                    // e.g. "khuỷu" → u,y,u → tone on y (penultimate)
                    targetIndex = vowelIndices[vowelIndices.count - 2]
                } else {
                    // Fallback: prefer modified vowels (circumflex/horn/breve)
                    let modifiedVowels: Set<String> = ["â", "ê", "ô", "ơ", "ư", "ă"]
                    var nucleusIndex = vowelIndices[vowelIndices.count - 2]
                    for vi in vowelIndices {
                        let lower = chars[vi].lowercased()
                        if modifiedVowels.contains(lower) {
                            nucleusIndex = vi
                            break
                        }
                    }
                    targetIndex = nucleusIndex
                }
            }
        }

        // Replace target vowel with accented version
        let targetChar = chars[targetIndex]
        chars[targetIndex] = addToneToVowel(targetChar, tone: tone)
    }

    private static func hasValidCoda(after lastIdx: Int, in chars: [Character], validCodaChars: Set<Character>) -> Bool {
        guard lastIdx < chars.count - 1 else { return false }
        let firstAfter = Character(chars[lastIdx + 1].lowercased())
        return validCodaChars.contains(firstAfter)
    }

    /// Returns `true` if `chars` contains at least one Vietnamese vowel and ends with a stop coda (`-c`, `-ch`, `-p`, `-t`).
    internal static func endsWithStopCodaAfterVowel(_ chars: [Character]) -> Bool {
        guard let lastVowelIdx = chars.lastIndex(where: { isVietnameseVowel($0) }),
              lastVowelIdx < chars.count - 1 else {
            return false
        }
        let coda = String(chars[(lastVowelIdx + 1)...]).lowercased()
        return coda == "c" || coda == "ch" || coda == "p" || coda == "t"
    }

    /// Implements Apple `UkEngine`'s `CharForm = NonVn` (`form = 0`) post-coda overflow lock:
    /// When `stemChars` has already formed a complete, valid Vietnamese syllable with diacritics/tone,
    /// and `nextChar` overflows the syllable without forming a valid extended syllable or prefix,
    /// returns the finalized syllable stem so the remaining overflow tail can be appended literally.
    internal static func shouldLockPostCodaOverflow(
        stemChars: [Character],
        tone: VietnameseTone,
        hasHorn: Bool,
        hornCancelled: Bool,
        circumflexCancelled: Bool = false,
        circumflexCancelledKey: Character?,
        strokeDCancelled: Bool = false,
        nextChar: Character,
        remainingChars: ArraySlice<Character>? = nil,
        fullRawChars: [Character]? = nil,
        modernOrthography: Bool
    ) -> [Character]? {
        let hasCancelledVowelShape = (hornCancelled || circumflexCancelled || circumflexCancelledKey != nil) && !stemChars.contains(where: { $0.lowercased() == "w" })
        guard !stemChars.isEmpty,
              stemChars.count <= 7,
              let lastChar = stemChars.last else {
            return nil
        }
        if !hasHorn && !hasCancelledVowelShape && !strokeDCancelled && stemChars.allSatisfy(\.isASCII) {
            guard tone != .none else { return nil }
            let lowerNextFast = nextChar.lowercased()
            let isModFast = lowerNextFast == "a" || lowerNextFast == "e" || lowerNextFast == "o" || lowerNextFast == "w"
            let isRepeatVowelFast = (lowerNextFast == "u" || lowerNextFast == "i" || lowerNextFast == "y") && lastChar.lowercased() == lowerNextFast
            guard isModFast || isRepeatVowelFast else { return nil }
            if let rem = remainingChars {
                let allowedChars = isRepeatVowelFast ? lowerNextFast : "aeowzsfrxj"
                if !rem.allSatisfy({ allowedChars.contains($0.lowercased()) }) {
                    return nil
                }
            }
        }
        let isCodaStem = stemChars.count >= 2 && ["c", "m", "n", "p", "t", "g", "h"].contains(Character(lastChar.lowercased()))
        let isSingleTonedHornVowelOverflow = stemChars.count == 1 && tone != .none &&
            "ơư".contains(lastChar.lowercased()) &&
            !(lastChar.lowercased() == "ư" && nextChar.lowercased() == "o")
        let isVowelStem = isVietnameseVowel(lastChar) && (stemChars.count >= 2 || hasCancelledVowelShape || isSingleTonedHornVowelOverflow)
        guard (isCodaStem || isVowelStem),
              stemChars.contains(where: { isVietnameseVowel($0) }) else {
            return nil
        }

        var candidateStem = stemChars
        if hasHorn {
            var appliedHorn = false
            for idx in 0..<(candidateStem.count - 1) {
                let c0 = Character(candidateStem[idx].lowercased())
                let c1 = Character(candidateStem[idx + 1].lowercased())
                let isAfterQ = idx >= 1 && Character(candidateStem[idx - 1].lowercased()) == "q"
                if !isAfterQ && c0 == "u" && c1 == "o" {
                    candidateStem[idx] = candidateStem[idx].isUppercase ? "Ư" : "ư"
                    candidateStem[idx + 1] = candidateStem[idx + 1].isUppercase ? "Ơ" : "ơ"
                    appliedHorn = true
                    break
                }
            }
            if !appliedHorn {
                for idx in 0..<candidateStem.count {
                    let c = Character(candidateStem[idx].lowercased())
                    let isAfterQ = idx >= 1 && Character(candidateStem[idx - 1].lowercased()) == "q"
                    if !isAfterQ && c == "u" {
                        candidateStem[idx] = candidateStem[idx].isUppercase ? "Ư" : "ư"
                        break
                    } else if c == "o" {
                        candidateStem[idx] = candidateStem[idx].isUppercase ? "Ơ" : "ơ"
                        break
                    } else if c == "a" {
                        candidateStem[idx] = candidateStem[idx].isUppercase ? "Ă" : "ă"
                        break
                    }
                }
            }
        }

        if !hornCancelled && circumflexCancelledKey != "o" && candidateStem.count >= 2 {
            for idx in 0..<(candidateStem.count - 1) {
                if Character(candidateStem[idx].lowercased()) == "ư" && Character(candidateStem[idx + 1].lowercased()) == "o" {
                    candidateStem[idx + 1] = candidateStem[idx + 1].isUppercase ? "Ơ" : "ơ"
                }
            }
        }

        let lowerUntoned = String(candidateStem).lowercased()
        let hasVnSpecificShape = lowerUntoned.contains(where: { "đăâơư".contains($0) }) || lowerUntoned.contains("uô") || lowerUntoned.contains("iê") || lowerUntoned.contains("yê") || strokeDCancelled
        let hasCircumflexEOrOWithTone = tone != .none && lowerUntoned.contains(where: { "êô".contains($0) })
        let hasSaturatedCodaCircumflex = isCodaStem && (
            (nextChar.lowercased() == "e" && lowerUntoned.contains("ê")) ||
            (nextChar.lowercased() == "o" && lowerUntoned.contains("ô"))
        )
        let hasFastLockShape = hasVnSpecificShape || hasCircumflexEOrOWithTone || hasSaturatedCodaCircumflex || hasCancelledVowelShape
        let lowerNext = nextChar.lowercased()
        let isModifierOverflow = ["a", "e", "o", "w"].contains(lowerNext)
        let isSameVowelRepeatOverflow =
            isVowelStem &&
            ["u", "i", "y"].contains(lowerNext) &&
            String(lastChar).lowercased() == lowerNext
        let hasPlainTonedCandidate: Bool = {
            if hasFastLockShape { return false }
            guard tone != .none,
                  (isModifierOverflow || isSameVowelRepeatOverflow) else {
                return false
            }
            if let rem = remainingChars {
                let allowedChars = isSameVowelRepeatOverflow ? lowerNext : "aeowzsfrxj"
                if !rem.allSatisfy({ allowedChars.contains($0.lowercased()) }) {
                    return false
                }
            }
            return true
        }()
        guard hasFastLockShape || hasPlainTonedCandidate else {
            return nil
        }

        // If `nextChar` extends `candidateStem` into a valid untoned Vietnamese syllable (e.g. 'n' -> 'ng'/'nh', 'c' -> 'ch',
        // or after vowel-shape undo 'đẻ' + 'o' -> 'đẻo', 'đó' + 'n' -> 'đón', 'củ' + 'a' -> 'của'), do not lock
        // unless `nextChar` is the repeated cancelled modifier itself.
        let isRepeatedCancelledModifier =
            (circumflexCancelledKey != nil && Character(nextChar.lowercased()) == circumflexCancelledKey) ||
            (hornCancelled && nextChar.lowercased() == "w")
        if !isRepeatedCancelledModifier {
            let extended = candidateStem + [nextChar]
            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(String(extended)) {
                return nil
            }
            if isVowelStem && !hasCancelledVowelShape && !strokeDCancelled {
                let stemHasModifiedVowel = candidateStem.contains(where: { "ăâêôơư".contains($0.lowercased()) })
                if VietnameseSyllableDictionary.shared.hasUntonedPrefix(
                    String(extended),
                    preserveVowelShape: stemHasModifiedVowel,
                    relaxedCoda: true,
                    genZMode: true
                ) {
                    return nil
                }
            }
        }

        var tonedStem = candidateStem
        if tone != .none {
            applyTone(&tonedStem, tone: tone, modern: modernOrthography)
        }
        let tonedStemStr = String(tonedStem)
        let isValidStem = (hasCancelledVowelShape || strokeDCancelled)
            ? (VietnameseSyllableDictionary.shared.isValidSyllableIgnoringVowelShape(tonedStemStr) ||
               (!VietnameseSyllableDictionary.hasToneMark(tonedStemStr) &&
                VietnameseSyllableDictionary.shared.isValidUntonedSyllableIgnoringVowelShape(tonedStemStr)))
            : (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(tonedStemStr) ||
               (tone == .none && (hasVnSpecificShape || hasSaturatedCodaCircumflex) && VietnameseSyllableDictionary.shared.isValidUntonedSyllable(tonedStemStr)) ||
               (isCodaStem && (hasVnSpecificShape || hasCircumflexEOrOWithTone || hasSaturatedCodaCircumflex || hasPlainTonedCandidate) &&
                VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(tonedStemStr, genZMode: true)))
        guard isValidStem else {
            return nil
        }

        if !hasFastLockShape && hasPlainTonedCandidate, let raw = fullRawChars {
            let rawStr = String(raw)
            let lowerRaw = rawStr.lowercased()
            if SmartBilingualDetector.isKnownEnglishWord(rawStr) || SyllableCandidateResolver.isEnglishCollision(lowerRaw) {
                return nil
            }
            if let rem = remainingChars, raw.count > rem.count {
                let rawStem = String(raw.dropLast(rem.count)).lowercased()
                if (!isSameVowelRepeatOverflow && SyllableCandidateResolver.isEnglishCollision(rawStem)) || rawStem.contains("st") {
                    return nil
                }
            }
        }

        return tonedStem
    }

    // MARK: - Character Utilities

    private static let vietnameseVowelCharacters: Set<Character> = [
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        "á", "à", "ả", "ã", "ạ",
        "ắ", "ằ", "ẳ", "ẵ", "ặ",
        "ấ", "ầ", "ẩ", "ẫ", "ậ",
        "é", "è", "ẻ", "ẽ", "ẹ",
        "ế", "ề", "ể", "ễ", "ệ",
        "í", "ì", "ỉ", "ĩ", "ị",
        "ó", "ò", "ỏ", "õ", "ọ",
        "ố", "ồ", "ổ", "ỗ", "ộ",
        "ớ", "ờ", "ở", "ỡ", "ợ",
        "ú", "ù", "ủ", "ũ", "ụ",
        "ứ", "ừ", "ử", "ữ", "ự",
        "ý", "ỳ", "ỷ", "ỹ", "ỵ",
        "A", "Ă", "Â", "E", "Ê", "I", "O", "Ô", "Ơ", "U", "Ư", "Y",
        "Á", "À", "Ả", "Ã", "Ạ",
        "Ắ", "Ằ", "Ẳ", "Ẵ", "Ặ",
        "Ấ", "Ầ", "Ẩ", "Ẫ", "Ậ",
        "É", "È", "Ẻ", "Ẽ", "Ẹ",
        "Ế", "Ề", "Ể", "Ễ", "Ệ",
        "Í", "Ì", "Ỉ", "Ĩ", "Ị",
        "Ó", "Ò", "Ỏ", "Õ", "Ọ",
        "Ố", "Ồ", "Ổ", "Ỗ", "Ộ",
        "Ớ", "Ờ", "Ở", "Ỡ", "Ợ",
        "Ú", "Ù", "Ủ", "Ũ", "Ụ",
        "Ứ", "Ừ", "Ử", "Ữ", "Ự",
        "Ý", "Ỳ", "Ỷ", "Ỹ", "Ỵ"
    ]

    internal static func isVietnameseVowel(_ ch: Character) -> Bool {
        vietnameseVowelCharacters.contains(ch)
    }

    private static let toneVowelTable: [Character: [Character]] = [
        // [none, acute, grave, hook, tilde, dot]
        "a": ["a", "á", "à", "ả", "ã", "ạ"],
        "ă": ["ă", "ắ", "ằ", "ẳ", "ẵ", "ặ"],
        "â": ["â", "ấ", "ầ", "ẩ", "ẫ", "ậ"],
        "e": ["e", "é", "è", "ẻ", "ẽ", "ẹ"],
        "ê": ["ê", "ế", "ề", "ể", "ễ", "ệ"],
        "i": ["i", "í", "ì", "ỉ", "ĩ", "ị"],
        "o": ["o", "ó", "ò", "ỏ", "õ", "ọ"],
        "ô": ["ô", "ố", "ồ", "ổ", "ỗ", "ộ"],
        "ơ": ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"],
        "u": ["u", "ú", "ù", "ủ", "ũ", "ụ"],
        "ư": ["ư", "ứ", "ừ", "ử", "ữ", "ự"],
        "y": ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"]
    ]

    private static let reverseBaseVowelMap: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (base, tones) in toneVowelTable {
            for t in tones {
                map[t] = base
            }
        }
        return map
    }()

    internal static func addToneToVowel(_ ch: Character, tone: VietnameseTone) -> Character {
        let isUpper = ch.isUppercase
        let lower = Character(ch.lowercased())
        guard let baseVowel = reverseBaseVowelMap[lower],
              let row = toneVowelTable[baseVowel],
              tone.rawValue < row.count else {
            return ch
        }
        let accented = row[tone.rawValue]
        return isUpper ? Character(accented.uppercased()) : accented
    }
}
