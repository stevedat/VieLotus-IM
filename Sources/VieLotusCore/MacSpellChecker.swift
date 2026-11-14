#if os(macOS)
import Cocoa

public struct MacSpellChecker: SpellCheckerProvider {
    public init() {
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
        _ = NSSpellChecker.shared.setLanguage("en")
    }

    public func isWordInEnglishDictionary(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(word) {
            return true
        }
        let lower = word.lowercased()
        if lower.contains("uoo") || lower.contains("uow") || lower.contains("uwo") ||
           lower.contains("iee") || lower.contains("yee") || lower.contains("ooi") ||
           lower.contains("oong") || lower.contains("ooc") || lower.hasPrefix("dd") ||
           lower.contains("aa") || (lower.contains("uw") && lower != "urw") ||
           (lower.contains("aw") && lower != "dawn" && lower != "lawn" && lower != "laws" && lower != "draws") {
            return false
        }
        // Reject macOS AppleSpell archaic/rare 'ee'/'oo' false positives (e.g. "treen" -> "trên", "toon" -> "tôn")
        // that are not in EmbeddedEnglishSpellChecker and compose into a valid attested Vietnamese syllable.
        // Genuine modern English collisions ("tree", "been", "seen", "teen", "queen", "moon", "noon", "room", "too", etc.)
        // already returned true via EmbeddedEnglishSpellChecker above.
        if (lower.contains("ee") || lower.contains("oo")),
           BilingualIntentArbiter.englishCollisionLogFrequencies[lower] == nil,
           !SmartBilingualDetector.isContextSensitiveEnglishCollision(lower) {
            let candidate = lower
                .replacingOccurrences(of: "ee", with: "ê")
                .replacingOccurrences(of: "oo", with: "ô")
            if candidate != lower &&
               (VietnameseSyllableDictionary.shared.isValidSyllable(candidate) ||
                VietnameseSyllableDictionary.shared.isValidUntonedSyllable(candidate)) {
                return false
            }
        }
        // Reject macOS AppleSpell's lowercase Roman-numeral false positives ({i,v,x,l,c,d,m} strings like "mixi", "mixxi", "lixi")
        // that are not real English words in EmbeddedEnglishSpellChecker, while preserving uppercase Roman numerals ("XIV", "MMXXVI").
        if word != word.uppercased(),
           lower.allSatisfy({ "ivxlcdm".contains($0) }) {
            return false
        }
        // Reject macOS AppleSpell's 4-letter Telex tone-escape false positives ("affa", "affe", "effa", "effe", "ossa", "offa", "eeff", "ooff")
        // that are not in EmbeddedEnglishSpellChecker (real words like "iffy" already returned true above).
        if word != word.uppercased() && lower.count == 4 {
            let chars = Array(lower)
            let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
            let pureVowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let tones: Set<Character> = ["s", "f", "r", "x", "j"]
            if vowels.contains(chars[0]) && tones.contains(chars[1]) && chars[2] == chars[1] &&
               (chars[3] == chars[0] || pureVowels.contains(chars[3])) {
                return false
            }
            if vowels.contains(chars[0]) && (chars[1] == chars[0] || chars[1] == "w") && tones.contains(chars[2]) && chars[3] == chars[2] {
                return false
            }
            if vowels.contains(chars[0]) && tones.contains(chars[1]) && (chars[2] == chars[0] || chars[2] == "w") && chars[3] == chars[1] {
                return false
            }
        }

        return autoreleasepool {
            let checker = NSSpellChecker.shared
            checker.automaticallyIdentifiesLanguages = false

            var wordCount = 0
            let range = checker.checkSpelling(
                of: word,
                startingAt: 0,
                language: "en",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            if range.location == NSNotFound && wordCount > 0 {
                return true
            }

            let rangeUS = checker.checkSpelling(
                of: word,
                startingAt: 0,
                language: "en_US",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            if rangeUS.location == NSNotFound && wordCount > 0 {
                return true
            }

            // Also check capitalized form for proper nouns (e.g. "facebook" -> "Facebook", "microsoft" -> "Microsoft")
            let capitalized = word.prefix(1).uppercased() + word.dropFirst()
            if capitalized != word && word.count >= 6 {
                let capRange = checker.checkSpelling(
                    of: capitalized,
                    startingAt: 0,
                    language: "en",
                    wrap: false,
                    inSpellDocumentWithTag: 0,
                    wordCount: &wordCount
                )
                if capRange.location == NSNotFound && wordCount > 0 {
                    return true
                }
                let capRangeUS = checker.checkSpelling(
                    of: capitalized,
                    startingAt: 0,
                    language: "en_US",
                    wrap: false,
                    inSpellDocumentWithTag: 0,
                    wordCount: &wordCount
                )
                if capRangeUS.location == NSNotFound && wordCount > 0 {
                    return true
                }
            }

            return false
        }
    }
}
#else
import Foundation

public struct MacSpellChecker: SpellCheckerProvider {
    public init() {}

    public func isWordInEnglishDictionary(_ word: String) -> Bool {
        EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(word)
    }
}
#endif
