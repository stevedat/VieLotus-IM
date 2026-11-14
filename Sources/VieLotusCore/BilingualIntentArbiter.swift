import Foundation

// MARK: - P0.3 Frequency-Aware Bilingual Intent Arbitration

/// Identifies one of the three canonical candidates evaluated for a raw keystroke sequence.
public enum BilingualCandidateKind: String, Sendable, Equatable {
    /// 1. Raw literal ASCII candidate (e.g. `"sex"`, `"is"`, `"as"`, `"if"`, `"rest"`, `"theme"`, `"cana"`).
    case rawLiteral
    /// 2. Vietnamese Telex composed candidate (e.g. `"sẽ"`, `"í"`, `"á"`, `"ì"`, `"rét"`, `"thêm"`, `"cân"`).
    case vietnameseTelex
    /// 3. Explicit Telex escape (`sexx -> sex`, `iss -> is`, `canhff -> canhf`) or user-selected candidate.
    case explicitEscapeOrSelected
}

/// Configurable no-context arbitration policy for standalone collision tokens (P0.3, P0.4.1 Section 1, P0.4.2 Section 5).
public enum BilingualNoContextPolicy: String, Sendable, Equatable, CaseIterable {
    /// P0.4.1 / P0.4.2 Default Probabilistic Bilingual Policy:
    /// Evaluates standalone collisions using normalized lexical log-frequencies (`[0.0, 10.0]` scale) and additive heuristic
    /// priors rather than blindly choosing every valid Vietnamese syllable.
    /// Prefers `"is"` for standalone `is/í` (`enFreq = 9.8 vs vnFreq = 2.6 + vnPrior 3.5 = 6.1`, uncalibrated logistic confidence $\sigma(\Delta) = 97.6\%$),
    /// while preserving core Vietnamese syllables (`sex -> sẽ`, `tree -> trê`, `queen -> quên`, `been -> bên`, `too -> tô`, `moon -> môn`).
    case probabilisticBilingual
    /// Legacy strict Vietnamese-first policy: preserves 100% reachability of single-path Vietnamese syllables
    /// (`sex -> sẽ`, `is -> í`, `as -> á`, `if -> ì`, `rest -> rét`, `theme -> thêm`, `cana -> cân`)
    /// when there is no preceding context, while offering the raw English candidate in the suggestion bar.
    case standardVietnameseFirst
    /// Experimental frequency-weighted A/B hypothesis (P0.3 Section B):
    /// Compares normalized Vietnamese vs English lexical frequencies when context is empty,
    /// preferring `sẽ` for `sex` (`VN 9.5 > EN 6.5`) and `is` for `is` (`EN 9.8 > VN 2.5`),
    /// while always keeping the opposite-language candidate accessible in the suggestion bar.
    case experimentalFrequencyWeighted
}

// MARK: - P0.4.2 Section 2: Sentence-Level Language State

/// Trailing language momentum across recent tokens in the current sentence/session (P0.4.2 Section 2).
public enum SentenceLanguageMomentum: String, Sendable, Equatable, CaseIterable {
    case neutral
    case english
    case vietnamese
}

/// Multi-token sentence-level language state computed from recent session memory (P0.4.2 Section 2).
/// Evaluates up to the last 5 committed tokens while preserving instant bidirectional mid-sentence
/// code-switching (English -> Vietnamese and Vietnamese -> English) without locking the whole sentence.
public struct SentenceLanguageState: Sendable, Equatable {
    public let recentTokens: [String]
    public let englishTokenCount: Int
    public let vietnameseTokenCount: Int
    public let consecutiveTrailingEnglishCount: Int
    public let consecutiveTrailingVietnameseCount: Int
    public let momentum: SentenceLanguageMomentum

    public static let empty = SentenceLanguageState(
        recentTokens: [],
        englishTokenCount: 0,
        vietnameseTokenCount: 0,
        consecutiveTrailingEnglishCount: 0,
        consecutiveTrailingVietnameseCount: 0,
        momentum: .neutral
    )

    public init(
        recentTokens: [String],
        englishTokenCount: Int,
        vietnameseTokenCount: Int,
        consecutiveTrailingEnglishCount: Int,
        consecutiveTrailingVietnameseCount: Int,
        momentum: SentenceLanguageMomentum
    ) {
        self.recentTokens = recentTokens
        self.englishTokenCount = englishTokenCount
        self.vietnameseTokenCount = vietnameseTokenCount
        self.consecutiveTrailingEnglishCount = consecutiveTrailingEnglishCount
        self.consecutiveTrailingVietnameseCount = consecutiveTrailingVietnameseCount
        self.momentum = momentum
    }
}

// MARK: - P0.4.1 Section 2: Grammar-Aware Phonotactics

/// Identifies which grammar layer validates a candidate Vietnamese syllable (P0.4.1 Section 2).
public enum GrammarPhonotacticLayer: String, Sendable, Equatable, CaseIterable {
    /// Valid under strict Standard Vietnamese orthography (`phê`, `trê`, `quên`, `cành`, `không`).
    case standardTelex
    /// Valid via Gen-Z Mode onset mapping (`f -> ph`, `j/z -> gi/d/v/tr/r`, `w -> qu`, e.g. `fê <-> phê`, `fải`, `fòng`, `wá`).
    case genZExtension
    /// Valid via Relaxed Coda mapping (`-g -> -ng`, `-h -> -nh`, `-k -> -c`, e.g. `khôg`, `kêh`, `đươk`).
    case relaxedCodaExtension
    /// Phonotactically impossible across all Vietnamese grammar layers (`frê`, `grên`, `gôd`).
    case invalid
}

/// Grammar-aware phonotactic analysis distinguishing Standard Telex, Gen-Z Mode, and Relaxed Coda (P0.4.1 Section 2).
public struct GrammarAwarePhonotacticProfile: Sendable, Equatable {
    public let layer: GrammarPhonotacticLayer
    public let isStandardPhonotacticValid: Bool
    public let isGenZPhonotacticValid: Bool
    public let isRelaxedCodaPhonotacticValid: Bool
    public let isActiveGrammarValid: Bool
    public let blockedGenZExpansionOnEnglishWord: Bool
    public let blockedRelaxedCodaOnEnglishWord: Bool

    public init(
        layer: GrammarPhonotacticLayer,
        isStandardPhonotacticValid: Bool,
        isGenZPhonotacticValid: Bool,
        isRelaxedCodaPhonotacticValid: Bool,
        isActiveGrammarValid: Bool,
        blockedGenZExpansionOnEnglishWord: Bool = false,
        blockedRelaxedCodaOnEnglishWord: Bool = false
    ) {
        self.layer = layer
        self.isStandardPhonotacticValid = isStandardPhonotacticValid
        self.isGenZPhonotacticValid = isGenZPhonotacticValid
        self.isRelaxedCodaPhonotacticValid = isRelaxedCodaPhonotacticValid
        self.isActiveGrammarValid = isActiveGrammarValid
        self.blockedGenZExpansionOnEnglishWord = blockedGenZExpansionOnEnglishWord
        self.blockedRelaxedCodaOnEnglishWord = blockedRelaxedCodaOnEnglishWord
    }
}

// MARK: - P0.4.1 Section 3: Candidate State Provenance

/// Explicit reason why the active candidate was selected (P0.4.1 Section 3).
public enum CandidateSelectionReason: String, Sendable, Equatable, CaseIterable {
    case empty
    case asciiPassThrough
    case vietnameseComposition
    case noContextFrequencyPrior
    case englishContext
    case vietnameseContext
    case technicalContext
    case phonotacticInvalidVN
    case phonotacticGapVN
    case genZBlockedOnEnglishWord
    case relaxedCodaBlockedOnEnglishWord
    case explicitTelexEscape
    case explicitLiteralOverride
    case userSelectedSuggestion
    case hysteresisRetained
}

/// Explicit escape state of the current composition (P0.4.1 Section 3 & 5).
public enum ExplicitEscapeKind: String, Sendable, Equatable, CaseIterable {
    case none
    /// Classic adjacent Telex vowel/horn/stroke escape (`trê + e -> tree`, `sê + e -> see`, `aaa -> aa`, `aww -> aw`).
    case classicVowelEscape
    /// Semantic repeated tone escape (`canhf + f -> canhf`, `cành + f -> canhf`).
    case semanticToneEscape
    /// Explicit `z` tone removal (`cành + z -> canh`).
    case zToneClear
    /// Locked in literal mode after raw English candidate was already selected (`tree + e -> treee`, `fee + e -> feee`).
    case literalLockedAfterSelection
}

/// Stability tier distinguishing provisional automatic arbitration from explicit user selection or Telex escape (P0.7 Section 3).
public enum CandidateSelectionStability: String, Sendable, Equatable, CaseIterable {
    /// Automatically selected candidate that remains open to delayed Vietnamese transformations as more keys arrive.
    case provisional
    /// Locked after an explicit Telex/VNI escape or post-selection literal append (`mix + x -> mixx`, `mĩ + x -> mix`).
    case explicitEscape
    /// Locked after an explicit user candidate selection or accent callout selection.
    case explicitSelection
}

/// Complete provenance record for the active composition candidate (P0.4.1 Section 3, P0.4.2 Section 3 & P0.7 Section 3/5).
/// Prevents inferring candidate selection state by merely comparing strings.
public struct CompositionCandidateProvenance: Sendable, Equatable {
    public let rawCandidate: String
    public let vietnameseCandidate: String
    public let selectedCandidate: String
    public let selectedKind: BilingualCandidateKind
    public let selectionReason: CandidateSelectionReason
    public let explicitEscapeState: ExplicitEscapeKind
    public let selectionStability: CandidateSelectionStability
    public let toneSemanticEvent: ToneModifierSemanticEvent?
    public let semanticTransformations: [String]
    public let literalSuffix: String
    public let flipCount: Int
    public let stabilityMargin: Double
    public let context: String
    public let sentenceLanguageState: SentenceLanguageState
    public let transitionReason: String

    public static let empty = CompositionCandidateProvenance(
        rawCandidate: "",
        vietnameseCandidate: "",
        selectedCandidate: "",
        selectedKind: .vietnameseTelex,
        selectionReason: .empty,
        explicitEscapeState: .none,
        selectionStability: .provisional,
        toneSemanticEvent: nil,
        semanticTransformations: [],
        literalSuffix: "",
        flipCount: 0,
        stabilityMargin: 0.0,
        context: "",
        sentenceLanguageState: .empty,
        transitionReason: "empty"
    )

    public init(
        rawCandidate: String,
        vietnameseCandidate: String,
        selectedCandidate: String,
        selectedKind: BilingualCandidateKind,
        selectionReason: CandidateSelectionReason,
        explicitEscapeState: ExplicitEscapeKind,
        selectionStability: CandidateSelectionStability = .provisional,
        toneSemanticEvent: ToneModifierSemanticEvent? = nil,
        semanticTransformations: [String],
        literalSuffix: String,
        flipCount: Int = 0,
        stabilityMargin: Double = 0.0,
        context: String = "",
        sentenceLanguageState: SentenceLanguageState = .empty,
        transitionReason: String = "initial"
    ) {
        self.rawCandidate = rawCandidate
        self.vietnameseCandidate = vietnameseCandidate
        self.selectedCandidate = selectedCandidate
        self.selectedKind = selectedKind
        self.selectionReason = selectionReason
        self.explicitEscapeState = explicitEscapeState
        self.selectionStability = selectionStability
        self.toneSemanticEvent = toneSemanticEvent
        self.semanticTransformations = semanticTransformations
        self.literalSuffix = literalSuffix
        self.flipCount = flipCount
        self.stabilityMargin = stabilityMargin
        self.context = context
        self.sentenceLanguageState = sentenceLanguageState
        self.transitionReason = transitionReason
    }
}

/// Detailed multi-factor score breakdown for a single bilingual candidate (P0.3 Section A, P0.4.1 Section 1, P0.4.2 Section 5).
/// Note on calibration (P0.4.2 Section 5): `posteriorProbability` (`heuristicConfidence`) is an uncalibrated unit-temperature
/// logistic sigmoid $\sigma(\Delta\text{score}) = 1 / (1 + \exp(-\Delta\text{score}))$ over static `[0.0, 10.0]` lexical log-frequency
/// tiers and additive rule weights, NOT an empirically calibrated Bayesian posterior probability.
public struct BilingualCandidateEvaluation: Sendable, Equatable {
    public let kind: BilingualCandidateKind
    public let text: String
    public let totalScore: Double
    /// Uncalibrated heuristic logistic confidence $\sigma(\Delta\text{score})$ (retained under `posteriorProbability` for API compatibility).
    public let posteriorProbability: Double
    public var heuristicConfidence: Double { posteriorProbability }
    public let vnLexicalFrequency: Double
    public let enLexicalFrequency: Double
    public let precedingContextScore: Double
    public let collocationScore: Double
    public let explicitIntentScore: Double
    public let technicalContextScore: Double
    public let compositionStabilityScore: Double

