#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

/// Resolves an untoned Vietnamese syllable into ranked toned variants using bigram context.
///
/// Leverages `WordSuggestionEngine.shared` for contextual ranking and
/// `VietnameseSyllableDictionary.shared` for enumerating all valid toned forms.
public struct GlideToneResolver {
    private static let variantsByBase: [String: [String]] = Dictionary(grouping:
        VietnameseSyllableDictionary.shared.syllables.sorted(),
        by: { VietnameseSyllableDictionary.stripToneMarks($0) })


    public static func prepare() { _ = variantsByBase }

    /// Resolves toned variants for an untoned syllable, ranked by context.
    ///
    /// - Parameters:
    ///   - untoned: The untoned base syllable (e.g. "nhan")
    ///   - context: Text before the cursor for bigram context (e.g. "tôi đang ")
    ///   - telexToneKey: Optional trailing Telex tone key from the glide path (e.g. "s" for sắc)
    ///   - limit: Maximum number of variants to return
    /// - Returns: Ranked toned syllable strings (e.g. ["nhận", "nhân", "nhàn", ...])
    public static func resolve(
        untoned: String,
        context: String,
        telexToneKey: Character? = nil,
        limit: Int = 5
    ) -> [String] {
        guard limit > 0 else { return [] }
        let dictionary = VietnameseSyllableDictionary.shared
        let lower = untoned.lowercased()

        // 1. Enumerate all toned variants from the syllable dictionary
        let allVariants = variantsByBase[lower] ?? []

        guard !allVariants.isEmpty else {
            // If untoned itself is valid, return it
            return dictionary.untonedSyllables.contains(lower) ? [lower] : []
        }

        // 2. If a Telex tone key was explicitly provided in the glide, filter to that tone
        if let toneKey = telexToneKey {
            let tonedByTelex = applyTelexTone(to: allVariants, toneKey: toneKey)
            if !tonedByTelex.isEmpty {
                // Still rank by context among the filtered set
                let ranked = rankByContext(tonedByTelex, context: context)
                var result = ranked
                // Also include untoned as fallback at the end
                if !result.contains(lower) { result.append(lower) }
                return Array(result.prefix(limit))
            }
        }

        // 3. Rank all variants by bigram context
        let ranked = rankByContext(Array(allVariants), context: context)
        return Array(ranked.prefix(limit))
    }

    /// Ranks multiple geometric candidates jointly using an immutable context snapshot.
    public static func resolve(candidates: [GlideCandidate], continuations: [String], limit: Int = 5) -> [GlideCandidate] {
        guard limit > 0 else { return [] }
        var scores: [String: Double] = [:]
        let contextRanks = Dictionary(continuations.enumerated().map { ($0.element.lowercased(), $0.offset) },
                                      uniquingKeysWith: min)
        for candidate in candidates {
            for variant in variantsByBase[candidate.syllable] ?? [] {
                let contextScore = contextRanks[variant].map { 0.2 / Double($0 + 1) } ?? 0
                let toneScore = candidate.toneKey.map { applyTelexTone(to: [variant], toneKey: $0).isEmpty ? 0.0 : 0.15 } ?? 0
                let score = candidate.score + contextScore + toneScore
                scores[variant] = max(scores[variant] ?? 0, score)
            }
        }
        var resolved: [GlideCandidate] = scores.map { GlideCandidate(syllable: $0.key, score: $0.value) }
        resolved.sort { a, b in
            if a.score == b.score {
                return a.syllable < b.syllable
            }
            return a.score > b.score
        }
        return Array(resolved.prefix(limit))
    }

    /// Ranks toned variants by bigram context score.
    private static func rankByContext(_ variants: [String], context: String) -> [String] {
        let engine = WordSuggestionEngine.shared
        let contextWords = context
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let lastWord = contextWords.last?.lowercased() ?? ""
        let bigramContinuations = engine.bigrams[lastWord] ?? []

        // Score each variant
        var scored: [(String, Double)] = variants.map { variant in
            var score = 0.0
            let varLower = variant.lowercased()

            // Bigram match: check if this variant appears in continuations
            if let idx = bigramContinuations.firstIndex(where: { $0.lowercased() == varLower }) {
                // Higher rank = higher score (first continuation = best)
                score += 10.0 / Double(idx + 1)
            }

            // User frequency boost
            let userBoost = UserFrequencyStore.shared.userBoost(for: varLower, contextKey: lastWord)
            score += userBoost

            // Slight preference for untoned form (common in casual typing)
            if !VietnameseSyllableDictionary.stripToneMarks(varLower).isEmpty {
                // Base frequency heuristic: common tones get small boost
                // Sắc (´) and Huyền (`) are most common in Vietnamese
                let nfd = varLower.decomposedStringWithCanonicalMapping
                if nfd.unicodeScalars.contains(where: { $0.value == 0x0301 }) { // Sắc
                    score += 0.3
                } else if nfd.unicodeScalars.contains(where: { $0.value == 0x0300 }) { // Huyền
                    score += 0.25
                } else if nfd.unicodeScalars.contains(where: { $0.value == 0x0323 }) { // Nặng
                    score += 0.2
                }
            }

            return (variant, score)
        }

        scored.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        return scored.map { $0.0 }
    }

    /// Filters variants to those matching a specific Telex tone key.
    private static func applyTelexTone(to variants: [String], toneKey: Character) -> [String] {
        // Map Telex key to Unicode combining mark
        let targetMark: UInt32?
        switch toneKey {
        case "s": targetMark = 0x0301  // Sắc (´)
        case "f": targetMark = 0x0300  // Huyền (`)
        case "r": targetMark = 0x0309  // Hỏi (hook)
        case "x": targetMark = 0x0303  // Ngã (~)
        case "j": targetMark = 0x0323  // Nặng (dot below)
        case "z": targetMark = nil     // Remove tone (return untoned)
        default: return variants
        }

        if toneKey == "z" {
            // Return only the untoned variant
            return variants.filter { variant in
                let nfd = variant.decomposedStringWithCanonicalMapping
                return !nfd.unicodeScalars.contains(where: { [0x0300, 0x0301, 0x0303, 0x0309, 0x0323].contains($0.value) })
            }
        }

        guard let mark = targetMark else { return variants }
        return variants.filter { variant in
            let nfd = variant.decomposedStringWithCanonicalMapping
            return nfd.unicodeScalars.contains(where: { $0.value == mark })
        }
    }
}
#endif
