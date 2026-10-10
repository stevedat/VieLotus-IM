import Foundation

// MARK: - Vietnamese Orthography Types

public enum VietnameseTone: Int, CaseIterable, Sendable {
    case none = 0
    case acute = 1   // Sắc
    case grave = 2   // Huyền
    case hook = 3    // Hỏi
    case tilde = 4   // Ngã
    case dot = 5     // Nặng
}

public enum VowelModification: Sendable {
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
public final class VietnameseEngine: @unchecked Sendable {
    
    // MARK: - Configuration
    
    public var inputMethod: InputMethodType = .telex
    public var modernOrthography: Bool = true
    public var relaxedCoda: Bool = false
    public var quickTelex: Bool = false
    public var quickStart: Bool = false
    public var genZMode: Bool = false
    
    // MARK: - Internal Syllable State
    
    /// Raw keystrokes entered for current composing syllable
    private var rawChars: [Character] = []
    
    /// Current rendered output of the active word
    private var renderedOutput: String = ""
    
    /// History of committed words for post-commit editing (ring buffer)
    /// Stores (rawChars, renderedOutput) pairs
    private var committedHistory: [(raw: [Character], rendered: String)] = []
    private static let maxHistoryCount = 20
    
    public var isComposing: Bool {
        return !rawChars.isEmpty
    }
    
    public var lastCommittedWord: String? {
        return committedHistory.last?.rendered
    }
    
    public init() {}
    
    // MARK: - Public Control API
    
    public func reset() {
        rawChars.removeAll(keepingCapacity: true)
        renderedOutput = ""
    }
    
    public func currentOutput() -> String {
        return renderedOutput
    }
    
    public func rawString() -> String {
        return String(rawChars)
    }
    
    // MARK: - Prefix & Re-composition API
    