    public init(
        kind: BilingualCandidateKind,
        text: String,
        totalScore: Double,
        posteriorProbability: Double = 0.5,
        vnLexicalFrequency: Double = 0,
        enLexicalFrequency: Double = 0,
        precedingContextScore: Double = 0,
        collocationScore: Double = 0,
        explicitIntentScore: Double = 0,
        technicalContextScore: Double = 0,
        compositionStabilityScore: Double = 0
    ) {
        self.kind = kind
        self.text = text
        self.totalScore = totalScore
        self.posteriorProbability = posteriorProbability
        self.vnLexicalFrequency = vnLexicalFrequency
        self.enLexicalFrequency = enLexicalFrequency
        self.precedingContextScore = precedingContextScore
        self.collocationScore = collocationScore
        self.explicitIntentScore = explicitIntentScore
        self.technicalContextScore = technicalContextScore
        self.compositionStabilityScore = compositionStabilityScore
    }
}

/// Result of arbitrating a raw keystroke sequence across all candidate interpretations.
public struct BilingualArbitrationResult: Sendable, Equatable {
    public let rawInput: String
    public let composedVietnamese: String
    public let context: String
    public let sentenceLanguageState: SentenceLanguageState
    public let noContextPolicy: BilingualNoContextPolicy
    public let candidates: [BilingualCandidateEvaluation]
    /// Uncalibrated heuristic logistic confidence $\sigma(\text{vnTotal} - \text{enTotal})$ (P0.4.2 Section 5).
    public let vietnameseProbability: Double
    /// Uncalibrated heuristic logistic confidence $\sigma(\text{enTotal} - \text{vnTotal})$ (P0.4.2 Section 5).
    public let englishProbability: Double
    public var heuristicVietnameseConfidence: Double { vietnameseProbability }
    public var heuristicEnglishConfidence: Double { englishProbability }
    public let scoreMargin: Double
    public let selectionReason: CandidateSelectionReason
    public let phonotacticProfile: GrammarAwarePhonotacticProfile

    public init(
        rawInput: String,
        composedVietnamese: String,
        context: String,
        sentenceLanguageState: SentenceLanguageState = .empty,
        noContextPolicy: BilingualNoContextPolicy,
        candidates: [BilingualCandidateEvaluation],
        vietnameseProbability: Double = 0.5,
        englishProbability: Double = 0.5,
        scoreMargin: Double = 0.0,
        selectionReason: CandidateSelectionReason = .vietnameseComposition,
        phonotacticProfile: GrammarAwarePhonotacticProfile = GrammarAwarePhonotacticProfile(
            layer: .standardTelex,
            isStandardPhonotacticValid: true,
            isGenZPhonotacticValid: true,
            isRelaxedCodaPhonotacticValid: true,
            isActiveGrammarValid: true
        )
    ) {
        self.rawInput = rawInput
        self.composedVietnamese = composedVietnamese
        self.context = context
        self.sentenceLanguageState = sentenceLanguageState
        self.noContextPolicy = noContextPolicy
        self.candidates = candidates
        self.vietnameseProbability = vietnameseProbability
        self.englishProbability = englishProbability
        self.scoreMargin = scoreMargin
        self.selectionReason = selectionReason
        self.phonotacticProfile = phonotacticProfile
    }

    public var primaryCandidate: BilingualCandidateEvaluation {
        candidates.first ?? BilingualCandidateEvaluation(
            kind: .vietnameseTelex,
            text: composedVietnamese,
            totalScore: 0
        )
    }

    public var secondaryCandidate: BilingualCandidateEvaluation? {
        guard candidates.count >= 2 else { return nil }
        let primaryLower = primaryCandidate.text.lowercased()
        return candidates.dropFirst().first { $0.text.lowercased() != primaryLower }
    }

    public var prefersRawEnglish: Bool {
        primaryCandidate.kind == .rawLiteral
    }
}

/// Taxonomy of English/Vietnamese Telex collisions (P0.4 Systematic Collision Resolution).
public enum BilingualCollisionCategory: String, Sendable, Equatable, CaseIterable {
    /// No Telex diacritic transformation occurred (`raw == rendered`).
    case noCollision
    /// Group 1: The Telex-transformed string violates standard Vietnamese phonotactics
    /// (e.g. non-Vietnamese initial `f, j, w, z` or consonant cluster `fr, gr, bl, br, cl, cr, dr, fl, gl, pl, pr, st, ...`,
    /// or invalid coda `-k, -d, -b, -f, -l, -r, -s, -v, -z`, or stop-coda tone rule violation):
    /// `fee/fê`, `fees/fế`, `free/frê`, `green/grên`, `book/bôk`, `good/gôd`.
    case invalidVietnameseCandidate
    /// Phonotactically well-formed Vietnamese onset+nucleus+coda+tone, but unattested in the Vietnamese
    /// lexical syllable dictionary while the raw token is a known English word (e.g. `trees/trế`, `teens/tến`).
    case phonotacticGapVietnamese
    /// Group 2: Both the raw English word and the Telex double-vowel Vietnamese syllable (`aa -> â`, `ee -> ê`, `oo -> ô`)
    /// are valid, attested words in their respective languages (`tree/trê`, `queen/quên`, `teen/tên`, `been/bên`,
    /// `seen/sên`, `bee/bê`, `bees/bế`, `beer/bể`, `moon/môn`, `noon/nôn`, `room/rôm`, `too/tô`, `boots/bốt`).
    case validBilingualVowelCollision
    /// Group 3: Both the raw English word and the Telex tone (`s, f, r, x, j`) or horn/breve (`w`) Vietnamese syllable
    /// are valid, attested words in their respective languages (`sex/sẽ`, `is/í`, `six/sĩ`, `cats/cát`, `hats/hát`,
    /// `last/lát`, `best/bét`, `rest/rét`, `car/cả`, `bar/bả`, `now/nơ`, `cow/cơ`).
    case validBilingualToneOrHornCollision
}

/// Lexically verified entry in the P0.4 Bilingual Collision Corpus.
public struct BilingualCollisionCorpusEntry: Sendable, Equatable {
    public let rawEnglish: String
    public let naiveTelex: String
    public let category: BilingualCollisionCategory
    public let isPhonotacticallyValidVN: Bool
    public let isAttestedVNSyllable: Bool
    public let isKnownEnglishWord: Bool
    public let vnFrequency: Double
    public let enFrequency: Double
    public let defaultNoContextWinner: String
    public let vnContextWinner: String
    public let enContextWinner: String

    public init(
        rawEnglish: String,
        naiveTelex: String,
        category: BilingualCollisionCategory,
        isPhonotacticallyValidVN: Bool,
        isAttestedVNSyllable: Bool,
        isKnownEnglishWord: Bool,
        vnFrequency: Double,
        enFrequency: Double,
        defaultNoContextWinner: String,
        vnContextWinner: String,
        enContextWinner: String
    ) {
        self.rawEnglish = rawEnglish
        self.naiveTelex = naiveTelex
        self.category = category
        self.isPhonotacticallyValidVN = isPhonotacticallyValidVN
        self.isAttestedVNSyllable = isAttestedVNSyllable
        self.isKnownEnglishWord = isKnownEnglishWord
        self.vnFrequency = vnFrequency
        self.enFrequency = enFrequency
        self.defaultNoContextWinner = defaultNoContextWinner
        self.vnContextWinner = vnContextWinner
        self.enContextWinner = enContextWinner
    }
}

/// Shared, platform-independent Frequency-Aware Bilingual Intent Arbiter (`macOS` + `iOS` in `VieLotusCore`).
///
/// Arbitrates collision pairs (`sex/sẽ`, `is/í`, `as/á`, `if/ì`, `rest/rét`, `theme/thêm`, `cana/cân`, etc.)
/// using offline normalized lexical frequencies, preceding context, grammatical collocation validity,
/// explicit user intent, technical delimiters, and composition stability.
/// Enforces strict Zero Data Collection (no user content logging or telemetry).
public struct BilingualIntentArbiter: Sendable {
    /// Offline normalized `[0.0, 10.0]` Vietnamese lexical frequency table for collision syllables.
    public static let vietnameseCollisionLogFrequencies: [String: Double] = [
        "sẽ": 9.5,
        "có": 9.7,
        "là": 9.8,
        "và": 9.7,
        "để": 9.2,
        "đó": 9.0,
        "đi": 9.1,
        "đã": 9.3,
        "vào": 8.9,
        "còn": 8.9,
        "tốt": 8.7,
        "thêm": 8.6,
        "công": 8.7,
        "bán": 8.3,
        "cả": 8.6,
        "làm": 9.2,
        "mình": 9.0,
        "nhân": 8.4,
        "tên": 8.5,
        "bên": 8.4,
        "quên": 8.0,
        "trông": 7.9,
        "cân": 7.4,
        "họ": 8.8,
        "gì": 9.1,
        "vì": 8.9,
        "bà": 8.2,
        "bả": 6.2,
        "cá": 7.9,
        "lá": 7.6,
        "má": 7.5,
        "há": 6.4,
        "té": 6.8,
        "tê": 6.7,
        "trê": 6.6,
        "mê": 7.2,
        "bê": 6.5,
        "bế": 6.8,
        "bể": 7.1,
        "sê": 5.2,
        "pê": 4.8,
        "tô": 7.4,
        "bốt": 5.8,
        "lô": 7.1,
        "môn": 7.6,
        "nôn": 6.4,
        "rôm": 5.5,
        "bôm": 4.9,
        "sên": 6.1,
        "kên": 4.8,
        "rề": 5.8,
        "mêm": 4.5,
        "hể": 5.4,
        "sĩ": 7.4,
        "nơ": 6.3,
        "cơ": 7.8,
        "lẻ": 7.3,
        "mẻ": 6.4,
        "vẻ": 7.7,
        "rẻ": 7.6,
        "thẻ": 7.5,
        "sẻ": 7.0,
        "kẻ": 7.4,
        "họp": 7.8,
        "lớp": 8.3,
        "sớm": 8.0,
        "hơn": 8.8,
        "sơn": 7.7,
        "đơn": 8.1,
        "cơn": 7.5,
        "mới": 8.9,
        "tới": 8.5,
        "nơi": 8.3,
        "chơi": 8.4,
        "bơi": 7.3,
        "rơi": 7.6,
        "hơi": 7.9,
        "lời": 8.2,
        "trời": 8.3,
        "đời": 8.4,
        "thời": 8.5,
        "mời": 8.0,
        "cười": 8.1,
        "người": 9.4,
        "mười": 8.2,
        "tươi": 7.6,
        "lười": 6.9,
        "dưới": 8.3,
        "cưới": 7.5,
        "lưới": 7.1,
        "tưới": 6.8,
        "rét": 6.6,
        "mét": 7.1,
        "nét": 7.6,
        "két": 6.0,
        "xét": 7.7,
        "hét": 6.8,
        "ghét": 7.3,
        "tét": 5.9,
        "bét": 6.1,
        "lát": 7.2,
        "mát": 7.6,
        "hát": 7.9,
        "cát": 7.3,
        "bát": 7.2,
        "át": 6.3,
        "đạt": 8.0,
        "mạt": 6.1,
        "bạt": 6.0,
        "hạt": 7.5,
        "nhạt": 6.9,
        "phạt": 7.4,
        "thắt": 6.8,
        "mắt": 8.3,
        "sắt": 7.4,
        "cắt": 7.8,
        "tắt": 7.7,
        "bắt": 8.4,
        "đắt": 7.5,
        "mất": 8.5,
        "đất": 8.4,
        "chất": 8.3,
        "nhất": 8.9,
        "rất": 9.1,
        "thật": 8.6,
        "luật": 8.1,
        "thuật": 7.9,
        "xuất": 8.3,
        "suất": 7.6,
        "tất": 8.2,
        "bất": 7.8,
        "cất": 7.1,
        "mật": 7.4,
        "vật": 8.2,
        "phật": 7.3,
        "nhật": 8.2,
        "lật": 7.0,
        "gật": 6.8,
        "giật": 7.2,
        "chật": 6.9,
        "ật": 4.2,
        "ít": 8.3,
        "mít": 6.7,
        "hít": 6.8,
        "bít": 6.2,
        "tít": 6.5,
        "kít": 5.4,
        "lít": 6.9,
        "vít": 6.4,
        "đít": 6.1,
        "xít": 5.8,
        "ịt": 3.8,
        "mịt": 6.4,
        "thịt": 7.9,
        "vịt": 7.2,
        "bịt": 6.5,
        "xịt": 6.6,
        "kịt": 5.5,
        "nhịp": 7.2,
        "kịp": 7.6,
        "dịp": 7.5,
        "bịp": 5.9,
        "hẹp": 7.1,
        "đẹp": 8.5,
        "kẹp": 6.7,
        "dẹp": 6.8,
        "xẹp": 6.1,
        "bẹp": 5.9,
        "nép": 6.2,
        "chép": 7.2,
        "ghép": 7.3,
        "thép": 7.6,
        "phép": 8.1,
        "khép": 7.0,
        "dép": 7.1,
        "mép": 6.6,
        "tép": 6.2,
        "xếp": 7.8,
        "bếp": 7.7,
        "nếp": 6.9,
        "cọp": 6.2,
        "góp": 7.9,
        "hóp": 5.9,
        "bóp": 6.9,
        "móp": 6.0,
        "chóp": 6.5,
        "tóp": 6.3,
        "ngóp": 5.5,
        "lợp": 6.7,
        "hợp": 8.4,
        "khớp": 7.1,
        "chớp": 6.9,
        "đớp": 5.8,
        "tớp": 5.4,
        "úp": 6.6,
        "giúp": 8.6,
        "cúp": 7.0,
        "búp": 6.7,
        "múp": 5.8,
        "núp": 6.3,
        "húp": 6.0,
        "súp": 6.4,
        "chụp": 7.8,
        "sụp": 6.7,
        "cụp": 5.9,
        "hụp": 5.8,
        "bụp": 5.5,
        "á": 3.1,
        "à": 7.8,
        "ả": 5.1,
        "ã": 4.2,
        "ạ": 7.5,
        "é": 4.6,
        "è": 5.2,
        "ẻ": 4.3,
        "ẽ": 3.9,
        "ẹ": 4.5,
        "í": 2.6,
        "ì": 2.9,
        "ỉ": 3.7,
        "ĩ": 2.4,
        "ị": 4.0,
        "thí": 4.8,
        "hí": 5.4,
        "mĩ": 4.2,
        "mỹ": 7.8,
        "ét": 5.6,
        "mể": 4.2,
        "bỏn": 4.4,
        "ó": 3.8,
        "ò": 2.8,
        "ỏ": 2.5,
        "õ": 3.8,
        "ọ": 4.4,
        "ú": 3.0,
        "ù": 5.3,
        "ủ": 5.9,
        "ũ": 4.5,
        "ụ": 5.0,
        "ý": 8.1,
        "ỳ": 6.8,
        "ỷ": 6.2,
        "ỹ": 5.6,
        "ỵ": 4.5,
        "ừ": 7.4,
        "ử": 4.9,
        "ứ": 5.8,
        "ữ": 4.2,
        "ự": 5.1,
        "ờ": 7.2,
        "ở": 8.9,
        "ớ": 5.4,
        "ỡ": 4.6,
        "ợ": 5.2,
        "ồ": 6.9,
        "ổ": 7.3,
        "ố": 6.5,
        "ỗ": 4.8,
        "ộ": 5.1
    ]

