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
    private let recognizer = NLLanguageRecognizer()

    /// 512-entry LRU-style cache for `isDominantLanguageEnglish` with 25% FIFO batch eviction.
    private static let dominantLangCacheCapacity = 512
    private var dominantLangCache: [String: Bool] = [:]
    private var dominantLangCacheKeys: [String] = []

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
        recognizer.reset()
        recognizer.processString(context)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let englishScore = hypotheses[.english, default: 0]
        let vietnameseScore = hypotheses[.vietnamese, default: 0]
        return englishScore >= 0.75 && englishScore >= vietnameseScore * 2
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