    /// Converts a rendered Vietnamese string into canonical raw keystrokes according to the input method.
    public static func rawKeys(for text: String, inputMethod: InputMethodType) -> String {
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
                raw.append(isVni ? "7" : "w")
            default:
                raw.append(String(scalar))
            }
        }
        if let toneKey {
            raw.append(toneKey)
        }
        return raw
    }
    
    /// Re-initializes composition state with an existing prefix already rendered on screen.
    public func setCompositionPrefix(_ text: String) {
        let raw = VietnameseEngine.rawKeys(for: text, inputMethod: inputMethod)
        reset()
        for ch in raw {
            _ = feed(ch)
        }
    }
    
    // MARK: - Core Feed / Edit / Commit API
    
    /// Feeds a single character into the engine.
    /// Returns (backspaces, suffix) diff if the on-screen text needs transformation,
    /// or returns (0, String(ch)) if it passes through, or nil if rejected.
    public func feed(_ ch: Character) -> (backspaces: Int, suffix: String)? {
        guard ch.isASCII else {
            // Non-ASCII characters commit previous composition and pass through
            if isComposing {
                _ = commit()
            }
            return (0, String(ch))
        }
        
        let previousOutput = renderedOutput
        rawChars.append(ch)
        
        let newOutput = transform(rawChars)
        renderedOutput = newOutput
        
        // Calculate diff between previousOutput and newOutput
        return calculateDiff(oldStr: previousOutput, newStr: newOutput, appendedChar: ch)
    }
    
    /// Handles backspace keypress during composition.
    public func backspace() -> (backspaces: Int, suffix: String)? {
        guard !rawChars.isEmpty else { return nil }
        let previousOutput = renderedOutput
        rawChars.removeLast()
        
        if rawChars.isEmpty {
            renderedOutput = ""
            return (previousOutput.utf16.count, "")
        }
        
        let newOutput = transform(rawChars)
        renderedOutput = newOutput
        return calculateDiff(oldStr: previousOutput, newStr: newOutput, appendedChar: nil)
    }
    
    /// Commits active composition into word history.
    public func commit() -> (backspaces: Int, suffix: String)? {
        guard isComposing else { return nil }
        let output = renderedOutput
        committedHistory.append((raw: rawChars, rendered: output))
        if committedHistory.count > Self.maxHistoryCount {
            committedHistory.removeFirst()
        }
        reset()
        return (0, "")
    }
    
    /// Post-commit editing (LabanKey-style).
    /// Caret back index into the committed text (0 = end of newest word).
    public func editAt(caretBack: Int, char: Character) -> (backspaces: Int, suffix: String)? {
        guard caretBack == 0 else { return nil }
        guard let lastEntry = committedHistory.last else { return nil }
        let lastWord = lastEntry.rendered
        var rawCopy = lastEntry.raw
        guard !rawCopy.isEmpty else { return nil }
        
        // Append new raw character to raw chars
        rawCopy.append(char)
        
        let newWord = transform(rawCopy)
        guard newWord != lastWord else { return nil }
        
        // Update history
        committedHistory.removeLast()
        committedHistory.append((raw: rawCopy, rendered: newWord))
        
        let backspaces = lastWord.utf16.count
        return (backspaces, newWord)
    }
    
    // MARK: - Diff Calculation
    
    private func calculateDiff(oldStr: String, newStr: String, appendedChar: Character?) -> (backspaces: Int, suffix: String) {
        if oldStr.isEmpty {
            return (0, newStr)
        }
        
        let oldArray = Array(oldStr)
        let newArray = Array(newStr)
        
        // Find common prefix
        var commonPrefixLen = 0
        let minLen = min(oldArray.count, newArray.count)
        while commonPrefixLen < minLen && oldArray[commonPrefixLen] == newArray[commonPrefixLen] {
            commonPrefixLen += 1
        }
        
        let deletedChars = oldArray[commonPrefixLen...]
        let backspacesUTF16 = deletedChars.reduce(0) { $0 + String($1).utf16.count }
        
        let suffix = String(newArray[commonPrefixLen...])
        return (backspacesUTF16, suffix)
    }
    
    // MARK: - Vietnamese Phonetic Transformation (FSM)
    
    public func transform(_ chars: [Character]) -> String {
        guard !chars.isEmpty else { return "" }
        
        let lowerRaw = String(chars).lowercased()
        
        // Non-Vietnamese initials: 'f', 'j', 'z' cannot start a Vietnamese syllable
        if let first = lowerRaw.first, (first == "f" || first == "j" || first == "z") && !genZMode {
            return String(chars)
        }
        
        
        
        if inputMethod == .vni {
            return transformVNI(chars)
        } else {
            return transformTelex(chars)
        }
    }
    
    // MARK: - Telex Transformation
    
    private func transformTelex(_ chars: [Character]) -> String {
        // State variables
        var result: [Character] = []
        var tone: VietnameseTone = .none
        
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            let lower = Character(ch.lowercased())
            
            // Check 'dd' / 'DD' -> 'đ' / 'Đ'
            if lower == "d" {
                if i + 2 < chars.count && Character(chars[i + 1].lowercased()) == "d" && Character(chars[i + 2].lowercased()) == "d" {
                    result.append(ch)
                    result.append(chars[i + 1])
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
            
            // Check vowel doubling (aa -> â, ee -> ê, oo -> ô)
            if (lower == "a" || lower == "e" || lower == "o") && i + 2 < chars.count && Character(chars[i + 1].lowercased()) == lower && Character(chars[i + 2].lowercased()) == lower {
                result.append(ch)
                result.append(chars[i + 1])
                i += 3
                continue
            }
            if (lower == "a" || lower == "e" || lower == "o") && i + 1 < chars.count && Character(chars[i + 1].lowercased()) == lower {
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
            
            // Check w-modifiers (aw -> ă, ow -> ơ, uw -> ư)
            if lower == "w" {
                // If w is at the beginning of the word
                if result.isEmpty {
                    if i + 2 < chars.count && Character(chars[i + 1].lowercased()) == "w" && Character(chars[i + 2].lowercased()) == "w" {
                        result.append(ch)
                        result.append(chars[i + 1])
                        result.append(chars[i + 2])
                        i += 3
                        continue
                    }
                    if i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "w" {
                        // Second 'w' cancels horn modifier -> 'w'
                        result.append(ch)
                        i += 2
                        continue
                    }
                    result.append(ch.isUppercase ? "Ư" : "ư")
                    i += 1
                    continue
                }
                
                if i + 1 < chars.count && Character(chars[i + 1].lowercased()) == "w" {
                    result.append(ch)
                    i += 2
                    continue
                }
                // Free-tone W modifier: scan backwards to find the last applicable vowel
                var transformed = false
                for idx in stride(from: result.count - 1, through: 0, by: -1) {
                    let lastLower = Character(result[idx].lowercased())
                    let isLastUpper = result[idx].isUppercase
                    
                    if lastLower == "a" {
                        if idx >= 1 {
                            let prevLower = Character(result[idx - 1].lowercased())
                            if prevLower == "u" {
                                let isAfterQ = (idx >= 2 && Character(result[idx - 2].lowercased()) == "q")
                                if !isAfterQ {
                                    // u a + w -> ư a
                                    let isPrevUpper = result[idx - 1].isUppercase
                                    result[idx - 1] = isPrevUpper ? "Ư" : "ư"
                                    transformed = true
                                    break
                                }
                            }
                        }
                        result[idx] = isLastUpper ? "Ă" : "ă"
                        transformed = true
                        break
                    } else if lastLower == "o" {
                        // Check 'uo' + 'w' -> 'ươ'
                        if idx >= 1 {
                            let prevLower = Character(result[idx - 1].lowercased())
                            let isPrevUpper = result[idx - 1].isUppercase
                            if prevLower == "u" {
                                result[idx - 1] = isPrevUpper ? "Ư" : "ư"
                                result[idx] = isLastUpper ? "Ơ" : "ơ"
                                transformed = true
                                break
                            }
                        }
                        result[idx] = isLastUpper ? "Ơ" : "ơ"
                        transformed = true
                        break
                    } else if lastLower == "u" {
                        result[idx] = isLastUpper ? "Ư" : "ư"
                        transformed = true
                        break
                    }
                }
                
                if transformed {
                    i += 1
                    continue
                } else {
                    // If no vowel was transformed, just append w
                    result.append(ch)
                    i += 1
                    continue
                }
            }
            
            // Check tone keys (s, f, r, x, j, z)
            // Tone keys only apply if we already have vowels in result!
            let hasVowels = result.contains { isVietnameseVowel($0) }
            if hasVowels {
                if lower == "z" {
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
                    if tone == t && t != .none {
                        // Double tone key cancels tone
                        tone = .none
                        // The previous tone character was eaten, so we restore it by appending it now.
                        result.append(ch)
                    } else {
                        tone = t
                    }
                    i += 1
                    continue
                }
            }
            
            // Relaxed coda shortcut: 'g' at end of word transforms to 'ng'
            if relaxedCoda && lower == "g" && i == chars.count - 1 && hasVowels {
                if let lastChar = result.last, isVietnameseVowel(lastChar) {
                    result.append(contentsOf: ch.isUppercase ? "NG" : "ng")
                    i += 1
                    continue
                }
            }
            
            result.append(ch)
            i += 1
        }
        
        // Apply tone mark to the correct vowel position
        if tone != .none {
            applyTone(&result, tone: tone, modern: modernOrthography)
        }
        
        return String(result)
    }
    
    // MARK: - VNI Transformation
    
    private func transformVNI(_ chars: [Character]) -> String {
        var result: [Character] = []
        var tone: VietnameseTone = .none
        
        for ch in chars {
            if ch.isNumber {
                let hasVowels = result.contains { isVietnameseVowel($0) }
                switch ch {
                case "1" where hasVowels: tone = .acute
                case "2" where hasVowels: tone = .grave
                case "3" where hasVowels: tone = .hook
                case "4" where hasVowels: tone = .tilde
                case "5" where hasVowels: tone = .dot
                case "0" where hasVowels: tone = .none
                case "6":
                    // â, ê, ô
                    var transformed = false
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                        let lower = Character(result[idx].lowercased())
                        let upper = result[idx].isUppercase
                        if lower == "a" { result[idx] = upper ? "Â" : "â"; transformed = true; break }
                        else if lower == "e" { result[idx] = upper ? "Ê" : "ê"; transformed = true; break }
                        else if lower == "o" { result[idx] = upper ? "Ô" : "ô"; transformed = true; break }
                    }
                    if !transformed { result.append(ch) }
                case "7":
                    // ơ, ư
                    var transformed = false
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                        let lower = Character(result[idx].lowercased())
                        let upper = result[idx].isUppercase
                        if lower == "o" {
                            if idx >= 1 {
                                let prevLower = Character(result[idx - 1].lowercased())
                                let prevUpper = result[idx - 1].isUppercase
                                if prevLower == "u" {
                                    result[idx - 1] = prevUpper ? "Ư" : "ư"
                                    result[idx] = upper ? "Ơ" : "ơ"
                                    transformed = true
                                    break
                                }
                            }
                            result[idx] = upper ? "Ơ" : "ơ"
                            transformed = true
                            break
                        }
                        else if lower == "u" {
                            result[idx] = upper ? "Ư" : "ư"
                            transformed = true
                            break
                        }
                    }
                    if !transformed { result.append(ch) }
                case "8":
                    // ă
                    var transformed = false
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                        let lower = Character(result[idx].lowercased())
                        let upper = result[idx].isUppercase
                        if lower == "a" { result[idx] = upper ? "Ă" : "ă"; transformed = true; break }
                    }
                    if !transformed { result.append(ch) }
                case "9":
                    // đ
                    var transformed = false
                    for idx in stride(from: result.count - 1, through: 0, by: -1) {
                        let lower = Character(result[idx].lowercased())
                        let upper = result[idx].isUppercase
                        if lower == "d" { result[idx] = upper ? "Đ" : "đ"; transformed = true; break }
                    }
                    if !transformed { result.append(ch) }
                default:
                    result.append(ch)
                }
            } else {
                result.append(ch)
            }
        }
        
        if tone != .none {
            applyTone(&result, tone: tone, modern: modernOrthography)
        }
        
        return String(result)
    }
    
    // MARK: - Tone Placement Algorithm
    
    /// Applies Vietnamese diacritic tone mark according to standard linguistic orthography.
    private func applyTone(_ chars: inout [Character], tone: VietnameseTone, modern: Bool) {
        guard tone != .none else { return }
        
        // Find indices of all vowels in chars
        var vowelIndices: [Int] = []
        for (idx, ch) in chars.enumerated() {
            if isVietnameseVowel(ch) {
                vowelIndices.append(idx)
            }
        }
        
        guard !vowelIndices.isEmpty else { return }
        
        // Determine target vowel index
        let targetIndex: Int
        
        if vowelIndices.count == 1 {
            targetIndex = vowelIndices[0]
        } else if vowelIndices.count == 2 {
            let firstVowel = Character(chars[vowelIndices[0]].lowercased())
            let secondVowel = Character(chars[vowelIndices[1]].lowercased())
            let hasCoda = vowelIndices[1] < chars.count - 1
            
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
                } else {
                    // All other diphthongs without coda (ai, ao, au, ay, ây, eo, êu, ia, oi, ôi, ơi, ua, ui, ưa, ưi, ưu)
                    // Tone goes to first vowel: mái, báo, cấu, mấy, kéo, nếu, mía, tối, mới, múa, túi, mứa, cứu
                    targetIndex = vowelIndices[0]
                }
            }
        } else {
            // 3 or more vowels (e.g. "người", "khuỷu", "ngoại", "quỳnh")
            let lastVowelIdx = vowelIndices.last!
            let hasCoda = lastVowelIdx < chars.count - 1
            
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
    
    // MARK: - Character Utilities
    
    private func isVietnameseVowel(_ ch: Character) -> Bool {
        let lower = ch.lowercased()
        let vowels: Set<String> = [
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
            "ý", "ỳ", "ỷ", "ỹ", "ỵ"
        ]
        return vowels.contains(lower)
    }
    
    private func addToneToVowel(_ ch: Character, tone: VietnameseTone) -> Character {
        let isUpper = ch.isUppercase
        let lower = Character(ch.lowercased())
        
        let table: [Character: [Character]] = [
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
        
        // Find base vowel (strip existing tone if any)
        var baseVowel = lower
        for (base, tones) in table {
            if tones.contains(lower) {
                baseVowel = base
                break
            }
        }
        
        guard let row = table[baseVowel], tone.rawValue < row.count else {
            return ch
        }
        
        let accented = row[tone.rawValue]
        return isUpper ? Character(accented.uppercased()) : accented
    }
}