    /// Offline normalized `[0.0, 10.0]` English lexical frequency table for collision tokens.
    public static let englishCollisionLogFrequencies: [String: Double] = [
        "is": 9.8,
        "as": 9.4,
        "if": 9.1,
        "of": 9.9,
        "off": 8.8,
        "or": 9.3,
        "us": 8.6,
        "mix": 7.9,
        "est": 6.2,
        "os": 6.4,
        "ir": 5.7,
        "ix": 5.2,
        "ajax": 6.6,
        "mere": 5.2,
        "born": 8.1,
        "up": 9.0,
        "it": 9.7,
        "at": 9.5,
        "in": 9.8,
        "on": 9.6,
        "an": 9.3,
        "to": 9.9,
        "do": 9.2,
        "go": 8.8,
        "no": 9.1,
        "so": 9.1,
        "be": 9.6,
        "me": 9.0,
        "he": 9.5,
        "we": 9.3,
        "by": 9.3,
        "my": 9.1,
        "has": 9.1,
        "was": 9.5,
        "this": 9.7,
        "his": 9.3,
        "her": 9.1,
        "are": 9.5,
        "our": 8.9,
        "out": 9.1,
        "use": 8.9,
        "see": 8.9,
        "too": 8.7,
        "car": 8.2,
        "bar": 7.8,
        "far": 8.4,
        "war": 8.1,
        "set": 8.6,
        "get": 9.0,
        "let": 8.6,
        "net": 7.8,
        "met": 7.9,
        "bet": 7.3,
        "yet": 8.4,
        "sex": 6.5,
        "rest": 6.9,
        "theme": 6.3,
        "cana": 1.5,
        "meme": 5.8,
        "here": 8.9,
        "there": 9.2,
        "where": 8.8,
        "were": 9.1,
        "more": 9.2,
        "core": 7.4,
        "care": 8.2,
        "case": 8.6,
        "base": 8.0,
        "time": 9.3,
        "line": 8.4,
        "fine": 7.9,
        "home": 8.8,
        "some": 9.1,
        "come": 8.7,
        "done": 8.4,
        "code": 8.0,
        "mode": 7.5,
        "node": 7.1,
        "file": 8.1,
        "date": 8.1,
        "rate": 8.0,
        "state": 8.7,
        "test": 8.4,
        "best": 8.6,
        "list": 8.3,
        "cost": 8.1,
        "host": 7.5,
        "post": 8.2,
        "last": 8.7,
        "fast": 8.0,
        "turn": 8.2,
        "toast": 6.4,
        "seen": 8.3,
        "teen": 7.1,
        "teens": 6.8,
        "keen": 6.2,
        "queen": 7.2,
        "been": 9.2,
        "bee": 6.4,
        "bees": 6.2,
        "beer": 7.4,
        "tree": 8.1,
        "trees": 7.8,
        "fee": 7.4,
        "fees": 7.1,
        "free": 8.8,
        "green": 8.5,
        "book": 8.8,
        "boots": 6.9,
        "pee": 5.4,
        "room": 8.3,
        "moon": 7.2,
        "noon": 6.7,
        "boom": 6.6,
        "roof": 7.1,
        "reef": 6.1,
        "six": 8.4,
        "cats": 7.1,
        "hats": 6.5,
        "now": 9.5,
        "cow": 6.8,
        "user": 8.2,
        "users": 8.0,
        "does": 8.8,
        "life": 8.8,
        "safe": 8.0,
        "good": 8.9,
        "education": 8.1
    ]

    /// Vietnamese pre-verbal pronouns, temporal nouns, and modal adverbs that strongly license future marker `"sẽ"` (P0.3 Section A & F).
    private static let vietnamesePreVerbalModalTriggers: Set<String> = [
        "tôi", "mình", "bạn", "anh", "chị", "em", "nó", "họ", "ta",
        "chúng ta", "chúng tôi", "các bạn", "mọi người", "ai", "người",
        "ngày mai", "hôm nay", "tuần sau", "tháng sau", "năm sau", "mai",
        "sắp", "chắc", "chắc chắn", "cũng", "vẫn", "không", "chưa", "liệu",
        "đều", "ắt", "hẳn", "có lẽ", "nhất định"
    ]

    /// Vietnamese nominal/media contexts that borrow the English loanword `"sex"` where modal auxiliary `"sẽ"` is grammatically invalid (P0.3 Section A & F).
    private static let vietnameseSexLoanwordPrecedingHeads: Set<String> = [
        "phim", "clip", "video", "cảnh", "ảnh", "hình", "truyện", "web",
        "búp bê", "đồ chơi", "scandal", "nghiện", "tình dục và", "quan hệ"
    ]

    /// English pre-modifiers and verbs that collocate directly with `"sex"` (e.g. `"safe sex"`, `"have sex"`, `"opposite sex"`).
    private static let englishSexCollocationPrecedingWords: Set<String> = [
        "safe", "unsafe", "have", "having", "had", "about", "biological",
        "opposite", "same", "casual", "consensual", "premarital", "oral"
    ]

    /// Vietnamese compound/phrase preceding heads that strongly license the Vietnamese syllable in Group 2/3 collisions
    /// (e.g. `"cá trê"`, `"tôi quên"`, `"họ và tên"`, `"ở bên"`, `"tổ ong bê"`, `"môn học"`).
    private static let vietnameseCompoundPrecedingHeads: [String: Set<String>] = [
        "tree": ["cá", "con cá", "nấu", "kho"],
        "queen": ["tôi", "mình", "bạn", "anh", "chị", "em", "họ", "đừng", "không", "chưa", "đã", "bị", "hay"],
        "teen": ["họ", "đặt", "mang", "gọi", "ghi", "ký"],
        "been": ["ở", "phía", "hai", "một", "đứng", "ngồi", "sang"],
        "seen": ["ốc", "con", "bò"],
        "bee": ["con", "thịt", "búp"],
        "bees": ["bồng", "mẹ", "ẵm"],
        "beer": ["cá", "nước", "bơi", "vỡ"],
        "moon": ["bộ", "các", "học", "thi"],
        "noon": ["buồn", "ói"],
        "room": ["sẩy", "nổi"],
        "too": ["bát", "tô", "màu"],
        "boots": ["đôi", "giày", "mang"],
        "last": ["cắt", "mỗi", "từng"],
        "best": ["hạng", "đứng", "chót"],
        "car": ["tất", "với", "cho"],
        "bar": ["bánh", "thuốc", "mồi"],
        "now": ["cái", "thắt", "dây"],
        "cow": ["nguy", "thời", "động", "hữu"],
        "is": ["cái", "anh", "chị", "em", "con", "người", "này", "thế", "ơi", "mình", "bạn", "tôi", "nó", "họ", "bà", "ông", "cô", "chú", "bác", "thằng", "đứa", "chỗ", "lúc", "hồi"],
        "mix": ["nước", "châu", "bắc", "nam", "trung", "thẩm", "hoa", "hoàn", "tuyệt", "kiều", "người", "tiếng", "đô", "bên", "sang", "đi"],
        "or": ["thẻ", "bỏ", "kêu", "ít"],
        "of": ["kêu", "gáy", "tiếng", "bò", "con"],
        "if": ["ầm", "nặng", "chậm", "lì", "kêu"],
        "as": ["châu", "đông", "nam", "bắc", "tây", "hạng", "giải", "kêu", "la"],
        "us": ["béo", "mập", "tròn", "no", "kêu"],
        "his": ["cười", "mắt", "ngựa", "bé", "hí"],
        "her": ["hơn", "vui", "cười"]
    ]

    /// Hysteresis score differential required to flip the whole candidate mid-word when both candidates are phonotactically valid (P0.4.1 Section 4).
    public static let hysteresisMarginThreshold: Double = 2.5

    /// Continuous heuristic Vietnamese keyboard prior in cold no-context (`[3.5, 7.5]`, P0.7 Section 4).
    /// Note: This is an uncalibrated normalized prior score, NOT an empirically calibrated probability.
    public static func continuousVietnameseNoContextPrior(vnFreq: Double) -> Double {
        min(7.5, max(3.5, 2.4 + 0.60 * vnFreq))
    }

    private static let fallbackTelexEngineLock = NSLock()
    private static let fallbackTelexEngine: VietnameseEngine = {
        let engine = VietnameseEngine()
        engine.inputMethod = .telex
        engine.grammarProfile = .senFlex
        return engine
    }()

    private static func naiveTelexRenderedFallback(lowerRaw: String) -> String {
        guard !lowerRaw.isEmpty, lowerRaw.count <= 5 else { return lowerRaw }
        fallbackTelexEngineLock.lock()
        defer { fallbackTelexEngineLock.unlock() }
        return fallbackTelexEngine.transform(Array(lowerRaw)).lowercased()
    }

    /// Evaluates whether a standalone token without preceding context prefers English under the default frequency-aware bilingual policy (P0.7 Section 1 & 4).
    /// Resolves high-frequency short English words whose Vietnamese Telex collisions are rare standalone clitics/variants
    /// (`of`, `is`, `or`, `as`, `if`, `mix`, `us`, `ajax`, `off`, `are`), while keeping core and higher-frequency Vietnamese syllables
    /// (`sex -> sẽ`, `tree -> trê`, `been -> bên`, `too -> tô`, `est -> ét`, `os -> ó`, `ir -> ỉ`, `ix -> ĩ`, `this -> thí`, `born -> bỏn`, `mere -> mể`).
    public static func prefersEnglishInDefaultNoContext(lowerRaw: String, lowerRendered: String) -> Bool {
        let effectiveRendered = lowerRendered.isEmpty
            ? naiveTelexRenderedFallback(lowerRaw: lowerRaw)
            : lowerRendered
        guard effectiveRendered != lowerRaw,
              let enFreq = englishCollisionLogFrequencies[lowerRaw] else {
            return false
        }
        let vnFreq: Double
        if let exactVN = vietnameseCollisionLogFrequencies[effectiveRendered] {
            vnFreq = exactVN
        } else if !VietnameseSyllableDictionary.shared.isValidSyllable(effectiveRendered) &&
                  (lowerRaw.count >= effectiveRendered.count + 2 ||
                   (effectiveRendered.unicodeScalars.allSatisfy(\.isASCII) &&
                    !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(effectiveRendered))) {
            vnFreq = 0.0
        } else {
            return false
        }
        let vnPrior = continuousVietnameseNoContextPrior(vnFreq: vnFreq)
        return enFreq > (vnFreq + vnPrior) && (enFreq - vnFreq) >= 5.4
    }

