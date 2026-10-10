#if canImport(UIKit)
import Foundation
import UIKit

/// iOS / iPadOS SpellCheckerProvider implementation utilizing Apple's UITextChecker.
public struct IOSSpellChecker: SpellCheckerProvider {
    public init() {}
    
    public func isWordInEnglishDictionary(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelledRange = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en"
        )
        if misspelledRange.location == NSNotFound {
            return true
        }
        
        let misspelledUS = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en_US"
        )
        return misspelledUS.location == NSNotFound
    }
}
#endif
