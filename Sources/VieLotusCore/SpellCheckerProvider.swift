import Foundation

public protocol SpellCheckerProvider {
    /// Checks if a given string is a valid English dictionary word
    func isWordInEnglishDictionary(_ word: String) -> Bool
}