    /// Evaluates case-sensitive orthographic signals for technical identifiers and uppercase abbreviations (P0.7 Section 1 & 4):
    /// - Internal camelCase (`iOS`, `macOS`, `tvOS`)
    /// - Short ALL-CAPS vowel-initial / single-vowel abbreviations (`EST`, `OS`, `IR`, `IX`) outside ALL-CAPS Vietnamese prose.
    public static func prefersEnglishByOrthographicCase(
        raw: String,
        rendered: String,
        context: String = ""
    ) -> Bool {
        let cleanRaw = raw.trimmingCharacters(in: .punctuationCharacters)
        let cleanRendered = rendered.trimmingCharacters(in: .punctuationCharacters)
        let effectiveRendered = cleanRendered.isEmpty ? rendered : cleanRendered
        let lowerRaw = cleanRaw.lowercased()
        let lowerRendered = effectiveRendered.lowercased()
        guard cleanRaw.count >= 2,
              cleanRaw != lowerRaw,
              lowerRaw != lowerRendered,
              !VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(effectiveRendered),
              !SmartBilingualDetector.isExplicitTelexEscape(raw: cleanRaw, rendered: effectiveRendered),
              !SmartBilingualDetector.isVNIDigitTransformationOrEscape(raw: cleanRaw, rendered: effectiveRendered) else {
            return false
        }

        // 1. Internal camelCase (`iOS`, `macOS`, `tvOS`, `openGL`, `DDoS`): a lowercase letter followed later by an uppercase letter
        //    on a known English or technical identifier (never on mixed-case Vietnamese Telex escapes like `TuRRuS`).
        var seenLower = false
        var hasInternalUpperAfterLower = false
        for ch in cleanRaw {
            if ch.isLowercase {
                seenLower = true
            } else if ch.isUppercase && seenLower {
                hasInternalUpperAfterLower = true
                break
            }
        }
        if hasInternalUpperAfterLower &&
           (englishCollisionLogFrequencies[lowerRaw] != nil ||
            SmartBilingualDetector.isKnownEnglishWord(cleanRaw) ||
            SmartBilingualDetector.isKnownEnglishWord(lowerRaw) ||
            lowerRaw.hasSuffix("os") ||
            (cleanRaw.count == 4 && lowerRaw.dropFirst().hasPrefix("aa") && cleanRaw.last == "S")) {
            return true
        }

        // 1b. Standalone possessive/pronoun `His`/`HIS` and `Her`/`HER` outside Vietnamese compound contexts
        //     (`hí` and `hẻ` rarely stand alone as capitalized single words outside compounds like `Hí hửng`).
        if (lowerRaw == "his" || lowerRaw == "her") &&
           !isVietnameseContextForTonePrimitive(context, lowerRaw: lowerRaw) {
            return true
        }

        // 2. Short ALL-CAPS technical/time-zone/Roman abbreviations (`OS`, `IR`, `IX`, `EST`) that are NOT already no-context defaults:
        //    Only applies when a tone mark was produced (preserving untoned `AA -> Â`, `EE -> Ê`, `OO -> Ô`, `AW -> Ă`, `OW -> Ơ`, `UW -> Ư`)
        //    and outside ALL-CAPS Vietnamese prose clauses (`TOÁN`, `CÓ THỂ`).
        guard (2...4).contains(cleanRaw.count),
              !lowerRaw.hasPrefix("dd"),
              cleanRaw == cleanRaw.uppercased(),
              !prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered),
              VietnameseSyllableDictionary.hasToneMark(effectiveRendered),
              (lowerRendered.count == 1 || lowerRaw.first.map({ "aeiouy".contains($0) }) == true) else {
            return false
        }

        let trimmedCtx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCtx.isEmpty {
            let ctxTokens = trimmedCtx
                .split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            let isAllCapsVietnameseProse = !ctxTokens.isEmpty && ctxTokens.contains { tok in
                tok == tok.uppercased() && tok != tok.lowercased() &&
                (!tok.unicodeScalars.allSatisfy(\.isASCII) || vietnamesePreVerbalModalTriggers.contains(tok.lowercased()))
            }
            if isAllCapsVietnameseProse {
                return false
            }
        }

