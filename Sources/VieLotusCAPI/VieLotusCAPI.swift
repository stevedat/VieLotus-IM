import Foundation
import VieLotusCore

/// Wrapper class managing an `InputSessionManager` instance and C-string memory lifetimes.
public final class VieLotusSessionWrapper {
    public let manager: InputSessionManager

    // C-compatible memory caches owned by this session instance
    private var composingCString: [CChar] = [0]
    private var rawCString: [CChar] = [0]
    private var lastTextCString: [CChar] = [0]
    private var suggestionsCString: [CChar] = [0]
    private var autocorrectCString: [CChar] = [0]

    // Cached outputs from the last step
    public var lastAction: Int32 = 0
    public var lastBackspaces: Int32 = 0
    public var lastIsOverride: Bool = false
    public var grammarProfile: GrammarProfile = .senFlex
    public var modernOrthography: Bool = true

    public init() {
        self.manager = InputSessionManager()
    }

    public func updateComposingCString() -> UnsafePointer<CChar> {
        composingCString = Array(manager.currentOutput().utf8CString)
        return composingCString.withUnsafeBufferPointer { $0.baseAddress! }
    }

    public func updateRawCString() -> UnsafePointer<CChar> {
        rawCString = Array(manager.rawWord.utf8CString)
        return rawCString.withUnsafeBufferPointer { $0.baseAddress! }
    }

    public func updateLastTextCString(_ text: String) -> UnsafePointer<CChar> {
        lastTextCString = Array(text.utf8CString)
        return lastTextCString.withUnsafeBufferPointer { $0.baseAddress! }
    }

    public func getLastTextCString() -> UnsafePointer<CChar> {
        return lastTextCString.withUnsafeBufferPointer { $0.baseAddress! }
    }

    public func updateSuggestionsCString(_ text: String) -> UnsafePointer<CChar> {
        suggestionsCString = Array(text.utf8CString)
        return suggestionsCString.withUnsafeBufferPointer { $0.baseAddress! }
    }

    public func updateAutocorrectCString(_ text: String) -> UnsafePointer<CChar> {
        autocorrectCString = Array(text.utf8CString)
        return autocorrectCString.withUnsafeBufferPointer { $0.baseAddress! }
    }

    public func recordAction(_ action: SessionAction) -> Int32 {
        switch action {
        case .passThrough:
            lastAction = 0
            lastBackspaces = 0
            lastIsOverride = false
            _ = updateLastTextCString("")
            return 0
        case .consumed:
            lastAction = 1
            lastBackspaces = 0
            lastIsOverride = false
            _ = updateLastTextCString("")
            return 1
        case .replace(let backspaces, let text):
            lastAction = 2
            lastBackspaces = Int32(backspaces)
            lastIsOverride = false
            _ = updateLastTextCString(text)
            return 2
        case .commit(let backspaces, let text, let isOverride):
            lastAction = 3
            lastBackspaces = Int32(backspaces)
            lastIsOverride = isOverride
            _ = updateLastTextCString(text)
            return 3
        case .reset:
            lastAction = 4
            lastBackspaces = 0
            lastIsOverride = false
            _ = updateLastTextCString("")
            return 4
        }
    }
}

// Static version string
private let engineVersionCString: [CChar] = Array(AppInfo.appVersion.utf8CString)

// ============================================================================
// Lifecycle Exports
// ============================================================================

#if os(Android) && !VIELOTUS_OPEN_CORE_MACOS && canImport(VieLotusMobileCore)
private let capiAndroidSpellProviderInit: Void = {
    SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()
    SmartBilingualDetector.warmUpModelsAsync()
}()
#endif

@_cdecl("vielotus_create_session")
public func vielotus_create_session() -> UnsafeMutableRawPointer {
    #if os(Android) && !VIELOTUS_OPEN_CORE_MACOS && canImport(VieLotusMobileCore)
    _ = capiAndroidSpellProviderInit
    #endif
    let wrapper = VieLotusSessionWrapper()
    return Unmanaged.passRetained(wrapper).toOpaque()
}

@_cdecl("vielotus_destroy_session")
public func vielotus_destroy_session(_ sessionPtr: UnsafeMutableRawPointer?) {
    guard let ptr = sessionPtr else { return }
    Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).release()
}

@_cdecl("vielotus_reset_session")
public func vielotus_reset_session(_ sessionPtr: UnsafeMutableRawPointer?) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.manager.reset()
    _ = session.recordAction(.reset)
}

// ============================================================================
// Configuration Exports
// ============================================================================

@_cdecl("vielotus_set_macro_enabled")
public func vielotus_set_macro_enabled(_ sessionPtr: UnsafeMutableRawPointer?, _ enabled: Bool) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.manager.macroEnabled = enabled
}

