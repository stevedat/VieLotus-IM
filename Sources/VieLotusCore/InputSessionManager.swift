import Foundation

/// Action to be taken by the Client (UI or Test Harness) after processing a key.
@frozen public enum SessionAction: Equatable {
    case passThrough             // Key wasn't handled, let system handle it
    case consumed                // Key was consumed internally
    case replace(backspaces: Int, text: String)  // Delete trailing chars and insert text
    case commit(backspaces: Int, text: String, isOverride: Bool)  // Commit a final word (override means it fell back to raw)
    case reset                   // Composition cancelled/reset
}

public class InputSessionManager {
    public static let caretDisarmed: Int = -999
    public let engine = EngineBridge()
    public var composingWord: String = ""
    public var rawWord: String = ""
    public var context: String = "" {
        didSet {
            invalidateSentenceStateCache()
            if !isAppendingCommittedContext {
                if context.isEmpty {
                    recentWords.removeAll(keepingCapacity: true)
                } else {
                    recentWords = context
                        .split(whereSeparator: \.isWhitespace)
                        .suffix(Self.maxRecentWords)
                        .map(String.init)
                }
                hasVietnameseInputEvidence = Self.containsVietnameseWord(context)
                hasLiteralRunSinceVietnamese = hasVietnameseInputEvidence &&
                    context.split(whereSeparator: \.isWhitespace).last.map {
                        $0.unicodeScalars.allSatisfy(\.isASCII) && !SmartBilingualDetector.isAllCapsAcronymToken(String($0))
                    } == true
            }
        }
    }

    private func syncContextFromRecentWords() {
        invalidateSentenceStateCache()
        isAppendingCommittedContext = true
        context = recentWords.joined(separator: " ")
        isAppendingCommittedContext = false
    }
    private var hasVietnameseInputEvidence = false
    private var hasLiteralRunSinceVietnamese = false
#if DEBUG
    public var debugVietnameseInputEvidence: Bool { hasVietnameseInputEvidence }
    public var debugLiteralRunSinceVietnamese: Bool { hasLiteralRunSinceVietnamese }
#endif
    private var isAppendingCommittedContext = false
    private static func containsVietnameseWord(_ text: String) -> Bool {
        guard text.unicodeScalars.contains(where: { !$0.isASCII }) else { return false }
        return text.split(whereSeparator: \.isWhitespace).contains { token in
            guard token.unicodeScalars.contains(where: { !$0.isASCII }) else { return false }
            let word = token.trimmingCharacters(in: .punctuationCharacters)
            return word.unicodeScalars.contains(where: { !$0.isASCII }) &&
                VietnameseSyllableDictionary.shared.isValidSyllable(word.lowercased())
        }
    }
    public var editCaretBack: Int = -1
    public var smartBilingualEnabled: Bool = true
    public var inlineBilingualEnabled: Bool = false
    public var bilingualNoContextPolicy: BilingualNoContextPolicy = .probabilisticBilingual
    public var genZMode: Bool = false
    public var hasExplicitAccentSelection: Bool = false
    public private(set) var explicitBilingualSelection: BilingualCandidateKind? = nil
    public private(set) var candidateProvenance: CompositionCandidateProvenance = .empty
    public private(set) var lastCommittedProvenance: CompositionCandidateProvenance = .empty
    private var provenanceHistory: [CompositionCandidateProvenance] = []
    public var sentenceLanguageState: SentenceLanguageState {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return cachedEvaluateSentenceLanguageState(context)
    }
    public private(set) var sessionGeneration: UInt64 = 0
    internal var pendingDotPrefix: (raw: String, rendered: String)? = nil
    internal var activeDotPrefix: (raw: String, rendered: String)? = nil
    internal var pendingSpacePrefix: (raw: String, rendered: String)? = nil
    internal var activeSpacePrefix: (raw: String, rendered: String)? = nil
    internal var precededByTechnicalDelimiter: Bool = false
    public var precededByLeadingSlash: Bool = false
    private let sessionLock = NSRecursiveLock()

    // MARK: - Per-Keystroke Sentence Language State Cache (iOS Latency Optimization)
    // `evaluateSentenceLanguageState` is called 3-4 times per keystroke from different paths.
    // Cache the result keyed on context string to avoid redundant computation within the same keystroke.
    private var cachedSentenceStateContext: String?
    private var cachedSentenceState: SentenceLanguageState?

    /// Returns the sentence language state for the given context, caching the result
    /// to avoid redundant computation within the same keystroke processing cycle.
    internal func cachedEvaluateSentenceLanguageState(_ ctx: String) -> SentenceLanguageState {
        if let cached = cachedSentenceState, cachedSentenceStateContext == ctx {
            return cached
        }
        let state = BilingualIntentArbiter.evaluateSentenceLanguageState(ctx)
        cachedSentenceStateContext = ctx
        cachedSentenceState = state
        return state
    }

    /// Invalidates the per-keystroke sentence language state cache.
    /// Called when context changes (appendContext, clearContext, popLastContextWord).
    private func invalidateSentenceStateCache() {
        cachedSentenceStateContext = nil
        cachedSentenceState = nil
    }

    private static let inlineDotSuffixTLDs: Set<String> = [
        "com", "net", "org", "edu", "gov", "app", "dev", "info", "tech",
        "pdf", "txt", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "png", "jpg", "jpeg", "gif", "webp", "svg", "mp3", "mp4", "mov",
        "zip", "rar", "tar", "json", "xml", "yml", "yaml", "csv",
        "html", "css", "tsx", "jsx", "swift", "php", "sql", "log", "env", "conf", "toml"
    ]

    private static let commitDotSuffixTLDs: Set<String> = inlineDotSuffixTLDs.union([
        "vn", "io", "ai", "co", "me", "uk", "us", "ca", "au", "de", "fr", "jp", "kr", "cn", "sg",
        "js", "ts", "py", "kt", "rs", "go", "rb", "sh", "md", "db", "gz", "ini", "cfg"
    ])

    /// Sentence-initial English determiners/possessives/copulas (`His`, `Her`, `This`, `Here`, `Is`, `Was`, `Car`)
    /// that must preserve Vietnamese (`Hí`, `Hẻ`, `Thí`, `Hể`, `Í`, `Ứa`, `Cả`) when typed as a single isolated word
    /// (`vn_survives_collision` / `whitelist_safe = never`), yet rarely stand alone before an English second word
    /// (`"This is..."`, `"His car is..."`, `"Her car is..."`, `"This car is..."`, `"Here is..."`, `"Is this..."`, `"Car is..."`).
    private static let sentenceInitialSpacePrefixStarters: Set<String> = [
        "his", "her", "this", "here", "is", "was", "car"
    ]

    /// Valid Vietnamese 2nd-syllable compound continuations after `"hí"` (`"his"`).
    /// Only diacritic Vietnamese continuations are included so English words starting with `"ha-"` (`"hat"`, `"hand"`, `"hair"`) never false-trigger.
    private static let vietnameseContinuationsAfterHi: Set<String> = [
        "hửng", "hoáy", "họa", "hoạ", "kịch", "trường", "viện", "hởn", "mắt", "mũi", "cước"
    ]

    /// Valid Vietnamese 2nd-syllable compound continuations after `"hẻ"` / `"hể"` (`"her"` / `"here"`).
    private static let vietnameseContinuationsAfterHe: Set<String> = [
        "hở", "hả", "lộ"
    ]

    /// Valid Vietnamese 2nd-syllable compound continuations after `"thí"` (`"this"`).
    private static let vietnameseContinuationsAfterThi: Set<String> = [
        "sinh", "nghiệm", "điểm", "dụ", "mạng", "tốt", "chủ", "cho", "pháp", "thực", "võ", "cô", "hồn"
    ]

    /// Valid Vietnamese 2nd-syllable continuations after `"í"` (`"is"`).
    private static let vietnameseContinuationsAfterI: Set<String> = [
        "ới", "a", "ẹ", "ỏi", "ở"
    ]

    /// Valid Vietnamese 2nd-syllable continuations after `"ứa"` (`"was"`).
    private static let vietnameseContinuationsAfterUa: Set<String> = [
        "nước", "máu", "lệ", "ra", "gan", "mật", "nhựa", "mồ"
    ]

    /// English copulas and modal auxiliaries that unambiguously confirm `"Car <verb>"` (`"Car is..."`, `"Car was..."`).
    private static let englishCopulasAndAuxiliariesAfterNoun: Set<String> = [
        "is", "was", "has", "had", "will", "can", "may", "must", "should", "would", "could", "are", "were"
    ]

    /// Common pure-ASCII English nouns/verbs after `His`/`Her`/`This`/`Is`/`Was` that share spelling with untoned Vietnamese syllables.
    private static let asciiEnglishSecondWordsAfterDeterminer: Set<String> = [
        "son", "man", "men", "can", "may", "fan", "van", "pan", "pen", "map", "hat", "cup", "plan"
    ]

    internal static func shouldArmSpacePrefix(raw: String, rendered: String) -> Bool {
        let lower = raw.lowercased()
        guard sentenceInitialSpacePrefixStarters.contains(lower) else { return false }
        if raw == rendered {
            // When `His`/`his` or `Her`/`her` committed as English, arm reverse Vietnamese compound lookback (`His hửng` -> `Hí hửng`).
            return lower == "his" || lower == "her"
        }
        if lower == "her" || lower == "his" || lower == "this" || lower == "here" {
            return true
        }
        return raw.first?.isUppercase == true
    }

    /// Returns the cased Vietnamese syllable (`"Hí"` / `"hí"`, `"Hẻ"` / `"hẻ"`) when Word #1 (`"His"`/`"his"` or `"Her"`/`"her"`)
    /// was committed as raw English (`prefixRaw == prefixRendered`) and Word #2 is an unambiguous Vietnamese compound continuation
    /// (`"hửng"`, `"hoáy"`, `"họa"`, `"kịch"`, `"trường"`, `"viện"`, `"hởn"`).
    internal static func vietnameseCompoundPrefixReplacement(
        prefixRaw: String,
        prefixRendered: String,
        secondRaw: String,
        secondRendered: String
    ) -> String? {
        guard prefixRaw == prefixRendered else { return nil }
        let lowerPrefix = prefixRaw.lowercased()
        let lowerSecondRendered = secondRendered.lowercased()
        guard !lowerSecondRendered.isEmpty,
              !lowerSecondRendered.unicodeScalars.allSatisfy(\.isASCII),
              !SmartBilingualDetector.isKnownEnglishWord(secondRaw.lowercased()) else {
            return nil
        }
        let targetLowerVN: String?
        switch lowerPrefix {
        case "his":
            targetLowerVN = vietnameseContinuationsAfterHi.contains(lowerSecondRendered) ? "hí" : nil
        case "her":
            targetLowerVN = (lowerSecondRendered == "hở") ? "hẻ" : nil
        default:
            targetLowerVN = nil
        }
        guard let vn = targetLowerVN else { return nil }
        if prefixRaw.count > 1 && prefixRaw == prefixRaw.uppercased() && prefixRaw != prefixRaw.lowercased() {
            return vn.uppercased()
        }
        if prefixRaw.first?.isUppercase == true, let first = vn.first {
            return String(first).uppercased() + vn.dropFirst()
        }
        return vn
    }