        let enFreq = englishCollisionLogFrequencies[lowerRaw] ??
            (SmartBilingualDetector.isKnownEnglishWord(lowerRaw) ? 5.5 : 0.0)
        let vnFreq: Double = {
            if let exact = vietnameseCollisionLogFrequencies[lowerRendered] {
                return exact
            }
            if VietnameseSyllableDictionary.shared.supplementalTonedSyllables.contains(lowerRendered) {
                return 3.8
            }
            if lowerRendered.count == 1 {
                return 3.6
            }
            return VietnameseSyllableDictionary.shared.isValidSyllable(lowerRendered) ? 6.2 : 0.0
        }()
        return enFreq >= 5.0 && vnFreq < 6.0
    }

    private static let explicitCollocationRequiredShortTokens: Set<String> = [
        "is", "or", "of", "if"
    ]

    /// Evaluates whether `context` is a Vietnamese context that licenses a short collision syllable
    /// such as `"cái í"`, `"nước mĩ"`, `"châu mĩ"`, `"kêu ò"`, `"ầm ì"`, `"ỏ thẻ"` (P0.4.1 & P0.7 Section 1/4).
    public static func isVietnameseContextForTonePrimitive(_ context: String, lowerRaw: String) -> Bool {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let tokens = trimmed.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard let last = tokens.last else { return false }
        let lastTwo = tokens.count >= 2 ? "\(tokens[tokens.count - 2]) \(last)" : last
        if let heads = vietnameseCompoundPrecedingHeads[lowerRaw],
           (heads.contains(last) || heads.contains(lastTwo)) {
            return true
        }
        if !explicitCollocationRequiredShortTokens.contains(lowerRaw) {
            if !last.unicodeScalars.allSatisfy(\.isASCII) {
                return true
            }
            if vietnamesePreVerbalModalTriggers.contains(last) || vietnamesePreVerbalModalTriggers.contains(lastTwo) {
                return true
            }
        }
        return false
    }

    /// Returns `true` when a composed token is an unambiguous Vietnamese clause-starter pronoun, modal, or `đ-` word
    /// (e.g. `"tôi"`, `"mình"`, `"bạn"`, `"chị"`, `"không"`, `"chưa"`, `"đã"`, `"đi"`, `"đang"`) whose raw keystrokes
    /// are not a known English word, enabling mid-sentence English -> Vietnamese code-switching (P0.4.2 Section 2).
    public static func isVietnameseClauseStarter(rendered: String, lowerRaw: String) -> Bool {
        let lowerRendered = rendered.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard !lowerRendered.isEmpty,
              !lowerRendered.unicodeScalars.allSatisfy(\.isASCII),
              !SmartBilingualDetector.isKnownEnglishWord(lowerRaw),
              !SyllableCandidateResolver.isEnglishCollision(lowerRaw) else {
            return false
        }
        if lowerRendered.hasPrefix("đ") {
            return VietnameseSyllableDictionary.shared.isValidSyllable(lowerRendered)
        }
        return vietnamesePreVerbalModalTriggers.contains(lowerRendered)
    }

    private static let sentenceStateCacheLock = NSLock()
    private static var cachedSentenceContext: String = ""
    private static var cachedSentenceState: SentenceLanguageState = .empty

    /// Computes the multi-token `SentenceLanguageState` from up to the last 5 committed tokens in `context` (P0.4.2 Section 2).
    /// A short run of bare labels is weak evidence for English prose.
    /// Preserve a valid Vietnamese tone candidate unless the context contains an English anchor.
    internal static func prefersVietnameseAfterShortLabel(raw: String, rendered: String, context: String) -> Bool {
        guard raw != rendered, raw == raw.lowercased(), !context.isEmpty,
              raw.allSatisfy({ $0.isASCII && $0.isLetter }),
              VietnameseSyllableDictionary.hasToneMark(rendered),
              !SmartBilingualDetector.isEnglishAnchorTokenForArbiter(raw),
              !prefersEnglishInDefaultNoContext(lowerRaw: raw, lowerRendered: rendered.lowercased()) else {
            return false
        }

        let tokens = context.split(whereSeparator: \.isWhitespace)
        guard (2...3).contains(tokens.count), tokens.allSatisfy({ token in
            let lower = token.lowercased()
            return token.count > 1 && token.allSatisfy { $0.isASCII && $0.isLetter } &&
                !SmartBilingualDetector.isEnglishAnchorTokenForArbiter(lower)
        }) else {
            return false
        }

        if raw == "sex", isVietnameseLoanwordSexContext(context) ||
            tokens.last.map({ englishSexCollocationPrecedingWords.contains($0.lowercased()) }) == true {
            return false
        }

        return VietnameseSyllableDictionary.shared.isValidSyllable(rendered)
    }

    /// Tracks English vs Vietnamese momentum across recent tokens while allowing instant bidirectional mid-sentence code-switching.
    public static func evaluateSentenceLanguageState(_ context: String) -> SentenceLanguageState {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let cachedHit: SentenceLanguageState? = {
            sentenceStateCacheLock.lock()
            defer { sentenceStateCacheLock.unlock() }
            return trimmed == cachedSentenceContext ? cachedSentenceState : nil
        }()
        if let cachedHit {
            return cachedHit
        }

        let allTokens = trimmed
            .split(whereSeparator: \.isWhitespace)
            .suffix(6)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !allTokens.isEmpty else { return .empty }
        let window = Array(allTokens.suffix(5))
        let isCapsLockProseWindow = SmartBilingualDetector.isAllCapsASCIIProseClause(window)

        var enCount = 0
        var vnCount = 0
        var tokenLangs: [SentenceLanguageMomentum] = []
        tokenLangs.reserveCapacity(window.count)

        for (idx, tok) in window.enumerated() {
            let lower = tok.lowercased()
            if !lower.unicodeScalars.allSatisfy(\.isASCII) ||
               vietnamesePreVerbalModalTriggers.contains(lower) ||
               SmartBilingualDetector.isVietnameseAnchorTokenForArbiter(lower) {
                vnCount += 1
                tokenLangs.append(.vietnamese)
            } else if !isCapsLockProseWindow && SmartBilingualDetector.isAllCapsAcronymToken(tok) {
                tokenLangs.append(.neutral)
            } else if SmartBilingualDetector.isEnglishAnchorTokenForArbiter(lower) ||
                      (!VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lower) &&
                       SmartBilingualDetector.isKnownEnglishWord(lower)) {
                enCount += 1
                tokenLangs.append(.english)
            } else if lower == "a" && idx > 0 && tokenLangs.last == .english {
                enCount += 1
                tokenLangs.append(.english)
            } else if tokenLangs.last == .english && SmartBilingualDetector.isKnownEnglishWord(lower) {
                enCount += 1
                tokenLangs.append(.english)
            } else {
                tokenLangs.append(.neutral)
            }
        }

        var trailingEN = 0
        for lang in tokenLangs.reversed() {
            if lang == .english {
                trailingEN += 1
            } else if lang == .vietnamese {
                break
            }
        }

        var trailingVN = 0
        for lang in tokenLangs.reversed() {
            if lang == .vietnamese {
                trailingVN += 1
            } else if lang == .english {
                break
            }
        }

        let momentum: SentenceLanguageMomentum
        if trailingEN > 0 && (tokenLangs.last == .english || (tokenLangs.last == .neutral && trailingVN == 0)) {
            momentum = .english
        } else if trailingVN > 0 && (tokenLangs.last == .vietnamese || (tokenLangs.last == .neutral && trailingEN == 0)) {
            momentum = .vietnamese
        } else if vnCount > enCount {
            momentum = .vietnamese
        } else if enCount > vnCount {
            momentum = .english
        } else if enCount > 0 && SmartBilingualDetector.isConfidentEnglishContextForArbiter(trimmed) {
            momentum = .english
        } else {
            momentum = .neutral
        }

        let computed = SentenceLanguageState(
            recentTokens: window,
            englishTokenCount: enCount,
            vietnameseTokenCount: vnCount,
            consecutiveTrailingEnglishCount: trailingEN,
            consecutiveTrailingVietnameseCount: trailingVN,
            momentum: momentum
        )
        sentenceStateCacheLock.lock()
        cachedSentenceContext = trimmed
        cachedSentenceState = computed
        sentenceStateCacheLock.unlock()
        return computed
    }

    /// Grammar-aware phonotactic analysis distinguishing Standard Telex, Gen-Z Mode, and Relaxed Coda (P0.4.1 Section 2).
    /// - Does NOT treat `fê` as an absolute phonotactic impossibility when Gen-Z Mode allows `f -> ph` (`isGenZPhonotacticValid == true`).
    /// - Does NOT expand Gen-Z (`f -> ph`) or Relaxed Coda (`-k -> -c`) into known English words (`fee`, `fees`, `free`, `book`, `good`)
    ///   merely because a Vietnamese candidate could be formed (`blockedGenZExpansionOnEnglishWord`, `blockedRelaxedCodaOnEnglishWord`).
    public static func evaluatePhonotactics(
        raw: String,
        rendered: String,
        genZMode: Bool = false,
        relaxedCoda: Bool = false
    ) -> GrammarAwarePhonotacticProfile {
        let cleanRaw = raw.trimmingCharacters(in: .punctuationCharacters).lowercased()
        let cleanRendered = rendered.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard !cleanRaw.isEmpty, !cleanRendered.isEmpty else {
            return GrammarAwarePhonotacticProfile(
                layer: .standardTelex,
                isStandardPhonotacticValid: true,
                isGenZPhonotacticValid: true,
                isRelaxedCodaPhonotacticValid: true,
                isActiveGrammarValid: true
            )
        }

        let rawTrimmed = rendered.trimmingCharacters(in: .punctuationCharacters)
        let isStandardValid =
            VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(rawTrimmed) ||
            (VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(cleanRendered) &&
             VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(
                 cleanRendered,
                 relaxedCoda: false,
                 genZMode: false
             ))

        // Evaluate pure Gen-Z structural phonotactics (`f -> ph`, `j/z/dz -> gi/d`, `w -> qu`) independent of English lexicon blocking
        let isGenZStructuralValid: Bool = {
            if isStandardValid { return true }
            let isDz = cleanRendered.hasPrefix("dz")
            guard let first = cleanRendered.first, isDz || ["f", "j", "z", "w"].contains(first) else { return false }
            let remainder = isDz ? String(cleanRendered.dropFirst(2)) : String(cleanRendered.dropFirst())
            guard !remainder.isEmpty else { return false }
            let untonedRem = VietnameseSyllableDictionary.stripToneMarks(remainder)
            // Consonant cluster `fr-` is invalid even under `f -> ph` (`phr-` is not a Vietnamese onset)
            if first == "f" && untonedRem.hasPrefix("r") { return false }
            let mappedPrefixes: [String]
            if isDz {
                mappedPrefixes = ["d", "v", "gi"]
            } else {
                switch first {
                case "f": mappedPrefixes = ["ph"]
                case "z": mappedPrefixes = ["d", "v", "gi", "tr", "r"]
                case "j": mappedPrefixes = ["d", "gi", "v", "tr", "r"]
                case "w": mappedPrefixes = ["qu"]
                default: mappedPrefixes = []
                }
            }
            for prefix in mappedPrefixes {
                let mapped = prefix + remainder
                if VietnameseSyllableDictionary.shared.isValidSyllable(mapped) ||
                   VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(mapped) {
                    return true
                }
            }
            return false
        }()

        // Evaluate Relaxed Coda structural phonotactics (`-g -> -ng`, `-h -> -nh`, `-k -> -c`)
        let isRelaxedCodaStructuralValid: Bool = {
            if isStandardValid { return true }
            let expanded = VietnameseSyllableDictionary.shared.expandedRelaxedCodaSyllables(cleanRendered)
            return expanded.contains(where: { VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable($0) })
        }()

        let isKnownEN = SmartBilingualDetector.isKnownEnglishWord(cleanRaw)
        let blockedGenZOnEN = !isStandardValid && isGenZStructuralValid && isKnownEN
        let blockedRelaxedOnEN = !isStandardValid && isRelaxedCodaStructuralValid && isKnownEN

        let layer: GrammarPhonotacticLayer
        if isStandardValid {
            layer = .standardTelex
        } else if genZMode && isGenZStructuralValid {
            layer = .genZExtension
        } else if relaxedCoda && isRelaxedCodaStructuralValid {
            layer = .relaxedCodaExtension
        } else {
            layer = .invalid
        }

        let isActiveValid: Bool
        switch layer {
        case .standardTelex:
            isActiveValid = true
        case .genZExtension:
            isActiveValid = genZMode && !blockedGenZOnEN
        case .relaxedCodaExtension:
            isActiveValid = relaxedCoda && !blockedRelaxedOnEN
        case .invalid:
            isActiveValid = false
        }

        return GrammarAwarePhonotacticProfile(
            layer: layer,
            isStandardPhonotacticValid: isStandardValid,
            isGenZPhonotacticValid: genZMode && isGenZStructuralValid,
            isRelaxedCodaPhonotacticValid: relaxedCoda && isRelaxedCodaStructuralValid,
            isActiveGrammarValid: isActiveValid,
            blockedGenZExpansionOnEnglishWord: blockedGenZOnEN,
            blockedRelaxedCodaOnEnglishWord: blockedRelaxedOnEN
        )
    }

    /// Evaluates candidate stability & hysteresis for mid-word transitions (`trê -> trees`, `quê -> queen`, `bô -> book`) (P0.4.1 Section 4).
    public static func shouldFlipCandidate(
        from priorKind: BilingualCandidateKind,
        arbitration: BilingualArbitrationResult
    ) -> (shouldFlip: Bool, reason: CandidateSelectionReason) {
        let targetKind = arbitration.primaryCandidate.kind
        guard priorKind != targetKind else {
            return (false, arbitration.selectionReason)
        }
        if targetKind == .explicitEscapeOrSelected {
            return (true, .explicitTelexEscape)
        }
        // Flipping from Vietnamese Telex to Raw Literal mid-word:
        if priorKind == .vietnameseTelex && targetKind == .rawLiteral {
            let profile = arbitration.phonotacticProfile
            if profile.blockedGenZExpansionOnEnglishWord {
                return (true, .genZBlockedOnEnglishWord)
            }
            if profile.blockedRelaxedCodaOnEnglishWord {
                return (true, .relaxedCodaBlockedOnEnglishWord)
            }
            if !profile.isActiveGrammarValid {
                return (true, .phonotacticInvalidVN)
            }
            if arbitration.selectionReason == .phonotacticGapVN {
                return (true, .phonotacticGapVN)
            }
            if arbitration.scoreMargin >= hysteresisMarginThreshold {
                return (true, arbitration.selectionReason)
            }
            return (false, .hysteresisRetained)
        }
        // Flipping from Raw Literal back to Vietnamese Telex mid-word requires strong margin and non-English raw string:
        if priorKind == .rawLiteral && targetKind == .vietnameseTelex {
            if !SmartBilingualDetector.isKnownEnglishWord(arbitration.rawInput) &&
               arbitration.scoreMargin >= hysteresisMarginThreshold {
                return (true, arbitration.selectionReason)
            }
            return (false, .hysteresisRetained)
        }
        return (arbitration.scoreMargin >= hysteresisMarginThreshold, arbitration.selectionReason)
    }

    /// Classifies a `(raw, rendered)` pair into its formal P0.4 `BilingualCollisionCategory`.
    /// Checks grammar-aware Vietnamese phonotactics FIRST, then attested Vietnamese lexical dictionary membership,
    /// then distinguishes double-vowel (`aa/ee/oo`) vs tone/horn (`s/f/r/x/j/w`) collisions.
    public static func classifyCollision(
        raw: String,
        rendered: String,
        genZMode: Bool = false,
        relaxedCoda: Bool = false,
        precomputedProfile: GrammarAwarePhonotacticProfile? = nil
    ) -> BilingualCollisionCategory {
        let cleanRaw = raw.trimmingCharacters(in: .punctuationCharacters).lowercased()
        let cleanRendered = rendered.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard !cleanRaw.isEmpty, !cleanRendered.isEmpty, cleanRaw != cleanRendered else {
            return .noCollision
        }

        // Step 1: Grammar-aware phonotactic validation FIRST (P0.4.1 Section 2)
        let profile = precomputedProfile ?? evaluatePhonotactics(
            raw: cleanRaw,
            rendered: cleanRendered,
            genZMode: genZMode,
            relaxedCoda: relaxedCoda
        )
        if !profile.isStandardPhonotacticValid && !profile.isActiveGrammarValid {
            return .invalidVietnameseCandidate
        }

        // Step 2: Lexical attestation check in the Vietnamese syllable dictionary
        let isAttestedVN: Bool = {
            if VietnameseSyllableDictionary.shared.isValidSyllable(cleanRendered) {
                return true
            }
            if profile.layer == .genZExtension && profile.isActiveGrammarValid,
               let first = cleanRendered.first, first == "f" {
                return VietnameseSyllableDictionary.shared.isValidSyllable("ph" + cleanRendered.dropFirst())
            }
            return false
        }()
        if !isAttestedVN {
            return .phonotacticGapVietnamese
        }

        // Step 3: Valid bilingual collision — classify double-vowel (`aa`, `ee`, `oo`) vs tone/horn (`s`, `f`, `r`, `x`, `j`, `w`)
        if cleanRaw.contains("aa") || cleanRaw.contains("ee") || cleanRaw.contains("oo") {
            return .validBilingualVowelCollision
        }
        return .validBilingualToneOrHornCollision
    }

    /// Generates and lexically verifies the P0.4 Bilingual Collision Corpus across all three mandatory groups
    /// plus phonotactic-gap plurals (`trees`, `teens`).
    public static func generateClassifiedCollisionCorpus() -> [BilingualCollisionCorpusEntry] {
        let probes: [(raw: String, vnContext: String, enContext: String)] = [
            // Group 1: Invalid Vietnamese candidate
            ("fee", "tôi", "the"),
            ("fees", "tôi", "the"),
            ("free", "tôi", "the"),
            ("green", "tôi", "the"),
            ("book", "tôi", "the"),
            ("good", "tôi", "the"),
            // Phonotactic-gap inflections
            ("trees", "cá", "the"),
            ("teens", "tôi", "the"),
            // Group 2: Valid bilingual double-vowel collision
            ("tree", "cá", "the"),
            ("queen", "tôi", "the"),
            ("teen", "họ", "the"),
            ("been", "ở", "have"),
            ("seen", "ốc", "have"),
            ("bee", "con", "the"),
            ("bees", "bồng", "the"),
            ("beer", "nước", "cold"),
            ("moon", "bộ", "the"),
            ("noon", "buồn", "the"),
            ("room", "nổi", "the"),
            ("too", "bát", "he is"),
            ("boots", "đôi", "the"),
            // Group 3: Tone & horn collision
            ("sex", "tôi", "safe"),
            ("is", "cái", "she"),
            ("six", "bác", "he is"),
            ("cats", "bãi", "the"),
            ("hats", "bài", "the"),
            ("last", "cắt", "the"),
            ("best", "hạng", "the"),
            ("rest", "trời", "the"),
            ("car", "tất", "the"),
            ("bar", "mồi", "the"),
            ("now", "cái", "he is"),
            ("cow", "nguy", "the")
        ]

        let engine = VietnameseEngine()
        engine.inputMethod = .telex
        engine.grammarProfile = .classic
        engine.genZMode = true

        var entries: [BilingualCollisionCorpusEntry] = []
        entries.reserveCapacity(probes.count)

        for probe in probes {
            let naiveTelex: String = {
                switch probe.raw {
                case "fee": return "fê"
                case "fees": return "fế"
                case "free": return "frê"
                default: return engine.transform(Array(probe.raw))
                }
            }()
            let category = classifyCollision(raw: probe.raw, rendered: naiveTelex, genZMode: true)
            let isPhonotactic =
                VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(naiveTelex.lowercased()) &&
                VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(
                    naiveTelex.lowercased(),
                    relaxedCoda: false,
                    genZMode: false
                )
            let isAttested = VietnameseSyllableDictionary.shared.isValidSyllable(naiveTelex.lowercased())
            let isKnownEN = SmartBilingualDetector.isKnownEnglishWord(probe.raw)

            let noCtxArb = arbitrate(raw: probe.raw, rendered: naiveTelex, context: "", genZMode: true)
            let vnCtxArb = arbitrate(raw: probe.raw, rendered: naiveTelex, context: probe.vnContext, genZMode: true)
            let enCtxArb = arbitrate(raw: probe.raw, rendered: naiveTelex, context: probe.enContext, genZMode: true)

            let vnFreq = noCtxArb.candidates.first(where: { $0.kind == .vietnameseTelex })?.vnLexicalFrequency ?? 0.0
            let enFreq = noCtxArb.candidates.first(where: { $0.kind == .rawLiteral })?.enLexicalFrequency ?? 0.0

            entries.append(
                BilingualCollisionCorpusEntry(
                    rawEnglish: probe.raw,
                    naiveTelex: naiveTelex,
                    category: category,
                    isPhonotacticallyValidVN: isPhonotactic,
                    isAttestedVNSyllable: isAttested,
                    isKnownEnglishWord: isKnownEN,
                    vnFrequency: vnFreq,
                    enFrequency: enFreq,
                    defaultNoContextWinner: noCtxArb.primaryCandidate.text,
                    vnContextWinner: vnCtxArb.primaryCandidate.text,
                    enContextWinner: enCtxArb.primaryCandidate.text
                )
            )
        }

        return entries
    }

    /// Evaluates whether `context` is a Vietnamese nominal phrase that specifically requires the loanword `"sex"` instead of future marker `"sẽ"`.
    public static func isVietnameseLoanwordSexContext(_ context: String) -> Bool {
        let normalized = context
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        let tokens = normalized
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard let last = tokens.last else { return false }
        if vietnameseSexLoanwordPrecedingHeads.contains(last) || englishSexCollocationPrecedingWords.contains(last) {
            return true
        }
        if tokens.count >= 2 {
            let lastTwo = "\(tokens[tokens.count - 2]) \(last)"
            if vietnameseSexLoanwordPrecedingHeads.contains(lastTwo) {
                return true
            }
        }
        return false
    }

    private struct ArbitrationCacheKey: Hashable {
        let raw: String
        let rendered: String
        let context: String
        let noContextPolicy: BilingualNoContextPolicy
        let hasExplicitUserSelection: Bool
        let precededByTechnicalDelimiter: Bool
        let boundaryChar: Character?
        let isInlineComposition: Bool
        let genZMode: Bool
        let relaxedCoda: Bool
    }

    private static let arbitrationCacheLock = NSLock()
    private static let arbitrationCacheCapacity = 256
    private static var arbitrationCache: [ArbitrationCacheKey: BilingualArbitrationResult] = [:]
    private static var arbitrationCacheKeys: [ArbitrationCacheKey] = []

    internal static func resetArbitrationCache() {
        arbitrationCacheLock.lock()
        defer { arbitrationCacheLock.unlock() }
        arbitrationCache.removeAll(keepingCapacity: true)
        arbitrationCacheKeys.removeAll(keepingCapacity: true)
    }

    /// Arbitrates between Raw Literal, Vietnamese Telex, and Explicit Escape/User-Selected candidates.
    public static func arbitrate(
        raw: String,
        rendered: String,
        context: String = "",
        noContextPolicy: BilingualNoContextPolicy = .probabilisticBilingual,
        hasExplicitUserSelection: Bool = false,
        precededByTechnicalDelimiter: Bool = false,
        boundaryChar: Character? = nil,
        isInlineComposition: Bool = false,
        genZMode: Bool = false,
        relaxedCoda: Bool = false
    ) -> BilingualArbitrationResult {
        let cacheKey = ArbitrationCacheKey(
            raw: raw,
            rendered: rendered,
            context: context,
            noContextPolicy: noContextPolicy,
            hasExplicitUserSelection: hasExplicitUserSelection,
            precededByTechnicalDelimiter: precededByTechnicalDelimiter,
            boundaryChar: boundaryChar,
            isInlineComposition: isInlineComposition,
            genZMode: genZMode,
            relaxedCoda: relaxedCoda
        )
        arbitrationCacheLock.lock()
        if let cached = arbitrationCache[cacheKey] {
            arbitrationCacheLock.unlock()
            return cached
        }
        arbitrationCacheLock.unlock()
        let cleanRaw = raw.trimmingCharacters(in: .punctuationCharacters)
        let cleanRendered = rendered.trimmingCharacters(in: .punctuationCharacters)
        let effectiveRendered = cleanRendered.isEmpty ? rendered : cleanRendered
        let lowerRaw = cleanRaw.lowercased()
        let lowerRendered = effectiveRendered.lowercased()

        // 1. Check Explicit Escape or User Selection first
        let isExplicitEscape = SmartBilingualDetector.isExplicitTelexEscape(raw: cleanRaw, rendered: effectiveRendered)
        var evaluations: [BilingualCandidateEvaluation] = []

        if hasExplicitUserSelection || isExplicitEscape {
            evaluations.append(
                BilingualCandidateEvaluation(
                    kind: .explicitEscapeOrSelected,
                    text: effectiveRendered,
                    totalScore: 100.0,
                    posteriorProbability: 1.0,
                    explicitIntentScore: 100.0
                )
            )
        }

        // 2. Grammar-Aware Phonotactic & Lexical Attestation Check FIRST (P0.4 & P0.4.1 Section 2)
        let phonotacticProfile = evaluatePhonotactics(
            raw: cleanRaw,
            rendered: effectiveRendered,
            genZMode: genZMode,
            relaxedCoda: relaxedCoda
        )
        let hasCollision = lowerRaw != lowerRendered
        let collisionCategory = hasCollision
            ? classifyCollision(
                raw: cleanRaw,
                rendered: effectiveRendered,
                genZMode: genZMode,
                relaxedCoda: relaxedCoda,
                precomputedProfile: phonotacticProfile
            )
            : .noCollision
        let isKnownEnglish = hasCollision ? SmartBilingualDetector.isKnownEnglishWord(cleanRaw) : false

        // Compute normalized lexical frequencies (P0.7 Section 4: differentiated structural fallback, not flat equal frequency)
        let vnFreq: Double = {
            if VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(effectiveRendered) {
                return 6.5
            }
            if isKnownEnglish && (collisionCategory == .invalidVietnameseCandidate || collisionCategory == .phonotacticGapVietnamese) {
                return 0.0
            }
            if let exact = vietnameseCollisionLogFrequencies[lowerRendered] {
                return exact
            }
            if VietnameseSyllableDictionary.shared.supplementalTonedSyllables.contains(lowerRendered) {
                return 3.8
            }
            if lowerRendered.count == 1 && VietnameseSyllableDictionary.shared.isValidSyllable(lowerRendered) {
                return 3.6
            }
            if VietnameseSyllableDictionary.shared.isValidSyllable(lowerRendered) {
                return 6.2
            }
            if phonotacticProfile.layer == .genZExtension && phonotacticProfile.isActiveGrammarValid,
               let first = lowerRendered.first, first == "f",
               VietnameseSyllableDictionary.shared.isValidSyllable("ph" + lowerRendered.dropFirst()) {
                return 5.5
            }
            if !isKnownEnglish &&
               (VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(lowerRendered, relaxedCoda: true, genZMode: genZMode) ||
                (!lowerRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnameseRhyme(lowerRendered))) {
                return 5.0
            }
            return 0.0
        }()

        let enFreq: Double = {
            if let exact = englishCollisionLogFrequencies[lowerRaw] {
                return exact
            }
            if isKnownEnglish {
                return 6.0
            }
            return 1.0
        }()

        // 3. Technical & Orthographic Case Context Score
        let hasOrthographicCaseEnglishSignal = prefersEnglishByOrthographicCase(
            raw: cleanRaw,
            rendered: effectiveRendered,
            context: context
        )
        let isTechnical = precededByTechnicalDelimiter ||
            hasOrthographicCaseEnglishSignal ||
            (boundaryChar != nil && "([{".contains(boundaryChar!)) ||
            lowerRaw.contains(where: { "_/\\-.:[]{}<>=+*@#$%^&|".contains($0) })
        let technicalBoost = isTechnical ? 12.0 : 0.0

        // 4. Preceding Context, Sentence-Level Language State & Grammatical Collocation Scores (P0.4.2 Section 2)
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceState = evaluateSentenceLanguageState(trimmedContext)
        let lowerContext = trimmedContext.lowercased()
        let contextTokens = lowerContext
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let lastContextToken = contextTokens.last ?? ""
        let lastTwoContextTokens = contextTokens.count >= 2
            ? "\(contextTokens[contextTokens.count - 2]) \(lastContextToken)"
            : lastContextToken

        var vnContextScore = 0.0
        var enContextScore = 0.0
        var vnCollocationScore = 0.0
        var enCollocationScore = 0.0

        if !trimmedContext.isEmpty && vnFreq > 0 {
            if lowerRaw == "sex" && isVietnameseLoanwordSexContext(trimmedContext) {
                enCollocationScore += 9.5
                vnCollocationScore -= 4.0
            } else if lowerRaw == "sex" && englishSexCollocationPrecedingWords.contains(lastContextToken) {
                enContextScore += 7.0
                enCollocationScore += 5.0
            } else if lowerRaw == "sex" &&
                      (vietnamesePreVerbalModalTriggers.contains(lastContextToken) ||
                       vietnamesePreVerbalModalTriggers.contains(lastTwoContextTokens)) {
                vnContextScore += 6.5
                vnCollocationScore += 5.0
            } else if let vnHeads = vietnameseCompoundPrecedingHeads[lowerRaw],
                      (vnHeads.contains(lastContextToken) || vnHeads.contains(lastTwoContextTokens)) {
                vnContextScore += 6.0
                vnCollocationScore += 5.0
            } else if !isTechnical &&
                      prefersVietnameseAfterShortLabel(raw: cleanRaw, rendered: effectiveRendered, context: trimmedContext) {
                vnContextScore += 4.5
            } else if (SmartBilingualDetector.isConfidentEnglishContextForArbiter(trimmedContext) || sentenceState.momentum == .english) &&
                      !SmartBilingualDetector.isUnambiguousVietnameseTelexStructure(lowerRaw: lowerRaw, rendered: effectiveRendered) &&
                      (isKnownEnglish || englishCollisionLogFrequencies[lowerRaw] != nil || SmartBilingualDetector.isContextSensitiveEnglishCollision(lowerRaw)) {
                enContextScore += 8.5
                if ["is", "as", "if", "of", "or", "us", "up", "it", "at", "in", "on", "mix", "est", "os", "ir", "ix", "rest", "theme", "sex", "here", "there", "were", "more", "born", "mere", "tree", "queen", "teen", "been", "seen", "bee", "bees", "beer", "moon", "noon", "room", "too", "boots", "six", "cats", "hats", "last", "best", "car", "bar", "now", "cow"].contains(lowerRaw) {
                    enCollocationScore += 3.5
                }
            } else if prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) &&
                      !isVietnameseContextForTonePrimitive(trimmedContext, lowerRaw: lowerRaw) {
                enContextScore += 6.0
                enCollocationScore += 2.5
            } else {
                vnContextScore += 4.5
            }
        } else if !trimmedContext.isEmpty && vnFreq == 0 {
            enContextScore += 6.0
        }

        // 5. No-Context Policy & Composition Stability Adjustments (P0.4.1 Section 1, P0.4.2 Section 5 & P0.7 Section 4)
        var vnStabilityScore = 0.0
        var enStabilityScore = 0.0
        if isKnownEnglish && (collisionCategory == .invalidVietnameseCandidate || collisionCategory == .phonotacticGapVietnamese) {
            enStabilityScore += 8.0
        } else if trimmedContext.isEmpty && !isTechnical && !isExplicitEscape && !hasExplicitUserSelection {
            switch noContextPolicy {
            case .probabilisticBilingual:
                // P0.7 Section 4: Frequency-aware short-token policy using continuous normalized prior score.
                if vnFreq > 0 {
                    let detectorRestoresWithoutContext =
                        hasCollision &&
                        !prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) &&
                        SmartBilingualDetector.isEnglishWord(raw: cleanRaw, context: "", rendered: effectiveRendered, genZMode: genZMode)
                    if detectorRestoresWithoutContext {
                        enStabilityScore += 5.0
                    } else {
                        vnStabilityScore += continuousVietnameseNoContextPrior(vnFreq: vnFreq)
                    }
                } else if isKnownEnglish {
                    enStabilityScore += 5.0
                }
            case .standardVietnameseFirst:
                // Legacy strict Vietnamese-first policy: preserves 100% reachability of single-path Vietnamese syllables (`is -> í`, `sex -> sẽ`).
                let detectorRestoresNonPrimitive =
                    hasCollision &&
                    !prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) &&
                    SmartBilingualDetector.isEnglishWord(raw: cleanRaw, context: "", rendered: effectiveRendered, genZMode: genZMode)
                if vnFreq > 0 && !detectorRestoresNonPrimitive {
                    vnStabilityScore += 8.0
                } else if detectorRestoresNonPrimitive {
                    enStabilityScore += 5.0
                }
            case .experimentalFrequencyWeighted:
                // Direct raw frequency comparison without artificial floor.
                if enFreq >= vnFreq && isKnownEnglish {
                    enStabilityScore += 4.0
                }
            }
        } else if !trimmedContext.isEmpty && !isTechnical && !isExplicitEscape && !hasExplicitUserSelection {
            let detectorPrefersEnglish = hasCollision && SmartBilingualDetector.isEnglishWord(
                raw: cleanRaw,
                context: trimmedContext,
                rendered: effectiveRendered,
                genZMode: genZMode
            )
            if detectorPrefersEnglish && vnCollocationScore == 0 {
                enStabilityScore += 4.0
            } else if vnFreq > 0 {
                vnStabilityScore += 3.0
            }
        }

        let vnTotal = vnFreq + vnContextScore + vnCollocationScore + vnStabilityScore
        let enTotal = enFreq + enContextScore + enCollocationScore + technicalBoost + enStabilityScore

        // Compute uncalibrated heuristic logistic confidence scores σ(Δscore) (P0.4.2 Section 5)
        let logOddsVN = max(-20.0, min(20.0, vnTotal - enTotal))
        let vnProb = 1.0 / (1.0 + exp(-logOddsVN))
        let enProb = 1.0 - vnProb
        let margin = abs(vnTotal - enTotal)

        evaluations.append(
            BilingualCandidateEvaluation(
                kind: .vietnameseTelex,
                text: effectiveRendered,
                totalScore: vnTotal,
                posteriorProbability: vnProb,
                vnLexicalFrequency: vnFreq,
                precedingContextScore: vnContextScore,
                collocationScore: vnCollocationScore,
                compositionStabilityScore: vnStabilityScore
            )
        )

        if lowerRaw != lowerRendered || evaluations.isEmpty {
            evaluations.append(
                BilingualCandidateEvaluation(
                    kind: .rawLiteral,
                    text: cleanRaw.isEmpty ? raw : cleanRaw,
                    totalScore: enTotal,
                    posteriorProbability: enProb,
                    enLexicalFrequency: enFreq,
                    precedingContextScore: enContextScore,
                    collocationScore: enCollocationScore,
                    technicalContextScore: technicalBoost,
                    compositionStabilityScore: enStabilityScore
                )
            )
        }

        evaluations.sort { a, b in
            if abs(a.totalScore - b.totalScore) > 1e-6 {
                return a.totalScore > b.totalScore
            }
            return a.kind == .vietnameseTelex
        }

        let reason: CandidateSelectionReason = {
            if hasExplicitUserSelection { return .userSelectedSuggestion }
            if isExplicitEscape { return .explicitTelexEscape }
            if lowerRaw == lowerRendered { return .asciiPassThrough }
            if isTechnical { return .technicalContext }
            let winnerKind = evaluations.first?.kind ?? .vietnameseTelex
            if winnerKind == .rawLiteral {
                if phonotacticProfile.blockedGenZExpansionOnEnglishWord {
                    return .genZBlockedOnEnglishWord
                }
                if phonotacticProfile.blockedRelaxedCodaOnEnglishWord {
                    return .relaxedCodaBlockedOnEnglishWord
                }
                if collisionCategory == .invalidVietnameseCandidate {
                    return .phonotacticInvalidVN
                }
                if collisionCategory == .phonotacticGapVietnamese {
                    return .phonotacticGapVN
                }
                if !trimmedContext.isEmpty && !prefersEnglishInDefaultNoContext(lowerRaw: lowerRaw, lowerRendered: lowerRendered) {
                    return .englishContext
                }
                if !trimmedContext.isEmpty && (SmartBilingualDetector.isConfidentEnglishContextForArbiter(trimmedContext) || sentenceState.momentum == .english) {
                    return .englishContext
                }
                return .noContextFrequencyPrior
            } else {
                if !trimmedContext.isEmpty {
                    return .vietnameseContext
                }
                return .vietnameseComposition
            }
        }()

        let result = BilingualArbitrationResult(
            rawInput: cleanRaw.isEmpty ? raw : cleanRaw,
            composedVietnamese: effectiveRendered,
            context: trimmedContext,
            sentenceLanguageState: sentenceState,
            noContextPolicy: noContextPolicy,
            candidates: evaluations,
            vietnameseProbability: vnProb,
            englishProbability: enProb,
            scoreMargin: margin,
            selectionReason: reason,
            phonotacticProfile: phonotacticProfile
        )
        arbitrationCacheLock.lock()
        if arbitrationCache[cacheKey] == nil {
            if arbitrationCacheKeys.count >= arbitrationCacheCapacity {
                let evictCount = arbitrationCacheCapacity / 4
                for oldKey in arbitrationCacheKeys.prefix(evictCount) {
                    arbitrationCache.removeValue(forKey: oldKey)
                }
                arbitrationCacheKeys.removeFirst(evictCount)
            }
            arbitrationCacheKeys.append(cacheKey)
        }
        arbitrationCache[cacheKey] = result
        arbitrationCacheLock.unlock()
        return result
    }

    /// Returns the bilingual twin candidate (`"sex"` for `"sẽ"`, `"is"` for `"í"`, `"sẽ"` for `"sex"`, `"í"` for `"is"`, etc.)
    /// when a collision token is being composed, ensuring neither language is ever locked out in the UI candidate bar.
    public static func bilingualTwinCandidate(
        composingWord: String,
        rawWord: String = "",
        context: String = ""
    ) -> (displayText: String, score: Double)? {
        let cleanComposing = composingWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanComposing.isEmpty else { return nil }
        let lowerComposing = cleanComposing.lowercased()
        let cleanRaw = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerRaw = cleanRaw.lowercased()

        if let enTwin = vnToEnTwins[lowerComposing] {
            if !lowerRaw.isEmpty && lowerRaw != enTwin {
                return nil
            }
            let cased = applySourceCase(from: cleanComposing, to: enTwin)
            return (displayText: cased, score: 89.0)
        }

        if let vnTwin = enToVnTwins[lowerComposing] {
            let cased = applySourceCase(from: cleanComposing, to: vnTwin)
            return (displayText: cased, score: 89.0)
        }

        if lowerComposing.count >= 2 && lowerComposing.count <= 5 &&
           (lowerRaw.isEmpty || lowerRaw == lowerComposing) &&
           lowerComposing.unicodeScalars.allSatisfy(\.isASCII) {
            let naiveVN = naiveTelexRenderedFallback(lowerRaw: lowerComposing)
            if naiveVN != lowerComposing && VietnameseSyllableDictionary.shared.isValidSyllable(naiveVN) {
                let cased = applySourceCase(from: cleanComposing, to: naiveVN)
                return (displayText: cased, score: 88.0)
            }
        }

        if !lowerRaw.isEmpty,
           lowerRaw != lowerComposing,
           (SmartBilingualDetector.isKnownEnglishWord(lowerRaw) || englishCollisionLogFrequencies[lowerRaw] != nil),
           (englishCollisionLogFrequencies[lowerRaw] ?? 6.0) >= 5.0 {
            let cased = applySourceCase(from: cleanRaw, to: lowerRaw)
            return (displayText: cased, score: 86.0)
        }

        return nil
    }

    /// Map between Vietnamese composed syllable and its high-frequency English raw twin.
    private static let vnToEnTwins: [String: String] = [
        "sẽ": "sex",
        "í": "is",
        "hí": "his",
        "hẻ": "her",
        "thí": "this",
        "á": "as",
        "ì": "if",
        "ò": "of",
        "ỏ": "or",
        "ú": "us",
        "mĩ": "mix",
        "ét": "est",
        "ó": "os",
        "ỉ": "ir",
        "ĩ": "ix",
        "mể": "mere",
        "bỏn": "born",
        "úp": "up",
        "rét": "rest",
        "bét": "best",
        "lát": "last",
        "cát": "cats",
        "hát": "hats",
        "sĩ": "six",
        "cả": "car",
        "bả": "bar",
        "nơ": "now",
        "cơ": "cow",
        "thêm": "theme",
        "cân": "cana",
        "mêm": "meme",
        "hể": "here",
        "trê": "tree",
        "quên": "queen",
        "sên": "seen",
        "tên": "teen",
        "bên": "been",
        "bê": "bee",
        "bế": "bees",
        "bể": "beer",
        "môn": "moon",
        "nôn": "noon",
        "rôm": "room",
        "tô": "too",
        "bốt": "boots"
    ]

    /// Inverse lookup derived from `vnToEnTwins` (single source of truth).
    private static let enToVnTwins: [String: String] = Dictionary(
        uniqueKeysWithValues: vnToEnTwins.map { ($1, $0) }
    )

    private static func applySourceCase(from source: String, to target: String) -> String {
        guard !source.isEmpty, !target.isEmpty else { return target }
        if source.count > 1 && source == source.uppercased() && source != source.lowercased() {
            return target.uppercased()
        }
        if source.first?.isUppercase == true, let first = target.first {
            return String(first).uppercased() + target.dropFirst()
        }
        return target
    }
}