@_cdecl("vielotus_load_macros_json")
public func vielotus_load_macros_json(_ jsonPtr: UnsafePointer<CChar>?) -> CBool {
    guard let jsonPtr = jsonPtr else { return false }
    let jsonString = String(cString: jsonPtr)
    guard let data = jsonString.data(using: .utf8) else { return false }
    let prevAutoSave = MacroEngine.shared.autoSaveToDisk
    MacroEngine.shared.autoSaveToDisk = false
    defer { MacroEngine.shared.autoSaveToDisk = prevAutoSave }
    do {
        try MacroEngine.shared.importJSON(data: data, replaceAll: true)
        return true
    } catch {
        return false
    }
}

@_cdecl("vielotus_reset_default_macros")
public func vielotus_reset_default_macros() {
    let prevAutoSave = MacroEngine.shared.autoSaveToDisk
    MacroEngine.shared.autoSaveToDisk = false
    defer { MacroEngine.shared.autoSaveToDisk = prevAutoSave }
    MacroEngine.shared.resetToDefaults()
}

@_cdecl("vielotus_set_input_method")
public func vielotus_set_input_method(_ sessionPtr: UnsafeMutableRawPointer?, _ method: Int32) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.manager.setInputMethod(method == 1 ? .vni : .telex)
}

@_cdecl("vielotus_set_grammar_profile")
public func vielotus_set_grammar_profile(_ sessionPtr: UnsafeMutableRawPointer?, _ profile: Int32) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    let targetProfile: GrammarProfile = (profile == 1) ? .senFlex : .classic
    session.grammarProfile = targetProfile
    session.manager.setGrammarProfile(targetProfile)
}

@_cdecl("vielotus_get_grammar_profile")
public func vielotus_get_grammar_profile(_ sessionPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let ptr = sessionPtr else { return 0 }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.grammarProfile == .senFlex ? 1 : 0
}

@_cdecl("vielotus_set_smart_bilingual")
public func vielotus_set_smart_bilingual(_ sessionPtr: UnsafeMutableRawPointer?, _ enabled: CBool) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.manager.smartBilingualEnabled = enabled
}

@_cdecl("vielotus_set_modern_orthography")
public func vielotus_set_modern_orthography(_ sessionPtr: UnsafeMutableRawPointer?, _ enabled: CBool) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.modernOrthography = enabled
    session.manager.setModernOrthography(enabled)
}

@_cdecl("vielotus_set_quick_telex")
public func vielotus_set_quick_telex(_ sessionPtr: UnsafeMutableRawPointer?, _ enabled: CBool) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.manager.setQuickTelex(enabled)
}

@_cdecl("vielotus_set_relaxed_coda")
public func vielotus_set_relaxed_coda(_ sessionPtr: UnsafeMutableRawPointer?, _ enabled: CBool) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    session.manager.setRelaxedCoda(enabled)
}

// ============================================================================
// Keystroke Processing Exports
// ============================================================================

@_cdecl("vielotus_feed_char")
public func vielotus_feed_char(
    _ sessionPtr: UnsafeMutableRawPointer?,
    _ codepoint: UInt32
) -> Int32 {
    guard let ptr = sessionPtr, let scalar = UnicodeScalar(codepoint) else {
        return 0
    }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    let char = Character(scalar)

    if session.manager.isWordBoundary(char) {
        if session.manager.isComposing {
            let action = session.manager.commitWord(
                smartBilingualEnabled: session.manager.smartBilingualEnabled,
                genZMode: session.manager.genZMode,
                boundaryChar: char
            )
            return session.recordAction(action)
        } else {
            session.manager.editCaretBack = -1
            return session.recordAction(.passThrough)
        }
    }

    let action = session.manager.handleCharacter(char)
    return session.recordAction(action)
}

@_cdecl("vielotus_commit_word")
public func vielotus_commit_word(_ sessionPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let ptr = sessionPtr else { return 0 }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    let action = session.manager.commitWord(
        smartBilingualEnabled: session.manager.smartBilingualEnabled,
        genZMode: session.manager.genZMode
    )
    return session.recordAction(action)
}

@_cdecl("vielotus_feed_backspace")
public func vielotus_feed_backspace(_ sessionPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let ptr = sessionPtr else { return 0 }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    let action = session.manager.handleBackspace()
    return session.recordAction(action)
}

@_cdecl("vielotus_feed_key")
public func vielotus_feed_key(
    _ sessionPtr: UnsafeMutableRawPointer?,
    _ keyCode: UInt32,
    _ charCode: CChar,
    _ modifiers: UInt32
) -> Int32 {
    guard sessionPtr != nil else { return 0 }
    // Check for backspace key code (Mac: 51, Win/Linux: 8)
    if keyCode == 51 || keyCode == 8 {
        return vielotus_feed_backspace(sessionPtr)
    }
    // If charCode is printable ASCII
    if charCode >= 32 && charCode < 127 {
        return vielotus_feed_char(sessionPtr, UInt32(charCode))
    }
    return 0
}

