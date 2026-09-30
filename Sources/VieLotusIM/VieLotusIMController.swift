import VieLotusCore
import Cocoa
import InputMethodKit
import NaturalLanguage

@objc(VieLotusIMController)
final class VieLotusIMController: IMKInputController {
    private let engine = EngineBridge()
    private var composingWord = ""
    private var rawWord = ""
    private var recentContext = ""
    private static let caretDisarmed: Int = -999
    private var editCaretBack: Int = VieLotusIMController.caretDisarmed
    private var lastClientIdentifier: String?
    private var virtualCursorLocation: Int = NSNotFound
    private var backtickDepth: Int = 0  // 0=normal, odd=inside backticks

    private func isCursorMovementKey(_ keyCode: UInt16) -> Bool {
        keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 ||
        keyCode == 115 || keyCode == 119 || keyCode == 116 || keyCode == 121
    }

    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        keyCode == 122 || keyCode == 120 || keyCode == 99 || keyCode == 118 ||
        keyCode == 96  || keyCode == 97  || keyCode == 98 || keyCode == 100 ||
        keyCode == 101 || keyCode == 109 || keyCode == 103 || keyCode == 111 ||
        keyCode == 105 || keyCode == 107 || keyCode == 113 || keyCode == 106 ||
        keyCode == 64  || keyCode == 79  || keyCode == 80  || keyCode == 90
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        applyPreferences()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidUpdate),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NSLog("VieLotusIMController: Initialized session")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func preferencesDidUpdate() {
        applyPreferences()
    }

    private func applyPreferences() {
        let prefs = Preferences.shared
        engine.setInputMethod(prefs.inputMethod)
        engine.setModernOrthography(prefs.modernOrthography)
        engine.setRelaxedCoda(prefs.relaxedCoda)
        engine.setQuickTelex(prefs.quickTelex)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

        // If Vietnamese is toggled off, pass through all events
        guard Preferences.shared.vietnameseEnabled else { return false }

        let bundleID = client.bundleIdentifier()
        let clientUID = "\(bundleID ?? ""):\(ObjectIdentifier(sender as AnyObject).debugDescription)"
        if let lastUID = lastClientIdentifier, lastUID != clientUID {
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            backtickDepth = 0
        }
        lastClientIdentifier = clientUID

        let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
        var presentationMode = ClientAdapter.presentationMode(for: appCategory, bundleIdentifier: bundleID, terminalDirectEnabled: Preferences.shared.terminalDirectMode)

        let selection = client.selectedRange()
        if selection.location == NSNotFound && presentationMode == .directReplacement {
            // Dynamic fallback: if a direct replacement app returns NSNotFound,
            // we cannot do backward deletion. We must switch to marked text mode.
            DiagnosticLogger.shared.log("FALLBACK_TO_MARKED_TEXT | app: \(bundleID ?? "?") | selection: NSNotFound")
            if let id = bundleID {
                ClientAdapter.forceMarkedText(for: id)
            }
            presentationMode = .markedText
        }

        let keyCode = event.keyCode
        let rawModifiers = event.modifierFlags
        let chordModifiers = rawModifiers.intersection([.command, .control, .option, .shift])
        let nonShiftModifiers = rawModifiers.intersection([.command, .control, .option])

        // Handle Escape: cancel composition
        if keyCode == 53 { // ESC
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                cancelComposition()
                rawWord = ""
                if presentationMode == .markedText {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                }
                if presentationMode == .terminalDirect {
                    return false
                }
                return true
            }
            return false
        }

        // Handle Backspace with modifiers (Cmd+Backspace, Option+Backspace, Ctrl+Backspace)
        if keyCode == 51 && !nonShiftModifiers.isEmpty {
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            if presentationMode == .markedText {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            return false // Let macOS / shell perform line or word deletion natively
        }

        // Handle Forward Delete (keyCode 117)
        if keyCode == 117 {
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                if presentationMode == .terminalDirect {
                    cancelComposition()
                } else {
                    commitComposition(client)
                }
            }
            return false
        }

        // Non-shift modifier shortcuts (Cmd, Ctrl, Option)
        if !nonShiftModifiers.isEmpty {
            if presentationMode == .terminalDirect {
                // In terminal direct mode, control keys (Ctrl+C, Ctrl+D, Ctrl+Z, Ctrl+L,
                // Ctrl+U, Ctrl+W, Ctrl+K, Ctrl+A, Ctrl+E, etc.) and shortcuts (Cmd+C, Option+...)
                // are signals, process controls, or navigation shortcuts.
                // Cancel composition immediately without emitting characters or polluting the history ring.
                cancelComposition()
                return false
            } else {
                if engine.isComposing {
                    commitComposition(client)
                }
                editCaretBack = Self.caretDisarmed
                return false
            }
        }

        // Handle Shift + Cursor Movement (Selection shortcuts)
        if chordModifiers.contains(.shift) && isCursorMovementKey(keyCode) {
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                if presentationMode == .terminalDirect {
                    cancelComposition()
                } else {
                    commitComposition(client)
                }
            }
            return false
        }

        // Handle Backspace: keyCode 51 (plain Backspace)
        if keyCode == 51 {
            if selection.location != NSNotFound && selection.length > 0 {
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
                if presentationMode == .markedText {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                }
                return false // Let macOS delete the highlighted text natively
            }

            if engine.isComposing {
                editCaretBack = Self.caretDisarmed
                if let diff = engine.backspace() {
                    if !rawWord.isEmpty {
                        rawWord.removeLast()
                    }
                    if presentationMode == .markedText {
                        let output = engine.currentOutput()
                        if output.isEmpty {
                            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                            engine.reset()
                            composingWord = ""
                            rawWord = ""
                            return true
                        } else {
                            client.setMarkedText(output, selectionRange: NSRange(location: output.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                            composingWord = output
                        }
                        return true
                    } else if presentationMode == .terminalDirect {
                        if diff.backspaces > 0 || !diff.suffix.isEmpty {
                            let maxBackspaces = composingWord.count
                            let safeBackspaces = min(diff.backspaces, maxBackspaces)
                            let backspaces = String(repeating: "\u{7F}", count: safeBackspaces)
                            client.insertText(backspaces + diff.suffix, replacementRange: NSRange(location: NSNotFound, length: 0))
                            composingWord = engine.currentOutput()

                            if composingWord.isEmpty || !engine.isComposing {
                                engine.reset()
                                composingWord = ""
                                rawWord = ""
                                editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
                            }
                            return true
                        }
                    } else {
                        // Direct replacement mode
                        if diff.backspaces > 0 || !diff.suffix.isEmpty {
                            let maxBackspaces = composingWord.utf16.count
                            let safeBackspaces = min(diff.backspaces, maxBackspaces)

                            let currentLoc = virtualCursorLocation != NSNotFound ? virtualCursorLocation : selection.location
                            let range = (currentLoc != NSNotFound && currentLoc >= safeBackspaces)
                                ? NSRange(location: currentLoc - safeBackspaces, length: safeBackspaces)
                                : NSRange(location: NSNotFound, length: 0)

                            client.insertText(diff.suffix, replacementRange: range)
                            if virtualCursorLocation != NSNotFound {
                                virtualCursorLocation = currentLoc - safeBackspaces + diff.suffix.utf16.count
                            }
                            composingWord = engine.currentOutput()

                            if composingWord.isEmpty {
                                engine.reset()
                                rawWord = ""
                                editCaretBack = Self.caretDisarmed
                            }

                            return true
                        }
                    }
                }
                engine.reset()
                composingWord = ""
                rawWord = ""
            } else {
                // Backspace while idle: deleting the space after committed word arms editing
                if editCaretBack == -1 {
                    editCaretBack = 0
                } else {
                    engine.reset()
                    editCaretBack = Self.caretDisarmed
                }
                // Likely deleted a backtick — decrement depth to stay in sync
                if backtickDepth > 0 {
                    backtickDepth -= 1
                }
            }
            return false
        }

        // Handle Return / Enter (keyCode 36, 76)
        if keyCode == 36 || keyCode == 76 {
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            backtickDepth = 0
            return false
        }

        // Handle Tab (keyCode 48)
        if keyCode == 48 {
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            return false
        }

        // Handle Plain Arrow & Navigation keys (no modifiers)
        if keyCode == 123 { // Plain Left arrow
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            if editCaretBack >= -1 {
                editCaretBack += 1
            }
            return false
        }
        if keyCode == 124 { // Plain Right arrow
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            if editCaretBack >= 0 {
                editCaretBack -= 1
            } else {
                editCaretBack = Self.caretDisarmed
            }
            return false
        }
        if keyCode == 125 || keyCode == 126 { // Down / Up arrow
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                if presentationMode == .terminalDirect {
                    cancelComposition()
                } else {
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
                }
            }
            return false
        }
        if keyCode == 115 || keyCode == 119 || keyCode == 116 || keyCode == 121 { // Home, End, PgUp, PgDn
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                if presentationMode == .terminalDirect {
                    cancelComposition()
                } else {
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
                }
            }
            return false
        }

        // Handle Function keys (F1-F20), Unicode Private Use Area (0xF700...0xF8FF),
        // and ASCII control characters (< 0x20)
        let firstCharCandidate = event.characters?.first
        let isPUAOrFunctionKey: Bool = {
            if isFunctionKey(keyCode) { return true }
            if let firstCharCandidate, let scalar = firstCharCandidate.unicodeScalars.first {
                if (0xF700...0xF8FF).contains(scalar.value) { return true }
                if let ascii = firstCharCandidate.asciiValue, ascii < 0x20 { return true }
            }
            return false
        }()

        if isPUAOrFunctionKey {
            editCaretBack = Self.caretDisarmed
            if engine.isComposing {
                if presentationMode == .terminalDirect {
                    cancelComposition()
                } else {
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
                }
            }
            return false
        }

        // Printable characters
        guard let characters = event.characters, let firstChar = characters.first else {
            return false
        }

        // Developer Context-Aware Mode (Markdown inline code & blocks)
        if Preferences.shared.developerMode {
            if firstChar == "`" {
                if engine.isComposing {
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
                }
                backtickDepth += 1
                return false
            }
            // Any non-backtick character after backtick(s) — check if we're inside
            if backtickDepth % 2 != 0 {
                return false // Bypass Vietnamese composition inside backticks
            }
            // Even backtickDepth means we closed a backtick pair — reset depth
            if backtickDepth > 0 {
                backtickDepth = 0
            }
        }

        // Space key: commit current word and pass through
        if firstChar == " " {
            DiagnosticLogger.shared.log("SPACE | app: \(bundleID ?? "?") | wasComposing: \(engine.isComposing) | output: '\(engine.currentOutput())'")
            var restored = false
            if engine.isComposing {
                restored = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection, suffixChar: " ")
            }
            editCaretBack = -1
            if restored && presentationMode == .directReplacement {
                return true
            }
            return false
        }

        // Punctuation and symbols: commit current word and pass through
        if firstChar.isPunctuation || firstChar.isSymbol {
            DiagnosticLogger.shared.log("PUNCT '\(firstChar)' | app: \(bundleID ?? "?") | wasComposing: \(engine.isComposing)")
            editCaretBack = Self.caretDisarmed
            var restored = false
            if engine.isComposing {
                restored = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection, suffixChar: firstChar)
            }
            if restored && presentationMode == .directReplacement {
                return true
            }
            return false
        }

        DiagnosticLogger.shared.log("CHAR '\(firstChar)' (\(keyCode)) | app: \(bundleID ?? "?") | mode: \(presentationMode) | sel: \(selection.location),\(selection.length)")

        // Typing over an active selection replaces the selection
        if selection.location != NSNotFound && selection.length > 0 {
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
        }

        let wasComposing = engine.isComposing

        // Post-commit editing (LabanKey-style)
        // ONLY armed if caret was stepped back to committed text (editCaretBack >= 0)
        var isEditing = false
        var feedResult: (backspaces: Int, suffix: String)? = nil

        if !engine.isComposing && editCaretBack >= 0 {
            if let diff = engine.editAt(caretBack: editCaretBack, char: firstChar) {
                isEditing = true
                feedResult = diff
                editCaretBack = Self.caretDisarmed
            } else {
                engine.reset()
                editCaretBack = Self.caretDisarmed
                feedResult = engine.feed(firstChar)
            }
        } else {
            editCaretBack = Self.caretDisarmed
            feedResult = engine.feed(firstChar)
        }

        // Feed to Vietnamese engine
        if let diff = feedResult {
            if !wasComposing {
                rawWord = String(firstChar)
                if virtualCursorLocation == NSNotFound && selection.location != NSNotFound {
                    virtualCursorLocation = selection.location
                }
            } else {
                rawWord.append(firstChar)
            }
            if presentationMode == .markedText {
                // Marked text mode: when explicitly forced
                let output = engine.currentOutput()
                DiagnosticLogger.shared.log("-> MARKED_TEXT '\(output)' (consumed)")
                client.setMarkedText(output,
                                     selectionRange: NSRange(location: output.utf16.count, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                composingWord = output
                return true
            } else if presentationMode == .terminalDirect {
                // Terminal Direct Mode: Deliver characters immediately to shell pty for
                // real-time auto-suggestions (e.g. zsh-autosuggestions, fish).
                // Use \u{7F} (ASCII DEL) to erase characters when diacritics are modified.
                if diff.backspaces > 0 || diff.suffix != String(firstChar) {
                    let maxBackspaces = isEditing ? Int.max : composingWord.count
                    let safeBackspaces = isEditing ? diff.backspaces : min(diff.backspaces, maxBackspaces)
                    let deleteChars = String(repeating: "\u{7F}", count: safeBackspaces)
                    DiagnosticLogger.shared.log("-> TERMINAL_REPLACE del:\(safeBackspaces) suffix:'\(diff.suffix)' (consumed)")
                    client.insertText(deleteChars + diff.suffix, replacementRange: NSRange(location: NSNotFound, length: 0))
                    composingWord = engine.currentOutput()
                    return true
                } else {
                    composingWord = engine.currentOutput()
                    DiagnosticLogger.shared.log("-> TERMINAL_PASSTHROUGH '\(firstChar)'")
                    return false
                }
            } else {
                // Direct Replacement Mode: For Chrome, Safari, Word, Electron, etc.
                if diff.backspaces > 0 || diff.suffix != String(firstChar) {
                    let hasSelection = selection.location != NSNotFound && selection.length > 0
                    let maxBackspaces = isEditing ? Int.max : composingWord.utf16.count
                    let safeBackspaces = isEditing ? diff.backspaces : min(diff.backspaces, maxBackspaces)

                    let range: NSRange
                    if selection.location != NSNotFound {
                        if hasSelection {
                            // Chromium Omnibox autocomplete case
                            let startLoc = max(0, selection.location - safeBackspaces)
                            let totalLen = (selection.location - startLoc) + selection.length
                            range = NSRange(location: startLoc, length: totalLen)
                        } else {
                            // Normal case
                            if selection.location >= safeBackspaces {
                                range = NSRange(location: selection.location - safeBackspaces, length: safeBackspaces)
                            } else {
                                range = NSRange(location: 0, length: selection.location)
                            }
                        }
                    } else {
                        // Should not reach here due to dynamic fallback above, but just in case
                        range = NSRange(location: NSNotFound, length: 0)
                    }

                    DiagnosticLogger.shared.log("-> DIRECT_REPLACE del:\(safeBackspaces) suffix:'\(diff.suffix)' range:\(range.location),\(range.length) (consumed)")
                    client.insertText(diff.suffix, replacementRange: range)
                    composingWord = engine.currentOutput()
                    return true
                } else {
                    composingWord = engine.currentOutput()
                    DiagnosticLogger.shared.log("-> DIRECT_PASSTHROUGH '\(firstChar)'")
                    return false
                }
            }
        } else {
            if wasComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            return false
        }
    }

    private func commitWordWithBilingualCheck(client: IMKTextInput, presentationMode: PresentationMode, selection: NSRange, suffixChar: Character? = nil) -> Bool {
        guard engine.isComposing else { return false }

        let output = engine.currentOutput()

        if Preferences.shared.smartBilingual && !rawWord.isEmpty && shouldRestoreEnglish(raw: rawWord, rendered: output, context: recentContext) {
            // Restore English rawWord
            let appendStr = suffixChar != nil ? String(suffixChar!) : ""
            if presentationMode == .directReplacement {
                let wordLen = output.utf16.count
                let currentLoc = virtualCursorLocation != NSNotFound ? virtualCursorLocation : (selection.location != NSNotFound ? selection.location : client.selectedRange().location)
                let range: NSRange
                if currentLoc != NSNotFound && currentLoc >= wordLen {
                    range = NSRange(location: currentLoc - wordLen, length: wordLen)
                } else {
                    range = NSRange(location: NSNotFound, length: 0)
                }
                client.insertText(rawWord + appendStr, replacementRange: range)
                virtualCursorLocation = NSNotFound
            } else if presentationMode == .terminalDirect {
                let deleteChars = String(repeating: "\u{7F}", count: output.count)
                client.insertText(deleteChars + rawWord + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
            } else {
                client.insertText(rawWord + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            appendContext(rawWord)
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            return true
        } else {
            // Commit Vietnamese word
            if presentationMode == .markedText {
                client.insertText(output, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            _ = engine.commit()
            appendContext(output)
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            return false
        }
    }

    private func appendContext(_ word: String) {
        recentContext.append(word + " ")
        if recentContext.count > 200 {
            recentContext = String(recentContext.suffix(100))
        }
    }

    private func shouldRestoreEnglish(raw: String, rendered: String, context: String) -> Bool {
        guard raw.count >= 2 else { return false }
        guard raw.lowercased() != rendered.lowercased() else { return false }

        // Core Vietnamese words must NEVER be overridden to English false-friends (e.g. "gì" vs "gif", "đó" vs "ddos", "có" vs "cos")
        let commonVietnameseWords: Set<String> = [
            "gì", "là", "và", "mà", "có", "của", "ở", "cho", "về", "với", "này", "được",
            "từ", "đã", "lại", "sẽ", "khi", "nói", "làm", "như", "người", "hay", "đó",
            "cũng", "ra", "vào", "đi", "đến", "họ", "tôi", "anh", "em", "bạn", "mình",
            "không", "biết", "phải", "rất", "nhiều", "sau", "qua", "thì", "đây", "nào"
        ]
        if commonVietnameseWords.contains(rendered.lowercased()) {
            return false
        }

        // 1. Check if raw is a recognized English word in macOS system dictionary
        var wordCount = 0
        let range = NSSpellChecker.shared.checkSpelling(
            of: raw,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
        let isEnglishWord = (range.location == NSNotFound)
        guard isEnglishWord else { return false }

        // Ignore Telex double keystrokes that might be flagged as English by spellchecker (aa, ee, oo, dd, ww)
        let lowerRaw = raw.lowercased()
        let telexDoubles: Set<String> = ["aa", "ee", "oo", "dd", "ww", "www", "wwww"]
        if telexDoubles.contains(lowerRaw) {
            return false
        }

        // 2. If it's a valid English word, check if the rendered version is a valid Vietnamese word.
        // If it's NOT a valid Vietnamese word (e.g., 'terminal' typed as 'teminảl', 'clarification' as 'claiicatiòn'),
        // we are 100% sure it was meant to be English.
        var viWordCount = 0
        let viRange = NSSpellChecker.shared.checkSpelling(
            of: rendered,
            startingAt: 0,
            language: "vi",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &viWordCount
        )
        let isVietnameseWord = (viRange.location == NSNotFound)
        if !isVietnameseWord {
            return true
        }

        // 3. Structural patterns: if raw has letters/combinations that cannot exist in Vietnamese
        // In Telex: 'f', 'j', 'w' at word start cannot be Vietnamese initials (e.g. format, file, json, web).
        // But trailing 'f', 'j', 'w' can be Telex diacritics (e.g. gif -> gì, hoj -> họ).
        let nonVietnameseInitials: Set<Character> = ["f", "j", "w", "z"]
        if let firstChar = lowerRaw.first, nonVietnameseInitials.contains(firstChar) {
            return true
        }

        // 'z' anywhere in the word cannot exist in Vietnamese
        if lowerRaw.contains("z") {
            return true
        }

        let doubleConsonants = ["bb", "cc", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss", "tt", "vv"]
        if doubleConsonants.contains(where: { lowerRaw.contains($0) }) {
            return true
        }

        let englishEndings = ["sh", "ck", "ds", "st", "nd", "ld", "rt", "ct", "pt", "lt", "nt"]
        if englishEndings.contains(where: { lowerRaw.hasSuffix($0) }) {
            return true
        }

        // 3. Contextual evaluation
        // Hardcode extremely common English stopwords that conflict with 1-character Vietnamese words (ì, á, ò, v.v.)
        let englishStopwords: Set<String> = ["if", "of", "is", "as", "or", "it", "in", "on", "am", "at", "to", "do", "go"]
        if englishStopwords.contains(lowerRaw) {
            return true
        }

        // Prevent restoring obscure words that are generated by manual tone cancellation
        if lowerRaw == "iff" || lowerRaw == "orr" {
            return false
        }

        // If there is no context (typing on a blank line) and we reached here,
        // it means the word is valid in BOTH English and Vietnamese (e.g. 'toots' vs 'tốt').
        // As a Vietnamese keyboard, we must default to Vietnamese for ambiguous isolated words.
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContext.isEmpty {
            return false
        }

        // Apple Silicon Neural Engine: NaturalLanguage.framework context evaluation
        let recognizer = NLLanguageRecognizer()
        let fullContext = trimmedContext + " " + raw
        recognizer.processString(fullContext)

        if let dominant = recognizer.dominantLanguage {
            if dominant == .english {
                return true
            }
            if dominant == .vietnamese {
                return false
            }
        }

        // 4. Single-word language probability check
        recognizer.reset()
        recognizer.processString(raw)
        if let dominant = recognizer.dominantLanguage, dominant == .english {
            return true
        }

        return false
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        if engine.isComposing {
            let bundleID = client.bundleIdentifier()
            let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
            let mode = ClientAdapter.presentationMode(for: appCategory, bundleIdentifier: bundleID, terminalDirectEnabled: Preferences.shared.terminalDirectMode)
            let selection = client.selectedRange()
            _ = commitWordWithBilingualCheck(client: client, presentationMode: mode, selection: selection)
        }
        editCaretBack = Self.caretDisarmed
    }

    override func cancelComposition() {
        engine.reset()
        composingWord = ""
        rawWord = ""
        editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        applyPreferences()
        engine.reset()
        composingWord = ""
        rawWord = ""
        editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
        NSLog("VieLotusIMController: Activated")
    }

    override func deactivateServer(_ sender: Any!) {
        engine.reset()
        composingWord = ""
        rawWord = ""
        editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
        super.deactivateServer(sender)
        NSLog("VieLotusIMController: Deactivated")
    }

    // MARK: - IMKMouseHandling

    override func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint, withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!, client sender: Any!) -> Bool {
        editCaretBack = Self.caretDisarmed
        if engine.isComposing {
            if let client = sender as? IMKTextInput {
                let bundleID = client.bundleIdentifier()
                let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
                let mode = ClientAdapter.presentationMode(for: appCategory, bundleIdentifier: bundleID, terminalDirectEnabled: Preferences.shared.terminalDirectMode)
                if mode == .terminalDirect {
                    cancelComposition()
                } else {
                    let selection = client.selectedRange()
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: mode, selection: selection)
                }
            } else {
                cancelComposition()
            }
        }
        return false // Do not consume mouse clicks; allow client to position caret/selection
    }

    // MARK: - Native Menu Bar Context Menu

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Sen Việt")
        let prefs = Preferences.shared

        // Toggle Tiếng Việt
        let toggleItem = NSMenuItem(
            title: prefs.vietnameseEnabled ? "✓ Bật Tiếng Việt" : "Tắt Tiếng Việt",
            action: #selector(toggleVietnamese),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        // Kiểu gõ Header
        let imHeader = NSMenuItem(title: "Kiểu gõ:", action: nil, keyEquivalent: "")
        imHeader.isEnabled = false
        menu.addItem(imHeader)

        // Telex
        let telexItem = NSMenuItem(
            title: prefs.inputMethod == .telex ? "    ✓ Telex" : "    Telex",
            action: #selector(selectTelex),
            keyEquivalent: ""
        )
        telexItem.target = self
        menu.addItem(telexItem)

        // VNI
        let vniItem = NSMenuItem(
            title: prefs.inputMethod == .vni ? "    ✓ VNI" : "    VNI",
            action: #selector(selectVNI),
            keyEquivalent: ""
        )
        vniItem.target = self
        menu.addItem(vniItem)


        menu.addItem(.separator())

        // Tùy chọn chính tả
        let modernItem = NSMenuItem(
            title: prefs.modernOrthography ? "✓ Dấu chuẩn mới (hoà → hoá)" : "Dấu chuẩn mới (hoà → hoá)",
            action: #selector(toggleModernOrthography),
            keyEquivalent: ""
        )
        modernItem.target = self
        menu.addItem(modernItem)

        let codaItem = NSMenuItem(
            title: prefs.relaxedCoda ? "✓ Viết tắt vần cuối (g→ng, h→nh)" : "Viết tắt vần cuối (g→ng, h→nh)",
            action: #selector(toggleRelaxedCoda),
            keyEquivalent: ""
        )
        codaItem.target = self
        menu.addItem(codaItem)

        let smartBilingualItem = NSMenuItem(
            title: prefs.smartBilingual ? "✓ Nhận diện tiếng Anh thông minh" : "Nhận diện tiếng Anh thông minh",
            action: #selector(toggleSmartBilingual),
            keyEquivalent: ""
        )
        smartBilingualItem.target = self
        menu.addItem(smartBilingualItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Cài đặt Sen Việt...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        // Thông tin phiên bản
        let versionItem = NSMenuItem(title: "Sen Việt (VieLotusIM) v1.1.0", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let sourceItem = NSMenuItem(
            title: "Mã nguồn mở trên GitHub...",
            action: #selector(openGitHub),
            keyEquivalent: ""
        )
        sourceItem.target = self
        menu.addItem(sourceItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        SettingsWindowManager.shared.showSettingsWindow()
    }

    @objc private func toggleVietnamese() {
        Preferences.shared.vietnameseEnabled.toggle()
        applyPreferences()
    }

    @objc private func selectTelex() {
        Preferences.shared.inputMethod = .telex
        applyPreferences()
    }

    @objc private func selectVNI() {
        Preferences.shared.inputMethod = .vni
        applyPreferences()
    }



    @objc private func toggleModernOrthography() {
        Preferences.shared.modernOrthography.toggle()
        applyPreferences()
    }

    @objc private func toggleRelaxedCoda() {
        Preferences.shared.relaxedCoda.toggle()
        applyPreferences()
    }

    @objc private func toggleSmartBilingual() {
        Preferences.shared.smartBilingual.toggle()
        applyPreferences()
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/uvie-project/uvie-mac") {
            NSWorkspace.shared.open(url)
        }
    }
}