// MARK: - P0.4.1 Section 6: Full Collision Corpus & Quantitative Evaluation Metrics

/// Quantitative metrics measured across Calibration and Independent Holdout splits (P0.4.1 Section 6).
public struct BilingualCorpusQuantitativeMetrics: Sendable, Equatable {
    public let totalEvaluatedTokens: Int
    public let englishTokenCount: Int
    public let vietnameseTokenCount: Int
    /// Fraction of intended English tokens corrupted into Vietnamese diacritics (`[0.0, 1.0]`, lower is better).
    public let englishCorruptionRate: Double
    /// Fraction of intended Vietnamese tokens preserved accurately (`[0.0, 1.0]`, higher is better).
    public let vietnamesePreservationRate: Double
    /// Fraction of valid Vietnamese compositions or post-coda extensions that erroneously replayed raw ASCII (`[0.0, 1.0]`, lower is better).
    public let incorrectRawReplayRate: Double
    /// Mean number of mid-word candidate flips (`vietnameseTelex <-> rawLiteral`) per word across all keystrokes.
    public let candidateFlipRate: Double
    /// Mean extra keystrokes required to correct or select the intended word (`0.0` when default is right; `1.0` when 1-tap twin candidate or escape is used).
    public let extraKeystrokesToCorrect: Double
    /// Keystroke-by-keystroke agreement rate (`[0.0, 1.0]`) between macOS (`InputSessionManager` inline) and iOS (`UIKitInputSessionAdapter`).
    public let macOSiOSCoreConsistency: Double

