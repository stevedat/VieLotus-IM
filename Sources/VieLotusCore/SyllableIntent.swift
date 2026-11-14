import Foundation

/// Defines the input grammar profile for Vietnamese syllable parsing.
public enum GrammarProfile: String, CaseIterable, Sendable {
    /// Classic Telex (traditional telex, backward compatible).
    case classic = "classic"

    /// Pre-vowel Telex: tone and modifier keys placed before or inside the vowel nucleus.
    case preVowel = "preVowel"

    /// Smart Hybrid: supports both pre-vowel and classic postfix keys.
    case smartHybrid = "smartHybrid"

    /// Unified multi-order Vietnamese input solver.
    case senFlex = "senFlex"
}

/// Consonant modification types.
internal enum ConsonantModification: Sendable, Equatable {
    case none
    case strokeD     // dd -> đ
}

/// Linguistic modifier categories acting on base character skeletons.
internal enum ModifierKind: Sendable, Equatable {
    case tone(VietnameseTone)
    case vowelShape(VowelModification)
    case consonantShape(ConsonantModification)
}

/// Describes an extracted modifier and its position in the raw keystroke sequence.
internal struct ModifierIntent: Sendable, Equatable {
    internal let kind: ModifierKind
    internal let rawIndices: [Int]

    internal init(kind: ModifierKind, rawIndices: [Int]) {
        self.kind = kind
        self.rawIndices = rawIndices
    }
}

/// Priority levels for candidate resolution.
internal enum CandidatePriority: Int, Comparable, Sendable {
    case p1_manualOverride = 1
    case p2_protectedToken = 2
    case p3_unambiguousPreVowel = 3
    case p4_multipleModifiers = 4
    case p5_classicTrailing = 5
    case p6_ambiguousOrEnglish = 6

    internal static func < (lhs: CandidatePriority, rhs: CandidatePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// SyllableCandidate represents an interpretation generated during candidate ranking.
internal struct SyllableCandidate: Sendable, Equatable {
    internal let raw: String
    internal let rendered: String
    internal let priority: CandidatePriority
    internal let isVietnamese: Bool
    internal let intent: SyllableIntent
    internal let score: Int

    internal init(
        raw: String,
        rendered: String,
        priority: CandidatePriority,
        isVietnamese: Bool,
        intent: SyllableIntent,
        score: Int = 0
    ) {
        self.raw = raw
        self.rendered = rendered
        self.priority = priority
        self.isVietnamese = isVietnamese
        self.intent = intent
        self.score = score
    }
}

/// SyllableIntent models the decomposed linguistic structure of a Vietnamese syllable.
/// Separates input keystroke syntax from syllable formation.
internal struct SyllableIntent: Sendable, Equatable {
    /// Initial consonant or consonant cluster (e.g. "tr", "th", "qu", "r", "c", "đ", "")
    internal var onset: String = ""

    /// Vowel nucleus (e.g. "ươ", "uyên", "ê", "o", "a", "u", "iê")
    internal var nucleus: String = ""

    /// Final consonant (coda) (e.g. "ng", "n", "t", "m", "c", "ch", "p", "nh", "")
    internal var coda: String = ""

    /// Vietnamese tone diacritic
    internal var tone: VietnameseTone = .none

    /// Raw keystrokes entering this intent
    internal var rawChars: [Character] = []

    /// Whether the intent was resolved as a valid Vietnamese syllable
    internal var isValidVietnamese: Bool = false

    /// Whether a pre-vowel tone modifier was detected
    internal var hasPreVowelTone: Bool = false

    /// Whether a pre-vowel or infix horn modifier 'w' was detected
    internal var hasHornModifier: Bool = false

    internal init(
        onset: String = "",
        nucleus: String = "",
        coda: String = "",
        tone: VietnameseTone = .none,
        rawChars: [Character] = [],
        isValidVietnamese: Bool = false,
        hasPreVowelTone: Bool = false,
        hasHornModifier: Bool = false
    ) {
        self.onset = onset
        self.nucleus = nucleus
        self.coda = coda
        self.tone = tone
        self.rawChars = rawChars
        self.isValidVietnamese = isValidVietnamese
        self.hasPreVowelTone = hasPreVowelTone
        self.hasHornModifier = hasHornModifier
    }
}
