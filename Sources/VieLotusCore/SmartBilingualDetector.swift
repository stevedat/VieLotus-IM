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

    private static let commonEnglishWords: Set<String> = ["user", "users"]

    private static let nonVietnameseLetters: Set<Character> = ["f", "j", "w", "z"]

    // NOTE: "dd" is excluded because "dd" = "đ" in Vietnamese
    private static let doubleConsonants = ["bb", "cc", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss", "tt", "vv"]

    private static let englishEndings = ["sh", "ck", "ts", "ds", "st", "nd", "ld", "rt", "ct", "pt", "lt", "nt"]

    public static func isEnglishWord(raw: String, context: String = "", rendered: String? = nil) -> Bool {
        let cleanRaw = raw.trimmingCharacters(in: .punctuationCharacters)
        let lowerRaw = cleanRaw.lowercased()
        if lowerRaw == "ww" && rendered?.lowercased() == "w" { return false }
        if lowerRaw == "iff" || lowerRaw == "orr" { return false }

        guard lowerRaw.count > 1 else { return false }

        // 1. Core Telex primitives check
        if telexPrimitives.contains(lowerRaw) {
            if context.isEmpty { return false }
            lock.lock()
            defer { lock.unlock() }
            sharedRecognizer.reset()
            sharedRecognizer.processString(context)
            return sharedRecognizer.dominantLanguage == .english
        }

        // 2. Code/URL structures
        let codeCharacters: Set<Character> = ["_", "/", "\\", "-", ".", "[", "]", "{", "}", "<", ">", "=", "+", "*", "@", "#", "$", "%", "^", "&", "|"]
        if lowerRaw.contains(where: { codeCharacters.contains($0) }) {
            // Except for hyphen, which might be in Vietnamese words like "viet-nam"
            if !lowerRaw.contains(where: { $0 != "-" && codeCharacters.contains($0) }) {
                // It only contains hyphen. Let it pass through to dictionary check.
            } else {
                return true
            }
        }

        if commonEnglishWords.contains(lowerRaw),
           let rendered,
           lowerRaw != rendered.lowercased() {
            return true
        }

        let isUppercaseWord = raw == raw.uppercased() && raw.count > 1
        if let rendered,
           lowerRaw != rendered.lowercased(),
           !isUppercaseWord,
           !commonEnglishTechWords.contains(lowerRaw),
           isPlausibleVietnameseText(rendered) {
            return isConfidentEnglishContext(context)
        }

        if let rendered,
           let escapedWord = collapsedTelexToneEscapes(lowerRaw),
           escapedWord == rendered.lowercased(),
           isKnownEnglishWord(escapedWord),
           !isKnownEnglishWord(lowerRaw) {
            return false
        }

        // A Telex modifier may precede a coda (for example, tuyeern -> tuyển).
        // Keep plausible Vietnamese output unless surrounding text is strongly English.
        let telexEndingKeys: Set<Character> = ["s", "f", "r", "x", "j", "z", "w"]
        if let rendered,
           lowerRaw != rendered.lowercased(),
           !isUppercaseWord,
           !commonEnglishTechWords.contains(lowerRaw),
           isPlausibleVietnameseSyllable(rendered),
           (lowerRaw.contains(where: telexEndingKeys.contains) || hasWModifierAfterVowel(lowerRaw)) {
            return isConfidentEnglishContext(context)
        }

        // Analyze how the engine transformed the word.
        if let rendered, lowerRaw != rendered.lowercased() {
            let hasVietnameseDiacritics = rendered.contains(where: { !$0.isASCII })
            if !hasVietnameseDiacritics {
                // If the engine transformed it (e.g. ate a character like 's' in Systems, or 'x' in maxx)
                // but didn't produce ANY Vietnamese diacritics, it's a mangled English word.
                // We must restore it to prevent data loss (e.g. Systems, maxx, cass, arr).
                return true
            }
            if !isPlausibleVietnameseText(rendered) {
                return true
            }
        }

        // 3. SpellChecker
        let isEnglishDictWord: Bool
        lock.lock()
        if let cached = spellCheckCache[lowerRaw] {
            isEnglishDictWord = cached
            lock.unlock()
        } else {
            lock.unlock()

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

        if isEnglishDictWord {
            if raw == raw.uppercased() && raw.count > 1 { return true }
            if lowerRaw.contains(where: { nonVietnameseLetters.contains($0) }) { return true }
            if doubleConsonants.contains(where: { lowerRaw.contains($0) }) { return true }
            if englishEndings.contains(where: { lowerRaw.hasSuffix($0) }) { return true }

            lock.lock()
            sharedRecognizer.reset()
            sharedRecognizer.processString((context.isEmpty ? "" : context + " ") + cleanRaw)
            if sharedRecognizer.dominantLanguage == .english { lock.unlock(); return true }
            lock.unlock()
            if lowerRaw.count > 3 { return true }
        } else {
            lock.lock()
            sharedRecognizer.reset()
            sharedRecognizer.processString(cleanRaw)
            if sharedRecognizer.dominantLanguage == .english {
                lock.unlock()
                let lastChar = lowerRaw.last!
                if ["j", "w", "f", "r", "s", "x"].contains(lastChar) && lowerRaw.count <= 6 {
                    return false
                }
                return true
            }
            lock.unlock()
        }

        return false
    }

    private static func isConfidentEnglishContext(_ context: String) -> Bool {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContext.split(whereSeparator: \.isWhitespace).count >= 2 else { return false }
        // A mixed-language recognizer can score short Vietnamese context as English.
        // Diacritics are strong evidence that the active sentence is Vietnamese.
        guard trimmedContext.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }

        lock.lock()
        defer { lock.unlock() }
        sharedRecognizer.reset()
        sharedRecognizer.processString(trimmedContext)
        let hypotheses = sharedRecognizer.languageHypotheses(withMaximum: 2)
        let englishScore = hypotheses[.english, default: 0]
        let vietnameseScore = hypotheses[.vietnamese, default: 0]
        return englishScore >= 0.75 && englishScore >= vietnameseScore * 2
    }

    private static func isPlausibleVietnameseSyllable(_ word: String) -> Bool {
        let normalized = word.lowercased()
        let characters = Array(normalized)
        let vowels: Set<Character> = [
            "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
            "á", "à", "ả", "ã", "ạ", "ắ", "ằ", "ẳ", "ẵ", "ặ", "ấ", "ầ", "ẩ", "ẫ", "ậ",
            "é", "è", "ẻ", "ẽ", "ẹ", "ế", "ề", "ể", "ễ", "ệ", "í", "ì", "ỉ", "ĩ", "ị",
            "ó", "ò", "ỏ", "õ", "ọ", "ố", "ồ", "ổ", "ỗ", "ộ", "ớ", "ờ", "ở", "ỡ", "ợ",
            "ú", "ù", "ủ", "ũ", "ụ", "ứ", "ừ", "ử", "ữ", "ự", "ý", "ỳ", "ỷ", "ỹ", "ỵ"
        ]
        guard let firstVowel = characters.firstIndex(where: { vowels.contains($0) }),
              let lastVowel = characters.lastIndex(where: { vowels.contains($0) }) else {
            return false
        }

        let nucleus = characters[firstVowel...lastVowel]
        guard nucleus.allSatisfy({ vowels.contains($0) }), nucleus.count <= 3 else { return false }

        let onset = String(characters[..<firstVowel])
        let coda = String(characters[(lastVowel + 1)...])
        let validOnsets: Set<String> = [
            "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n",
            "ng", "ngh", "nh", "p", "ph", "q", "qu", "r", "s", "t", "th", "tr", "v", "x"
        ]
        let validCodas: Set<String> = ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"]
        return validOnsets.contains(onset) && validCodas.contains(coda)
    }

    private static func isPlausibleVietnameseText(_ text: String) -> Bool {
        let syllables = text.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        return !syllables.isEmpty && syllables.allSatisfy { isPlausibleVietnameseSyllable(String($0)) }
    }

    private static func hasWModifierAfterVowel(_ word: String) -> Bool {
        let characters = Array(word)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        return characters.indices.contains { index in
            characters[index] == "w" && index > 0 && vowels.contains(characters[index - 1])
        }
    }

    private static func collapsedTelexToneEscapes(_ word: String) -> String? {
        let characters = Array(word)
        let toneKeys: Set<Character> = ["s", "r"]
        var collapsed: [Character] = []
        var removedEscape = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if toneKeys.contains(character),
               index + 1 < characters.count,
               characters[index + 1] == character {
                collapsed.append(character)
                index += 2
                removedEscape = true
            } else {
                collapsed.append(character)
                index += 1
            }
        }

        return removedEscape ? String(collapsed) : nil
    }

    private static func isKnownEnglishWord(_ word: String) -> Bool {
        commonEnglishWords.contains(word.lowercased()) ||
            (spellCheckerProvider?.isWordInEnglishDictionary(word) ?? false)
    }
}
