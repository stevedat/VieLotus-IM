import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// SPI protocol for detecting languages and scoring context confidence.
internal protocol LanguageRecognizerProvider: Sendable {
    func isDominantLanguageEnglish(_ text: String) -> Bool
    func isConfidentEnglishContext(_ context: String) -> Bool
}

#if canImport(NaturalLanguage)
/// Apple-native implementation using `NLLanguageRecognizer` on macOS/iOS.
internal final class AppleLanguageRecognizerProvider: LanguageRecognizerProvider, @unchecked Sendable {
    private let lock = NSLock()
    /// Unconstrained recognizer for single-token / open-vocabulary `isDominantLanguageEnglish`.
    private let recognizer = NLLanguageRecognizer()
    /// Dedicated binary-constrained recognizer (`[.vietnamese, .english]`) for sentence-context
    /// arbitration so probability mass is never diluted across 50+ unrelated languages.
    private let contextRecognizer = NLLanguageRecognizer()

    /// 512-entry bounded caches with 25% FIFO batch eviction.
    private static let dominantLangCacheCapacity = 512
    private static let confidentContextCacheCapacity = 512
    /// Binary-constrained (`vi` vs `en`) English confidence floors.
    /// After structural pre-checks exclude single-token inputs, Vietnamese diacritics,
    /// all-Vietnamese-syllable clauses (`an com`, `cam on`, `ban be`), and third-language
    /// phrases (`bonjour monsieur`, `hola amigo`), these floors remain stable across
    /// macOS 13–26 `NLLanguageRecognizer` model revisions (including short 2-word phrases
    /// such as `code review` and `fix bug` on macOS 15).
    private static let constrainedEnglishConfidenceThreshold: Double = 0.95
    private static let dictionaryBackedEnglishConfidenceThreshold: Double = 0.55
    private static let bilingualConstraints: [NLLanguage] = [.vietnamese, .english]

    private var dominantLangCache: [String: Bool] = [:]
    private var dominantLangCacheKeys: [String] = []
    private var confidentContextCache: [String: Bool] = [:]
    private var confidentContextCacheKeys: [String] = []

    internal init() {}

    private func storeConfidentContextCache(_ context: String, result: Bool) {
        if confidentContextCacheKeys.count >= Self.confidentContextCacheCapacity {
            let evictCount = Self.confidentContextCacheCapacity / 4
            let evictedKeys = Array(confidentContextCacheKeys.prefix(evictCount))
            for key in evictedKeys {
                confidentContextCache.removeValue(forKey: key)
            }
            confidentContextCacheKeys.removeFirst(evictCount)
        }
        confidentContextCache[context] = result
        confidentContextCacheKeys.append(context)
    }

    internal func isDominantLanguageEnglish(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Fast path: return cached result
        if let cached = dominantLangCache[text] {
            return cached
        }

        recognizer.reset()
        recognizer.processString(text)
        let result = recognizer.dominantLanguage == .english

        // Evict oldest 25% when cache is full
        if dominantLangCacheKeys.count >= Self.dominantLangCacheCapacity {
            let evictCount = Self.dominantLangCacheCapacity / 4
            let evictedKeys = Array(dominantLangCacheKeys.prefix(evictCount))
            for key in evictedKeys {
                dominantLangCache.removeValue(forKey: key)
            }
            dominantLangCacheKeys.removeFirst(evictCount)
        }

        dominantLangCache[text] = result
        dominantLangCacheKeys.append(text)
        return result
    }

    internal func isConfidentEnglishContext(_ context: String) -> Bool {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Single-token inputs ("server", "error") and clauses containing Vietnamese diacritics
        // ("tôi đang", "deploy server nó", "merge PR này") are never confident English context.
        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII || $0.value == 0x2018 || $0.value == 0x2019 }) else {
            return false
        }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: .punctuationCharacters).lowercased()
        }.filter { !$0.isEmpty }
        guard tokens.count >= 2 else { return false }

        lock.lock()
        defer { lock.unlock() }

        if let cached = confidentContextCache[context] {
            return cached
        }

        // Reject unaccented Vietnamese clauses where every token is a valid untoned Vietnamese
        // syllable (e.g. "an com", "cam on", "ban be", "khong sao", "hom nay", "di choi").
        if tokens.allSatisfy({ VietnameseSyllableDictionary.shared.isValidUntonedSyllable($0) }) {
            storeConfidentContextCache(context, result: false)
            return false
        }

        let allKnownEnglishWords = tokens.allSatisfy { token in
            guard token.count >= 2 || token == "a" || token == "i" else { return false }
            // Exclude vowelless abbreviations / web noise ("ww", "www", "ws", "wf") even if present in SCOWL.
            guard token.unicodeScalars.contains(where: {
                let v = $0.value
                return v == 0x61 || v == 0x65 || v == 0x69 || v == 0x6F || v == 0x75 || v == 0x79
            }) else {
                return false
            }
            return EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(token)
        }

        // Reject confident third-language phrases (e.g. "bonjour monsieur", "hola amigo")
        // before binary [vi, en] renormalization can force their mass onto .english.
        if !allKnownEnglishWords {
            recognizer.reset()
            recognizer.processString(trimmed)
            let unconstrained = recognizer.languageHypotheses(withMaximum: 2)
            let unconstrainedEnglish = unconstrained[.english, default: 0]
            if let dominant = recognizer.dominantLanguage,
               dominant != .english,
               dominant != .vietnamese,
               unconstrainedEnglish < 0.20 {
                storeConfidentContextCache(context, result: false)
                return false
            }
        }

        contextRecognizer.reset()
        // Re-apply constraints after every reset(): Apple's NLLanguageRecognizer clears
        // internal constraint state on reset() even though the getter still reports them.
        contextRecognizer.languageConstraints = Self.bilingualConstraints
        contextRecognizer.processString(trimmed)
        let hypotheses = contextRecognizer.languageHypotheses(withMaximum: 2)
        let englishScore = hypotheses[.english, default: 0]
        let vietnameseScore = hypotheses[.vietnamese, default: 0]
        let result: Bool
        if allKnownEnglishWords {
            result = englishScore >= Self.dictionaryBackedEnglishConfidenceThreshold && englishScore > vietnameseScore
        } else {
            result = englishScore >= Self.constrainedEnglishConfidenceThreshold && englishScore >= vietnameseScore * 2
        }

        storeConfidentContextCache(context, result: result)
        return result
    }
}
#endif

/// Lightweight fallback implementation for Linux/Windows/WASM without Apple NaturalLanguage.
internal final class HeuristicLanguageRecognizerProvider: LanguageRecognizerProvider, @unchecked Sendable {
    internal init() {}

    internal func isDominantLanguageEnglish(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy { $0.isASCII }
    }

    internal func isConfidentEnglishContext(_ context: String) -> Bool {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return false }
        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        return words.contains { word in
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            return EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(cleaned)
        }
    }
}