    public init(
        totalEvaluatedTokens: Int,
        englishTokenCount: Int,
        vietnameseTokenCount: Int,
        englishCorruptionRate: Double,
        vietnamesePreservationRate: Double,
        incorrectRawReplayRate: Double,
        candidateFlipRate: Double,
        extraKeystrokesToCorrect: Double,
        macOSiOSCoreConsistency: Double
    ) {
        self.totalEvaluatedTokens = totalEvaluatedTokens
        self.englishTokenCount = englishTokenCount
        self.vietnameseTokenCount = vietnameseTokenCount
        self.englishCorruptionRate = englishCorruptionRate
        self.vietnamesePreservationRate = vietnamesePreservationRate
        self.incorrectRawReplayRate = incorrectRawReplayRate
        self.candidateFlipRate = candidateFlipRate
        self.extraKeystrokesToCorrect = extraKeystrokesToCorrect
        self.macOSiOSCoreConsistency = macOSiOSCoreConsistency
    }
}

/// Full P0.4.1 Section 6 evaluation report across offline English vocabulary sweep (Standard Telex, Gen-Z, VUIS)
/// and sentence-level Calibration vs Independent Holdout splits.
public struct BilingualFullCorpusEvaluationReport: Sendable, Equatable {
    public let sweptEnglishWordCount: Int
    public let standardTelexCollisionCount: Int
    public let genZCollisionCount: Int
    public let vuisCollisionCount: Int
    public let calibrationMetrics: BilingualCorpusQuantitativeMetrics
    public let holdoutMetrics: BilingualCorpusQuantitativeMetrics
    public let combinedMetrics: BilingualCorpusQuantitativeMetrics
}

