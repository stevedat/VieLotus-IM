#if os(macOS)
import Cocoa

public struct MacSpellChecker: SpellCheckerProvider {
    public init() {}
    
    public func isWordInEnglishDictionary(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        
        var wordCount = 0
        let range = NSSpellChecker.shared.checkSpelling(
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
        
        // Also check capitalized form for proper nouns (e.g. "facebook" -> "Facebook", "microsoft" -> "Microsoft")
        let capitalized = word.prefix(1).uppercased() + word.dropFirst()
        if capitalized != word {
            let capRange = NSSpellChecker.shared.checkSpelling(
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
        }
        
        // Also check uppercase for acronyms (e.g. "url" -> "URL", "api" -> "API")
        let uppercased = word.uppercased()
        if uppercased != word && uppercased != capitalized {
            let upperRange = NSSpellChecker.shared.checkSpelling(
                of: uppercased,
                startingAt: 0,
                language: "en",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            if upperRange.location == NSNotFound {
                return true
            }
        }
        
        return false
    }
}
#endif
