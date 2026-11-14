import Foundation

public enum InputMethodType: Int32, Sendable {
    case telex = 0
    case vni = 1
}

/// Verified semantic classification for a post-commit edit transaction (`editAt`, P0.5).
public enum PostCommitEditDecisionKind: String, Sendable, Equatable {
    case toneModification = "tone_modification"
    case toneReplacement = "tone_replacement"
    case toneCancellationClear = "tone_cancellation_clear"
    case toneCancellationEmitLiteral = "tone_cancellation_emit_literal"
    case vowelShapeModification = "vowel_shape_modification"
    case vowelShapeReshape = "vowel_shape_reshape"
    case vowelShapeCancellation = "vowel_shape_cancellation"
    case strokeModification = "stroke_modification"
    case strokeCancellation = "stroke_cancellation"
}

/// Verified provenance record and replacement plan for a post-commit edit transaction (P0.5 Section 2).
public struct PostCommitEditTransaction: Sendable, Equatable {
    public let inputMethod: InputMethodType
    public let triggerKey: Character
    public let priorRenderedWord: String
    public let priorCanonicalRaw: String
    public let resultingRenderedWord: String
    public let resultingCanonicalRaw: String
    public let decisionKind: PostCommitEditDecisionKind
    public let utf16Backspaces: Int
    public let replacementSuffix: String
    public let isLiteralLockedAfterEdit: Bool

    public init(
        inputMethod: InputMethodType,
        triggerKey: Character,
        priorRenderedWord: String,
        priorCanonicalRaw: String,
        resultingRenderedWord: String,
        resultingCanonicalRaw: String,
        decisionKind: PostCommitEditDecisionKind,
        utf16Backspaces: Int,
        replacementSuffix: String,
        isLiteralLockedAfterEdit: Bool
    ) {
        self.inputMethod = inputMethod
        self.triggerKey = triggerKey
        self.priorRenderedWord = priorRenderedWord
        self.priorCanonicalRaw = priorCanonicalRaw
        self.resultingRenderedWord = resultingRenderedWord
        self.resultingCanonicalRaw = resultingCanonicalRaw
        self.decisionKind = decisionKind
        self.utf16Backspaces = utf16Backspaces
        self.replacementSuffix = replacementSuffix
        self.isLiteralLockedAfterEdit = isLiteralLockedAfterEdit
    }
}

/// Backspace behavior during active composition (VieLotus Unified Telex V1).
public enum BackspaceStyle: Int, CaseIterable, Sendable {
    /// Apple-style semantic backspace (default): strips tone first, then vowel shape, then characters (`được -> đươc -> đuoc -> đuo -> đu -> đ -> d -> ∅`).
    case appleSemantic = 0
    /// Gboard-style fast character backspace: deletes the last displayed character directly (`được -> đượ -> đư -> đ -> ∅`).
    case gboardCharacter = 1
}

/// Native Pure Swift Vietnamese input engine bridge wrapping VietnameseEngine.
public final class EngineBridge {
    private let engine = VietnameseEngine()

    public var isComposing: Bool {
        engine.isComposing
    }

    public var renderedOutputIsASCII: Bool {
        engine.renderedOutputIsASCII
    }

    public var rawFastMask: UInt16 {
        engine.rawFastMask
    }

    public init() {
        setInputMethod(.telex)
        setModernOrthography(true)
    }

    public var inputMethod: InputMethodType {
        engine.inputMethod
    }

    public func setInputMethod(_ method: InputMethodType) {
        engine.inputMethod = method
    }

    public var grammarProfile: GrammarProfile {
        engine.grammarProfile
    }

    public func setGrammarProfile(_ profile: GrammarProfile) {
        engine.grammarProfile = profile
    }

    public var modernOrthography: Bool {
        engine.modernOrthography
    }

    public func setModernOrthography(_ enabled: Bool) {
        engine.modernOrthography = enabled
    }

    public func setRelaxedCoda(_ enabled: Bool) {
        engine.relaxedCoda = enabled
    }

    public func setQuickTelex(_ enabled: Bool) {
        engine.quickTelex = enabled
    }

    public func setGenZMode(_ enabled: Bool) {
        engine.genZMode = enabled
    }

    public func setQuickStart(_ enabled: Bool) {
        engine.quickStart = enabled
    }

