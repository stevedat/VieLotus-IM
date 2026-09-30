import Foundation
import NaturalLanguage

public struct SmartBilingualDetector {
    private static let lock = NSLock()
    private static let sharedRecognizer = NLLanguageRecognizer()
    private static var spellCheckCache: [String: Bool] = [:]
    private static var cacheKeys: [String] = []
    private static let maxCacheEntries = 1024

    public static var spellCheckerProvider: SpellCheckerProvider?

    // Core Telex tone/diacritic multi-letter primitives that must NEVER be restored without English context
    private static let telexPrimitives: Set<String> = [
        "of", "is", "as", "us", "if", "os", "es", "ex", "ar",
        "dd", "aa", "ee", "oo", "aw", "ow", "uw", "beef", "has"
    ]

    // Known popular tech words / proper nouns that are universally recognized
    private static let commonEnglishTechWords: Set<String> = [
        "facebook", "google", "apple", "microsoft", "github", "gitlab",
        "twitter", "youtube", "amazon", "netflix", "spotify", "tiktok",
        "instagram", "docker", "kubernetes", "vscode", "slack", "zoom",
        "linux", "ubuntu", "macos", "ios", "android", "windows"
    ]

    private static let nonVietnameseLetters: Set<Character> = ["f", "j", "w", "z"]

    // NOTE: "dd" is excluded because "dd" = "đ" in Vietnamese
    private static let doubleConsonants = ["bb", "cc", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss", "tt", "vv"]

    private static let englishEndings = ["sh", "ck", "ts", "ds", "st", "nd", "ld", "rt", "ct", "pt", "lt", "nt"]

    public static func isEnglishWord(raw: String, context: String = "") -> Bool {
        let lowerRaw = raw.lowercased()
        if lowerRaw == "iff" || lowerRaw == "orr" { return false }

        guard lowerRaw.count > 1 else { return false } // Single letters usually aren't overridden

        // 1. Core Telex primitives check
        if telexPrimitives.contains(lowerRaw) {
            if context.isEmpty { return false }
            lock.lock()
            defer { lock.unlock() }
            sharedRecognizer.reset()
            sharedRecognizer.processString(context)
            return sharedRecognizer.dominantLanguage == .english
        }

        // 2. SpellChecker with thread-safe memoization
        let isEnglishDictWord: Bool
        lock.lock()
        if let cached = spellCheckCache[lowerRaw] {
            isEnglishDictWord = cached
            lock.unlock()
        } else {
            lock.unlock()
            
            // Check dictionary using the injected provider or common tech words
            let result = commonEnglishTechWords.contains(lowerRaw) || (spellCheckerProvider?.isWordInEnglishDictionary(raw) ?? false)
            
            lock.lock()
            if spellCheckCache.count >= maxCacheEntries {
                let evictCount = maxCacheEntries / 4
                for _ in 0..<evictCount {
                    if !cacheKeys.isEmpty {
                        let oldKey = cacheKeys.removeFirst()
                        spellCheckCache.removeValue(forKey: oldKey)
                    }
                }
            }
            spellCheckCache[lowerRaw] = result
            cacheKeys.append(lowerRaw)
            isEnglishDictWord = result
            lock.unlock()
        }

        guard isEnglishDictWord else { return false }

        // 3. Structural patterns (Letters/combinations that cannot exist in Vietnamese)
        if lowerRaw.contains(where: { nonVietnameseLetters.contains($0) }) { return true }
        if doubleConsonants.contains(where: { lowerRaw.contains($0) }) { return true }
        if englishEndings.contains(where: { lowerRaw.hasSuffix($0) }) { return true }

        // 4. NaturalLanguage context evaluation (reusing lock-guarded recognizer)
        lock.lock()
        defer { lock.unlock() }
        sharedRecognizer.reset()
        let fullContext = (context.isEmpty ? "" : context + " ") + raw
        sharedRecognizer.processString(fullContext)
        
        if let dominant = sharedRecognizer.dominantLanguage {
            if dominant == .english { return true }
            if dominant == .vietnamese { return false }
        }

        // 5. Single-word fallback
        sharedRecognizer.reset()
        sharedRecognizer.processString(raw)
        if let dominant = sharedRecognizer.dominantLanguage, dominant == .english {
            return true
        }

        return false
    }
}
