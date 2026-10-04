import VieLotusCore
import Cocoa
import InputMethodKit
import NaturalLanguage
import VieLotusTrace
import Carbon.HIToolbox

@objc(VieLotusIMController)
final class VieLotusIMController: IMKInputController {
    private static let labBundlePrefix = "org.vielotus.inputmethod.vielotuslab."
    private static let labTraceStart = Notification.Name("org.vielotus.inputmethod.vielotuslab.trace.start")
    private static let labTraceStop = Notification.Name("org.vielotus.inputmethod.vielotuslab.trace.stop")
    private let engine = EngineBridge()
    private var composingWord = ""
    private var rawWord = ""
    private var recentContext = ""
    private static let caretDisarmed: Int = -999
    private var editCaretBack: Int = VieLotusIMController.caretDisarmed
    private var lastClientIdentifier: String?
    private var virtualCursorLocation: Int = NSNotFound
    private var backtickDepth: Int = 0  // 0=normal, odd=inside backticks
    private var labTraceID: String?
    private var labTraceTargetBundleID: String?

    private func isSecureFieldActive() -> Bool {
        // Check system-wide secure event input (Keychain, sudo in terminal, login window, 1Password,
        // and Cocoa NSSecureTextField / WebKit password inputs which activate SecureEventInput).
        // Uses Carbon HIToolbox with zero Accessibility / AX permissions required.
        IsSecureEventInputEnabled()
    }

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
        LabTraceSpool.cleanupStaleTraces()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidUpdate),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(beginLabTrace(_:)), name: Self.labTraceStart, object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(endLabTrace(_:)), name: Self.labTraceStop, object: nil
        )

        NSLog("VieLotusIMController: Initialized session")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func beginLabTrace(_ notification: Notification) {
        labTraceID = notification.userInfo?["traceID"] as? String
        labTraceTargetBundleID = (notification.userInfo?["targetBundleID"] as? String).flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }

    @objc private func endLabTrace(_ notification: Notification) {
        guard let requestedID = notification.userInfo?["traceID"] as? String, requestedID == labTraceID else { return }
        labTraceID = nil
        labTraceTargetBundleID = nil
    }

    private func traceLab(_ event: String, bundleID: String?, key: String = "", detail: String = "",
                          selection: NSRange? = nil) {
        guard let clientID = bundleID?.lowercased() else { return }
        let activeSession = LabTraceSpool.activeSession()
        let traceID = activeSession?.traceID ?? labTraceID
        let targetID = activeSession?.targetBundleID ?? labTraceTargetBundleID
        guard let traceID,
              clientID.hasPrefix(Self.labBundlePrefix) ||
              (targetID != nil && clientID == targetID) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let selectionDetail = selection.map { " selection=\($0.location),\($0.length)" } ?? ""
        let record = LabTraceEvent(traceID: traceID, event: event, key: key, raw: rawWord,
                                   composing: engine.currentOutput(),
                                   detail: "client=\(bundleID ?? "unknown")\(selectionDetail) \(detail)",
                                   time: formatter.string(from: Date()),
                                   monotonic: DispatchTime.now().uptimeNanoseconds)
        do {
            try LabTraceSpool.append(record)
        } catch {
            NSLog("VieLotus Lab trace spool write failed: %@", String(describing: error))
        }
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

        // 0. Secure Input / Password Field Protection:
        // When typing in any password field (NSSecureTextField, web password input)
        // or a system-wide secure session (Terminal sudo, Keychain, 1Password),
        // passthrough immediately with zero buffering, zero logging, and zero transformation.
        if isSecureFieldActive() {
            if engine.isComposing {
                cancelComposition()
                rawWord = ""
            }
            return false
        }

        let bundleID = client.bundleIdentifier()
        traceLab("keyDown", bundleID: bundleID, key: event.charactersIgnoringModifiers ?? "",
                 detail: "keyCode=\(event.keyCode)", selection: client.selectedRange())
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
        if presentationMode == .terminalDirect,
           engine.isComposing,
           virtualCursorLocation != NSNotFound,
           selection.location != NSNotFound,
           selection.location != virtualCursorLocation {
            traceLab("terminalCaretMismatch", bundleID: bundleID,
                     detail: "expected=\(virtualCursorLocation) actual=\(selection.location) output=\(composingWord)",
                     selection: selection)
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
        }

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
            virtualCursorLocation = NSNotFound
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
            let isUserSelection = selection.location != NSNotFound && selection.length > 0 &&
                !(presentationMode == .markedText && engine.isComposing)
            if isUserSelection {
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
                    let rawBefore = rawWord
                    if !rawWord.isEmpty {
                        rawWord.removeLast()
                    }
                    traceLab("backspace", bundleID: bundleID, key: "Backspace",
                             detail: "rawBefore=\(rawBefore) rawAfter=\(rawWord) diff=\(diff.backspaces),\(diff.suffix)",
                             selection: client.selectedRange())
                    let clientID = bundleID?.lowercased() ?? ""
                    let isEdgeOrCodex = clientID.contains("edgemac") || clientID.contains("codex")
                    if isEdgeOrCodex,
                       presentationMode == .directReplacement,
                       diff.backspaces == 1, diff.suffix.isEmpty,
                       rawBefore.last == composingWord.last,
                       engine.currentOutput() == String(composingWord.dropLast()) {
                        composingWord = engine.currentOutput()
                        if virtualCursorLocation != NSNotFound {
                            virtualCursorLocation = max(0, virtualCursorLocation - 1)
                        }
                        if composingWord.isEmpty {
                            engine.reset()
                            rawWord = ""
                        }
                        traceLab("backspaceNative", bundleID: bundleID,
                                 detail: "literal suffix; composition retained", selection: selection)
                        return false
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
                    }
                    if diff.backspaces == 0 && diff.suffix.isEmpty {
                        composingWord = engine.currentOutput()
                        return true
                    } else if presentationMode == .terminalDirect {
                        if diff.backspaces > 0 || !diff.suffix.isEmpty {
                            let maxBackspaces = composingWord.count
                            let safeBackspaces = min(diff.backspaces, maxBackspaces)
                            let backspaces = String(repeating: "\u{7F}", count: safeBackspaces)
                            client.insertText(backspaces + diff.suffix, replacementRange: NSRange(location: NSNotFound, length: 0))
                            traceLab("insertText", bundleID: bundleID,
                                     detail: "backspace del=\(safeBackspaces) suffix=\(diff.suffix)",
                                     selection: client.selectedRange())
                            if virtualCursorLocation != NSNotFound {
                                virtualCursorLocation = max(0, virtualCursorLocation - safeBackspaces) + diff.suffix.utf16.count
                            }
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
                        let output = engine.currentOutput()
                        let previousOutputLength = (composingWord as NSString).length
                        let currentLoc = virtualCursorLocation != NSNotFound ? virtualCursorLocation : selection.location

                        if ["com.apple.notes", "com.apple.systempreferences"].contains(bundleID?.lowercased() ?? "") {
                            if output.isEmpty {
                                engine.reset()
                                composingWord = ""
                                rawWord = ""
                                editCaretBack = Self.caretDisarmed
                                virtualCursorLocation = NSNotFound
                                traceLab("backspaceNative", bundleID: bundleID,
                                         detail: "finish-composition output=empty", selection: selection)
                                return false
                            }
                            if output != composingWord,
                               selection.location != NSNotFound,
                               selection.location >= previousOutputLength {
                                let range = NSRange(location: selection.location - previousOutputLength,
                                                    length: previousOutputLength)
                                client.insertText(output, replacementRange: range)
                                traceLab("insertText", bundleID: bundleID,
                                         detail: "backspace whole-word range=\(range.location),\(range.length) replacement=\(output)",
                                         selection: client.selectedRange())
                                virtualCursorLocation = range.location + (output as NSString).length
                            } else if output != composingWord {
                                engine.reset()
                                composingWord = ""
                                rawWord = ""
                                virtualCursorLocation = NSNotFound
                                traceLab("backspaceNativeFallback", bundleID: bundleID,
                                         detail: "whole-word range unavailable", selection: selection)
                                return false
                            }
                            composingWord = output
                            return true
                        }

                        if output.isEmpty, previousOutputLength > 0 {
                            let range = currentLoc != NSNotFound && currentLoc >= previousOutputLength
                                ? NSRange(location: currentLoc - previousOutputLength, length: previousOutputLength)
                                : NSRange(location: NSNotFound, length: 0)
                            if range.location != NSNotFound {
                                client.insertText("", replacementRange: range)
                                traceLab("insertText", bundleID: bundleID,
                                         detail: "backspace finish-composition range=\(range.location),\(range.length)",
                                         selection: client.selectedRange())
                                virtualCursorLocation = range.location
                            } else {
                                traceLab("backspaceNativeFallback", bundleID: bundleID,
                                         detail: "finish-composition range unavailable currentLoc=\(currentLoc) length=\(previousOutputLength)",
                                         selection: client.selectedRange())
                            }
                            engine.reset()
                            composingWord = ""
                            rawWord = ""
                            editCaretBack = Self.caretDisarmed
                            if range.location == NSNotFound { virtualCursorLocation = NSNotFound }
                            return range.location != NSNotFound
                        }

                        if diff.backspaces > 0 || !diff.suffix.isEmpty {
                            let maxBackspaces = (composingWord as NSString).length
                            let safeBackspaces = min(diff.backspaces, maxBackspaces)
                            let range = currentLoc != NSNotFound && currentLoc >= safeBackspaces
                                ? NSRange(location: currentLoc - safeBackspaces, length: safeBackspaces)
                                : NSRange(location: NSNotFound, length: 0)
                            let replacement = diff.suffix
                            if range.location != NSNotFound, !replacement.isEmpty {
                                client.insertText(replacement, replacementRange: range)
                                traceLab("insertText", bundleID: bundleID,
                                         detail: "backspace replaceRange=\(range.location),\(range.length) replacement=\(replacement)",
                                         selection: client.selectedRange())
                                virtualCursorLocation = range.location + replacement.utf16.count
                            } else if range.location != NSNotFound, range.length > 0 {
                                client.insertText("", replacementRange: range)
                                traceLab("insertText", bundleID: bundleID,
                                         detail: "backspace empty-replacement range=\(range.location),\(range.length)",
                                         selection: client.selectedRange())
                                virtualCursorLocation = range.location
                            }
                            composingWord = output
                            if composingWord.isEmpty {
                                engine.reset()
                                rawWord = ""
                                editCaretBack = Self.caretDisarmed
                            }
                            return true
                        }
                    }
                }
                if presentationMode == .markedText {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
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
        if isCursorMovementKey(keyCode) { virtualCursorLocation = NSNotFound }
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
            traceLab("space", bundleID: bundleID, key: "Space", detail: "restored=\(restored)",
                     selection: client.selectedRange())
            editCaretBack = -1
            if restored {
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
            if restored {
                return true
            }
            return false
        }

        DiagnosticLogger.shared.log("CHAR '\(firstChar)' (\(keyCode)) | app: \(bundleID ?? "?") | mode: \(presentationMode) | sel: \(selection.location),\(selection.length)")

        // Typing over an active selection replaces the selection
        let isUserSelection = selection.location != NSNotFound && selection.length > 0 &&
            !(presentationMode == .markedText && engine.isComposing)
        if isUserSelection {
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
            traceLab("feed", bundleID: bundleID, key: String(firstChar),
                     detail: "diff=\(diff.backspaces),\(diff.suffix) raw=\(rawWord)",
                     selection: client.selectedRange())
            if presentationMode == .markedText {
                // Marked text mode: when explicitly forced
                let output = engine.currentOutput()
                DiagnosticLogger.shared.log("-> MARKED_TEXT '\(output)' (consumed)")
                client.setMarkedText(output,
                                     selectionRange: NSRange(location: output.utf16.count, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                traceLab("setMarkedText", bundleID: bundleID, detail: "output=\(output)",
                         selection: client.selectedRange())
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
                    traceLab("terminalReplace", bundleID: bundleID,
                             detail: "delete=\(safeBackspaces) suffix=\(diff.suffix)",
                             selection: client.selectedRange())
                    if virtualCursorLocation != NSNotFound {
                        virtualCursorLocation = max(0, virtualCursorLocation - safeBackspaces) + diff.suffix.utf16.count
                    }
                    composingWord = engine.currentOutput()
                    return true
                } else {
                    composingWord = engine.currentOutput()
                    DiagnosticLogger.shared.log("-> TERMINAL_PASSTHROUGH '\(firstChar)'")
                    if virtualCursorLocation != NSNotFound {
                        virtualCursorLocation += String(firstChar).utf16.count
                    }
                    return false
                }
            } else {
                // Direct Replacement Mode: For Chrome, Safari, Word, Electron, etc.
                if diff.backspaces > 0 || diff.suffix != String(firstChar) {
                    let hasSelection = selection.location != NSNotFound && selection.length > 0
                    let maxBackspaces = isEditing ? Int.max : composingWord.utf16.count
                    let safeBackspaces = isEditing ? diff.backspaces : min(diff.backspaces, maxBackspaces)

                    let currentLoc = virtualCursorLocation != NSNotFound ? virtualCursorLocation : selection.location
                    let range: NSRange
                    
                    if currentLoc != NSNotFound {
                        if hasSelection && virtualCursorLocation == NSNotFound {
                            // Only use selection length if we just started tracking
                            let startLoc = max(0, currentLoc - safeBackspaces)
                            let totalLen = (currentLoc - startLoc) + selection.length
                            range = NSRange(location: startLoc, length: totalLen)
                        } else {
                            // Normal case
                            if currentLoc >= safeBackspaces {
                                range = NSRange(location: currentLoc - safeBackspaces, length: safeBackspaces)
                            } else {
                                range = NSRange(location: 0, length: currentLoc)
                            }
                        }
                    } else {
                        range = NSRange(location: NSNotFound, length: 0)
                    }

                    DiagnosticLogger.shared.log("-> DIRECT_REPLACE del:\(safeBackspaces) suffix:'\(diff.suffix)' range:\(range.location),\(range.length) (consumed)")
                    client.insertText(diff.suffix, replacementRange: range)
                    traceLab("directReplace", bundleID: bundleID,
                             detail: "range=\(range.location),\(range.length) suffix=\(diff.suffix)",
                             selection: client.selectedRange())
                    composingWord = engine.currentOutput()
                    
                    if currentLoc != NSNotFound {
                        virtualCursorLocation = currentLoc - safeBackspaces + diff.suffix.utf16.count
                    }
                    return true
                } else {
                    composingWord = engine.currentOutput()
                    DiagnosticLogger.shared.log("-> DIRECT_PASSTHROUGH '\(firstChar)'")
                    
                    let currentLoc = virtualCursorLocation != NSNotFound ? virtualCursorLocation : selection.location
                    if currentLoc != NSNotFound {
                        virtualCursorLocation = currentLoc + String(firstChar).utf16.count
                    }
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

        if Preferences.shared.smartBilingual && !rawWord.isEmpty && rawWord.count >= 2 && rawWord.lowercased() != output.lowercased() && SmartBilingualDetector.isEnglishWord(raw: rawWord, context: recentContext, rendered: output) {
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
                traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                         detail: "word=\(rawWord) suffix=\(appendStr) range=\(range.location),\(range.length)",
                         selection: client.selectedRange())
                if range.location != NSNotFound {
                    virtualCursorLocation = range.location + (rawWord + appendStr).utf16.count
                } else if virtualCursorLocation != NSNotFound {
                    virtualCursorLocation += (rawWord + appendStr).utf16.count
                }
            } else if presentationMode == .terminalDirect {
                let deleteChars = String(repeating: "\u{7F}", count: output.count)
                client.insertText(deleteChars + rawWord + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                         detail: "word=\(rawWord) suffix=\(appendStr) terminal=true",
                         selection: client.selectedRange())
            } else {
                client.insertText(rawWord + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                         detail: "word=\(rawWord) suffix=\(appendStr) marked=true",
                         selection: client.selectedRange())
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
            traceLab("commitVietnamese", bundleID: client.bundleIdentifier(),
                     detail: "raw=\(rawWord) output=\(output) suffix=\(suffixChar.map(String.init) ?? "")",
                     selection: client.selectedRange())
            if presentationMode == .markedText {
                client.insertText(output, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            _ = engine.commit()
            appendContext(output)
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            return false
        }
    }

    private func appendContext(_ word: String) {
        recentContext.append(word + " ")
        if recentContext.count > 200 {
            recentContext = String(recentContext.suffix(100))
        }
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
        lastClientIdentifier = nil
        NSLog("VieLotusIMController: Activated")
    }

    override func deactivateServer(_ sender: Any!) {
        engine.reset()
        composingWord = ""
        rawWord = ""
        editCaretBack = Self.caretDisarmed
        virtualCursorLocation = NSNotFound
        lastClientIdentifier = nil
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