    public var simpleTelex: Bool {
        get { engine.simpleTelex }
        set { engine.simpleTelex = newValue }
    }

    public func setSimpleTelex(_ enabled: Bool) {
        engine.simpleTelex = enabled
    }

    public var backspaceStyle: BackspaceStyle {
        get { engine.backspaceStyle }
        set { engine.backspaceStyle = newValue }
    }

    public func setBackspaceStyle(_ style: BackspaceStyle) {
        engine.backspaceStyle = style
    }

    public var literalOverrideEnabled: Bool {
        get { engine.literalOverrideEnabled }
        set { engine.literalOverrideEnabled = newValue }
    }

    public var isExplicitlyLiteralLocked: Bool {
        engine.isExplicitlyLiteralLocked
    }

    public var lastFeedWasRejectedNoOp: Bool {
        engine.lastFeedWasRejectedNoOp
    }

    public var lastToneSemanticEvent: ToneModifierSemanticEvent? {
        engine.lastToneSemanticEvent
    }

    public var hasConfirmedSemanticEscapeInComposition: Bool {
        engine.hasConfirmedSemanticEscapeInComposition
    }

    internal var activeToneModifier: Character? {
        engine.activeToneModifier
    }

    internal var activeVowelModifiers: [Character] {
        engine.activeVowelModifiers
    }

    internal var supersededModifiers: [Character] {
        engine.supersededModifiers
    }

    internal var isEditingCommittedWord: Bool {
        engine.isEditingCommittedWord
    }

    internal var nextBackspaceRestorationState: String? {
        engine.nextBackspaceRestorationState
    }

    public func feedLiteral(_ ch: Character) -> (backspaces: Int, suffix: String)? {
        engine.feedLiteral(ch)
    }

    public func forceLiteralOutput(_ text: String) {
        engine.forceLiteralOutput(text)
    }

    public func reset() {
        engine.reset()
    }

    public func feed(_ ch: Character) -> (backspaces: Int, suffix: String)? {
        engine.feed(ch)
    }

    public func backspace(displayedAsRaw: Bool = false) -> (backspaces: Int, suffix: String)? {
        engine.backspace(displayedAsRaw: displayedAsRaw)
    }

    public func commit() -> (backspaces: Int, suffix: String)? {
        engine.commit()
    }

    public var lastCommittedWord: String? {
        engine.lastCommittedWord
    }

    public var lastCommittedRaw: String? {
        engine.lastCommittedRaw
    }

    #if VIELOTUS_OPEN_CORE_MACOS
    public func commitWord(raw: String, rendered: String) {
        engine.commitWord(raw: raw, rendered: rendered)
    }
    #else
    public func commitWord(raw: String, rendered: String, isOfficialSuggestion: Bool = false) {
        engine.commitWord(raw: raw, rendered: rendered, isOfficialSuggestion: isOfficialSuggestion)
    }
    #endif

    public func clearHistory() {
        engine.clearHistory()
    }

    public var lastPostCommitEditTransaction: PostCommitEditTransaction? {
        engine.lastPostCommitEditTransaction
    }

    public func editAt(caretBack: Int, char: Character) -> (backspaces: Int, suffix: String)? {
        guard caretBack == 0 else { return nil }
        return engine.editAt(caretBack: caretBack, char: char)
    }

    public func editBackspaceAt(caretBack: Int) -> (backspaces: Int, suffix: String)? {
        guard caretBack == 0 else { return nil }
        return engine.editBackspaceAt(caretBack: caretBack)
    }

    public func currentOutput() -> String {
        engine.currentOutput()
    }

    public func rawString() -> String {
        engine.rawString()
    }

    public func setCompositionPrefix(_ text: String) {
        engine.setCompositionPrefix(text)
    }

    public static func rawKeys(for text: String, inputMethod: InputMethodType) -> String {
        VietnameseEngine.rawKeys(for: text, inputMethod: inputMethod)
    }

    public func semanticTransformations(for text: String) -> [String] {
        VietnameseEngine.extractSemanticTransformations(from: text, inputMethod: engine.inputMethod)
    }

    public func literalSuffix(for rendered: String, raw: String) -> String {
        VietnameseEngine.extractLiteralSuffix(
            from: rendered,
            raw: raw,
            relaxedCoda: engine.relaxedCoda,
            genZMode: engine.genZMode
        )
    }
}