    internal static func shouldRestoreSpacePrefix(
        prefixRaw: String,
        prefixRendered: String,
        secondRaw: String,
        secondRendered: String
    ) -> Bool {
        let lowerPrefix = prefixRaw.lowercased()
        let lowerSecondRaw = secondRaw.lowercased()
        let lowerSecondRendered = secondRendered.lowercased()
        guard prefixRaw != prefixRendered,
              sentenceInitialSpacePrefixStarters.contains(lowerPrefix),
              secondRaw.count >= 2,
              secondRaw.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) }) else {
            return false
        }

        // Never restore if Word #2 is a valid Vietnamese syllable containing modified Vietnamese vowels/stroke (ă, â, ê, ô, ơ, ư, đ)
        let untonedSecond = VietnameseSyllableDictionary.stripToneMarks(lowerSecondRendered)
        if untonedSecond.contains(where: { "ăâêôơưđ".contains($0) }) &&
           VietnameseSyllableDictionary.shared.isValidSyllable(lowerSecondRendered) {
            return false
        }

        switch lowerPrefix {
        case "his":
            if vietnameseContinuationsAfterHi.contains(lowerSecondRendered) { return false }
        case "her", "here":
            if vietnameseContinuationsAfterHe.contains(lowerSecondRendered) { return false }
        case "this":
            if vietnameseContinuationsAfterThi.contains(lowerSecondRendered) { return false }
        case "is":
            if vietnameseContinuationsAfterI.contains(lowerSecondRendered) { return false }
        case "was":
            if vietnameseContinuationsAfterUa.contains(lowerSecondRendered) { return false }
        case "car":
            if englishCopulasAndAuxiliariesAfterNoun.contains(lowerSecondRaw) {
                return true
            }
            return SmartBilingualDetector.isKnownEnglishWord(lowerSecondRaw) &&
                !VietnameseSyllableDictionary.shared.isValidSyllable(lowerSecondRendered)
        default:
            break
        }

        guard SmartBilingualDetector.isKnownEnglishWord(lowerSecondRaw) else {
            return false
        }
        if lowerSecondRaw != lowerSecondRendered {
            return true
        }
        if !VietnameseSyllableDictionary.shared.isValidSyllable(lowerSecondRendered) {
            return true
        }
        return asciiEnglishSecondWordsAfterDeterminer.contains(lowerSecondRaw)
    }

    public var isComposing: Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return engine.isComposing
    }

    public init() {}

    public func isCurrentGeneration(_ generation: UInt64) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return sessionGeneration == generation
    }

    @discardableResult
    public func advanceSessionGeneration() -> UInt64 {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        sessionGeneration &+= 1
        return sessionGeneration
    }

    public func reset() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        engine.reset()
        composingWord = ""
        rawWord = ""
        hasExplicitAccentSelection = false
        explicitBilingualSelection = nil
        candidateProvenance = .empty
        provenanceHistory.removeAll(keepingCapacity: true)
        pendingDotPrefix = nil
        activeDotPrefix = nil
        pendingSpacePrefix = nil
        activeSpacePrefix = nil
        precededByTechnicalDelimiter = false
        precededByLeadingSlash = false
        editCaretBack = -1
        sessionGeneration &+= 1
    }

    public func stepCaretBack() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        pendingDotPrefix = nil
        activeDotPrefix = nil
        pendingSpacePrefix = nil
        activeSpacePrefix = nil
        precededByTechnicalDelimiter = false
        precededByLeadingSlash = false
        if engine.isComposing {
            let engineOut = engine.currentOutput()
            let output = composingWord.isEmpty ? engineOut : composingWord
            let savedRaw = rawWord.isEmpty ? output : rawWord
            engine.commitWord(raw: savedRaw, rendered: output)
            composingWord = ""
            rawWord = ""
            hasExplicitAccentSelection = false
            explicitBilingualSelection = nil
            editCaretBack = 1
            sessionGeneration &+= 1
            return
        }
        if editCaretBack >= -1 && editCaretBack < 255 {
            editCaretBack += 1
        }
    }

    public func stepCaretForward() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        pendingDotPrefix = nil
        activeDotPrefix = nil
        precededByTechnicalDelimiter = false
        precededByLeadingSlash = false
        if engine.isComposing {
            let engineOut = engine.currentOutput()
            let output = composingWord.isEmpty ? engineOut : composingWord
            let savedRaw = rawWord.isEmpty ? output : rawWord
            engine.commitWord(raw: savedRaw, rendered: output)
            composingWord = ""
            rawWord = ""
            hasExplicitAccentSelection = false
            explicitBilingualSelection = nil
            editCaretBack = Self.caretDisarmed
            sessionGeneration &+= 1
            return
        }
        if editCaretBack >= 0 {
            editCaretBack -= 1
        } else {
            editCaretBack = Self.caretDisarmed
        }
    }

    public func resetCaret() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        pendingDotPrefix = nil
        activeDotPrefix = nil
        precededByTechnicalDelimiter = false
        precededByLeadingSlash = false
        editCaretBack = -1
    }

    public func setCompositionPrefix(_ text: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        pendingDotPrefix = nil
        activeDotPrefix = nil
        precededByTechnicalDelimiter = false
        precededByLeadingSlash = false
        explicitBilingualSelection = nil
        engine.setCompositionPrefix(text)
        composingWord = text
        rawWord = engine.rawString()
        editCaretBack = -1
        sessionGeneration &+= 1
    }

    /// Explicitly locks the active composition to either its raw English literal (`"mix"`, `"of"`, `"or"`)
    /// or its Vietnamese Telex candidate (`"mĩ"`, `"ò"`, `"ỏ"`) without committing a boundary space (P0.7 Section 2 & 3).
    /// - After selecting Vietnamese (`"mĩ"`, `"ò"`), pressing the repeated tone key (`x`, `f`) performs Semantic Tone Escape (`"mix"`, `"of"`),
    ///   and subsequent vowels remain on the Vietnamese syllable (`"mĩ" + "i" -> "mĩi"`).
    /// - After selecting English (`"or"`, `"mix"`, `"of"`), subsequent keys append literally (`"or" + "m" -> "orm"`, `"mix" + "x" -> "mixx"`).
    public func selectCompositionCandidate(_ candidate: String) -> SessionAction {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard isComposing, !candidate.isEmpty else {
            return .passThrough
        }
        let priorComposingWord = composingWord
        let priorProvenance = candidateProvenance
        if !rawWord.isEmpty && candidate.lowercased() == rawWord.lowercased() {
            explicitBilingualSelection = .rawLiteral
            engine.forceLiteralOutput(candidate)
            composingWord = candidate
        } else {
            explicitBilingualSelection = .vietnameseTelex
            if engine.currentOutput().lowercased() != candidate.lowercased() {
                let savedRaw = rawWord
                if !savedRaw.isEmpty {
                    engine.reset()
                    for ch in savedRaw {
                        _ = engine.feed(ch)
                    }
                }
                if engine.currentOutput().lowercased() != candidate.lowercased() {
                    engine.reset()
                    let synthRaw = VietnameseEngine.rawKeys(for: candidate, inputMethod: engine.inputMethod)
                    for ch in synthRaw {
                        _ = engine.feed(ch)
                    }
                    rawWord = engine.rawString()
                }
            }
            composingWord = candidate
        }
        updateCandidateProvenance(
            rawWord: rawWord,
            engineOutput: engine.currentOutput(),
            selectedCandidate: composingWord,
            priorProvenance: priorProvenance,
            wasLiteralLockedStep: false
        )
        let diff = Self.computeUTF16Diff(oldStr: priorComposingWord, newStr: composingWord)
        return .replace(backspaces: diff.backspaces, text: diff.suffix)
    }

    public func currentOutput() -> String {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if !composingWord.isEmpty { return composingWord }
        return engine.currentOutput()
    }

    public var inputMethod: InputMethodType {
        engine.inputMethod
    }

    public func setInputMethod(_ method: InputMethodType) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard engine.inputMethod != method else { return }
        engine.setInputMethod(method)
        composingWord = ""
        rawWord = ""
        hasExplicitAccentSelection = false
        explicitBilingualSelection = nil
        candidateProvenance = .empty
        pendingDotPrefix = nil
        activeDotPrefix = nil
        pendingSpacePrefix = nil
        activeSpacePrefix = nil
        precededByTechnicalDelimiter = false
        precededByLeadingSlash = false
        editCaretBack = -1
        sessionGeneration &+= 1
    }

    public var grammarProfile: GrammarProfile {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return engine.grammarProfile
    }

    public func setGrammarProfile(_ profile: GrammarProfile) {
        engine.setGrammarProfile(profile)
    }

    public func setModernOrthography(_ enabled: Bool) {
        engine.setModernOrthography(enabled)
    }

    public func setRelaxedCoda(_ enabled: Bool) {
        engine.setRelaxedCoda(enabled)
    }

    public func setQuickTelex(_ enabled: Bool) {
        engine.setQuickTelex(enabled)
    }

    public func setGenZMode(_ enabled: Bool) {
        self.genZMode = enabled
        engine.setGenZMode(enabled)
    }

    public func setSmartBilingualEnabled(_ enabled: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        self.smartBilingualEnabled = enabled
    }

    public func setQuickStart(_ enabled: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        engine.setQuickStart(enabled)
    }

    public var simpleTelex: Bool {
        get {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            return engine.simpleTelex
        }
        set {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            engine.simpleTelex = newValue
        }
    }

    public func setSimpleTelex(_ enabled: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        engine.setSimpleTelex(enabled)
    }

    /// Controls active composition Backspace behavior (`.appleSemantic` default vs `.gboardCharacter`).
    public var backspaceStyle: BackspaceStyle {
        get {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            return engine.backspaceStyle
        }
        set {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            engine.backspaceStyle = newValue
        }
    }

    public func setBackspaceStyle(_ style: BackspaceStyle) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        engine.setBackspaceStyle(style)
    }

    /// Controls Explicit Literal Intent (`Literal Override` / `ABC` mode) in Core.
    /// When enabled, incoming characters are appended literally without Telex/VNI transformation.
    public var literalOverrideEnabled: Bool {
        get {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            return engine.literalOverrideEnabled
        }
        set {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            engine.literalOverrideEnabled = newValue
        }
    }

    public func setLiteralOverride(_ enabled: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        engine.literalOverrideEnabled = enabled
    }

    public var lastPostCommitEditTransaction: PostCommitEditTransaction? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return engine.lastPostCommitEditTransaction
    }

    /// True if the most recent `handleCharacter(_:)` call was rejected as a no-op by the Strict Vietnamese Guard.
    public var lastFeedWasRejectedNoOp: Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return engine.lastFeedWasRejectedNoOp
    }

    /// Inserts a character literally into the active composition without Telex/VNI transformation
    /// (Invariant 4: Explicit Literal Intent, e.g. long-press literal insertion or `ABC` override).
    public func handleLiteralCharacter(_ char: Character) -> SessionAction {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        pendingDotPrefix = nil
        activeDotPrefix = nil
        pendingSpacePrefix = nil
        activeSpacePrefix = nil
        if !engine.isComposing {
            sessionGeneration &+= 1
        }
        editCaretBack = Self.caretDisarmed
        let priorComposingWord = composingWord
        if let _ = engine.feedLiteral(char) {
            hasExplicitAccentSelection = true
            rawWord = engine.rawString()
            let targetComposingWord = engine.currentOutput()
            composingWord = targetComposingWord
            let screenDiff = Self.computeUTF16Diff(oldStr: priorComposingWord, newStr: targetComposingWord)
            return .replace(backspaces: screenDiff.backspaces, text: screenDiff.suffix)
        }
        rawWord.append(char)
        return .passThrough
    }

    public var recentWords: [String] = []
    private static let maxRecentWords = 32

    public func clearContext() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        recentWords.removeAll(keepingCapacity: true)
        hasVietnameseInputEvidence = false
        hasLiteralRunSinceVietnamese = false
        invalidateSentenceStateCache()
        context = ""
        pendingDotPrefix = nil
        activeDotPrefix = nil
        pendingSpacePrefix = nil
        activeSpacePrefix = nil
        precededByTechnicalDelimiter = false
        sessionGeneration &+= 1
    }

    public func appendContext(_ word: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let earlierVietnameseEvidence = hasVietnameseInputEvidence
        recentWords.append(trimmed)
        if recentWords.count > Self.maxRecentWords {
            recentWords.removeFirst(recentWords.count - Self.maxRecentWords)
        }
        invalidateSentenceStateCache()
        isAppendingCommittedContext = true
        context = recentWords.joined(separator: " ")
        isAppendingCommittedContext = false
        let vietnameseWord = Self.containsVietnameseWord(trimmed)
        hasVietnameseInputEvidence = earlierVietnameseEvidence || vietnameseWord
        if vietnameseWord { hasLiteralRunSinceVietnamese = false }
        else if earlierVietnameseEvidence && trimmed.unicodeScalars.allSatisfy(\.isASCII) &&
                    !SmartBilingualDetector.isAllCapsAcronymToken(trimmed) {
            hasLiteralRunSinceVietnamese = true
        }
    }

    public func popLastContextWord() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard !recentWords.isEmpty else { return }
        recentWords.removeLast()
        invalidateSentenceStateCache()
        isAppendingCommittedContext = true
        context = recentWords.joined(separator: " ")
        isAppendingCommittedContext = false
        if recentWords.isEmpty {
            hasVietnameseInputEvidence = false
            hasLiteralRunSinceVietnamese = false
        } else if Self.containsVietnameseWord(recentWords.last ?? "") {
            hasLiteralRunSinceVietnamese = false
        }
    }

    /// Evaluates if a character acts as a word boundary
    public func isWordBoundary(_ char: Character) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let isBoundary: Bool
        if char == " " || char.isNewline || ".,;:!?\"'()[]{}<>-%/".contains(char) {
            isBoundary = true
        } else if char.isNumber && (engine.inputMethod != .vni || (!engine.isComposing && (editCaretBack < 0 || engine.lastCommittedWord == nil))) {
            isBoundary = true
        } else {
            isBoundary = false
        }
        if isBoundary && !engine.isComposing {
            pendingDotPrefix = nil
            activeDotPrefix = nil
            pendingSpacePrefix = nil
            activeSpacePrefix = nil
            precededByTechnicalDelimiter = MacroEngine.isTechnicalDelimiter(char)
            precededByLeadingSlash = (char == "/")
        }
        return isBoundary
    }

    /// Processes a single character feed
    public func handleCharacter(_ char: Character) -> SessionAction {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let wasComposing = engine.isComposing
        if !wasComposing {
            sessionGeneration &+= 1
        }
        var dotRestorePrefix: (backspaces: Int, rawPrefix: String)? = nil
        if !wasComposing, let dotPrefix = pendingDotPrefix {
            pendingDotPrefix = nil
            if char.isASCII && char.isLetter {
                if dotPrefix.raw != dotPrefix.rendered && SmartBilingualDetector.isKnownEnglishWord(dotPrefix.raw) {
                    dotRestorePrefix = (backspaces: dotPrefix.rendered.utf16.count + 1, rawPrefix: dotPrefix.raw + ".")
                    if !recentWords.isEmpty {
                        recentWords[recentWords.count - 1] = dotPrefix.raw
                        syncContextFromRecentWords()
                    }
                    activeDotPrefix = dotPrefix
                } else {
                    activeDotPrefix = dotPrefix
                }
            } else {
                activeDotPrefix = nil
            }
        } else if !wasComposing {
            activeDotPrefix = nil
        }
        if !wasComposing, let spacePrefix = pendingSpacePrefix {
            pendingSpacePrefix = nil
            if char.isASCII && char.isLetter {
                activeSpacePrefix = spacePrefix
            } else {
                activeSpacePrefix = nil
            }
        } else if !wasComposing {
            activeSpacePrefix = nil
        }
        var isEditing = false
        let priorCommittedWasASCII = (engine.lastCommittedWord?.allSatisfy(\.isASCII) ?? true)
        var feedResult: (backspaces: Int, suffix: String)? = nil

        if engine.literalOverrideEnabled {
            editCaretBack = Self.caretDisarmed
            hasExplicitAccentSelection = true
            feedResult = engine.feed(char)
        } else if !wasComposing && editCaretBack >= 0 && dotRestorePrefix == nil {
            if let diff = engine.editAt(caretBack: editCaretBack, char: char) {
                isEditing = true
                feedResult = diff
                editCaretBack = Self.caretDisarmed
                if !recentWords.isEmpty {
                    recentWords.removeLast()
                    syncContextFromRecentWords()
                }
            } else {
                engine.reset()
                editCaretBack = Self.caretDisarmed
                feedResult = engine.feed(char)
            }
        } else {
            editCaretBack = Self.caretDisarmed
            feedResult = engine.feed(char)
        }

        if let diff = feedResult {
            let priorRawWord = rawWord
            let priorComposingWord = composingWord
            let priorProvenance = candidateProvenance
            if isEditing {
                rawWord = engine.rawString()
                var targetComposingWord = engine.currentOutput()
                if !priorCommittedWasASCII && !targetComposingWord.allSatisfy(\.isASCII) {
                    explicitBilingualSelection = .vietnameseTelex
                } else if priorCommittedWasASCII && inlineBilingualEnabled && smartBilingualEnabled && rawWord.count >= 2 && rawWord.lowercased() != targetComposingWord.lowercased() &&
                   SmartBilingualDetector.isInlineEnglishWord(raw: rawWord, rendered: targetComposingWord, context: context, genZMode: genZMode) {
                    targetComposingWord = rawWord
                }
                composingWord = targetComposingWord
                updateCandidateProvenance(
                    rawWord: rawWord,
                    engineOutput: engine.currentOutput(),
                    selectedCandidate: targetComposingWord,
                    priorProvenance: priorProvenance,
                    wasLiteralLockedStep: false
                )
                return .replace(backspaces: diff.backspaces, text: targetComposingWord)
            } else {
                rawWord = engine.rawString()
            }

            // Visual logic with UTF-16 code unit precision against actual on-screen composingWord
            var targetComposingWord = engine.currentOutput()
            var wasLiteralLockedStep = false

            if targetComposingWord.isEmpty {
                engine.reset()
                rawWord = ""
                composingWord = ""
                hasExplicitAccentSelection = false
                explicitBilingualSelection = nil
                candidateProvenance = .empty
                provenanceHistory.removeAll(keepingCapacity: true)
                pendingDotPrefix = nil
                activeDotPrefix = nil
                pendingSpacePrefix = nil
                activeSpacePrefix = nil
                editCaretBack = Self.caretDisarmed
                sessionGeneration &+= 1
                if !diff.suffix.isEmpty {
                    return .replace(backspaces: 0, text: diff.suffix)
                }
                return .replace(backspaces: priorComposingWord.utf16.count, text: "")
            }

            if activeDotPrefix == nil &&
               activeSpacePrefix == nil &&
               dotRestorePrefix == nil &&
               engine.renderedOutputIsASCII &&
               priorComposingWord == priorRawWord &&
               targetComposingWord == rawWord &&
               rawWord.utf8.count == priorRawWord.utf8.count + 1 {
                if engine.isExplicitlyLiteralLocked {
                    composingWord = rawWord
                    let sentenceState = (!priorProvenance.rawCandidate.isEmpty && priorProvenance.context == context)
                        ? priorProvenance.sentenceLanguageState
                        : cachedEvaluateSentenceLanguageState(context)
                    let selectedKind: BilingualCandidateKind = hasExplicitAccentSelection ? .explicitEscapeOrSelected : .rawLiteral
                    let reason: CandidateSelectionReason = hasExplicitAccentSelection ? .userSelectedSuggestion : .explicitLiteralOverride
                    let nextProvenance = CompositionCandidateProvenance(
                        rawCandidate: rawWord,
                        vietnameseCandidate: rawWord,
                        selectedCandidate: rawWord,
                        selectedKind: selectedKind,
                        selectionReason: reason,
                        explicitEscapeState: .literalLockedAfterSelection,
                        selectionStability: .explicitEscape,
                        toneSemanticEvent: nil,
                        semanticTransformations: [],
                        literalSuffix: "",
                        flipCount: priorProvenance.flipCount,
                        stabilityMargin: 100.0,
                        context: context,
                        sentenceLanguageState: sentenceState,
                        transitionReason: "escaped(literalLockedAfterSelection)"
                    )
                    candidateProvenance = nextProvenance
                    provenanceHistory.append(nextProvenance)
                    return .replace(backspaces: 0, text: String(char))
                }
                if !hasExplicitAccentSelection &&
                   explicitBilingualSelection == nil &&
                   !Self.mayBeMixedCaseCompoundCandidate(rawWord) &&
                   Self.computeNaiveVietnameseCandidate(raw: rawWord, engineOutput: targetComposingWord) == targetComposingWord {
                    composingWord = rawWord
                    let sentenceState = (!priorProvenance.rawCandidate.isEmpty && priorProvenance.context == context)
                        ? priorProvenance.sentenceLanguageState
                        : cachedEvaluateSentenceLanguageState(context)
                    let transition = priorProvenance.rawCandidate.isEmpty
                        ? "initial(asciiPassThrough)"
                        : "retained(asciiPassThrough)"
                    let nextProvenance = CompositionCandidateProvenance(
                        rawCandidate: rawWord,
                        vietnameseCandidate: rawWord,
                        selectedCandidate: rawWord,
                        selectedKind: .vietnameseTelex,
                        selectionReason: .asciiPassThrough,
                        explicitEscapeState: .none,
                        selectionStability: .provisional,
                        toneSemanticEvent: nil,
                        semanticTransformations: [],
                        literalSuffix: "",
                        flipCount: priorProvenance.flipCount,
                        stabilityMargin: 0.0,
                        context: context,
                        sentenceLanguageState: sentenceState,
                        transitionReason: transition
                    )
                    candidateProvenance = nextProvenance
                    provenanceHistory.append(nextProvenance)
                    return .replace(backspaces: 0, text: String(char))
                }
            }

            // Never allow a subsequent keystroke to strip explicit long-press diacritics back to raw ASCII
            // or strip an explicitly long-pressed vowel shape (e.g. `ế` + `e` -> `ếe`, `đ` + `d` -> `dd`, or `ế` + `k` -> `eesk`).
            if hasExplicitAccentSelection && !priorComposingWord.allSatisfy(\.isASCII) {
                let priorUntonedLower = VietnameseSyllableDictionary.stripToneMarks(priorComposingWord.lowercased())
                let targetUntonedLower = VietnameseSyllableDictionary.stripToneMarks(targetComposingWord.lowercased())
                let strippedExplicitVowelShape = priorUntonedLower.contains(where: { "ăâêôơư".contains($0) }) &&
                    !targetUntonedLower.contains(where: { "ăâêôơư".contains($0) })
                if targetComposingWord.allSatisfy(\.isASCII) || strippedExplicitVowelShape {
                    appendContext(priorComposingWord)
                    engine.commitWord(raw: priorComposingWord, rendered: priorComposingWord)
                    engine.reset()
                    hasExplicitAccentSelection = false
                    explicitBilingualSelection = nil
                    candidateProvenance = .empty
                    provenanceHistory.removeAll(keepingCapacity: true)
                    pendingDotPrefix = nil
                    activeDotPrefix = nil
                    editCaretBack = Self.caretDisarmed
                    sessionGeneration &+= 1
                    if let _ = engine.feed(char) {
                        let nextOut = engine.currentOutput()
                        rawWord = String(char)
                        composingWord = nextOut.isEmpty ? String(char) : nextOut
                        updateCandidateProvenance(
                            rawWord: rawWord,
                            engineOutput: nextOut,
                            selectedCandidate: composingWord,
                            priorProvenance: .empty,
                            wasLiteralLockedStep: false
                        )
                        return .replace(backspaces: 0, text: composingWord)
                    } else {
                        rawWord = ""
                        composingWord = ""
                        return .replace(backspaces: 0, text: String(char))
                    }
                }
            }

            let resolved = resolvePostFeedCandidate(
                priorRawWord: priorRawWord,
                priorOnScreenWord: priorComposingWord,
                priorProvenance: priorProvenance,
                rawWord: rawWord,
                engineOutput: targetComposingWord,
                smartBilingualEnabled: smartBilingualEnabled,
                forceInlineEvaluation: inlineBilingualEnabled,
                genZMode: genZMode
            )
            targetComposingWord = resolved.selectedCandidate
            wasLiteralLockedStep = resolved.wasLiteralLockedStep

            if let dotPrefix = activeDotPrefix,
               Self.inlineDotSuffixTLDs.contains(rawWord.lowercased()) {
                // Keep dot context through commit. The prefix is now literal on screen,
                // so subsequent suffix keys must not restore its old rendered form again.
                activeDotPrefix = (raw: dotPrefix.raw, rendered: dotPrefix.raw)
                targetComposingWord = rawWord
                composingWord = targetComposingWord
                updateCandidateProvenance(
                    rawWord: rawWord,
                    engineOutput: engine.currentOutput(),
                    selectedCandidate: targetComposingWord,
                    priorProvenance: priorProvenance,
                    wasLiteralLockedStep: wasLiteralLockedStep
                )
                if dotPrefix.raw != dotPrefix.rendered {
                    if !recentWords.isEmpty {
                        recentWords[recentWords.count - 1] = dotPrefix.raw
                        syncContextFromRecentWords()
                    }
                    let totalBackspaces = dotPrefix.rendered.utf16.count + 1 + priorComposingWord.utf16.count
                    return .replace(backspaces: totalBackspaces, text: dotPrefix.raw + "." + targetComposingWord)
                }
            }

            if let spacePrefix = activeSpacePrefix {
                if smartBilingualEnabled &&
                   inlineBilingualEnabled &&
                   !hasExplicitAccentSelection &&
                   explicitBilingualSelection != .vietnameseTelex &&
                   spacePrefix.raw != spacePrefix.rendered &&
                   targetComposingWord == rawWord &&
                   Self.shouldRestoreSpacePrefix(
                       prefixRaw: spacePrefix.raw,
                       prefixRendered: spacePrefix.rendered,
                       secondRaw: rawWord,
                       secondRendered: engine.currentOutput()
                   ) {
                    activeSpacePrefix = (raw: spacePrefix.raw, rendered: spacePrefix.raw)
                    if !recentWords.isEmpty {
                        recentWords[recentWords.count - 1] = spacePrefix.raw
                        syncContextFromRecentWords()
                        hasVietnameseInputEvidence = recentWords.contains(where: { Self.containsVietnameseWord($0) })
                    }
                    composingWord = targetComposingWord
                    updateCandidateProvenance(
                        rawWord: rawWord,
                        engineOutput: engine.currentOutput(),
                        selectedCandidate: targetComposingWord,
                        priorProvenance: priorProvenance,
                        wasLiteralLockedStep: wasLiteralLockedStep
                    )
                    let totalBackspaces = spacePrefix.rendered.utf16.count + 1 + priorComposingWord.utf16.count
                    return .replace(backspaces: totalBackspaces, text: spacePrefix.raw + " " + targetComposingWord)
                }
                if smartBilingualEnabled &&
                   !hasExplicitAccentSelection &&
                   explicitBilingualSelection != .rawLiteral,
                   let vnPrefix = Self.vietnameseCompoundPrefixReplacement(
                       prefixRaw: spacePrefix.raw,
                       prefixRendered: spacePrefix.rendered,
                       secondRaw: rawWord,
                       secondRendered: targetComposingWord
                   ) {
                    activeSpacePrefix = (raw: spacePrefix.raw, rendered: vnPrefix)
                    if !recentWords.isEmpty {
                        recentWords[recentWords.count - 1] = vnPrefix
                        syncContextFromRecentWords()
                        hasVietnameseInputEvidence = true
                    }
                    composingWord = targetComposingWord
                    updateCandidateProvenance(
                        rawWord: rawWord,
                        engineOutput: engine.currentOutput(),
                        selectedCandidate: targetComposingWord,
                        priorProvenance: priorProvenance,
                        wasLiteralLockedStep: wasLiteralLockedStep
                    )
                    let totalBackspaces = spacePrefix.rendered.utf16.count + 1 + priorComposingWord.utf16.count
                    return .replace(backspaces: totalBackspaces, text: vnPrefix + " " + targetComposingWord)
                }
            }

            composingWord = targetComposingWord
            updateCandidateProvenance(
                rawWord: rawWord,
                engineOutput: engine.currentOutput(),
                selectedCandidate: targetComposingWord,
                priorProvenance: priorProvenance,
                wasLiteralLockedStep: wasLiteralLockedStep
            )
            if let dotRestore = dotRestorePrefix {
                return .replace(backspaces: dotRestore.backspaces + priorComposingWord.utf16.count, text: dotRestore.rawPrefix + targetComposingWord)
            }
            let screenDiff = Self.computeUTF16Diff(oldStr: priorComposingWord, newStr: targetComposingWord)
            return .replace(backspaces: screenDiff.backspaces, text: screenDiff.suffix)
        } else {
            pendingDotPrefix = nil
            activeDotPrefix = nil
            pendingSpacePrefix = nil
            activeSpacePrefix = nil
            rawWord.append(char)
            return .passThrough
        }
    }

    /// Once this document/session has demonstrated Vietnamese input, English
    /// momentum alone must not lock the next valid toned syllable into raw mode.
    /// Use the existing word-local arbiter, not phrase exceptions or a new lock.
    private func mixedInputPrefersVietnamese(raw: String, rendered: String) -> Bool? {
        guard hasVietnameseInputEvidence, hasLiteralRunSinceVietnamese, raw == raw.lowercased(),
              raw != rendered, rendered.unicodeScalars.contains(where: { !$0.isASCII }),
              VietnameseSyllableDictionary.shared.isValidSyllable(rendered),
              !SmartBilingualDetector.isExplicitTelexEscape(raw: raw, rendered: rendered),
              !SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: raw, rendered: rendered) else { return nil }
        // General English coordination evidence: preserve a recognized plural
        // following another recognized plural (with an optional coordinator).
        // This uses morphology + lexical membership, not a phrase whitelist.
        let tokens = context.lowercased().split(whereSeparator: \.isWhitespace).suffix(2)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        let coordinators: Set<String> = ["and", "or", "versus", "vs"]
        let preceding = tokens.last.flatMap { coordinators.contains($0) ? tokens.dropLast().last : $0 }
        if raw.hasSuffix("s"), let preceding, preceding.hasSuffix("s"),
           EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(raw),
           EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(String(raw.dropLast())),
           EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(preceding),
           EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(String(preceding.dropLast())) {
            return false
        }
        let local = BilingualIntentArbiter.arbitrate(
            raw: raw, rendered: rendered, context: "", noContextPolicy: bilingualNoContextPolicy,
            hasExplicitUserSelection: false, precededByTechnicalDelimiter: false,
            isInlineComposition: true, genZMode: genZMode)
        let enFrequency = local.candidates.first(where: { $0.kind == .rawLiteral })?.enLexicalFrequency ?? 0
        let vnFrequency = local.candidates.first(where: { $0.kind == .vietnameseTelex })?.vnLexicalFrequency ?? 0
        if enFrequency > vnFrequency && SmartBilingualDetector.isKnownEnglishWord(raw) {
            return SmartBilingualDetector.isConfidentEnglishContextForArbiter(context) ||
                cachedEvaluateSentenceLanguageState(context).momentum == .english ? false : nil
        }
        guard VietnameseSyllableDictionary.hasToneMark(rendered), !local.prefersRawEnglish else { return nil }
        if SmartBilingualDetector.isKnownEnglishWord(raw) {
            let contextual = BilingualIntentArbiter.arbitrate(
                raw: raw, rendered: rendered, context: context, noContextPolicy: bilingualNoContextPolicy,
                hasExplicitUserSelection: false, precededByTechnicalDelimiter: false,
                isInlineComposition: true, genZMode: genZMode)
            // Respect existing strong collocation evidence, not generic English momentum.
            if (contextual.candidates.first(where: { $0.kind == .rawLiteral })?.collocationScore ?? 0) >= 5 { return nil }
        }
        return true
    }

    private static let archiveFormats: Set<String> = ["rar", "tar", "zip"]

    private func shouldPreserveTechnicalToken(_ rawWord: String, followsDot: Bool) -> Bool {
        let lower = rawWord.lowercased()
        if followsDot && Self.inlineDotSuffixTLDs.contains(lower) {
            return true
        }
        return Self.archiveFormats.contains(lower) &&
            context.lowercased().split(whereSeparator: \.isWhitespace).suffix(3).elementsEqual(["convert", "it", "to"])
    }

    /// Unified single-authority post-feed candidate resolver shared across `InputSessionManager`, `UIKitInputSessionAdapter`,
    /// and `VieLotusIMController` (P0.7 Section 2, 3 & 5).
    /// Distinguishes:
    /// - Explicit selection (`selectCompositionCandidate("or") + m -> "orm"` vs `selectCompositionCandidate("mĩ") + x -> "mix"`),
    /// - Auto-selected English literal continuation (`mix + x -> mixx`, `of + f -> off`, `fee + e -> feee`),
    /// - Intentional Vietnamese tone escape (`ò + f -> of`, `mĩ + x -> mix`),
    /// - Provisional English yielding to valid delayed Vietnamese (`or -> orm -> ỏm`, `is -> ist -> ít`, `awe -> aweeoo -> ăeeoo`)
    ///   without mid-word flipping on English stems (`mixer`, `mixed`, `order`, `organ`, `offer`, `issue`).
    public func resolvePostFeedCandidate(
        priorRawWord: String,
        priorOnScreenWord: String,
        priorProvenance: CompositionCandidateProvenance,
        rawWord: String,
        engineOutput: String,
        smartBilingualEnabled: Bool? = nil,
        forceInlineEvaluation: Bool = false,
        genZMode: Bool? = nil,
        followsDot: Bool = false
    ) -> (selectedCandidate: String, wasLiteralLockedStep: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        if explicitBilingualSelection == .rawLiteral {
            engine.forceLiteralOutput(rawWord)
            return (rawWord, true)
        }
        if explicitBilingualSelection == .vietnameseTelex {
            return (engineOutput, false)
        }

        let effectiveBilingual = smartBilingualEnabled ?? self.smartBilingualEnabled
        if effectiveBilingual && shouldPreserveTechnicalToken(rawWord, followsDot: followsDot) {
            return (rawWord, false)
        }
        if effectiveBilingual,
           !hasExplicitAccentSelection,
           let mixedCompound = resolveMixedCaseCompoundUnlocked(
               rawWord: rawWord,
               wholeRendered: engineOutput,
               smartBilingualEnabled: effectiveBilingual,
               followsDot: followsDot
           ) {
            return (mixedCompound, false)
        }
        let effectiveInline = forceInlineEvaluation || self.inlineBilingualEnabled
        let checkedMixedInput = effectiveBilingual && effectiveInline && !hasExplicitAccentSelection && !followsDot && !precededByTechnicalDelimiter && activeDotPrefix == nil
        if effectiveBilingual {
            if let rawPreferred = SmartBilingualDetector.functionTokenPrefersRaw(
                rawWord, context: context, technical: followsDot || precededByTechnicalDelimiter || activeDotPrefix != nil) {
                return (rawPreferred ? rawWord : engineOutput, false)
            }
            if checkedMixedInput,
               let preferVN = mixedInputPrefersVietnamese(raw: rawWord, rendered: engineOutput) {
                return (preferVN ? engineOutput : rawWord, false)
            }
            if !effectiveInline && SmartBilingualDetector.isEnglishCompound(raw: rawWord, rendered: engineOutput) {
                return (rawWord, false)
            }
        }
        let lowerPriorRaw = priorRawWord.lowercased()
        let isRepeatedTrailingKey =
            !priorRawWord.isEmpty &&
            rawWord.last?.lowercased() == priorRawWord.last?.lowercased()
        let wasAlreadyLiteralSelected =
            (priorProvenance.selectedKind == .rawLiteral ||
             priorProvenance.explicitEscapeState == .literalLockedAfterSelection) &&
            priorProvenance.selectedCandidate.lowercased() == priorProvenance.rawCandidate.lowercased() &&
            (priorRawWord.count >= 3 || rawWord.lowercased() == "off" || rawWord.lowercased() == "err") &&
            isRepeatedTrailingKey &&
            lowerPriorRaw != "gree" &&
            (priorProvenance.explicitEscapeState == .literalLockedAfterSelection ||
             lowerPriorRaw.contains(where: { "_/\\.:[]{}<>=+*@#$%^&|".contains($0) }) ||
             SmartBilingualDetector.isKnownEnglishWord(priorProvenance.rawCandidate) ||
             BilingualIntentArbiter.englishCollisionLogFrequencies[lowerPriorRaw] != nil)
        if wasAlreadyLiteralSelected &&
           !priorOnScreenWord.isEmpty &&
           engineOutput.lowercased() == priorOnScreenWord.lowercased() &&
           rawWord.count == priorRawWord.count + 1 {
            engine.forceLiteralOutput(rawWord)
            return (rawWord, true)
        }

        let priorWasIntentionalVietnameseOnDefaultEnglishToken =
            priorProvenance.selectedKind == .vietnameseTelex &&
            !priorProvenance.selectedCandidate.unicodeScalars.allSatisfy(\.isASCII) &&
            rawWord.count == priorProvenance.rawCandidate.count + 1 &&
            BilingualIntentArbiter.prefersEnglishInDefaultNoContext(
                lowerRaw: priorProvenance.rawCandidate.lowercased(),
                lowerRendered: priorProvenance.vietnameseCandidate.lowercased()
            )
        if priorWasIntentionalVietnameseOnDefaultEnglishToken &&
           !VietnameseSyllableDictionary.hasToneMark(engineOutput) &&
           engine.lastToneSemanticEvent == .cancelToneAndEmitLiteral {
            return (engineOutput, false)
        }

        if effectiveBilingual &&
           effectiveInline &&
           !hasExplicitAccentSelection &&
           priorProvenance.selectedKind == .rawLiteral &&
           priorProvenance.selectionStability == .provisional &&
           priorProvenance.rawCandidate == priorRawWord &&
           rawWord.lowercased() != engineOutput.lowercased() &&
           !SmartBilingualDetector.isExplicitTelexEscape(raw: rawWord, rendered: engineOutput) &&
           !SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: rawWord, rendered: engineOutput) {
            let lowerEngineOut = engineOutput.lowercased()
            let untonedEngineOut = VietnameseSyllableDictionary.stripToneMarks(lowerEngineOut)
            let hasModifiedVowelOrStroke = untonedEngineOut.contains(where: { "ăâêôơưđ".contains($0) })
            let appendedPlainASCIIVowel: Bool = {
                guard rawWord.count == priorRawWord.count + 1,
                      let lastRaw = rawWord.last?.lowercased().first else { return false }
                return "aeiouy".contains(lastRaw)
            }()
            let inVietnameseMomentum =
                BilingualIntentArbiter.isVietnameseContextForTonePrimitive(context, lowerRaw: lowerPriorRaw) ||
                cachedEvaluateSentenceLanguageState(context).momentum == .vietnamese
            let isGenuineDelayedVN =
                hasModifiedVowelOrStroke ||
                ((VietnameseSyllableDictionary.shared.isValidSyllable(lowerEngineOut) ||
                  VietnameseSyllableDictionary.shared.hasStrictSyllablePrefix(lowerEngineOut)) &&
                 (!appendedPlainASCIIVowel || inVietnameseMomentum))
            if !isGenuineDelayedVN {
                return (rawWord, false)
            }
        }

        if shouldSelectRawEnglishInlineImpl(
            rawWord: rawWord,
            rendered: engineOutput,
            smartBilingualEnabled: smartBilingualEnabled,
            forceInlineEvaluation: forceInlineEvaluation,
            genZMode: genZMode,
            compoundWasChecked: effectiveBilingual && !effectiveInline,
            mixedInputWasChecked: checkedMixedInput
        ) {
            return (rawWord, false)
        }

        return (engineOutput, false)
    }

    private func hasConfirmedNonEnglishSemanticEscapeUnlocked(rawWord: String, rendered: String) -> Bool {
        guard engine.hasConfirmedSemanticEscapeInComposition,
              !VietnameseSyllableDictionary.hasToneMark(rendered),
              (SmartBilingualDetector.isExplicitTelexEscape(raw: rawWord, rendered: rendered) ||
               SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: rawWord, rendered: rendered)) else {
            return false
        }
        let cleanRaw = SmartBilingualDetector.trimPunctuationFast(rawWord)
        guard !cleanRaw.isEmpty,
              !cleanRaw.contains(where: { "_/\\.:[]{}<>=+*@#$%^&|".contains($0) }),
              !(precededByLeadingSlash && SmartBilingualDetector.isLeadingSlashCommandOrPathToken(cleanRaw.lowercased())) else {
            return false
        }
        return !SmartBilingualDetector.isKnownEnglishWord(cleanRaw)
    }

    public func hasConfirmedNonEnglishSemanticEscape(rawWord: String, rendered: String) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return hasConfirmedNonEnglishSemanticEscapeUnlocked(rawWord: rawWord, rendered: rendered)
    }

    /// Unified inline bilingual arbitration check shared across `InputSessionManager`, `UIKitInputSessionAdapter`, and `VieLotusIMController` (P0.4.2 Section 3).
    public func shouldSelectRawEnglishInline(
        rawWord: String,
        rendered: String,
        smartBilingualEnabled: Bool? = nil,
        forceInlineEvaluation: Bool = false,
        genZMode: Bool? = nil
    ) -> Bool {
        shouldSelectRawEnglishInlineImpl(
            rawWord: rawWord, rendered: rendered,
            smartBilingualEnabled: smartBilingualEnabled,
            forceInlineEvaluation: forceInlineEvaluation, genZMode: genZMode,
            compoundWasChecked: false,
            mixedInputWasChecked: false)
    }

    private func shouldSelectRawEnglishInlineImpl(
        rawWord: String,
        rendered: String,
        smartBilingualEnabled: Bool?,
        forceInlineEvaluation: Bool,
        genZMode: Bool?,
        compoundWasChecked: Bool,
        mixedInputWasChecked: Bool
    ) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let effectiveBilingual = smartBilingualEnabled ?? self.smartBilingualEnabled
        let effectiveInline = forceInlineEvaluation || self.inlineBilingualEnabled
        let effectiveGenZ = genZMode ?? self.genZMode
        let effectiveTech = self.precededByTechnicalDelimiter || self.activeDotPrefix != nil
        if !hasExplicitAccentSelection && effectiveBilingual && effectiveTech && rawWord.lowercased() == "w" && rawWord.lowercased() != rendered.lowercased() {
            return explicitBilingualSelection != .vietnameseTelex
        }
        guard !hasExplicitAccentSelection,
              effectiveBilingual,
              rawWord.count >= 2,
              rawWord.lowercased() != rendered.lowercased() else {
            return false
        }
        if explicitBilingualSelection == .vietnameseTelex {
            return false
        }
        if explicitBilingualSelection == .rawLiteral {
            return true
        }
        if let resolvedCompound = resolveMixedCaseCompoundUnlocked(
            rawWord: rawWord,
            wholeRendered: rendered,
            smartBilingualEnabled: effectiveBilingual
        ) {
            return resolvedCompound == rawWord
        }
        if !mixedInputWasChecked,
           let rawPreferred = SmartBilingualDetector.functionTokenPrefersRaw(
               rawWord, context: context, technical: effectiveTech) {
            return rawPreferred
        }
        if !mixedInputWasChecked && effectiveInline && !effectiveTech, let preferVN = mixedInputPrefersVietnamese(raw: rawWord, rendered: rendered) { return !preferVN }
        if !compoundWasChecked && !effectiveInline && SmartBilingualDetector.isEnglishCompound(raw: rawWord, rendered: rendered) { return true }
        if hasConfirmedNonEnglishSemanticEscapeUnlocked(rawWord: rawWord, rendered: rendered) {
            return false
        }
        if engine.inputMethod == .vni && rawWord.utf8.contains(where: { $0 >= 48 && $0 <= 57 }) {
            return false
        }
        if SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: rawWord, rendered: rendered) {
            return false
        }
        let lowerRaw = rawWord.lowercased()
        let lowerRendered = rendered.lowercased()
        if precededByLeadingSlash && SmartBilingualDetector.isLeadingSlashCommandOrPathToken(lowerRaw) {
            return true
        }
        if bilingualNoContextPolicy == .standardVietnameseFirst &&
           context.isEmpty &&
           BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) {
            return false
        }
        if effectiveInline &&
           SmartBilingualDetector.isInlineEnglishWord(raw: rawWord, rendered: rendered, context: context, genZMode: effectiveGenZ) {
            return true
        }
        if !compoundWasChecked && effectiveInline && SmartBilingualDetector.isEnglishCompound(raw: rawWord, rendered: rendered) {
            return true
        }
        if effectiveInline &&
           bilingualNoContextPolicy == .probabilisticBilingual &&
           (BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) ||
            lowerRaw == "his" ||
            lowerRaw == "her") &&
           !BilingualIntentArbiter.isVietnameseContextForTonePrimitive(context, lowerRaw: lowerRaw) {
            return true
        }
        if bilingualNoContextPolicy == .experimentalFrequencyWeighted && context.isEmpty {
            let arb = BilingualIntentArbiter.arbitrate(
                raw: rawWord,
                rendered: rendered,
                context: context,
                noContextPolicy: bilingualNoContextPolicy,
                hasExplicitUserSelection: hasExplicitAccentSelection,
                precededByTechnicalDelimiter: precededByTechnicalDelimiter || activeDotPrefix != nil,
                isInlineComposition: true,
                genZMode: effectiveGenZ
            )
            if arb.prefersRawEnglish {
                return true
            }
        }
        return false
    }

    /// Unified commit-time bilingual arbitration check shared across `InputSessionManager`, `UIKitInputSessionAdapter`, and `VieLotusIMController` (P0.4.2 Section 3).
    public func shouldSelectRawEnglishOnCommit(
        rawWord: String,
        rendered: String,
        smartBilingualEnabled: Bool? = nil,
        genZMode: Bool? = nil,
        wasPrecededByTechnicalDelimiter: Bool? = nil,
        boundaryChar: Character? = nil,
        followsDot: Bool = false
    ) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let effectiveBilingual = smartBilingualEnabled ?? self.smartBilingualEnabled
        let effectiveGenZ = genZMode ?? self.genZMode
        let effectiveTech = wasPrecededByTechnicalDelimiter ?? (self.precededByTechnicalDelimiter || self.activeDotPrefix != nil)
        if !hasExplicitAccentSelection && effectiveBilingual && effectiveTech && rawWord.lowercased() == "w" && rawWord.lowercased() != rendered.lowercased() {
            return explicitBilingualSelection != .vietnameseTelex
        }
        guard !hasExplicitAccentSelection,
              effectiveBilingual,
              !rawWord.isEmpty,
              rawWord.count >= 2,
              rawWord.lowercased() != rendered.lowercased() else {
            return false
        }
        if explicitBilingualSelection == .vietnameseTelex {
            return false
        }
        if explicitBilingualSelection == .rawLiteral {
            return true
        }
        if let resolvedCompound = resolveMixedCaseCompoundUnlocked(
            rawWord: rawWord,
            wholeRendered: rendered,
            smartBilingualEnabled: effectiveBilingual,
            followsDot: followsDot
        ) {
            return resolvedCompound == rawWord
        }
        if let rawPreferred = SmartBilingualDetector.functionTokenPrefersRaw(
            rawWord, context: context, technical: followsDot || effectiveTech) {
            return rawPreferred
        }
        if !effectiveTech, let preferVN = mixedInputPrefersVietnamese(raw: rawWord, rendered: rendered) { return !preferVN }
        if SmartBilingualDetector.isEnglishCompound(raw: rawWord, rendered: rendered) { return true }
        if hasConfirmedNonEnglishSemanticEscapeUnlocked(rawWord: rawWord, rendered: rendered) {
            return false
        }
        if engine.inputMethod == .vni && rawWord.contains(where: \.isNumber) {
            return false
        }
        if SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: rawWord, rendered: rendered) {
            return false
        }
        if shouldPreserveTechnicalToken(rawWord, followsDot: followsDot) {
            return true
        }
        let lowerRaw = rawWord.lowercased()
        let lowerRendered = rendered.lowercased()
        if precededByLeadingSlash && SmartBilingualDetector.isLeadingSlashCommandOrPathToken(lowerRaw) {
            return true
        }
        if bilingualNoContextPolicy == .standardVietnameseFirst &&
           context.isEmpty &&
           BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) {
            return false
        }
        if candidateProvenance.rawCandidate == rawWord {
            if candidateProvenance.explicitEscapeState == .literalLockedAfterSelection {
                return true
            }
            if candidateProvenance.selectionStability == .explicitEscape &&
               candidateProvenance.selectedKind == .explicitEscapeOrSelected &&
               candidateProvenance.explicitEscapeState == .semanticToneEscape &&
               lowerRaw == "off" &&
               BilingualIntentArbiter.isVietnameseContextForTonePrimitive(context, lowerRaw: "of") {
                return false
            }
            if candidateProvenance.selectionStability == .explicitSelection &&
               candidateProvenance.selectedKind == .rawLiteral &&
               candidateProvenance.selectedCandidate.lowercased() == rawWord.lowercased() {
                return true
            }
        }
        if SmartBilingualDetector.isEnglishWord(raw: rawWord, context: context, rendered: rendered, genZMode: effectiveGenZ) {
            return true
        }
        if inlineBilingualEnabled &&
           bilingualNoContextPolicy == .probabilisticBilingual &&
           (lowerRaw == "his" || lowerRaw == "her") &&
           !BilingualIntentArbiter.isVietnameseContextForTonePrimitive(context, lowerRaw: lowerRaw) {
            return true
        }
        if bilingualNoContextPolicy == .experimentalFrequencyWeighted && context.isEmpty {
            let arb = BilingualIntentArbiter.arbitrate(
                raw: rawWord,
                rendered: rendered,
                context: context,
                noContextPolicy: bilingualNoContextPolicy,
                hasExplicitUserSelection: hasExplicitAccentSelection,
                precededByTechnicalDelimiter: effectiveTech,
                boundaryChar: boundaryChar,
                genZMode: effectiveGenZ
            )
            if arb.prefersRawEnglish {
                return true
            }
        }
        return false
    }

    internal static func mayBeMixedCaseCompoundCandidate(_ raw: String) -> Bool {
        guard raw.utf8.count >= 4, raw.utf8.count < 64 else { return false }
        var hasUpper = false
        var hasLower = false
        var firstIsUpper = false
        var restAllLower = true
        var idx = 0
        for byte in raw.utf8 {
            if byte >= 65 && byte <= 90 {
                hasUpper = true
                if idx == 0 { firstIsUpper = true } else { restAllLower = false }
            } else if byte >= 97 && byte <= 122 {
                hasLower = true
            } else {
                return false
            }
            idx += 1
        }
        if !hasUpper || !hasLower { return false }
        if firstIsUpper && restAllLower { return false }
        return true
    }

    internal static func partitionMixedCaseSubwords(_ raw: String) -> [String]? {
        guard mayBeMixedCaseCompoundCandidate(raw) else { return nil }
        let chars = Array(raw)
        let rawLen = chars.count
        guard rawLen >= 4 else { return nil }

        @inline(__always)
        func isUpperASCII(_ c: Character) -> Bool {
            guard let a = c.asciiValue else { return false }
            return a >= 65 && a <= 90
        }
        @inline(__always)
        func isLowerASCII(_ c: Character) -> Bool {
            guard let a = c.asciiValue else { return false }
            return a >= 97 && a <= 122
        }
        @inline(__always)
        func isBaseVowelASCII(_ c: Character) -> Bool {
            guard let a = c.asciiValue else { return false }
            let lo = a | 0x20
            return lo == 97 || lo == 101 || lo == 105 || lo == 111 || lo == 117 || lo == 121
        }

        var segments: [String] = []
        var curStart = 0
        var i = 0

        var leadUpper = 0
        while leadUpper < rawLen && isUpperASCII(chars[leadUpper]) {
            leadUpper += 1
        }
        if leadUpper >= 3 && leadUpper < rawLen && isLowerASCII(chars[leadUpper]) {
            var splitAt = leadUpper - 1
            if leadUpper >= 4 && chars[leadUpper - 2] == "D" && chars[leadUpper - 1] == "D" {
                splitAt = leadUpper - 2
            }
            if splitAt >= 2 {
                segments.append(String(chars[0..<splitAt]))
                curStart = splitAt
                i = splitAt
            }
        }

        var curSegHasVowel = false
        while i < rawLen {
            let c = chars[i]
            if i > curStart && isUpperASCII(c) && isLowerASCII(chars[i - 1]) && curSegHasVowel {
                if segments.count >= 15 { return nil }
                segments.append(String(chars[curStart..<i]))
                curStart = i
                curSegHasVowel = isBaseVowelASCII(c)
            } else if isBaseVowelASCII(c) {
                curSegHasVowel = true
            }
            i += 1
        }
        if curStart < rawLen {
            segments.append(String(chars[curStart..<rawLen]))
        }
        guard segments.count >= 2 else { return nil }
        for (segIdx, seg) in segments.enumerated() {
            let bytes = Array(seg.utf8)
            guard bytes.count >= 2 else { return nil }
            let allUpper = bytes.allSatisfy { $0 >= 65 && $0 <= 90 }
            if allUpper { continue }
            let hasVowel = bytes.contains { b in
                let lo = b | 0x20
                return lo == 97 || lo == 101 || lo == 105 || lo == 111 || lo == 117 || lo == 121
            }
            guard hasVowel else { return nil }
            if segIdx == 0 && bytes.allSatisfy({ $0 >= 97 && $0 <= 122 }) {
                continue
            }
            guard bytes[0] >= 65 && bytes[0] <= 90 else { return nil }
            let tailStart: Int
            if bytes.count >= 3 && bytes[0] == 68 && bytes[1] == 68 {
                tailStart = 2
            } else {
                tailStart = 1
            }
            guard bytes[tailStart...].allSatisfy({ $0 >= 97 && $0 <= 122 }) else {
                return nil
            }
        }
        return segments
    }

    public func resolveMixedCaseCompound(
        rawWord: String,
        wholeRendered: String,
        smartBilingualEnabled: Bool? = nil,
        followsDot: Bool = false
    ) -> String? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return resolveMixedCaseCompoundUnlocked(
            rawWord: rawWord,
            wholeRendered: wholeRendered,
            smartBilingualEnabled: smartBilingualEnabled,
            followsDot: followsDot
        )
    }

    private func resolveMixedCaseCompoundUnlocked(
        rawWord: String,
        wholeRendered: String,
        smartBilingualEnabled: Bool? = nil,
        followsDot: Bool = false
    ) -> String? {
        let effectiveBilingual = smartBilingualEnabled ?? self.smartBilingualEnabled
        guard effectiveBilingual,
              !hasExplicitAccentSelection,
              explicitBilingualSelection == nil,
              !followsDot,
              !precededByTechnicalDelimiter,
              !precededByLeadingSlash,
              activeDotPrefix == nil,
              engine.inputMethod == .telex,
              let segments = Self.partitionMixedCaseSubwords(rawWord) else {
            return nil
        }

        let lowerWholeRendered = wholeRendered.lowercased()
        if !wholeRendered.unicodeScalars.allSatisfy(\.isASCII),
           (VietnameseSyllableDictionary.shared.isValidSyllable(lowerWholeRendered) ||
            VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(wholeRendered)) {
            return nil
        }

        var combined = ""
        combined.reserveCapacity(rawWord.count)
        var compoundHasNonASCII = false
        var allSegmentsEnglish = true
        let profile = engine.grammarProfile
        let modernOrtho = engine.modernOrthography
        let effectiveGenZ = self.genZMode

        for seg in segments {
            let isAllCaps = seg.utf8.allSatisfy { $0 >= 65 && $0 <= 90 }
            if isAllCaps {
                combined.append(seg)
                continue
            }

            let subEngine = VietnameseEngine()
            subEngine.inputMethod = .telex
            subEngine.grammarProfile = profile
            subEngine.modernOrthography = modernOrtho
            for ch in seg {
                _ = subEngine.feed(ch)
            }
            let subOut = subEngine.currentOutput()
            let lowerSeg = seg.lowercased()

            let subIsKnownEnglish =
                EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerSeg) ||
                BilingualIntentArbiter.englishCollisionLogFrequencies[lowerSeg] != nil ||
                BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: lowerSeg, lowerRendered: subOut.lowercased()) ||
                SmartBilingualDetector.isEnglishAnchorTokenForArbiter(lowerSeg) ||
                Self.sentenceInitialSpacePrefixStarters.contains(lowerSeg) ||
                SmartBilingualDetector.isContextSensitiveEnglishCollision(lowerSeg)

            let subIsEnglish =
                subOut.lowercased() == lowerSeg ||
                subIsKnownEnglish ||
                SmartBilingualDetector.isInlineEnglishWord(raw: lowerSeg, rendered: subOut.lowercased(), context: "the is", genZMode: effectiveGenZ) ||
                SmartBilingualDetector.isEnglishWord(raw: lowerSeg, context: "the is", rendered: subOut.lowercased(), genZMode: effectiveGenZ)

            if subIsEnglish {
                combined.append(seg)
            } else {
                allSegmentsEnglish = false
                let subHasNonASCII = !subOut.unicodeScalars.allSatisfy(\.isASCII)
                if subHasNonASCII {
                    let lowerSubOut = subOut.lowercased()
                    let isValidSubVN =
                        lowerSubOut == "đ" ||
                        VietnameseSyllableDictionary.shared.isValidSyllable(lowerSubOut) ||
                        VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lowerSubOut, genZMode: effectiveGenZ) ||
                        VietnameseSyllableDictionary.shared.hasStrictSyllablePrefix(lowerSubOut)
                    guard isValidSubVN else {
                        return nil
                    }
                    compoundHasNonASCII = true
                }
                combined.append(subOut)
            }
        }

        if allSegmentsEnglish && rawWord != wholeRendered {
            return rawWord
        }
        guard compoundHasNonASCII else { return nil }
        return combined
    }

    public func backspaceEngine(
        rawWord currentRaw: String,
        displayedAsRaw: Bool,
        smartBilingualEnabled: Bool? = nil
    ) -> (backspaces: Int, suffix: String)? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return backspaceEngineUnlocked(
            currentRaw: currentRaw,
            displayedAsRaw: displayedAsRaw,
            smartBilingualEnabled: smartBilingualEnabled
        )
    }

    private func backspaceEngineUnlocked(
        currentRaw: String,
        displayedAsRaw: Bool,
        smartBilingualEnabled: Bool? = nil
    ) -> (backspaces: Int, suffix: String)? {
        let effectiveBilingual = smartBilingualEnabled ?? self.smartBilingualEnabled
        if effectiveBilingual,
           engine.inputMethod == .telex,
           !hasExplicitAccentSelection,
           explicitBilingualSelection == nil,
           !precededByTechnicalDelimiter,
           !precededByLeadingSlash,
           activeDotPrefix == nil {
            if resolveMixedCaseCompoundUnlocked(
                rawWord: currentRaw,
                wholeRendered: engine.currentOutput(),
                smartBilingualEnabled: effectiveBilingual
            ) != nil,
               let segments = Self.partitionMixedCaseSubwords(currentRaw),
               segments.count >= 2 {
                let lastSeg = segments[segments.count - 1]
                let isAllCaps = lastSeg.utf8.allSatisfy { $0 >= 65 && $0 <= 90 }
                let shortenedLast: String
                if isAllCaps {
                    shortenedLast = String(lastSeg.dropLast())
                } else {
                    let subEngine = VietnameseEngine()
                    subEngine.inputMethod = .telex
                    subEngine.grammarProfile = engine.grammarProfile
                    subEngine.modernOrthography = engine.modernOrthography
                    subEngine.backspaceStyle = engine.backspaceStyle
                    for ch in lastSeg {
                        _ = subEngine.feed(ch)
                    }
                    let subOut = subEngine.currentOutput()
                    let lowerSeg = lastSeg.lowercased()
                    let effectiveGenZ = self.genZMode
                    let subIsEnglish =
                        subOut.lowercased() == lowerSeg ||
                        EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerSeg) ||
                        BilingualIntentArbiter.englishCollisionLogFrequencies[lowerSeg] != nil ||
                        BilingualIntentArbiter.prefersEnglishInDefaultNoContext(lowerRaw: lowerSeg, lowerRendered: subOut.lowercased()) ||
                        SmartBilingualDetector.isEnglishAnchorTokenForArbiter(lowerSeg) ||
                        Self.sentenceInitialSpacePrefixStarters.contains(lowerSeg) ||
                        SmartBilingualDetector.isContextSensitiveEnglishCollision(lowerSeg) ||
                        SmartBilingualDetector.isInlineEnglishWord(raw: lowerSeg, rendered: subOut.lowercased(), context: "the is", genZMode: effectiveGenZ) ||
                        SmartBilingualDetector.isEnglishWord(raw: lowerSeg, context: "the is", rendered: subOut.lowercased(), genZMode: effectiveGenZ)
                    if subIsEnglish {
                        shortenedLast = String(lastSeg.dropLast())
                    } else {
                        _ = subEngine.backspace()
                        shortenedLast = subEngine.rawString()
                    }
                }
                let newRaw = segments.dropLast().joined() + shortenedLast
                let prevOut = engine.currentOutput()
                engine.reset()
                for ch in newRaw {
                    _ = engine.feed(ch)
                }
                return Self.computeUTF16Diff(oldStr: prevOut, newStr: engine.currentOutput())
            } else if currentRaw.count >= 3,
                      Self.partitionMixedCaseSubwords(currentRaw) == nil,
                      Self.partitionMixedCaseSubwords(currentRaw + "a") != nil {
                let newRaw = String(currentRaw.dropLast())
                let prevOut = engine.currentOutput()
                engine.reset()
                for ch in newRaw {
                    _ = engine.feed(ch)
                }
                return Self.computeUTF16Diff(oldStr: prevOut, newStr: engine.currentOutput())
            }
        }
        return engine.backspace(displayedAsRaw: displayedAsRaw)
    }

    /// Records composition candidate provenance from an external controller (`VieLotusIMController`) into the unified session state (P0.4.2 Section 3).
    public func recordExternalCompositionProvenance(
        rawWord: String,
        engineOutput: String,
        selectedCandidate: String,
        wasLiteralLockedStep: Bool = false
    ) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if rawWord.isEmpty && selectedCandidate.isEmpty {
            explicitBilingualSelection = nil
        }
        let prior = candidateProvenance
        updateCandidateProvenance(
            rawWord: rawWord,
            engineOutput: engineOutput,
            selectedCandidate: selectedCandidate,
            priorProvenance: prior,
            wasLiteralLockedStep: wasLiteralLockedStep
        )
    }

    /// Records the final committed candidate provenance into `lastCommittedProvenance` before resetting composition state (P0.4.2 Section 3).
    public func recordExternalCommitProvenance(
        rawWord: String,
        engineOutput: String,
        committedCandidate: String
    ) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let prior = candidateProvenance
        updateCandidateProvenance(
            rawWord: rawWord,
            engineOutput: engineOutput,
            selectedCandidate: committedCandidate,
            priorProvenance: prior,
            wasLiteralLockedStep: false
        )
        lastCommittedProvenance = candidateProvenance
        explicitBilingualSelection = nil
        hasExplicitAccentSelection = false
        candidateProvenance = .empty
        provenanceHistory.removeAll(keepingCapacity: true)
    }

    private static func computeNaiveVietnameseCandidate(raw: String, engineOutput: String) -> String {
        let lower = raw.lowercased()
        if engineOutput.lowercased() != lower {
            return engineOutput
        }
        switch lower {
        case "fee": return "fê"
        case "fees": return "fế"
        case "free": return "frê"
        case "green": return "grên"
        default: return engineOutput
        }
    }

    private func bilingualCollisionLogFrequencyFastCheck(_ lowerRaw: String) -> Double? {
        BilingualIntentArbiter.englishCollisionLogFrequencies[lowerRaw]
    }

    private func updateCandidateProvenance(
        rawWord: String,
        engineOutput: String,
        selectedCandidate: String,
        priorProvenance: CompositionCandidateProvenance,
        wasLiteralLockedStep: Bool
    ) {
        guard !rawWord.isEmpty || !selectedCandidate.isEmpty else {
            candidateProvenance = .empty
            provenanceHistory.removeAll(keepingCapacity: true)
            return
        }
        let vnCandidate = Self.computeNaiveVietnameseCandidate(raw: rawWord, engineOutput: engineOutput)
        let lowerRaw = rawWord.lowercased()
        let lowerVN = vnCandidate.lowercased()
        let lowerSelected = selectedCandidate.lowercased()
        let sentenceState = (!priorProvenance.rawCandidate.isEmpty && priorProvenance.context == context)
            ? priorProvenance.sentenceLanguageState
            : cachedEvaluateSentenceLanguageState(context)

        var cachedIsKnownRawEnglish: Bool? = nil
        func isKnownRawEnglish() -> Bool {
            if let cached = cachedIsKnownRawEnglish { return cached }
            let computed = SmartBilingualDetector.isKnownEnglishWord(
                rawWord.trimmingCharacters(in: .punctuationCharacters)
            )
            cachedIsKnownRawEnglish = computed
            return computed
        }
        let priorWasIntentionalVietnameseOnDefaultEnglishToken =
            priorProvenance.selectedKind == .vietnameseTelex &&
            !priorProvenance.selectedCandidate.unicodeScalars.allSatisfy(\.isASCII) &&
            rawWord.count == priorProvenance.rawCandidate.count + 1 &&
            (explicitBilingualSelection == .vietnameseTelex ||
             BilingualIntentArbiter.prefersEnglishInDefaultNoContext(
                 lowerRaw: priorProvenance.rawCandidate.lowercased(),
                 lowerRendered: priorProvenance.vietnameseCandidate.lowercased()
             ))
        let hasUntonedDifference = lowerRaw != lowerSelected && !VietnameseSyllableDictionary.hasToneMark(selectedCandidate)
        let priorAlreadyConfirmedEscape =
            hasUntonedDifference &&
            priorProvenance.selectionStability == .explicitEscape &&
            priorProvenance.selectedKind == .explicitEscapeOrSelected &&
            !isKnownRawEnglish()

        let escapeKind: ExplicitEscapeKind = {
            if wasLiteralLockedStep || engine.literalOverrideEnabled {
                return .literalLockedAfterSelection
            }
            if lowerRaw == lowerSelected {
                return .none
            }
            if lowerRaw.contains("z") && SmartBilingualDetector.hasExplicitZToneClear(lowerRaw: lowerRaw, rendered: selectedCandidate) {
                return .zToneClear
            }
            let hasCandidateSemanticEscape =
                (engine.hasConfirmedSemanticEscapeInComposition && hasUntonedDifference) ||
                (lowerRaw.count >= 3 && hasUntonedDifference && SmartBilingualDetector.hasSemanticToneEscape(lowerRaw: lowerRaw, lowerRendered: lowerSelected)) ||
                (priorWasIntentionalVietnameseOnDefaultEnglishToken &&
                 hasUntonedDifference &&
                 engine.lastToneSemanticEvent == .cancelToneAndEmitLiteral)
            if hasCandidateSemanticEscape {
                let allowsSemanticEscapeDespiteEnglishSpelling =
                    explicitBilingualSelection == .vietnameseTelex ||
                    priorWasIntentionalVietnameseOnDefaultEnglishToken ||
                    lowerRaw == "orr" || lowerRaw == "iff" || lowerRaw == "arr" ||
                    !isKnownRawEnglish()
                if allowsSemanticEscapeDespiteEnglishSpelling {
                    return .semanticToneEscape
                }
            }
            if SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: rawWord, rendered: selectedCandidate) &&
               !VietnameseSyllableDictionary.hasToneMark(selectedCandidate) {
                return .semanticToneEscape
            }
            if SmartBilingualDetector.isExplicitTelexEscape(raw: rawWord, rendered: selectedCandidate) {
                return .classicVowelEscape
            }
            if priorAlreadyConfirmedEscape {
                return priorProvenance.explicitEscapeState == .none ? .semanticToneEscape : priorProvenance.explicitEscapeState
            }
            return .none
        }()

        let selectionStability: CandidateSelectionStability = {
            if escapeKind != .none {
                return .explicitEscape
            }
            if hasExplicitAccentSelection || explicitBilingualSelection != nil {
                return .explicitSelection
            }
            return .provisional
        }()

        let selectedKind: BilingualCandidateKind
        let selectionReason: CandidateSelectionReason
        var margin: Double = 0.0

        if hasExplicitAccentSelection {
            selectedKind = .explicitEscapeOrSelected
            selectionReason = .userSelectedSuggestion
            margin = 100.0
        } else if escapeKind == .literalLockedAfterSelection {
            selectedKind = .rawLiteral
            selectionReason = .explicitLiteralOverride
            margin = 100.0
        } else if escapeKind != .none {
            selectedKind = .explicitEscapeOrSelected
            selectionReason = .explicitTelexEscape
            margin = 100.0
        } else if let explicitChoice = explicitBilingualSelection {
            selectedKind = explicitChoice
            selectionReason = .userSelectedSuggestion
            margin = 100.0
        } else if lowerRaw != lowerVN {
            if lowerSelected != lowerRaw {
                selectedKind = .vietnameseTelex
                selectionReason = context.isEmpty ? .vietnameseComposition : .vietnameseContext
                margin = 10.0
            } else if lowerSelected == lowerRaw &&
                      !precededByTechnicalDelimiter &&
                      activeDotPrefix == nil &&
                      !(lowerRaw.first.map { "fjzw".contains($0) } ?? false) &&
                      (lowerVN.count > 7 || !(lowerVN.last.map { "ghk".contains($0) } ?? false)) &&
                      !lowerRaw.contains(where: { "_/\\-.:[]{}<>=+*@#$%^&|".contains($0) }) &&
                      !VietnameseSyllableDictionary.shared.isValidSyllable(lowerVN) {
                selectedKind = .rawLiteral
                let isPhonotactic =
                    lowerVN.count <= 7 &&
                    VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(lowerVN) &&
                    VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(
                        lowerVN,
                        relaxedCoda: false,
                        genZMode: false
                    )
                selectionReason = isPhonotactic ? .phonotacticGapVN : .phonotacticInvalidVN
                margin = 8.0
            } else {
                let arb = BilingualIntentArbiter.arbitrate(
                    raw: rawWord,
                    rendered: vnCandidate,
                    context: context,
                    noContextPolicy: bilingualNoContextPolicy,
                    hasExplicitUserSelection: hasExplicitAccentSelection,
                    precededByTechnicalDelimiter: precededByTechnicalDelimiter || activeDotPrefix != nil,
                    isInlineComposition: true,
                    genZMode: genZMode
                )
                margin = arb.scoreMargin
                if lowerSelected == lowerRaw {
                    selectedKind = .rawLiteral
                    if arb.phonotacticProfile.blockedGenZExpansionOnEnglishWord {
                        selectionReason = .genZBlockedOnEnglishWord
                    } else if arb.phonotacticProfile.blockedRelaxedCodaOnEnglishWord {
                        selectionReason = .relaxedCodaBlockedOnEnglishWord
                    } else if arb.selectionReason == .vietnameseComposition || arb.selectionReason == .vietnameseContext {
                        selectionReason = .phonotacticInvalidVN
                    } else {
                        selectionReason = arb.selectionReason
                    }
                } else {
                    selectedKind = .vietnameseTelex
                    if arb.prefersRawEnglish && arb.scoreMargin < BilingualIntentArbiter.hysteresisMarginThreshold {
                        selectionReason = .hysteresisRetained
                    } else {
                        selectionReason = arb.selectionReason == .englishContext ? .vietnameseComposition : arb.selectionReason
                    }
                }
            }
        } else {
            selectedKind = .vietnameseTelex
            selectionReason = .asciiPassThrough
        }

        let didFlip: Bool = {
            guard !priorProvenance.rawCandidate.isEmpty,
                  priorProvenance.selectionReason != .asciiPassThrough,
                  selectionReason != .asciiPassThrough,
                  selectedKind != .explicitEscapeOrSelected,
                  priorProvenance.selectedKind != .explicitEscapeOrSelected else {
                return false
            }
            return priorProvenance.selectedKind != selectedKind
        }()

        let transitionReason: String = {
            if priorProvenance.rawCandidate.isEmpty {
                return "initial(\(selectionReason.rawValue))"
            }
            if escapeKind != .none {
                return "escaped(\(escapeKind.rawValue))"
            }
            if didFlip {
                return "flipped(\(priorProvenance.selectedKind.rawValue)->\(selectedKind.rawValue):\(selectionReason.rawValue))"
            }
            return "retained(\(selectionReason.rawValue))"
        }()

        let newFlipCount = priorProvenance.flipCount + (didFlip ? 1 : 0)
        let isPureASCII = selectedCandidate.unicodeScalars.allSatisfy(\.isASCII)
        let semanticTransforms = (selectedKind == .rawLiteral || isPureASCII) ? [] : engine.semanticTransformations(for: selectedCandidate)
        let litSuffix: String = {
            if escapeKind == .literalLockedAfterSelection {
                let baseLen = priorProvenance.literalSuffix.isEmpty
                    ? priorProvenance.selectedCandidate.count
                    : (priorProvenance.selectedCandidate.count - priorProvenance.literalSuffix.count)
                if selectedCandidate.count > baseLen {
                    return String(selectedCandidate.dropFirst(baseLen))
                }
            }
            if isPureASCII && escapeKind != .semanticToneEscape {
                return ""
            }
            return engine.literalSuffix(for: selectedCandidate, raw: rawWord)
        }()

        let nextProvenance = CompositionCandidateProvenance(
            rawCandidate: rawWord,
            vietnameseCandidate: vnCandidate,
            selectedCandidate: selectedCandidate,
            selectedKind: selectedKind,
            selectionReason: selectionReason,
            explicitEscapeState: escapeKind,
            selectionStability: selectionStability,
            toneSemanticEvent: engine.lastToneSemanticEvent,
            semanticTransformations: semanticTransforms,
            literalSuffix: litSuffix,
            flipCount: newFlipCount,
            stabilityMargin: margin,
            context: context,
            sentenceLanguageState: sentenceState,
            transitionReason: transitionReason
        )
        candidateProvenance = nextProvenance
        provenanceHistory.append(nextProvenance)
    }

    /// Computes minimal UTF-16 backspace + suffix replacement between two on-screen strings.
    private static func computeUTF16Diff(oldStr: String, newStr: String) -> (backspaces: Int, suffix: String) {
        if oldStr.isEmpty {
            return (0, newStr)
        }
        if oldStr == newStr {
            return (0, "")
        }
        var oldIdx = oldStr.startIndex
        var newIdx = newStr.startIndex
        while oldIdx < oldStr.endIndex && newIdx < newStr.endIndex &&
              oldStr[oldIdx] == newStr[newIdx] &&
              oldStr[oldIdx].unicodeScalars.elementsEqual(newStr[newIdx].unicodeScalars) {
            oldIdx = oldStr.index(after: oldIdx)
            newIdx = newStr.index(after: newIdx)
        }
        let backspacesUTF16 = oldStr[oldIdx...].utf16.count
        let suffix = String(newStr[newIdx...])
        return (backspacesUTF16, suffix)
    }

    /// Handle backspace key
    public func handleBackspace() -> SessionAction {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if isComposing {
            editCaretBack = Self.caretDisarmed
            let priorComposingWord = composingWord
            let priorProvenance = candidateProvenance
            let wasDisplayingRaw =
                !priorComposingWord.isEmpty &&
                priorComposingWord == rawWord &&
                priorComposingWord != engine.currentOutput()
            if let _ = backspaceEngineUnlocked(currentRaw: rawWord, displayedAsRaw: wasDisplayingRaw) {
                rawWord = engine.rawString()
                if !provenanceHistory.isEmpty {
                    provenanceHistory.removeLast()
                }

                var targetComposingWord = resolveMixedCaseCompoundUnlocked(
                    rawWord: rawWord,
                    wholeRendered: engine.currentOutput(),
                    smartBilingualEnabled: smartBilingualEnabled
                ) ?? engine.currentOutput()
                if targetComposingWord.isEmpty && rawWord.isEmpty {
                    engine.reset()
                    composingWord = ""
                    rawWord = ""
                    hasExplicitAccentSelection = false
                    explicitBilingualSelection = nil
                    candidateProvenance = .empty
                    provenanceHistory.removeAll(keepingCapacity: true)
                    pendingDotPrefix = activeDotPrefix
                    activeDotPrefix = nil
                    pendingSpacePrefix = activeSpacePrefix
                    activeSpacePrefix = nil
                    editCaretBack = Self.caretDisarmed
                    sessionGeneration &+= 1
                    return .reset
                }

                if targetComposingWord.allSatisfy(\.isASCII) {
                    hasExplicitAccentSelection = false
                    if explicitBilingualSelection == .vietnameseTelex &&
                       !engine.hasConfirmedSemanticEscapeInComposition {
                        explicitBilingualSelection = nil
                    }
                }
                if rawWord.count <= 1 {
                    explicitBilingualSelection = nil
                }

                if wasDisplayingRaw {
                    targetComposingWord = rawWord
                    let baseProv = provenanceHistory.last ?? priorProvenance
                    if !provenanceHistory.isEmpty {
                        provenanceHistory.removeLast()
                    }
                    updateCandidateProvenance(
                        rawWord: rawWord,
                        engineOutput: engine.currentOutput(),
                        selectedCandidate: targetComposingWord,
                        priorProvenance: baseProv,
                        wasLiteralLockedStep: engine.literalOverrideEnabled
                    )
                } else if let restoredProv = provenanceHistory.last, restoredProv.rawCandidate == rawWord {
                    targetComposingWord = restoredProv.selectedCandidate
                    candidateProvenance = restoredProv
                } else {
                    let baseProv = provenanceHistory.last ?? .empty
                    if !provenanceHistory.isEmpty {
                        provenanceHistory.removeLast()
                    }
                    updateCandidateProvenance(
                        rawWord: rawWord,
                        engineOutput: engine.currentOutput(),
                        selectedCandidate: targetComposingWord,
                        priorProvenance: baseProv,
                        wasLiteralLockedStep: false
                    )
                }

                composingWord = targetComposingWord
                let screenDiff = Self.computeUTF16Diff(oldStr: priorComposingWord, newStr: targetComposingWord)
                return .replace(backspaces: screenDiff.backspaces, text: screenDiff.suffix)
            }
            engine.reset()
            composingWord = ""
            rawWord = ""
            hasExplicitAccentSelection = false
            explicitBilingualSelection = nil
            candidateProvenance = .empty
            provenanceHistory.removeAll(keepingCapacity: true)
            pendingDotPrefix = nil
            activeDotPrefix = nil
            pendingSpacePrefix = nil
            activeSpacePrefix = nil
            editCaretBack = Self.caretDisarmed
            sessionGeneration &+= 1
            return .reset
        } else {
            pendingDotPrefix = nil
            activeDotPrefix = nil
            pendingSpacePrefix = nil
            activeSpacePrefix = nil
            precededByTechnicalDelimiter = false
            precededByLeadingSlash = false
            // Idle backspace: only a single boundary deletion (editCaretBack == -1) arms post-commit editing
            if editCaretBack == -1 {
                editCaretBack = 0
            } else if editCaretBack == 0 {
                // Second backspace: deleting into the committed word itself!
                if let diff = engine.editBackspaceAt(caretBack: editCaretBack) {
                    if engine.isComposing {
                        rawWord = engine.lastCommittedRaw ?? ""
                        composingWord = engine.lastCommittedWord ?? ""
                        provenanceHistory.removeAll(keepingCapacity: true)
                        updateCandidateProvenance(
                            rawWord: rawWord,
                            engineOutput: engine.currentOutput(),
                            selectedCandidate: composingWord,
                            priorProvenance: .empty,
                            wasLiteralLockedStep: false
                        )
                    } else {
                        rawWord = ""
                        composingWord = ""
                        candidateProvenance = .empty
                        provenanceHistory.removeAll(keepingCapacity: true)
                        sessionGeneration &+= 1
                    }
                    editCaretBack = Self.caretDisarmed
                    return .replace(backspaces: diff.backspaces, text: diff.suffix)
                } else {
                    engine.reset()
                    editCaretBack = Self.caretDisarmed
                }
            } else {
                // Disarmed idle backspace (e.g. holding backspace on empty/fully-deleted buffer):
                // purge committed history so stale words can never resurrect.
                engine.reset()
                engine.clearHistory()
                editCaretBack = Self.caretDisarmed
            }
            return .passThrough
        }
    }

    public var macroEngine: MacroEngine? = MacroEngine.shared
    public var macroEnabled: Bool = false

    /// Commit the current composition, applying Macro, Code Protection, and Smart Bilingual if needed
    public func commitWord(
        smartBilingualEnabled: Bool,
        genZMode: Bool? = nil,
        macroEngine: MacroEngine? = nil,
        boundaryChar: Character? = nil
    ) -> SessionAction {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard isComposing else {
            pendingDotPrefix = nil
            activeDotPrefix = nil
            pendingSpacePrefix = nil
            activeSpacePrefix = nil
            precededByTechnicalDelimiter = boundaryChar.map { MacroEngine.isTechnicalDelimiter($0) } ?? false
            precededByLeadingSlash = (boundaryChar == "/")
            return .passThrough
        }

        let effectiveGenZMode = genZMode ?? self.genZMode
        let resolvedMixedCompound = resolveMixedCaseCompoundUnlocked(
            rawWord: rawWord,
            wholeRendered: engine.currentOutput(),
            smartBilingualEnabled: smartBilingualEnabled
        )
        let rawEngineOutput = resolvedMixedCompound ?? engine.currentOutput()
        let output = smartBilingualEnabled
            ? (resolvedMixedCompound ?? currentOutput())
            : (rawEngineOutput.isEmpty ? currentOutput() : rawEngineOutput)
        let finalWord: String
        var isOverride = false
        let wasPrecededByTechnicalDelimiter = precededByTechnicalDelimiter || activeDotPrefix != nil
        let wasPrecededByLeadingSlash = precededByLeadingSlash
        precededByTechnicalDelimiter = boundaryChar.map { MacroEngine.isTechnicalDelimiter($0) } ?? false
        let dotPrefixToRestore: (raw: String, rendered: String)? = {
            guard let dotPrefix = activeDotPrefix,
                  !rawWord.isEmpty,
                  Self.commitDotSuffixTLDs.contains(rawWord.lowercased()) else {
                return nil
            }
            return dotPrefix
        }()
        activeDotPrefix = nil

        let commitRenderedForArbitration =
            (candidateProvenance.selectionStability == .provisional && !rawEngineOutput.isEmpty)
            ? rawEngineOutput
            : output

        let spacePrefixToRestore: (raw: String, rendered: String)? = {
            guard smartBilingualEnabled,
                  !hasExplicitAccentSelection,
                  explicitBilingualSelection != .vietnameseTelex,
                  dotPrefixToRestore == nil,
                  let spacePrefix = activeSpacePrefix,
                  spacePrefix.raw != spacePrefix.rendered,
                  !rawWord.isEmpty,
                  Self.shouldRestoreSpacePrefix(
                      prefixRaw: spacePrefix.raw,
                      prefixRendered: spacePrefix.rendered,
                      secondRaw: rawWord,
                      secondRendered: commitRenderedForArbitration
                  ) else {
                return nil
            }
            return spacePrefix
        }()
        let vnCompoundPrefixToRestore: (prefix: (raw: String, rendered: String), vnPrefix: String)? = {
            guard smartBilingualEnabled,
                  !hasExplicitAccentSelection,
                  explicitBilingualSelection != .rawLiteral,
                  dotPrefixToRestore == nil,
                  spacePrefixToRestore == nil,
                  let spacePrefix = activeSpacePrefix,
                  spacePrefix.raw == spacePrefix.rendered,
                  !rawWord.isEmpty,
                  let vnPrefix = Self.vietnameseCompoundPrefixReplacement(
                      prefixRaw: spacePrefix.raw,
                      prefixRendered: spacePrefix.rendered,
                      secondRaw: rawWord,
                      secondRendered: commitRenderedForArbitration
                  ) else {
                return nil
            }
            return (spacePrefix, vnPrefix)
        }()
        activeSpacePrefix = nil

        let suppressMacro = MacroEngine.shouldSuppressMacroExpansion(
            precededByTechnicalDelimiter: wasPrecededByTechnicalDelimiter,
            boundaryChar: boundaryChar
        )
        let activeMacro = suppressMacro ? nil : (macroEngine ?? (self.macroEnabled ? self.macroEngine : nil))
        let candidateKey = rawWord.isEmpty ? output : rawWord
        let expansion = activeMacro?.lookup(word: candidateKey) ?? (output != candidateKey ? activeMacro?.lookup(word: output) : nil)

        // Code delimiter protection (e.g. cfung() -> cfung() without preceding space)
        let isCodeBoundary = smartBilingualEnabled && boundaryChar != nil && "([{".contains(boundaryChar!) &&
            !SmartBilingualDetector.isExplicitTelexEscape(raw: rawWord, rendered: output) &&
            !hasConfirmedNonEnglishSemanticEscapeUnlocked(rawWord: rawWord, rendered: output)

        if dotPrefixToRestore != nil {
            finalWord = rawWord.isEmpty ? output : rawWord
            isOverride = (finalWord != composingWord)
        } else if spacePrefixToRestore != nil {
            finalWord = rawWord.isEmpty ? output : rawWord
            isOverride = true
        } else if let expansion = expansion {
            finalWord = expansion
            isOverride = true
        } else if isCodeBoundary && !rawWord.isEmpty && rawWord.lowercased() != commitRenderedForArbitration.lowercased() {
            finalWord = rawWord
            isOverride = true
        } else if shouldSelectRawEnglishOnCommit(
            rawWord: rawWord,
            rendered: commitRenderedForArbitration,
            smartBilingualEnabled: smartBilingualEnabled,
            genZMode: effectiveGenZMode,
            wasPrecededByTechnicalDelimiter: wasPrecededByTechnicalDelimiter,
            boundaryChar: boundaryChar
        ) {
            finalWord = rawWord
            isOverride = (finalWord != composingWord)
        } else {
            let preferredVNOutput = (candidateProvenance.selectionStability == .provisional && !rawEngineOutput.isEmpty)
                ? rawEngineOutput
                : output
            finalWord = preferredVNOutput.isEmpty ? (composingWord.isEmpty ? rawWord : composingWord) : preferredVNOutput
            isOverride = (finalWord != composingWord)
        }

        let savedRaw = rawWord.isEmpty ? output : rawWord
        precededByLeadingSlash = (boundaryChar == "/" && wasPrecededByLeadingSlash && finalWord == savedRaw)
        let effectiveEngineOutput = rawEngineOutput.isEmpty ? output : rawEngineOutput
        if !isOverride &&
           candidateProvenance.rawCandidate == savedRaw &&
           candidateProvenance.selectedCandidate == finalWord &&
           candidateProvenance.context == context {
            lastCommittedProvenance = candidateProvenance
        } else {
            updateCandidateProvenance(
                rawWord: savedRaw,
                engineOutput: effectiveEngineOutput,
                selectedCandidate: finalWord,
                priorProvenance: candidateProvenance,
                wasLiteralLockedStep: false
            )
            lastCommittedProvenance = candidateProvenance
        }

        let oldComposingCount = (composingWord.isEmpty ? output : composingWord).utf16.count
        if let dotPrefix = dotPrefixToRestore, !recentWords.isEmpty {
            recentWords[recentWords.count - 1] = dotPrefix.raw
            hasVietnameseInputEvidence = recentWords.contains(where: { Self.containsVietnameseWord($0) })
        }
        if let spacePrefix = spacePrefixToRestore, !recentWords.isEmpty {
            recentWords[recentWords.count - 1] = spacePrefix.raw
            hasVietnameseInputEvidence = recentWords.contains(where: { Self.containsVietnameseWord($0) })
        }
        if let vnCompound = vnCompoundPrefixToRestore, !recentWords.isEmpty {
            recentWords[recentWords.count - 1] = vnCompound.vnPrefix
            hasVietnameseInputEvidence = true
        }
        appendContext(finalWord)

        if boundaryChar == "." {
            pendingDotPrefix = (raw: savedRaw, rendered: finalWord)
            pendingSpacePrefix = nil
        } else if boundaryChar == " " &&
                  spacePrefixToRestore == nil &&
                  vnCompoundPrefixToRestore == nil &&
                  dotPrefixToRestore == nil &&
                  smartBilingualEnabled &&
                  !hasExplicitAccentSelection &&
                  explicitBilingualSelection == nil &&
                  Self.shouldArmSpacePrefix(raw: savedRaw, rendered: finalWord) {
            pendingDotPrefix = nil
            pendingSpacePrefix = (raw: savedRaw, rendered: finalWord)
        } else {
            pendingDotPrefix = nil
            pendingSpacePrefix = nil
        }
        engine.commitWord(raw: savedRaw, rendered: finalWord)
        composingWord = ""
        rawWord = ""
        hasExplicitAccentSelection = false
        explicitBilingualSelection = nil
        candidateProvenance = .empty
        provenanceHistory.removeAll(keepingCapacity: true)
        editCaretBack = -1
        sessionGeneration &+= 1
        if let dotPrefix = dotPrefixToRestore, dotPrefix.raw != dotPrefix.rendered {
            let totalBackspaces = dotPrefix.rendered.utf16.count + 1 + oldComposingCount
            return .commit(backspaces: totalBackspaces, text: dotPrefix.raw + "." + finalWord, isOverride: true)
        }
        if let spacePrefix = spacePrefixToRestore, spacePrefix.raw != spacePrefix.rendered {
            let totalBackspaces = spacePrefix.rendered.utf16.count + 1 + oldComposingCount
            return .commit(backspaces: totalBackspaces, text: spacePrefix.raw + " " + finalWord, isOverride: true)
        }
        if let vnCompound = vnCompoundPrefixToRestore {
            let totalBackspaces = vnCompound.prefix.rendered.utf16.count + 1 + oldComposingCount
            return .commit(backspaces: totalBackspaces, text: vnCompound.vnPrefix + " " + finalWord, isOverride: true)
        }
        return .commit(backspaces: oldComposingCount, text: finalWord, isOverride: isOverride)
    }

    /// Evaluates the active composition across all three Bilingual Intent candidates (P0.3):
    /// 1) Raw literal candidate, 2) Vietnamese Telex candidate, 3) Explicit escape / user-selected candidate.
    public func evaluateBilingualCandidates(boundaryChar: Character? = nil) -> BilingualArbitrationResult {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let currentRendered = engine.currentOutput()
        let effectiveRaw = rawWord.isEmpty ? currentRendered : rawWord
        return BilingualIntentArbiter.arbitrate(
            raw: effectiveRaw,
            rendered: currentRendered.isEmpty ? composingWord : currentRendered,
            context: context,
            noContextPolicy: bilingualNoContextPolicy,
            hasExplicitUserSelection: hasExplicitAccentSelection,
            precededByTechnicalDelimiter: precededByTechnicalDelimiter || activeDotPrefix != nil,
            boundaryChar: boundaryChar,
            isInlineComposition: isComposing,
            genZMode: genZMode
        )
    }

    #if !VIELOTUS_OPEN_CORE_MACOS
    /// Commits a user-selected suggestion as official Unicode (V1 Section 2.D: `teh -> chọn "the" -> Backspace -> th`),
    /// replacing the active composition and arming character-level deletion at the end of the committed suggestion.
    public func selectSuggestion(_ suggestion: String, trailingSpace: Bool = false) -> SessionAction {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let priorCount = composingWord.utf16.count
        let tokens = suggestion.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for tok in tokens {
            appendContext(tok)
        }
        let lastToken = tokens.last ?? suggestion
        engine.commitWord(raw: lastToken, rendered: lastToken, isOfficialSuggestion: true)
        composingWord = ""
        rawWord = ""
        hasExplicitAccentSelection = false
        explicitBilingualSelection = nil
        pendingDotPrefix = nil
        activeDotPrefix = nil
        pendingSpacePrefix = nil
        activeSpacePrefix = nil
        editCaretBack = trailingSpace ? -1 : 0
        sessionGeneration &+= 1
        let finalOutput = trailingSpace ? (suggestion + " ") : suggestion
        return .commit(backspaces: priorCount, text: finalOutput, isOverride: true)
    }
    #endif
}