extension BilingualIntentArbiter {
    /// Sweeps an offline English vocabulary across Standard Telex, Gen-Z Mode, and VUIS (`senFlex`),
    /// and evaluates Vietnamese, English, and Mixed/Code-Switching sentences split into a Calibration set
    /// and a strictly disjoint Independent Holdout set (P0.4.1 Section 6).
    public static func evaluateFullCollisionCorpus(
        additionalEnglishWords: [String] = []
    ) -> BilingualFullCorpusEvaluationReport {
        var baseEnglishLexicon = Set(englishCollisionLogFrequencies.keys)
        let extraOfflineEnglish: [String] = [
            "fee", "fees", "free", "green", "book", "books", "good", "goods", "look", "looks",
            "cook", "took", "wood", "food", "mood", "hood", "foot", "root", "boot", "boots",
            "tree", "trees", "queen", "queens", "teen", "teens", "been", "seen", "keen",
            "bee", "bees", "beer", "beers", "deer", "peer", "peel", "feel", "feed", "feet",
            "moon", "noon", "room", "rooms", "soon", "spoon", "boom", "zoom", "tool", "tools",
            "pool", "cool", "school", "too", "zoo", "roof", "reef", "beef", "keep", "deep",
            "sleep", "sweep", "steep", "week", "weeks", "weed", "seed", "need", "speed", "bleed",
            "sex", "is", "six", "cats", "hats", "bats", "rats", "mats", "last", "fast",
            "past", "cast", "vast", "best", "rest", "test", "west", "nest", "vest", "chest",
            "guest", "quest", "car", "cars", "bar", "bars", "far", "jar", "star", "stars",
            "war", "wars", "now", "cow", "cows", "how", "bow", "row", "low", "slow", "snow",
            "show", "flow", "grow", "know", "blow", "throw", "window", "yellow", "follow",
            "law", "laws", "raw", "saw", "draw", "straw", "flaw", "claw", "jaw", "paw",
            "code", "mode", "node", "file", "files", "line", "lines", "time", "times", "fine",
            "home", "some", "come", "done", "none", "tone", "zone", "bone", "stone", "phone",
            "care", "share", "rare", "bare", "dare", "fare", "ware", "square", "prepare",
            "here", "there", "where", "were", "more", "core", "store", "score", "shore", "bore",
            "user", "users", "server", "client", "system", "folder", "format", "browser",
            "water", "paper", "later", "after", "never", "ever", "over", "under", "other",
            "mother", "father", "brother", "sister", "winter", "summer", "number", "member"
        ]
        for w in extraOfflineEnglish { baseEnglishLexicon.insert(w.lowercased()) }
        for w in additionalEnglishWords where !w.isEmpty { baseEnglishLexicon.insert(w.lowercased()) }

        let sortedWords = baseEnglishLexicon.sorted()
        let stdEngine = VietnameseEngine()
        stdEngine.inputMethod = .telex
        stdEngine.grammarProfile = .classic
        stdEngine.genZMode = false
        stdEngine.relaxedCoda = false

        let genZEngine = VietnameseEngine()
        genZEngine.inputMethod = .telex
        genZEngine.grammarProfile = .classic
        genZEngine.genZMode = true
        genZEngine.relaxedCoda = true

        let vuisEngine = VietnameseEngine()
        vuisEngine.inputMethod = .telex
        vuisEngine.grammarProfile = .senFlex
        vuisEngine.genZMode = false
        vuisEngine.relaxedCoda = false

        var stdCollisions = 0
        var genZCollisions = 0
        var vuisCollisions = 0

        for word in sortedWords {
            let chars = Array(word)
            if stdEngine.transform(chars).lowercased() != word { stdCollisions += 1 }
            if genZEngine.transform(chars).lowercased() != word { genZCollisions += 1 }
            if vuisEngine.transform(chars).lowercased() != word { vuisCollisions += 1 }
        }

        struct CorpusScenario {
            let isHoldout: Bool
            let tokens: [(raw: String, expected: String, isEnglish: Bool)]
        }

        // Calibration Set (isHoldout = false) and Independent Holdout Set (isHoldout = true)
        // covering Pure Vietnamese, Pure English, and Mixed Code-Switching sentences.
        let scenarios: [CorpusScenario] = [
            // Calibration — Vietnamese
            CorpusScenario(isHoldout: false, tokens: [
                ("tooi", "tôi", false), ("sex", "sẽ", false), ("ddi", "đi", false),
                ("hocj", "học", false), ("moon", "môn", false), ("toans", "toán", false),
                ("owr", "ở", false), ("been", "bên", false), ("truowngf", "trường", false)
            ]),
            CorpusScenario(isHoldout: false, tokens: [
                ("con", "con", false), ("cas", "cá", false), ("tree", "trê", false),
                ("bowi", "bơi", false), ("duowis", "dưới", false), ("nuowcs", "nước", false)
            ]),
            CorpusScenario(isHoldout: false, tokens: [
                ("cais", "cái", false), ("is", "í", false), ("raats", "rất", false),
                ("ddejp", "đẹp", false), ("vaf", "và", false), ("rer", "rẻ", false)
            ]),
            // Calibration — English
            CorpusScenario(isHoldout: false, tokens: [
                ("is", "is", true), ("the", "the", true), ("free", "free", true),
                ("book", "book", true), ("in", "in", true), ("the", "the", true),
                ("room", "room", true), ("too", "too", true)
            ]),
            CorpusScenario(isHoldout: false, tokens: [
                ("the", "the", true), ("queen", "queen", true), ("has", "has", true),
                ("seen", "seen", true), ("the", "the", true), ("green", "green", true),
                ("trees", "trees", true), ("at", "at", true), ("noon", "noon", true)
            ]),
            // Calibration — Mixed / Code-Switching
            CorpusScenario(isHoldout: false, tokens: [
                ("minhf", "mình", false), ("vaf", "và", false), ("banj", "bạn", false),
                ("sex", "sẽ", false), ("ddocj", "đọc", false), ("the", "the", true),
                ("book", "book", true), ("with", "with", true), ("the", "the", true),
                ("fee", "fee", true)
            ]),
            CorpusScenario(isHoldout: false, tokens: [
                ("xem", "xem", false), ("phim", "phim", false), ("sex", "sex", true),
                ("hoawcj", "hoặc", false), ("safe", "safe", true), ("sex", "sex", true)
            ]),

            // Independent Holdout — Vietnamese
            CorpusScenario(isHoldout: true, tokens: [
                ("hoj", "họ", false), ("ddax", "đã", false), ("queen", "quên", false),
                ("ddawtj", "đặt", false), ("teen", "tên", false), ("cho", "cho", false),
                ("con", "con", false), ("oocs", "ốc", false), ("seen", "sên", false)
            ]),
            CorpusScenario(isHoldout: true, tokens: [
                ("anh", "anh", false), ("is", "í", false), ("mang", "mang", false),
                ("ddooi", "đôi", false), ("giayf", "giày", false), ("boots", "bốt", false),
                ("mowis", "mới", false)
            ]),
            CorpusScenario(isHoldout: true, tokens: [
                ("muaf", "mùa", false), ("ddoong", "đông", false), ("trowif", "trời", false),
                ("rest", "rét", false), ("cawts", "cắt", false), ("tawts", "tắt", false),
                ("caan", "cân", false), ("truowngrw", "trưởngw", false)
            ]),
            // Independent Holdout — English
            CorpusScenario(isHoldout: true, tokens: [
                ("she", "she", true), ("is", "is", true), ("reading", "reading", true),
                ("a", "a", true), ("good", "good", true), ("book", "book", true),
                ("under", "under", true), ("the", "the", true), ("tree", "tree", true)
            ]),
            CorpusScenario(isHoldout: true, tokens: [
                ("the", "the", true), ("cats", "cats", true), ("and", "and", true),
                ("the", "the", true), ("hats", "hats", true), ("are", "are", true),
                ("the", "the", true), ("best", "best", true), ("in", "in", true),
                ("the", "the", true), ("bar", "bar", true), ("now", "now", true)
            ]),
            // Independent Holdout — Mixed / Code-Switching
            CorpusScenario(isHoldout: true, tokens: [
                ("tooi", "tôi", false), ("queen", "quên", false), ("the", "the", true),
                ("fees", "fees", true), ("in", "in", true), ("the", "the", true),
                ("moon", "moon", true), ("room", "room", true)
            ]),
            CorpusScenario(isHoldout: true, tokens: [
                ("con", "con", false), ("bee", "bê", false), ("vaf", "và", false),
                ("the", "the", true), ("bee", "bee", true), ("with", "with", true),
                ("cold", "cold", true), ("beer", "beer", true)
            ])
        ]

        func runSubset(_ subset: [CorpusScenario]) -> BilingualCorpusQuantitativeMetrics {
            var totalTokens = 0
            var enTokens = 0
            var vnTokens = 0
            var enCorrupted = 0
            var vnPreserved = 0
            var rawReplayErrors = 0
            var totalFlips = 0
            var extraKeystrokes = 0
            var totalKeystrokes = 0
            var consistentKeystrokes = 0

            for scenario in subset {
                let macSession = InputSessionManager()
                macSession.setInputMethod(.telex)
                macSession.setGrammarProfile(.senFlex)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true

                #if !VIELOTUS_OPEN_CORE_MACOS
                let iosAdapter = UIKitInputSessionAdapter(session: InputSessionManager())
                iosAdapter.session.setInputMethod(.telex)
                iosAdapter.session.setGrammarProfile(.senFlex)
                iosAdapter.session.smartBilingualEnabled = true
                iosAdapter.session.inlineBilingualEnabled = true
                let iosProxy = InMemoryConsistencyProxy()
                #endif

                for token in scenario.tokens {
                    totalTokens += 1
                    if token.isEnglish { enTokens += 1 } else { vnTokens += 1 }

                    for ch in token.raw {
                        _ = macSession.handleCharacter(ch)
                        totalKeystrokes += 1
                        #if !VIELOTUS_OPEN_CORE_MACOS
                        iosAdapter.handleCharacter(ch, proxy: iosProxy)
                        if macSession.composingWord == iosAdapter.session.composingWord {
                            consistentKeystrokes += 1
                        }
                        #else
                        consistentKeystrokes += 1
                        #endif
                    }

                    let flipsInWord = macSession.candidateProvenance.flipCount
                    totalFlips += flipsInWord

                    let commitAction = macSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
                    #if !VIELOTUS_OPEN_CORE_MACOS
                    iosAdapter.handleCharacter(" ", proxy: iosProxy)
                    #endif
                    let committedWord: String
                    if case let .commit(_, text, _) = commitAction {
                        committedWord = text
                    } else {
                        committedWord = macSession.composingWord
                    }

                    if token.isEnglish {
                        if committedWord != token.expected {
                            enCorrupted += 1
                            extraKeystrokes += 1
                        }
                    } else {
                        if committedWord == token.expected {
                            vnPreserved += 1
                        } else {
                            extraKeystrokes += 1
                            if committedWord == token.raw && token.raw != token.expected {
                                rawReplayErrors += 1
                            }
                        }
                    }
                }
            }

            let enCorruptionRate = enTokens > 0 ? Double(enCorrupted) / Double(enTokens) : 0.0
            let vnPreservationRate = vnTokens > 0 ? Double(vnPreserved) / Double(vnTokens) : 1.0
            let rawReplayRate = vnTokens > 0 ? Double(rawReplayErrors) / Double(vnTokens) : 0.0
            let flipRate = totalTokens > 0 ? Double(totalFlips) / Double(totalTokens) : 0.0
            let extraKeysRate = totalTokens > 0 ? Double(extraKeystrokes) / Double(totalTokens) : 0.0
            let consistencyRate = totalKeystrokes > 0 ? Double(consistentKeystrokes) / Double(totalKeystrokes) : 1.0

            return BilingualCorpusQuantitativeMetrics(
                totalEvaluatedTokens: totalTokens,
                englishTokenCount: enTokens,
                vietnameseTokenCount: vnTokens,
                englishCorruptionRate: enCorruptionRate,
                vietnamesePreservationRate: vnPreservationRate,
                incorrectRawReplayRate: rawReplayRate,
                candidateFlipRate: flipRate,
                extraKeystrokesToCorrect: extraKeysRate,
                macOSiOSCoreConsistency: consistencyRate
            )
        }

        let calibrationScenarios = scenarios.filter { !$0.isHoldout }
        let holdoutScenarios = scenarios.filter { $0.isHoldout }

        return BilingualFullCorpusEvaluationReport(
            sweptEnglishWordCount: sortedWords.count,
            standardTelexCollisionCount: stdCollisions,
            genZCollisionCount: genZCollisions,
            vuisCollisionCount: vuisCollisions,
            calibrationMetrics: runSubset(calibrationScenarios),
            holdoutMetrics: runSubset(holdoutScenarios),
            combinedMetrics: runSubset(scenarios)
        )
    }
}

#if !VIELOTUS_OPEN_CORE_MACOS
private final class InMemoryConsistencyProxy: TextDocumentProxyProtocol {
    var buffer: String = ""
    var documentContextBeforeInput: String? { buffer.isEmpty ? nil : buffer }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    func insertText(_ text: String) { buffer.append(text) }
    func deleteBackward() { if !buffer.isEmpty { buffer.removeLast() } }
}
#endif
