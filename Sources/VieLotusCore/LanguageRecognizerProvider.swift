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
    /// Binary-constrained (`vi` vs `en`) English confidence floor.
    /// Empirically calibrated so short English/dev phrases (`pull request`, `git commit`,
    /// `code review`, `fix bug`, `check code`) score >= 0.98 while unaccented Vietnamese
    /// (`an com` 0.943, `ban be` 0.923, `cam on` 0.921, `ban an com chua` 0.794),
    /// loanword nouns (`server` 0.944), and non-EN/VI phrases (`bonjour monsieur` 0.735)
    /// stay strictly below threshold.
    private static let constrainedEnglishConfidenceThreshold: Double = 0.95
    private static let bilingualConstraints: [NLLanguage] = [.vietnamese, .english]

    private var dominantLangCache: [String: Bool] = [:]
    private var dominantLangCacheKeys: [String] = []
    private var confidentContextCache: [String: Bool] = [:]
    private var confidentContextCacheKeys: [String] = []

    internal init() {}

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
        lock.lock()
        defer { lock.unlock() }

        if let cached = confidentContextCache[context] {
            return cached
        }

        contextRecognizer.reset()
        // Re-apply constraints after every reset(): Apple's NLLanguageRecognizer clears
        // internal constraint state on reset() even though the getter still reports them.
        contextRecognizer.languageConstraints = Self.bilingualConstraints
        contextRecognizer.processString(context)
        let hypotheses = contextRecognizer.languageHypotheses(withMaximum: 2)
        let englishScore = hypotheses[.english, default: 0]
        let vietnameseScore = hypotheses[.vietnamese, default: 0]
        let result = englishScore >= Self.constrainedEnglishConfidenceThreshold && englishScore >= vietnameseScore * 2

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