@_cdecl("vielotus_feed_char_ex")
public func vielotus_feed_char_ex(
    _ sessionPtr: UnsafeMutableRawPointer?,
    _ codepoint: UInt32,
    _ outBackspaces: UnsafeMutablePointer<Int32>?,
    _ outText: UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> Int32 {
    let actionCode = vielotus_feed_char(sessionPtr, codepoint)
    guard let ptr = sessionPtr else { return actionCode }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    
    if let outB = outBackspaces {
        outB.pointee = session.lastBackspaces
    }
    if let outT = outText {
        outT.pointee = session.getLastTextCString()
    }
    return actionCode
}

@_cdecl("vielotus_get_last_action")
public func vielotus_get_last_action(_ sessionPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let ptr = sessionPtr else { return 0 }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.lastAction
}

@_cdecl("vielotus_get_last_backspaces")
public func vielotus_get_last_backspaces(_ sessionPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let ptr = sessionPtr else { return 0 }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.lastBackspaces
}

@_cdecl("vielotus_get_last_text")
public func vielotus_get_last_text(_ sessionPtr: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    guard let ptr = sessionPtr else { return nil }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.getLastTextCString()
}

@_cdecl("vielotus_get_last_is_override")
public func vielotus_get_last_is_override(_ sessionPtr: UnsafeMutableRawPointer?) -> CBool {
    guard let ptr = sessionPtr else { return false }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.lastIsOverride
}

// ============================================================================
// Buffer & State Inspection Exports
// ============================================================================

@_cdecl("vielotus_is_composing")
public func vielotus_is_composing(_ sessionPtr: UnsafeMutableRawPointer?) -> CBool {
    guard let ptr = sessionPtr else { return false }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.manager.isComposing
}

@_cdecl("vielotus_get_composing_text")
public func vielotus_get_composing_text(_ sessionPtr: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    guard let ptr = sessionPtr else { return nil }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.updateComposingCString()
}

@_cdecl("vielotus_get_raw_text")
public func vielotus_get_raw_text(_ sessionPtr: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    guard let ptr = sessionPtr else { return nil }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    return session.updateRawCString()
}

@_cdecl("vielotus_append_context")
public func vielotus_append_context(_ sessionPtr: UnsafeMutableRawPointer?, _ wordPtr: UnsafePointer<CChar>?) {
    guard let ptr = sessionPtr, let wordPtr = wordPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    let word = String(cString: wordPtr)
    session.manager.appendContext(word)
}

@_cdecl("vielotus_sync_armed_word")
public func vielotus_sync_armed_word(_ sessionPtr: UnsafeMutableRawPointer?, _ beforeContextPtr: UnsafePointer<CChar>?) {
    guard let ptr = sessionPtr else { return }
    let session = Unmanaged<VieLotusSessionWrapper>.fromOpaque(ptr).takeUnretainedValue()
    guard !session.manager.isComposing else { return }
    let before = beforeContextPtr.map { String(cString: $0) } ?? ""
    guard !before.isEmpty else {
        session.manager.engine.clearHistory()
        session.manager.clearContext()
        session.manager.editCaretBack = -1
        return
    }
    let contextSlice: Substring
    if before.last?.isLetter == true {
        let trailingCount = before.reversed().prefix(while: { $0.isLetter }).count
        contextSlice = before.dropLast(trailingCount)
    } else {
        contextSlice = before[...]
    }
    let words = contextSlice
        .components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        .filter { !$0.isEmpty && $0.contains(where: { $0.isLetter }) }
    session.manager.context = words.suffix(3).joined(separator: " ")

    guard let lastChar = before.last, lastChar.isLetter else {
        session.manager.editCaretBack = -1
        return
    }
    let trailingLetters = before.reversed().prefix(while: { $0.isLetter })
    let trailingWord = String(trailingLetters.reversed())
    guard !trailingWord.isEmpty, trailingWord.count <= 15 else {
        session.manager.editCaretBack = -1
        return
    }
    if !(session.manager.engine.lastCommittedWord?.unicodeScalars.elementsEqual(trailingWord.unicodeScalars) ?? false) {
        let raw = EngineBridge.rawKeys(for: trailingWord, inputMethod: session.manager.inputMethod)
        session.manager.engine.commitWord(raw: raw, rendered: trailingWord)
    }
    session.manager.editCaretBack = 0
}

// ============================================================================
// Context-Aware Word Suggestion Engine Exports
// ============================================================================


// ============================================================================
// Version & Metadata Exports
// ============================================================================

@_cdecl("vielotus_get_version")
public func vielotus_get_version() -> UnsafePointer<CChar> {
    return engineVersionCString.withUnsafeBufferPointer { $0.baseAddress! }
}

// ============================================================================
// EDU-TYPE Local Loopback Bridge Exports (127.0.0.1:2811)
// ============================================================================

