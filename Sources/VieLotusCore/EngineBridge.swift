import Foundation

public enum InputMethodType: Int32, Sendable {
    case telex = 0
    case vni = 1
}

/// Native Pure Swift Vietnamese input engine bridge wrapping VietnameseEngine.
public final class EngineBridge {
    private let engine = VietnameseEngine()

    public var isComposing: Bool {
        engine.isComposing
    }

    public init() {
        setInputMethod(.telex)
        setModernOrthography(true)
    }

    public func setInputMethod(_ method: InputMethodType) {
        engine.inputMethod = method
    }

    public func setModernOrthography(_ enabled: Bool) {
        engine.modernOrthography = enabled
    }

    public func setRelaxedCoda(_ enabled: Bool) {
        engine.relaxedCoda = enabled
    }

    public func setQuickTelex(_ enabled: Bool) {
        engine.quickTelex = enabled
    }

    public func setGenZMode(_ enabled: Bool) {
        engine.genZMode = enabled
    }

    public func setQuickStart(_ enabled: Bool) {
        engine.quickStart = enabled
    }

    public func reset() {
        engine.reset()
    }

    public func feed(_ ch: Character) -> (backspaces: Int, suffix: String)? {
        engine.feed(ch)
    }

    public func backspace() -> (backspaces: Int, suffix: String)? {
        engine.backspace()
    }

    public func commit() -> (backspaces: Int, suffix: String)? {
        engine.commit()
    }

    public func editAt(caretBack: Int, char: Character) -> (backspaces: Int, suffix: String)? {
        guard caretBack == 0 else { return nil }
        let oldWord = engine.lastCommittedWord ?? ""
        guard let (_, newWord) = engine.editAt(caretBack: caretBack, char: char) else { return nil }
        
        if !oldWord.isEmpty {
            let oldArr = Array(oldWord)
            let newArr = Array(newWord)
            var commonPrefixLen = 0
            let minLen = min(oldArr.count, newArr.count)
            while commonPrefixLen < minLen && oldArr[commonPrefixLen] == newArr[commonPrefixLen] {
                commonPrefixLen += 1
            }
            let deletedChars = oldArr[commonPrefixLen...]
            let backspaces = deletedChars.reduce(0) { $0 + String($1).utf16.count }
            let suffix = String(newArr[commonPrefixLen...])
            return (backspaces, suffix)
        }
        return (oldWord.utf16.count, newWord)
    }

    public func currentOutput() -> String {
        engine.currentOutput()
    }

    public func rawString() -> String {
        engine.rawString()
    }

    public func setCompositionPrefix(_ text: String) {
        engine.setCompositionPrefix(text)
    }
}
