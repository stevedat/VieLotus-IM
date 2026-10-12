#if os(macOS)
import Cocoa

public struct MacSpellChecker: SpellCheckerProvider {
    public init() {
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
        _ = NSSpellChecker.shared.setLanguage("en")
    }
    
    public func isWordInEnglishDictionary(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        
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
        if range.location == NSNotFound {
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
        if rangeUS.location == NSNotFound {
            return true
        }
        
        // Also check capitalized form for proper nouns (e.g. "facebook" -> "Facebook", "microsoft" -> "Microsoft")
        let capitalized = word.prefix(1).uppercased() + word.dropFirst()
        if capitalized != word {
            let capRange = checker.checkSpelling(
                of: capitalized,
                startingAt: 0,
                language: "en",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            if capRange.location == NSNotFound {
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
            if capRangeUS.location == NSNotFound {
                return true
            }
        }
        
        return false
    }
}
#endif
