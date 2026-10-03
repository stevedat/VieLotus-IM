import Foundation

/// Action to be taken by the Client (UI or Test Harness) after processing a key.
public enum SessionAction {
    case passThrough             // Key wasn't handled, let system handle it
    case consumed                // Key was consumed internally
    case replace(backspaces: Int, text: String)  // Delete trailing chars and insert text
    case commit(backspaces: Int, text: String, isOverride: Bool)  // Commit a final word (override means it fell back to raw)
    case reset                   // Composition cancelled/reset
}

public class InputSessionManager {
    public let engine = EngineBridge()
    public var composingWord: String = ""
    public var rawWord: String = ""
    public var context: String = ""
    public var editCaretBack: Int = -1

    public var isComposing: Bool {
        return engine.isComposing
    }

    public init() {}

    public func reset() {
        engine.reset()
        composingWord = ""
        rawWord = ""
        editCaretBack = -1
    }

    public func stepCaretBack() {
        if editCaretBack < 255 {
            editCaretBack += 1
        }
    }

    public func stepCaretForward() {
        editCaretBack = max(-1, editCaretBack - 1)
    }

    public func resetCaret() {
        editCaretBack = -1
    }

    public func currentOutput() -> String {
        if !composingWord.isEmpty { return composingWord }
        return engine.currentOutput()
    }

    public func setInputMethod(_ method: InputMethodType) {
        engine.setInputMethod(method)
    }

    public func setModernOrthography(_ enabled: Bool) {
        engine.setModernOrthography(enabled)
    }

    public func setRelaxedCoda(_ enabled: Bool) {
        engine.setRelaxedCoda(enabled)
    }

    public func setQuickTelex(_ enabled: Bool) {
        engine.setQuickTelex(enabled)
    }

    public func setQuickStart(_ enabled: Bool) {
        engine.setQuickStart(enabled)
    }

    public var recentWords: [String] = []
    private static let maxRecentWords = 32

    public func appendContext(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentWords.append(trimmed)
        if recentWords.count > Self.maxRecentWords {
            recentWords.removeFirst(recentWords.count - Self.maxRecentWords)
        }
        context = recentWords.joined(separator: " ")
    }

    /// Evaluates if a character acts as a word boundary
    public func isWordBoundary(_ char: Character) -> Bool {
        return char == " " || char.isNewline || ",;:!?\"'()[]{}<>-".contains(char)
    }

    /// Processes a single character feed
    public func handleCharacter(_ char: Character) -> SessionAction {
        let wasComposing = engine.isComposing
        var isEditing = false
        var feedResult: (backspaces: Int, suffix: String)? = nil

        if !wasComposing && editCaretBack >= 0 {
            if let diff = engine.editAt(caretBack: editCaretBack, char: char) {
                isEditing = true
                feedResult = diff
                editCaretBack = -1
            } else {
                engine.reset()
                editCaretBack = -1
                feedResult = engine.feed(char)
            }
        } else {
            editCaretBack = -1
            feedResult = engine.feed(char)
        }

        if let diff = feedResult {
            if isEditing {
                if rawWord.isEmpty {
                    rawWord = (composingWord.isEmpty ? engine.currentOutput() : composingWord) + String(char)
                } else {
                    rawWord.append(char)
                }
            } else if !wasComposing {
                rawWord = String(char)
            } else {
                rawWord.append(char)
            }
            
            // Visual logic with UTF-16 code unit precision
            var utf16Backspaces = 0
            if diff.backspaces > 0 {
                let safeBackspaces = min(diff.backspaces, composingWord.count)
                let removedChars = String(composingWord.suffix(safeBackspaces))
                utf16Backspaces = removedChars.utf16.count
                composingWord.removeLast(safeBackspaces)
            }
            composingWord += diff.suffix
            
            if composingWord.isEmpty {
                engine.reset()
                rawWord = ""
                editCaretBack = -1
            }

            return .replace(backspaces: utf16Backspaces, text: diff.suffix)
        } else {
            rawWord.append(char)
            return .passThrough
        }
    }

    /// Handle backspace key
    public func handleBackspace() -> SessionAction {
        if isComposing {
            editCaretBack = -1
            if let diff = engine.backspace() {
                if !rawWord.isEmpty {
                    rawWord.removeLast()
                }
                
                let safeBackspaces = min(diff.backspaces, composingWord.count)
                let removedChars = String(composingWord.suffix(safeBackspaces))
                let utf16Backspaces = removedChars.utf16.count
                composingWord.removeLast(safeBackspaces)
                composingWord += diff.suffix
                
                if composingWord.isEmpty {
                    engine.reset()
                    rawWord = ""
                    return .reset
                }
                
                return .replace(backspaces: utf16Backspaces, text: diff.suffix)
            }
            engine.reset()
            composingWord = ""
            rawWord = ""
            return .reset
        } else {
            // Idle backspace: deleting the space after committed word arms editing
            if editCaretBack < 0 {
                editCaretBack += 1
            } else {
                // Deleting into the committed word itself: reset engine history
                engine.reset()
                editCaretBack = -1
            }
            return .passThrough
        }
    }

    /// Commit the current composition, applying Smart Bilingual if needed
    public func commitWord(smartBilingualEnabled: Bool) -> SessionAction {
        guard isComposing else { return .passThrough }
        
        let output = currentOutput()
        let finalWord: String
        var isOverride = false
        
        if smartBilingualEnabled && !rawWord.isEmpty && rawWord.count >= 2 && rawWord.lowercased() != output.lowercased() && SmartBilingualDetector.isEnglishWord(raw: rawWord, context: context, rendered: output) {
            finalWord = rawWord
            isOverride = true
        } else {
            finalWord = output.isEmpty ? (composingWord.isEmpty ? rawWord : composingWord) : output
        }
        
        let oldComposingCount = (composingWord.isEmpty ? output : composingWord).utf16.count
        appendContext(finalWord)
        
        reset()
        return .commit(backspaces: oldComposingCount, text: finalWord, isOverride: isOverride)
    }
}
