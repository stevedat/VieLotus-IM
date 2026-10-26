import VieLotusCore
import Cocoa
import InputMethodKit
import NaturalLanguage
import VieLotusTrace
import Carbon.HIToolbox

@objc(VieLotusIMController)
final class VieLotusIMController: IMKInputController {
    private static let labBundlePrefix = "org.vielotus.inputmethod.vielotuslab"
    private static let labTraceStart = Notification.Name("org.vielotus.inputmethod.vielotuslab.trace.start")
    private static let labTraceStop = Notification.Name("org.vielotus.inputmethod.vielotuslab.trace.stop")
    private let session = InputSessionManager()
    private static let caretDisarmed: Int = -999
    private var editCaretBack: Int = VieLotusIMController.caretDisarmed

    private var engine: EngineBridge { session.engine }
    private var composingWord: String {
        get { session.composingWord }
        set { session.composingWord = newValue }
    }
    private var rawWord: String {
        get { session.rawWord }
        set { session.rawWord = newValue }
    }
    private var recentContext: String {
        get { session.context }
        set { session.context = newValue }
    }
    private var lastClientIdentifier: String?
    private var virtualCursorLocation: Int = NSNotFound
    private var compositionStartLocation: Int = NSNotFound
    private var lastCommittedWordStartLocation: Int = NSNotFound
    private var lastCommittedWordLength: Int = 0
    private var didEditMarkedTextInComposition: Bool = false
    private var isEditingInTerminalOverlay: Bool = false
    private var lastNativeBackspaceReportedLocation: Int = NSNotFound
    private var accumulatedSelectionDrift: Int = 0
    private var lastBackspaceDidNotMoveSelection: Bool = false
    private var lastDirectReplacementDelta: Int = 0
    private var backtickDepth: Int = 0  // 0=normal, odd=inside backticks
    private var lastBackspaceTime: UInt64 = 0
    private var labTraceID: String?
    private var labTraceTargetBundleID: String?
    private var hasActiveMarkedText: Bool = false
    private var machineTypingDetector = MachineTypingDetector()
    private static var isBrowserOmniboxSession: Bool = false
    private static var lastOmniboxShortcutTime: UInt64 = 0
    private static var omniboxFocusTransitionsSinceShortcut: Int = 0

    private func clearBrowserOmniboxSession() {
        Self.isBrowserOmniboxSession = false
        Self.lastOmniboxShortcutTime = 0
        Self.omniboxFocusTransitionsSinceShortcut = 0
    }

    private func isURLContinuationPunctuation(_ char: Character) -> Bool {
        char == "." || char == "/" || char == ":" || char == "-" ||
        char == "_" || char == "?" || char == "&" || char == "=" ||
        char == "#" || char == "%" || char == "@" || char == "~" || char == "+"
    }

    private func hasActiveOmniboxAutocompleteTail(client: IMKTextInput, bundleID: String?, rawSelection: NSRange) -> Bool {
        guard ClientAdapter.isBrowserApp(bundleIdentifier: bundleID),
              rawSelection.location != NSNotFound,
              rawSelection.length > 0 else {
            return false
        }
        let clampedLen = min(rawSelection.length, 512)
        let tail = client.attributedSubstring(from: NSRange(location: rawSelection.location, length: clampedLen))?.string ?? ""
        return ClientAdapter.isInlineURLAutocompleteTail(tail)
    }

    private func resetSelectionDrift() {
        lastNativeBackspaceReportedLocation = NSNotFound
        accumulatedSelectionDrift = 0
        lastBackspaceDidNotMoveSelection = false
        lastDirectReplacementDelta = 0
    }

    private func effectiveSelection(for rawSelection: NSRange) -> NSRange {
        guard rawSelection.location != NSNotFound else {
            resetSelectionDrift()
            return rawSelection
        }
        if lastNativeBackspaceReportedLocation != NSNotFound {
            if rawSelection.location == lastNativeBackspaceReportedLocation {
                // Client (e.g. xterm.js terminal overlay in Orca) did not decrement selectedRange().location
                // on the previous native Backspace; compensate so DOM replacementRange stays exact.
                lastBackspaceDidNotMoveSelection = true
                accumulatedSelectionDrift = min(rawSelection.location, accumulatedSelectionDrift + 1)
            } else {
                // Client updated selectedRange().location natively.
                lastBackspaceDidNotMoveSelection = false
                accumulatedSelectionDrift = 0
            }
            lastNativeBackspaceReportedLocation = NSNotFound
        }
        if accumulatedSelectionDrift > rawSelection.location {
            accumulatedSelectionDrift = rawSelection.location
        }
        return NSRange(location: max(0, rawSelection.location - accumulatedSelectionDrift), length: rawSelection.length)
    }

    private func isSecureFieldActive() -> Bool {
        SecureInputMonitor.shared.isSecureInputActive
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
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(externalPreferencesDidUpdate), name: Preferences.preferencesChangedNotification, object: nil
        )

        NSLog("VieLotusIMController: Initialized session")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func beginLabTrace(_ notification: Notification) {
        LabTraceSpool.invalidateActiveSessionCache()
        labTraceID = notification.userInfo?["traceID"] as? String
        labTraceTargetBundleID = (notification.userInfo?["targetBundleID"] as? String).flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }

    @objc private func endLabTrace(_ notification: Notification) {
        LabTraceSpool.invalidateActiveSessionCache()
        guard let requestedID = notification.userInfo?["traceID"] as? String, requestedID == labTraceID else { return }
        labTraceID = nil
        labTraceTargetBundleID = nil
    }

    private static let traceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func traceLab(
        _ event: String,
        bundleID: @autoclosure () -> String?,
        key: @autoclosure () -> String = "",
        detail: @autoclosure () -> String = "",
        selection: @autoclosure () -> NSRange? = nil,
        composingOverride: @autoclosure () -> String? = nil
    ) {
        // Fast path: exit in ~5ns from in-memory cache before evaluating any @autoclosure
        // arguments (preventing synchronous client.selectedRange() / client.bundleIdentifier()
        // IPC round-trips and String interpolations during normal typing).
        let activeSession = LabTraceSpool.activeSession()
        guard let traceID = activeSession?.traceID ?? labTraceID else { return }
        let resolvedBundleID = bundleID()
        guard let clientID = resolvedBundleID?.lowercased(),
              !LabTraceSpool.isProtectedBundleID(clientID),
              !SecureInputMonitor.shared.isSecureInputActive else { return }
        let targetID = activeSession?.targetBundleID ?? labTraceTargetBundleID
        guard clientID.hasPrefix(Self.labBundlePrefix) ||
              (targetID != nil && clientID == targetID) else { return }
        let selectionDetail = selection().map { " selection=\($0.location),\($0.length)" } ?? ""
        let record = LabTraceEvent(traceID: traceID, event: event, key: key(), raw: rawWord,
                                   composing: composingOverride() ?? engine.currentOutput(),
                                   detail: "client=\(resolvedBundleID ?? "unknown")\(selectionDetail) \(detail())",
                                   time: Self.traceDateFormatter.string(from: Date()),
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

    @objc private func externalPreferencesDidUpdate() {
        Preferences.shared.reload()
        applyPreferences()
    }

    private func applyPreferences() {
        let prefs = Preferences.shared
        session.setInputMethod(prefs.inputMethod)
        session.setGrammarProfile(prefs.grammarProfile)
        session.setModernOrthography(prefs.modernOrthography)
        session.setRelaxedCoda(prefs.relaxedCoda)
        session.setQuickTelex(prefs.quickTelex)
        session.setGenZMode(prefs.genZMode)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    // MARK: - Apple IMKit Standard: Composition Attributes

    /// Returns the preferred visual attributes for marked (composing) text.
    /// IMKInputController calls this when it needs to render the composition region.
    /// We return Apple-standard single underline + markedClauseSegment:0 — matching
    /// Apple's own Japanese, Pinyin, and Korean IMEs exactly.
    override func compositionAttributes(at range: NSRange) -> NSMutableDictionary! {
        let dict = NSMutableDictionary()
        dict[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
        dict[NSAttributedString.Key.markedClauseSegment] = 0
        return dict
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

        let bundleID = ClientAdapter.resolveBundleIdentifier(client.bundleIdentifier())
        if ClientStallBreaker.shared.isDegraded(bundleIdentifier: bundleID) {
            if engine.isComposing {
                cancelComposition()
                rawWord = ""
            }
            return false
        }
        traceLab("keyDown", bundleID: bundleID, key: event.charactersIgnoringModifiers ?? "",
                 detail: "keyCode=\(event.keyCode)", selection: client.selectedRange())
        let clientUID = "\(bundleID ?? ""):\(ObjectIdentifier(sender as AnyObject).debugDescription)"
        if let lastUID = lastClientIdentifier, lastUID != clientUID {
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            lastCommittedWordLength = 0
            didEditMarkedTextInComposition = false
            resetSelectionDrift()
            backtickDepth = 0
            machineTypingDetector.reset()
            if !ClientAdapter.isBrowserApp(bundleIdentifier: bundleID) {
                clearBrowserOmniboxSession()
            } else if Self.isBrowserOmniboxSession {
                let now = DispatchTime.now().uptimeNanoseconds
                Self.omniboxFocusTransitionsSinceShortcut += 1
                if Self.omniboxFocusTransitionsSinceShortcut > 3 || (now - Self.lastOmniboxShortcutTime) > 10_000_000_000 {
                    clearBrowserOmniboxSession()
                }
            }
        } else if !ClientAdapter.isBrowserApp(bundleIdentifier: bundleID) && Self.isBrowserOmniboxSession {
            clearBrowserOmniboxSession()
        }
        lastClientIdentifier = clientUID

        let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
        let preferences = Preferences.shared
        if session.inputMethod != preferences.inputMethod {
            session.setInputMethod(preferences.inputMethod)
        }
        var presentationMode = ClientAdapter.presentationMode(
            for: appCategory,
            bundleIdentifier: bundleID,
            terminalDirectEnabled: preferences.terminalDirectMode,
            passthroughRemoteApps: preferences.passthroughRemoteApps,
            preference: preferences.presentationModePreference,
            appOverrides: preferences.appModeOverrides
        )
        if hasActiveMarkedText && presentationMode == .directReplacement {
            presentationMode = .markedText
        }

        if presentationMode == .passthrough {
            return false
        }

        let rawSelection = client.selectedRange()
        let selection = effectiveSelection(for: rawSelection)
        var detectedDirectReplacementDesync = false
        let hadMidCompositionValidCursor = engine.isComposing && virtualCursorLocation != NSNotFound
        if !Self.isBrowserOmniboxSession,
           (presentationMode == .terminalDirect || presentationMode == .directReplacement),
           engine.isComposing,
           virtualCursorLocation != NSNotFound,
           selection.location != NSNotFound,
           selection.location != virtualCursorLocation {
            
            let composingLen = (composingWord as NSString).length
            let cursorEval = DirectReplacementGuard.evaluateCursorState(
                selection: selection,
                virtualCursorLocation: virtualCursorLocation,
                compositionStartLocation: compositionStartLocation,
                composingWordUTF16Length: composingLen,
                lastReplacementLength: presentationMode == .directReplacement ? lastDirectReplacementDelta : 0
            )
            
            switch cursorEval {
            case .prefixRetained(let charsDeleted):
                let remainingCount = composingLen - charsDeleted
                let remainingText = (composingWord as NSString).substring(to: remainingCount)
                
                // Rewind the engine to match the remaining prefix on screen
                var rewound = false
                while engine.isComposing && (engine.currentOutput() as NSString).length > remainingCount {
                    _ = engine.backspace()
                    if !rawWord.isEmpty {
                        rawWord.removeLast()
                    }
                }
                
                let currentOut = engine.currentOutput()
                if (currentOut as NSString).length == remainingCount &&
                   currentOut.unicodeScalars.elementsEqual(remainingText.unicodeScalars) {
                    rewound = true
                    composingWord = remainingText
                    rawWord = engine.rawString()
                    virtualCursorLocation = selection.location
                    if compositionStartLocation != NSNotFound {
                        compositionStartLocation = selection.location - remainingCount
                    }
                }
                
                if !rewound {
                    session.setCompositionPrefix(remainingText)
                    virtualCursorLocation = selection.location
                    if compositionStartLocation != NSNotFound {
                        compositionStartLocation = selection.location - remainingCount
                    }
                }
                lastDirectReplacementDelta = 0
                
                traceLab("prefixRetained", bundleID: bundleID,
                         detail: "remaining='\(remainingText)' raw='\(rawWord)' deleted=\(charsDeleted)",
                         selection: selection)
            case .compositionCleared:
                traceLab("prefixCleared", bundleID: bundleID,
                         detail: "deleted=\(composingLen) output=\(composingWord)",
                         selection: selection)
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                lastCommittedWordLength = 0
                lastDirectReplacementDelta = 0
            case .ignoredReplacementFallbackToMarkedText:
                detectedDirectReplacementDesync = true
                traceLab("ignoredReplacementFallback", bundleID: bundleID,
                         detail: "expected=\(virtualCursorLocation) actual=\(selection.location) delta=\(lastDirectReplacementDelta) output=\(composingWord)",
                         selection: selection)
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastDirectReplacementDelta = 0
            case .externalCursorJumpResetSession, .invalidSelectionFallbackToMarkedText, .inSync:
                traceLab("terminalCaretMismatch", bundleID: bundleID,
                         detail: "expected=\(virtualCursorLocation) actual=\(selection.location) output=\(composingWord)",
                         selection: selection)
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastDirectReplacementDelta = 0
            }
        }

        if !Self.isBrowserOmniboxSession &&
            presentationMode == .directReplacement &&
            ClientAdapter.allowsDynamicMarkedTextFallback(
                bundleIdentifier: bundleID,
                preference: preferences.presentationModePreference,
                appOverrides: preferences.appModeOverrides
            ) {
            var shouldFallback = false
            var shouldPinBundleToMarkedText = false
            if selection.location == NSNotFound {
                shouldFallback = true
                // Only pin the entire app bundle to .markedText if the host dropped its cursor
                // mid-composition after previously reporting a valid cursor. If selection is
                // NSNotFound before composition starts (e.g. a web canvas in Safari while native
                // Safari fields support directReplacement), fall back for the current word only.
                shouldPinBundleToMarkedText = hadMidCompositionValidCursor
                if hadMidCompositionValidCursor {
                    engine.reset()
                    composingWord = ""
                    rawWord = ""
                    editCaretBack = Self.caretDisarmed
                    virtualCursorLocation = NSNotFound
                    compositionStartLocation = NSNotFound
                    lastDirectReplacementDelta = 0
                }
                DiagnosticLogger.shared.log("FALLBACK_TO_MARKED_TEXT | app: \(bundleID ?? "?") | selection: NSNotFound | pinApp: \(shouldPinBundleToMarkedText)")
            } else if detectedDirectReplacementDesync {
                shouldFallback = true
                shouldPinBundleToMarkedText = true
                DiagnosticLogger.shared.log("FALLBACK_TO_MARKED_TEXT_RANGE_DESYNC | app: \(bundleID ?? "?") | actual: \(selection.location)")
            }

            if shouldFallback {
                if shouldPinBundleToMarkedText, let id = bundleID {
                    ClientAdapter.forceMarkedText(for: id)
                }
                presentationMode = .markedText
            }
        }

        let keyCode = event.keyCode
        let rawModifiers = event.modifierFlags
        let chordModifiers = rawModifiers.intersection([.command, .control, .option, .shift])
        let nonShiftModifiers = rawModifiers.intersection([.command, .control, .option])

        // Handle Escape: cancel composition
        if keyCode == 53 { // ESC
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            if Self.isBrowserOmniboxSession {
                clearBrowserOmniboxSession()
                cancelComposition()
                rawWord = ""
                return false
            }
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
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            if presentationMode == .markedText && hasActiveMarkedText {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                hasActiveMarkedText = false
            }
            return false // Let macOS / shell perform line or word deletion natively
        }

        // Handle Forward Delete (keyCode 117)
        if keyCode == 117 {
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            if engine.isComposing {
                if presentationMode == .terminalDirect || Self.isBrowserOmniboxSession {
                    cancelComposition()
                } else {
                    commitComposition(client)
                }
            }
            return false
        }

        // Non-shift modifier shortcuts (Cmd, Ctrl, Option)
        if !nonShiftModifiers.isEmpty {
            let isBrowserOmniboxShortcut = ClientAdapter.isBrowserApp(bundleIdentifier: bundleID) &&
                rawModifiers.contains(.command) &&
                !rawModifiers.contains(.control) &&
                !rawModifiers.contains(.option) &&
                (keyCode == 37 || keyCode == 17 || keyCode == 45) // Cmd+L (37), Cmd+T (17), Cmd+N / Cmd+Shift+N (45)
            let isBrowserOmniboxPreservingShortcut = ClientAdapter.isBrowserApp(bundleIdentifier: bundleID) &&
                rawModifiers.contains(.command) &&
                !rawModifiers.contains(.control) &&
                !rawModifiers.contains(.option) &&
                (keyCode == 0 || keyCode == 8) // Cmd+A (0), Cmd+C (8)

            if presentationMode == .terminalDirect {
                // In terminal direct mode, control keys (Ctrl+C, Ctrl+D, Ctrl+Z, Ctrl+L,
                // Ctrl+U, Ctrl+W, Ctrl+K, Ctrl+A, Ctrl+E, etc.) and shortcuts (Cmd+C, Option+...)
                // are signals, process controls, or navigation shortcuts.
                // Cancel composition immediately without emitting characters or polluting the history ring.
                cancelComposition()
                clearBrowserOmniboxSession()
                return false
            } else {
                if engine.isComposing {
                    if Self.isBrowserOmniboxSession && !hasActiveMarkedText {
                        cancelComposition()
                    } else {
                        commitComposition(client)
                    }
                }
                if isBrowserOmniboxShortcut {
                    Self.isBrowserOmniboxSession = true
                    Self.lastOmniboxShortcutTime = DispatchTime.now().uptimeNanoseconds
                    Self.omniboxFocusTransitionsSinceShortcut = 0
                    traceLab("omniboxShortcut", bundleID: bundleID, key: event.charactersIgnoringModifiers ?? "",
                             detail: "keyCode=\(keyCode)", selection: rawSelection)
                } else if !isBrowserOmniboxPreservingShortcut {
                    clearBrowserOmniboxSession()
                }
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                resetSelectionDrift()
                return false
            }
        }

        // Handle Shift + Cursor Movement (Selection shortcuts)
        if chordModifiers.contains(.shift) && isCursorMovementKey(keyCode) {
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            if engine.isComposing {
                if presentationMode == .terminalDirect || (Self.isBrowserOmniboxSession && !hasActiveMarkedText) {
                    cancelComposition()
                } else {
                    commitComposition(client)
                }
            }
            return false
        }

        // Handle Backspace: keyCode 51 (plain Backspace)
        if keyCode == 51 {
            return handleBackspace(client: client, selection: selection, rawSelection: rawSelection, bundleID: bundleID, presentationMode: presentationMode)
        }

        // Handle Return / Enter (keyCode 36, 76)
        if keyCode == 36 || keyCode == 76 {
            if Self.isBrowserOmniboxSession || hasActiveOmniboxAutocompleteTail(client: client, bundleID: bundleID, rawSelection: rawSelection) {
                clearBrowserOmniboxSession()
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                resetSelectionDrift()
                backtickDepth = 0
                hasActiveMarkedText = false
                traceLab("omniboxEnterPassthrough", bundleID: bundleID, key: "Enter",
                         detail: "preserved omnibox URL/autocomplete", selection: rawSelection)
                return false
            }
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            session.clearContext()
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            backtickDepth = 0
            return false
        }

        // Handle Tab (keyCode 48)
        if keyCode == 48 {
            if Self.isBrowserOmniboxSession || hasActiveOmniboxAutocompleteTail(client: client, bundleID: bundleID, rawSelection: rawSelection) {
                clearBrowserOmniboxSession()
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                resetSelectionDrift()
                hasActiveMarkedText = false
                return false
            }
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            return false
        }

        // Handle Plain Arrow & Navigation keys (no modifiers)
        if isCursorMovementKey(keyCode) {
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            if Self.isBrowserOmniboxSession {
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                hasActiveMarkedText = false
                return false
            }
        }
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
                if presentationMode == .terminalDirect || (Self.isBrowserOmniboxSession && !hasActiveMarkedText) {
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
            clearBrowserOmniboxSession()
            let wasComposingBeforeSpace = engine.isComposing
            DiagnosticLogger.shared.log("SPACE | app: \(bundleID ?? "?") | wasComposing: \(wasComposingBeforeSpace) | output: '\(engine.currentOutput())'")
            var restored = false
            if wasComposingBeforeSpace {
                restored = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection, suffixChar: " ")
            }
            traceLab("space", bundleID: bundleID, key: "Space", detail: "restored=\(restored)",
                     selection: client.selectedRange())
            editCaretBack = wasComposingBeforeSpace ? -1 : Self.caretDisarmed
            if restored {
                return true
            }
            return false
        }

        // Punctuation and symbols: commit current word and pass through
        if firstChar.isPunctuation || firstChar.isSymbol {
            DiagnosticLogger.shared.log("PUNCT '\(firstChar)' | app: \(bundleID ?? "?") | wasComposing: \(engine.isComposing)")
            if Self.isBrowserOmniboxSession && isURLContinuationPunctuation(firstChar) {
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                hasActiveMarkedText = false
                traceLab("omniboxURLPunct", bundleID: bundleID, key: String(firstChar),
                         detail: "continue omnibox URL session", selection: rawSelection)
                return false
            }
            clearBrowserOmniboxSession()
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

        // Numbers (0-9): In Telex mode, digits are not tone marks or Vietnamese keys.
        // Commit current composing word so the digit does not corrupt the word into raw English or cause caret jumps.
        let isDigitInTelex = firstChar.isNumber && Preferences.shared.inputMethod != .vni
        if isDigitInTelex {
            DiagnosticLogger.shared.log("DIGIT '\(firstChar)' | app: \(bundleID ?? "?") | wasComposing: \(engine.isComposing)")
            if Self.isBrowserOmniboxSession {
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                hasActiveMarkedText = false
                return false
            }
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

        // Synthetic Machine-Typing Guard (AI Computer-Use Agents, Barcode Scanners, Text Expanders):
        // Bypass composition when 6+ consecutive non-repeat keystrokes arrive at < 12ms on both
        // hardware and monotonic clocks. Exempt VieLotusLab diagnostic trace sessions.
        let isLabSession = labTraceID != nil || (bundleID?.lowercased().hasPrefix(Self.labBundlePrefix) ?? false)
        if !isLabSession && machineTypingDetector.observe(
            eventTimestampSeconds: event.timestamp,
            arrivalNanoseconds: DispatchTime.now().uptimeNanoseconds,
            isRepeat: event.isARepeat
        ) {
            if engine.isComposing {
                let restoredRaw = rawWord
                let priorComposing = composingWord
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                let startLoc = compositionStartLocation
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                lastCommittedWordLength = 0
                if !restoredRaw.isEmpty && priorComposing != restoredRaw {
                    if hasActiveMarkedText {
                        client.insertText(restoredRaw + String(firstChar), replacementRange: NSRange(location: NSNotFound, length: 0))
                        hasActiveMarkedText = false
                        return true
                    } else if startLoc != NSNotFound {
                        let priorLen = (priorComposing as NSString).length
                        client.insertText(restoredRaw + String(firstChar), replacementRange: NSRange(location: startLoc, length: priorLen))
                        return true
                    }
                } else if hasActiveMarkedText {
                    client.insertText(priorComposing, replacementRange: NSRange(location: NSNotFound, length: 0))
                    hasActiveMarkedText = false
                }
            }
            return false
        }

        // Guard #1 & Guard #2: Browser Address Bar (Omnibox) URL & Inline Autocomplete Detection.
        // Only queries `client.attributedSubstring` when `rawSelection.length > 0` in a browser app,
        // ensuring zero IPC overhead during normal typing on web pages (`rawSelection.length == 0`).
        var isOmniboxAutocompleteSelection = false
        var isBrowserInlineTailSelection = false
        if ClientAdapter.isBrowserApp(bundleIdentifier: bundleID),
           rawSelection.location != NSNotFound,
           rawSelection.length > 0 {
            let clampedLen = min(rawSelection.length, 512)
            let selectedText = client.attributedSubstring(from: NSRange(location: rawSelection.location, length: clampedLen))?.string ?? ""
            let expectedCaretEnd = (compositionStartLocation != NSNotFound ? compositionStartLocation : 0) + (composingWord as NSString).length
            if rawSelection.location == 0 && !engine.isComposing && ClientAdapter.isHighlightedURLOrDomain(selectedText) {
                Self.isBrowserOmniboxSession = true
                traceLab("omniboxHighlightedURL", bundleID: bundleID, key: String(firstChar),
                         detail: "selectedURL=\(selectedText)", selection: rawSelection)
            } else if rawSelection.location > 0 &&
                      (Self.isBrowserOmniboxSession || compositionStartLocation == 0 || rawSelection.location == (composingWord as NSString).length || (engine.isComposing && rawSelection.location == expectedCaretEnd)) {
                if ClientAdapter.isInlineURLAutocompleteTail(selectedText) {
                    Self.isBrowserOmniboxSession = true
                    isOmniboxAutocompleteSelection = true
                    isBrowserInlineTailSelection = true
                    traceLab("omniboxInlineTail", bundleID: bundleID, key: String(firstChar),
                             detail: "tail=\(selectedText)", selection: rawSelection)
                } else if engine.isComposing && rawSelection.location == expectedCaretEnd {
                    isBrowserInlineTailSelection = true
                }
            }
        }

        // Typing over an active selection replaces the selection (except when the selection is a browser inline autocomplete tail)
        let isUserSelection = !isOmniboxAutocompleteSelection &&
            !isBrowserInlineTailSelection &&
            selection.location != NSNotFound && selection.length > 0 &&
            !(presentationMode == .markedText && engine.isComposing)
        if isUserSelection {
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            lastCommittedWordLength = 0
            resetSelectionDrift()
        }

        // In Terminal Direct mode (e.g. macOS Terminal.app), plain Backspace while !engine.isComposing
        // is handled directly by the terminal PTY without routing keyCode=51 through IMKInputController.
        // Detect if the user deleted the trailing Space (or part of the committed word) via rawSelection.location.
        if presentationMode == .terminalDirect && !engine.isComposing && editCaretBack == -1 &&
           lastCommittedWordStartLocation != NSNotFound && lastCommittedWordLength > 0 &&
           rawSelection.location != NSNotFound {
            let wordEnd = lastCommittedWordStartLocation + lastCommittedWordLength
            if rawSelection.location == wordEnd {
                editCaretBack = 0
            } else if rawSelection.location > lastCommittedWordStartLocation && rawSelection.location < wordEnd {
                let charsDeletedFromWord = wordEnd - rawSelection.location
                var resurrected = false
                for _ in 0..<charsDeletedFromWord {
                    if engine.editBackspaceAt(caretBack: 0) != nil {
                        resurrected = true
                    } else {
                        resurrected = false
                        break
                    }
                }
                let resurrectedOutput = engine.currentOutput()
                if resurrected && engine.isComposing &&
                   (resurrectedOutput as NSString).length == rawSelection.location - lastCommittedWordStartLocation {
                    composingWord = resurrectedOutput
                    rawWord = engine.rawString()
                    compositionStartLocation = lastCommittedWordStartLocation
                    virtualCursorLocation = rawSelection.location
                    editCaretBack = Self.caretDisarmed
                    traceLab("prefixRetained", bundleID: bundleID,
                             detail: "remaining='\(resurrectedOutput)' raw='\(rawWord)' deleted=\(charsDeletedFromWord)",
                             selection: rawSelection)
                } else {
                    engine.reset()
                    composingWord = ""
                    rawWord = ""
                    editCaretBack = Self.caretDisarmed
                }
            }
        }

        let wasComposing = engine.isComposing
        let priorOnScreenWord: String? = (!wasComposing && editCaretBack == 0)
            ? engine.lastCommittedWord
            : (wasComposing && !composingWord.isEmpty ? composingWord : nil)

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
        if var diff = feedResult {
            if isEditing {
                rawWord = engine.rawString()
                let backspaces = diff.backspaces
                if presentationMode == .markedText &&
                   (lastBackspaceDidNotMoveSelection ||
                    (rawSelection.location != NSNotFound && rawSelection.location < backspaces)) {
                    isEditingInTerminalOverlay = true
                }
                let currentLoc = selection.location != NSNotFound ? selection.location : virtualCursorLocation
                let canTrustLastCommittedStart = lastCommittedWordStartLocation != NSNotFound &&
                    (currentLoc == NSNotFound ||
                     currentLoc < backspaces ||
                     abs((lastCommittedWordStartLocation + backspaces) - currentLoc) <= 2)
                if canTrustLastCommittedStart {
                    compositionStartLocation = lastCommittedWordStartLocation
                    virtualCursorLocation = lastCommittedWordStartLocation + backspaces
                } else if currentLoc != NSNotFound && currentLoc >= backspaces {
                    compositionStartLocation = currentLoc - backspaces
                    virtualCursorLocation = currentLoc
                } else {
                    compositionStartLocation = NSNotFound
                }
            } else if !wasComposing {
                rawWord = engine.rawString()
                didEditMarkedTextInComposition = false
                isEditingInTerminalOverlay = false
                lastCommittedWordStartLocation = NSNotFound
                lastCommittedWordLength = 0
                compositionStartLocation = selection.location != NSNotFound ? selection.location : virtualCursorLocation
                if virtualCursorLocation == NSNotFound && selection.location != NSNotFound {
                    virtualCursorLocation = selection.location
                }
            } else {
                rawWord = engine.rawString()
            }
            traceLab("feed", bundleID: bundleID, key: String(firstChar),
                     detail: "diff=\(diff.backspaces),\(diff.suffix) raw=\(rawWord)",
                     selection: client.selectedRange())
            var output = engine.currentOutput()
            let prefs = Preferences.shared
            var isInlineEnglish = false

            // Guard #3: Browser Omnibox First-Token Passthrough.
            // Keep the first token in the browser address bar as raw ASCII (no Marked Text and no
            // premature Telex mutation like "goo" -> "gô" or "shopee" -> "shopê") so inline URL
            // autocomplete suggestions stay intact. If the user later presses Space to write a
            // multi-word Vietnamese search query (e.g. "thowif tieets" -> "thời tiết"), Space
            // converts the first token to Vietnamese `output` and resumes normal composition.
            if Self.isBrowserOmniboxSession {
                let lowerRawWord = rawWord.lowercased()
                let omniboxWord: String
                if lowerRawWord.hasPrefix("ww") && !lowerRawWord.hasPrefix("www") &&
                   priorOnScreenWord != nil && !priorOnScreenWord!.unicodeScalars.allSatisfy({ $0.isASCII }) {
                    omniboxWord = output
                } else {
                    omniboxWord = rawWord
                }
                if hasActiveMarkedText || (priorOnScreenWord != nil && !priorOnScreenWord!.isEmpty && priorOnScreenWord != String(omniboxWord.dropLast())) {
                    let priorLen = ((priorOnScreenWord ?? "") as NSString).length
                    let startLoc = compositionStartLocation != NSNotFound ? compositionStartLocation : 0
                    let tailLen = isOmniboxAutocompleteSelection ? rawSelection.length : 0
                    let replaceRange = hasActiveMarkedText
                        ? NSRange(location: NSNotFound, length: 0)
                        : NSRange(location: startLoc, length: priorLen + tailLen)
                    client.insertText(omniboxWord, replacementRange: replaceRange)
                    hasActiveMarkedText = false
                    output = omniboxWord
                    composingWord = omniboxWord
                    compositionStartLocation = startLoc
                    virtualCursorLocation = startLoc + (omniboxWord as NSString).length
                    traceLab("omniboxReplaceTransition", bundleID: bundleID, key: String(firstChar),
                             detail: "omniboxWord=\(omniboxWord) raw=\(rawWord)",
                             selection: client.selectedRange(), composingOverride: omniboxWord)
                    return true
                }
                output = omniboxWord
                composingWord = omniboxWord
                hasActiveMarkedText = false
                if compositionStartLocation == NSNotFound {
                    compositionStartLocation = selection.location != NSNotFound ? selection.location : 0
                }
                if compositionStartLocation != NSNotFound {
                    virtualCursorLocation = compositionStartLocation + (omniboxWord as NSString).length
                }
                traceLab("omniboxPassthrough", bundleID: bundleID, key: String(firstChar),
                         detail: "raw=\(rawWord) engineOutput=\(engine.currentOutput())",
                         selection: rawSelection, composingOverride: omniboxWord)
                return false
            }

            if prefs.smartBilingual && rawWord.count >= 2 && rawWord.lowercased() != output.lowercased() &&
               SmartBilingualDetector.isInlineEnglishWord(raw: rawWord, rendered: output) {
                // Inline Latin Passthrough:
                // An English word (or English phonotactic pattern) was recognized inline!
                // Bypass/restore diacritics immediately so the user never sees flickering ("pót" -> "post").
                output = rawWord
                isInlineEnglish = true
                traceLab("inlineEnglish", bundleID: bundleID, detail: "raw=\(rawWord)", selection: client.selectedRange(), composingOverride: rawWord)
            } else if !isEditing, wasComposing, let priorWord = priorOnScreenWord, !priorWord.isEmpty {
                var oldIdx = priorWord.startIndex
                var newIdx = output.startIndex
                while oldIdx < priorWord.endIndex && newIdx < output.endIndex &&
                      priorWord[oldIdx] == output[newIdx] &&
                      priorWord[oldIdx].unicodeScalars.elementsEqual(output[newIdx].unicodeScalars) {
                    oldIdx = priorWord.index(after: oldIdx)
                    newIdx = output.index(after: newIdx)
                }
                diff = (backspaces: priorWord[oldIdx...].utf16.count, suffix: String(output[newIdx...]))
            }

            let isPureAppendToOnScreenWord = priorOnScreenWord != nil &&
                !priorOnScreenWord!.isEmpty &&
                output == priorOnScreenWord! + String(firstChar)

            if presentationMode == .markedText {
                if isEditing || (wasComposing && !hasActiveMarkedText && !composingWord.isEmpty) {
                    let currentLoc = selection.location != NSNotFound ? selection.location : virtualCursorLocation
                    let safeBackspaces = isEditing ? diff.backspaces : (composingWord as NSString).length
                    let range: NSRange
                    if compositionStartLocation != NSNotFound {
                        range = NSRange(location: compositionStartLocation, length: safeBackspaces)
                    } else if currentLoc != NSNotFound && currentLoc >= safeBackspaces {
                        range = NSRange(location: currentLoc - safeBackspaces, length: safeBackspaces)
                    } else {
                        range = NSRange(location: NSNotFound, length: 0)
                    }
                    didEditMarkedTextInComposition = true
                    DiagnosticLogger.shared.log("-> EDITING_MARKED_TEXT '\(output)' range:\(range.location),\(range.length) (consumed)")
                    let editStrategy: String
                    if !hasActiveMarkedText && isPureAppendToOnScreenWord {
                        // The existing word on screen is already identical to the prefix of `output`,
                        // and only `firstChar` is being appended at the caret. Insert just `firstChar`
                        // at the caret instead of replacing the entire word via `replacementRange`
                        // (which duplicates the word in editors like Orca when !hasActiveMarkedText).
                        resetSelectionDrift()
                        client.insertText(String(firstChar), replacementRange: NSRange(location: NSNotFound, length: 0))
                        hasActiveMarkedText = false
                        editStrategy = "appendChar"
                    } else if !hasActiveMarkedText && isEditingInTerminalOverlay, let priorWord = priorOnScreenWord, !priorWord.isEmpty {
                        // Terminal overlay in Marked Text mode (e.g. xterm.js in Orca):
                        // The committed word is already in the Unix PTY buffer, and Backspace sent "\x7f"
                        // directly to the PTY without mutating the hidden .xterm-helper-textarea value.
                        // Replacing a DOM range in the hidden textarea cannot delete characters from the PTY;
                        // send the exact ASCII DEL ("\u{7F}") + suffix delta so _claimImeKeydownCommit updates
                        // the PTY word in place.
                        let commonPrefixCount = zip(priorWord, output).prefix(while: { $0 == $1 }).count
                        let deleteCount = priorWord.count - commonPrefixCount
                        let suffixToInsert = String(output.dropFirst(commonPrefixCount))
                        let payload = String(repeating: "\u{7F}", count: deleteCount) + suffixToInsert
                        resetSelectionDrift()
                        if !payload.isEmpty {
                            client.insertText(payload, replacementRange: NSRange(location: NSNotFound, length: 0))
                        }
                        hasActiveMarkedText = false
                        editStrategy = "terminalDelta"
                    } else if !hasActiveMarkedText && range.location != NSNotFound && range.length > 0 {
                        // In Chromium/Electron (ProseMirror/Tiptap contenteditable and Views AXTextField),
                        // calling setMarkedText with a replacementRange while !HasComposition() dispatches
                        // compositionstart before replacing the range (duplicating the word), and calling
                        // insertText("", replacementRange:) is ignored by Blink because the string is empty.
                        // Calling insertText(output, replacementRange: range) with a non-empty string invokes
                        // ImeCommitText(output, range) synchronously without compositionstart, replacing the
                        // committed word cleanly in place and positioning the caret at the end of the word.
                        resetSelectionDrift()
                        client.insertText(output, replacementRange: range)
                        hasActiveMarkedText = false
                        editStrategy = "directInsert"
                    } else {
                        _ = setCompositionMarkedText(output, client: client, replacementRange: range, resolvedBundleID: bundleID)
                        editStrategy = "replaceMarked"
                    }
                    composingWord = output
                    traceLab("editMarkedText", bundleID: bundleID,
                             detail: "range=\(range.location),\(range.length) strategy=\(editStrategy) output=\(output)",
                             selection: client.selectedRange(), composingOverride: output)
                    if range.location != NSNotFound {
                        virtualCursorLocation = range.location + (output as NSString).length
                        compositionStartLocation = range.location
                    }
                    return true
                } else {
                    // Stealth Composition Mode: delivers zero-underline composition session
                    DiagnosticLogger.shared.log("-> STEALTH_MARKED_TEXT '\(output)' (consumed)")
                    let postMarkedSelection = setCompositionMarkedText(output, client: client, resolvedBundleID: bundleID)
                    composingWord = output
                    traceLab("setMarkedText", bundleID: bundleID, detail: "output=\(output)",
                             selection: postMarkedSelection, composingOverride: output)
                    return true
                }
            } else if presentationMode == .terminalDirect {
                if isInlineEnglish {
                    if isPureAppendToOnScreenWord {
                        composingWord = rawWord
                        traceLab("terminalInlineEnglish", bundleID: bundleID, detail: "raw=\(rawWord) appendChar=true", selection: client.selectedRange(), composingOverride: rawWord)
                        if virtualCursorLocation != NSNotFound {
                            virtualCursorLocation += String(firstChar).utf16.count
                        }
                        return false
                    }
                    let deleteCount = isEditing ? diff.backspaces : composingWord.count
                    let deleteChars = String(repeating: "\u{7F}", count: deleteCount)
                    client.insertText(deleteCount > 0 ? (deleteChars + rawWord) : rawWord, replacementRange: NSRange(location: NSNotFound, length: 0))
                    composingWord = rawWord
                    traceLab("terminalInlineEnglish", bundleID: bundleID, detail: "raw=\(rawWord)", selection: client.selectedRange(), composingOverride: rawWord)
                    if virtualCursorLocation != NSNotFound {
                        virtualCursorLocation = max(0, virtualCursorLocation - deleteCount) + (rawWord as NSString).length
                    }
                    return true
                }
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
                // Direct Replacement Mode: For Apple Notes, Safari, Pages, Xcode, etc.
                if isInlineEnglish {
                    let previousCount = isEditing ? diff.backspaces : (composingWord as NSString).length
                    let startLoc: Int
                    if compositionStartLocation != NSNotFound {
                        startLoc = compositionStartLocation
                    } else {
                        let currentLoc = selection.location != NSNotFound ? selection.location : virtualCursorLocation
                        startLoc = currentLoc != NSNotFound && currentLoc >= previousCount ? currentLoc - previousCount : NSNotFound
                    }
                    let range = startLoc != NSNotFound && previousCount > 0
                        ? NSRange(location: startLoc, length: previousCount + (isBrowserInlineTailSelection ? selection.length : 0))
                        : NSRange(location: NSNotFound, length: 0)
                    if isPureAppendToOnScreenWord {
                        client.insertText(String(firstChar), replacementRange: NSRange(location: NSNotFound, length: 0))
                    } else {
                        client.insertText(rawWord, replacementRange: range)
                    }
                    composingWord = rawWord
                    traceLab("directInlineEnglish", bundleID: bundleID, detail: "raw=\(rawWord) range=\(range.location),\(range.length)", selection: client.selectedRange(), composingOverride: rawWord)
                    if startLoc != NSNotFound {
                        compositionStartLocation = startLoc
                        virtualCursorLocation = startLoc + (rawWord as NSString).length
                    }
                    return true
                }
                if diff.backspaces > 0 || diff.suffix != String(firstChar) {
                    let hasSelection = selection.location != NSNotFound && selection.length > 0
                    let maxBackspaces = isEditing ? Int.max : composingWord.utf16.count
                    let safeBackspaces = isEditing ? diff.backspaces : min(diff.backspaces, maxBackspaces)

                    let currentLoc = selection.location != NSNotFound ? selection.location : virtualCursorLocation
                    let range: NSRange
                    
                    if isEditing && compositionStartLocation != NSNotFound {
                        range = NSRange(location: compositionStartLocation, length: safeBackspaces)
                    } else if currentLoc != NSNotFound {
                        if hasSelection && (virtualCursorLocation == NSNotFound || isBrowserInlineTailSelection) {
                            // Only use selection length if we just started tracking or browser inline autocomplete tail is selected
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
                    let previousComposingUTF16 = composingWord.utf16.count
                    let ownership = DirectReplacementGuard.verifyRangeOwnership(
                        replacementRange: range,
                        composingWord: composingWord,
                        compositionStartLocation: compositionStartLocation,
                        virtualCursorLocation: virtualCursorLocation,
                        isEditingCommittedWord: isEditing,
                        extraAutocompleteLength: isBrowserInlineTailSelection ? selection.length : 0
                    )
                    let validatedRange: NSRange
                    if ownership == .owned || (hasSelection && virtualCursorLocation == NSNotFound) {
                        validatedRange = range
                    } else if currentLoc != NSNotFound && previousComposingUTF16 > 0 && currentLoc >= previousComposingUTF16 {
                        validatedRange = NSRange(location: currentLoc - min(safeBackspaces, previousComposingUTF16), length: min(safeBackspaces, previousComposingUTF16))
                    } else {
                        validatedRange = NSRange(location: NSNotFound, length: 0)
                    }
                    lastDirectReplacementDelta = validatedRange.location != NSNotFound ? validatedRange.length : 0
                    client.insertText(diff.suffix, replacementRange: validatedRange)
                    traceLab("directReplace", bundleID: bundleID,
                             detail: "range=\(validatedRange.location),\(validatedRange.length) suffix=\(diff.suffix)",
                             selection: client.selectedRange())
                    composingWord = engine.currentOutput()
                    
                    if validatedRange.location != NSNotFound {
                        if safeBackspaces >= previousComposingUTF16 {
                            compositionStartLocation = validatedRange.location
                        }
                        virtualCursorLocation = validatedRange.location + diff.suffix.utf16.count
                    } else if currentLoc != NSNotFound {
                        virtualCursorLocation = currentLoc - safeBackspaces + diff.suffix.utf16.count
                    }
                    return true
                } else {
                    lastDirectReplacementDelta = 0
                    composingWord = engine.currentOutput()
                    DiagnosticLogger.shared.log("-> DIRECT_PASSTHROUGH '\(firstChar)'")
                    
                    let currentLoc = selection.location != NSNotFound ? selection.location : virtualCursorLocation
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

    // MARK: - Keybinding & Command Handling (Apple InputMethodKit)

    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        guard let aSelector, let client = sender as? IMKTextInput else { return false }
        let selectorName = NSStringFromSelector(aSelector)
        let bundleID = ClientAdapter.resolveBundleIdentifier(client.bundleIdentifier())
        let rawSelection = client.selectedRange()
        let selection = effectiveSelection(for: rawSelection)

        guard Preferences.shared.vietnameseEnabled else { return false }
        if isSecureFieldActive() {
            if engine.isComposing {
                cancelComposition()
                rawWord = ""
            }
            return false
        }
        if ClientStallBreaker.shared.isDegraded(bundleIdentifier: bundleID) {
            if engine.isComposing {
                cancelComposition()
                rawWord = ""
            }
            return false
        }

        let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
        let preferences = Preferences.shared
        if session.inputMethod != preferences.inputMethod {
            session.setInputMethod(preferences.inputMethod)
        }
        let presentationMode = ClientAdapter.presentationMode(
            for: appCategory,
            bundleIdentifier: bundleID,
            terminalDirectEnabled: preferences.terminalDirectMode,
            passthroughRemoteApps: preferences.passthroughRemoteApps,
            preference: preferences.presentationModePreference,
            appOverrides: preferences.appModeOverrides
        )

        traceLab("didCommand", bundleID: bundleID, key: selectorName,
                 detail: "selector=\(selectorName) isComposing=\(engine.isComposing)",
                 selection: rawSelection)

        switch selectorName {
        case "deleteBackward:":
            return handleBackspace(client: client, selection: selection, rawSelection: rawSelection, bundleID: bundleID, presentationMode: presentationMode)

        case "deleteForward:":
            if engine.isComposing {
                if presentationMode == .terminalDirect || Self.isBrowserOmniboxSession {
                    cancelComposition()
                } else {
                    commitComposition(client)
                }
            }
            return false

        case "deleteWordBackward:", "deleteToBeginningOfLine:", "deleteToEndOfLine:":
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            if engine.isComposing {
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                if presentationMode == .markedText && hasActiveMarkedText {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                    hasActiveMarkedText = false
                }
            }
            return false

        case "insertNewline:", "insertLineBreak:", "insertNewlineIgnoringFieldEditor:":
            if Self.isBrowserOmniboxSession || hasActiveOmniboxAutocompleteTail(client: client, bundleID: bundleID, rawSelection: rawSelection) {
                clearBrowserOmniboxSession()
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                resetSelectionDrift()
                backtickDepth = 0
                hasActiveMarkedText = false
                return false
            }
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                backtickDepth = 0
            }
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            return false

        case "insertTab:":
            if Self.isBrowserOmniboxSession || hasActiveOmniboxAutocompleteTail(client: client, bundleID: bundleID, rawSelection: rawSelection) {
                clearBrowserOmniboxSession()
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                resetSelectionDrift()
                hasActiveMarkedText = false
                return false
            }
            if engine.isComposing {
                _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
            }
            return false

        case "cancelOperation:": // Escape
            if Self.isBrowserOmniboxSession {
                clearBrowserOmniboxSession()
                cancelComposition()
                rawWord = ""
                return false
            }
            if engine.isComposing {
                cancelComposition()
                rawWord = ""
                if presentationMode == .markedText {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                    hasActiveMarkedText = false
                }
                if presentationMode == .terminalDirect {
                    return false
                }
                return true
            }
            return false

        case "moveLeft:", "moveRight:", "moveUp:", "moveDown:",
             "moveToBeginningOfLine:", "moveToEndOfLine:",
             "moveToBeginningOfParagraph:", "moveToEndOfParagraph:",
             "pageUp:", "pageDown:":
            if Self.isBrowserOmniboxSession {
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                resetSelectionDrift()
                hasActiveMarkedText = false
                return false
            }
            if engine.isComposing {
                if presentationMode == .terminalDirect {
                    cancelComposition()
                } else {
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: presentationMode, selection: selection)
                }
                virtualCursorLocation = NSNotFound
                compositionStartLocation = NSNotFound
            }
            lastCommittedWordStartLocation = NSNotFound
            resetSelectionDrift()
            return false

        default:
            return false
        }
    }

    @discardableResult
    private func handleBackspace(client: IMKTextInput, selection: NSRange, rawSelection: NSRange, bundleID: String?, presentationMode: PresentationMode) -> Bool {
        if ClientAdapter.isBrowserApp(bundleIdentifier: bundleID),
           rawSelection.location == 0,
           rawSelection.length > 0,
           !engine.isComposing {
            let clampedLen = min(rawSelection.length, 512)
            let selectedText = client.attributedSubstring(from: NSRange(location: 0, length: clampedLen))?.string ?? ""
            if ClientAdapter.isHighlightedURLOrDomain(selectedText) {
                Self.isBrowserOmniboxSession = true
            }
        }
        if Self.isBrowserOmniboxSession {
            resetSelectionDrift()
            if rawSelection.location > 0 && rawSelection.length > 0 {
                // Pressing Backspace while an inline URL autocomplete tail (e.g. "go[ogle.com]") is highlighted
                // deletes only the highlighted autocomplete tail in the browser, leaving the typed prefix intact.
                return false
            }
            if rawSelection.location == 0 && rawSelection.length > 0 {
                // Deleting the entire highlighted URL in the address bar leaves the user in an empty Omnibox.
                engine.reset()
                composingWord = ""
                rawWord = ""
                editCaretBack = Self.caretDisarmed
                virtualCursorLocation = 0
                compositionStartLocation = 0
                lastCommittedWordStartLocation = NSNotFound
                hasActiveMarkedText = false
                return false
            }
            if engine.isComposing {
                _ = engine.backspace(displayedAsRaw: true)
                rawWord = engine.rawString()
                composingWord = rawWord
                if virtualCursorLocation != NSNotFound {
                    virtualCursorLocation = max(0, virtualCursorLocation - 1)
                }
                if composingWord.isEmpty {
                    engine.reset()
                    rawWord = ""
                    editCaretBack = Self.caretDisarmed
                    virtualCursorLocation = 0
                    compositionStartLocation = 0
                }
            }
            return false
        }
        let isUserSelection = selection.location != NSNotFound && selection.length > 0 &&
            !(presentationMode == .markedText && engine.isComposing)
        if isUserSelection {
            resetSelectionDrift()
        }
        let consumed = handleBackspaceCore(client: client, selection: selection, isUserSelection: isUserSelection, bundleID: bundleID, presentationMode: presentationMode)
        if !consumed && !isUserSelection && rawSelection.location != NSNotFound {
            lastNativeBackspaceReportedLocation = rawSelection.location
        }
        return consumed
    }

    private func handleBackspaceCore(client: IMKTextInput, selection: NSRange, isUserSelection: Bool, bundleID: String?, presentationMode: PresentationMode) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastBackspaceTime < 25_000_000 {
            return true
        }
        lastBackspaceTime = now

        if isUserSelection {
            engine.reset()
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            if presentationMode == .markedText {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                hasActiveMarkedText = false
            }
            return false // Let macOS delete the highlighted text natively
        }

        if engine.isComposing {
            editCaretBack = Self.caretDisarmed
            let wasDisplayingRaw = !composingWord.isEmpty && composingWord == rawWord && composingWord != engine.currentOutput()
            if let diff = engine.backspace(displayedAsRaw: wasDisplayingRaw) {
                let rawBefore = rawWord
                rawWord = engine.rawString()
                var effectiveOutput = engine.currentOutput()
                if wasDisplayingRaw || (Preferences.shared.smartBilingual && rawWord.count >= 2 &&
                   rawWord.lowercased() != effectiveOutput.lowercased() &&
                   SmartBilingualDetector.isInlineEnglishWord(raw: rawWord, rendered: effectiveOutput)) {
                    effectiveOutput = rawWord
                }
                traceLab("backspace", bundleID: bundleID, key: "Backspace",
                         detail: "rawBefore=\(rawBefore) rawAfter=\(rawWord) diff=\(diff.backspaces),\(diff.suffix)",
                         selection: client.selectedRange(), composingOverride: effectiveOutput)
                if (presentationMode == .directReplacement || (presentationMode == .markedText && !hasActiveMarkedText)),
                   diff.backspaces == 1, diff.suffix.isEmpty,
                   effectiveOutput == String(composingWord.dropLast()) {
                    composingWord = effectiveOutput
                    if virtualCursorLocation != NSNotFound {
                        virtualCursorLocation = max(0, virtualCursorLocation - 1)
                    }
                    if composingWord.isEmpty {
                        engine.reset()
                        rawWord = ""
                        editCaretBack = Self.caretDisarmed
                        virtualCursorLocation = NSNotFound
                        compositionStartLocation = NSNotFound
                        isEditingInTerminalOverlay = false
                    }
                    traceLab("backspaceNative", bundleID: bundleID,
                             detail: "character backspace; composition retained", selection: selection, composingOverride: effectiveOutput)
                    return false
                }
                if presentationMode == .markedText {
                    let output = effectiveOutput
                    if !hasActiveMarkedText && isEditingInTerminalOverlay {
                        let commonPrefixCount = zip(composingWord, output).prefix(while: { $0 == $1 }).count
                        let deleteCount = composingWord.count - commonPrefixCount
                        let suffixToInsert = String(output.dropFirst(commonPrefixCount))
                        if output.isEmpty {
                            engine.reset()
                            composingWord = ""
                            rawWord = ""
                            virtualCursorLocation = NSNotFound
                            compositionStartLocation = NSNotFound
                            isEditingInTerminalOverlay = false
                            if deleteCount <= 1 && suffixToInsert.isEmpty {
                                return false
                            }
                            resetSelectionDrift()
                            client.insertText(String(repeating: "\u{7F}", count: deleteCount), replacementRange: NSRange(location: NSNotFound, length: 0))
                            return true
                        }
                        if deleteCount == 1 && suffixToInsert.isEmpty {
                            composingWord = output
                            return false
                        }
                        let payload = String(repeating: "\u{7F}", count: deleteCount) + suffixToInsert
                        resetSelectionDrift()
                        if !payload.isEmpty {
                            client.insertText(payload, replacementRange: NSRange(location: NSNotFound, length: 0))
                        }
                        hasActiveMarkedText = false
                        composingWord = output
                        return true
                    }
                    let replacementRange: NSRange
                    if hasActiveMarkedText {
                        replacementRange = NSRange(location: NSNotFound, length: 0)
                    } else {
                        let previousOutputLength = (composingWord as NSString).length
                        let startLoc: Int
                        if compositionStartLocation != NSNotFound {
                            startLoc = compositionStartLocation
                        } else if selection.location != NSNotFound, selection.location >= previousOutputLength {
                            startLoc = selection.location - previousOutputLength
                        } else if virtualCursorLocation != NSNotFound, virtualCursorLocation >= previousOutputLength {
                            startLoc = virtualCursorLocation - previousOutputLength
                        } else {
                            startLoc = NSNotFound
                        }
                        replacementRange = startLoc != NSNotFound && previousOutputLength > 0
                            ? NSRange(location: startLoc, length: previousOutputLength)
                            : NSRange(location: NSNotFound, length: 0)
                    }
                    if output.isEmpty {
                        let hadActiveMarkedText = hasActiveMarkedText
                        if hadActiveMarkedText {
                            setCompositionMarkedText("", client: client)
                        } else if replacementRange.location != NSNotFound {
                            resetSelectionDrift()
                            client.insertText("", replacementRange: replacementRange)
                        }
                        engine.reset()
                        composingWord = ""
                        rawWord = ""
                        virtualCursorLocation = replacementRange.location
                        compositionStartLocation = NSNotFound
                        return hadActiveMarkedText || replacementRange.location != NSNotFound
                    } else {
                        if hasActiveMarkedText || replacementRange.location == NSNotFound {
                            setCompositionMarkedText(output, client: client, replacementRange: replacementRange)
                        } else {
                            resetSelectionDrift()
                            client.insertText(output, replacementRange: replacementRange)
                            hasActiveMarkedText = false
                        }
                        composingWord = output
                        if replacementRange.location != NSNotFound {
                            virtualCursorLocation = replacementRange.location + (output as NSString).length
                            compositionStartLocation = replacementRange.location
                        }
                    }
                    return true
                }
                if diff.backspaces == 0 && diff.suffix.isEmpty {
                    composingWord = effectiveOutput
                    return true
                } else if presentationMode == .terminalDirect {
                    if diff.backspaces > 0 || !diff.suffix.isEmpty {
                        let maxBackspaces = (composingWord as NSString).length
                        let safeBackspaces = min(diff.backspaces, maxBackspaces)
                        let backspaces = String(repeating: "\u{7F}", count: safeBackspaces)
                        client.insertText(backspaces + diff.suffix, replacementRange: NSRange(location: NSNotFound, length: 0))
                        traceLab("insertText", bundleID: bundleID,
                                 detail: "backspace del=\(safeBackspaces) suffix=\(diff.suffix)",
                                 selection: client.selectedRange(), composingOverride: effectiveOutput)
                        if virtualCursorLocation != NSNotFound {
                            virtualCursorLocation = max(0, virtualCursorLocation - safeBackspaces) + diff.suffix.utf16.count
                        }
                        composingWord = effectiveOutput

                        if composingWord.isEmpty || !engine.isComposing {
                            engine.reset()
                            composingWord = ""
                            rawWord = ""
                            editCaretBack = Self.caretDisarmed
                            virtualCursorLocation = NSNotFound
                            compositionStartLocation = NSNotFound
                        }
                        return true
                    }
                } else {
                    let output = effectiveOutput
                    let previousOutputLength = (composingWord as NSString).length
                    
                    let startLoc: Int
                    if compositionStartLocation != NSNotFound {
                        startLoc = compositionStartLocation
                    } else if selection.location != NSNotFound, selection.location >= previousOutputLength {
                        startLoc = selection.location - previousOutputLength
                    } else if virtualCursorLocation != NSNotFound, virtualCursorLocation >= previousOutputLength {
                        startLoc = virtualCursorLocation - previousOutputLength
                    } else {
                        startLoc = NSNotFound
                    }

                    let wordRange = startLoc != NSNotFound && previousOutputLength > 0
                        ? NSRange(location: startLoc, length: previousOutputLength)
                        : NSRange(location: NSNotFound, length: 0)

                    let clientID = bundleID?.lowercased() ?? ""
                    let isNotesOrPrefs = ["com.apple.notes", "com.apple.systempreferences"].contains(clientID)

                    if output.isEmpty {
                        if isNotesOrPrefs {
                            engine.reset()
                            composingWord = ""
                            rawWord = ""
                            editCaretBack = Self.caretDisarmed
                            virtualCursorLocation = NSNotFound
                            compositionStartLocation = NSNotFound
                            traceLab("backspaceNative", bundleID: bundleID,
                                     detail: "finish-composition output=empty", selection: selection)
                            return false
                        }

                        if wordRange.location != NSNotFound {
                            client.insertText("", replacementRange: wordRange)
                            traceLab("insertText", bundleID: bundleID,
                                     detail: "backspace finish-composition range=\(wordRange.location),\(wordRange.length)",
                                     selection: client.selectedRange())
                            virtualCursorLocation = wordRange.location
                        } else {
                            traceLab("backspaceNativeFallback", bundleID: bundleID,
                                     detail: "finish-composition range unavailable startLoc=\(startLoc) length=\(previousOutputLength)",
                                     selection: client.selectedRange())
                            virtualCursorLocation = NSNotFound
                        }
                        engine.reset()
                        composingWord = ""
                        rawWord = ""
                        editCaretBack = Self.caretDisarmed
                        compositionStartLocation = NSNotFound
                        return wordRange.location != NSNotFound
                    }

                    if output != composingWord {
                        if wordRange.location != NSNotFound {
                            resetSelectionDrift()
                            lastDirectReplacementDelta = wordRange.length
                            client.insertText(output, replacementRange: wordRange)
                            traceLab("insertText", bundleID: bundleID,
                                     detail: "backspace whole-word range=\(wordRange.location),\(wordRange.length) replacement=\(output)",
                                     selection: client.selectedRange())
                            composingWord = output
                            virtualCursorLocation = wordRange.location + (output as NSString).length
                            return true
                        } else {
                            engine.reset()
                            composingWord = ""
                            rawWord = ""
                            virtualCursorLocation = NSNotFound
                            compositionStartLocation = NSNotFound
                            traceLab("backspaceNativeFallback", bundleID: bundleID,
                                     detail: "whole-word range unavailable startLoc=\(startLoc) length=\(previousOutputLength)",
                                     selection: selection)
                            return false
                        }
                    }
                    composingWord = output
                    return true
                }
            }
            if presentationMode == .markedText && hasActiveMarkedText {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                hasActiveMarkedText = false
            }
            engine.reset()
            composingWord = ""
            rawWord = ""
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            isEditingInTerminalOverlay = false
            return false
        } else {
            // Backspace while idle: deleting the space after committed word arms editing
            if editCaretBack == -1 {
                editCaretBack = 0
            } else if editCaretBack == 0 {
                if let _ = engine.editBackspaceAt(caretBack: editCaretBack) {
                    let output = engine.currentOutput()
                    let outLen = (output as NSString).length
                    composingWord = output
                    rawWord = engine.rawString()
                    editCaretBack = Self.caretDisarmed
                    traceLab("backspace", bundleID: bundleID, key: "Backspace",
                             detail: "editBackspace output=\(output)",
                             selection: client.selectedRange())
                    if outLen == 0 {
                        // A 1-character word (e.g. "á", "í") was completely deleted by this Backspace.
                        // Clear all composition & cursor anchors so the next word starts fresh.
                        engine.reset()
                        composingWord = ""
                        rawWord = ""
                        compositionStartLocation = NSNotFound
                        virtualCursorLocation = NSNotFound
                        lastCommittedWordStartLocation = NSNotFound
                        lastCommittedWordLength = 0
                        isEditingInTerminalOverlay = false
                    } else {
                        if presentationMode == .markedText &&
                           (lastBackspaceDidNotMoveSelection ||
                            (selection.location != NSNotFound && selection.location < outLen)) {
                            isEditingInTerminalOverlay = true
                        }
                        if lastCommittedWordStartLocation != NSNotFound {
                            compositionStartLocation = lastCommittedWordStartLocation
                            virtualCursorLocation = lastCommittedWordStartLocation + outLen
                        } else if virtualCursorLocation != NSNotFound {
                            virtualCursorLocation = max(0, virtualCursorLocation - 1)
                            if virtualCursorLocation >= outLen {
                                compositionStartLocation = virtualCursorLocation - outLen
                            }
                        } else if selection.location != NSNotFound, selection.location >= outLen + 1 {
                            virtualCursorLocation = selection.location - 1
                            compositionStartLocation = selection.location - 1 - outLen
                        }
                    }
                } else {
                    engine.reset()
                    editCaretBack = Self.caretDisarmed
                    compositionStartLocation = NSNotFound
                    virtualCursorLocation = NSNotFound
                    lastCommittedWordStartLocation = NSNotFound
                    lastCommittedWordLength = 0
                    isEditingInTerminalOverlay = false
                }
            } else {
                engine.reset()
                engine.clearHistory()
                editCaretBack = Self.caretDisarmed
                compositionStartLocation = NSNotFound
                virtualCursorLocation = NSNotFound
                lastCommittedWordStartLocation = NSNotFound
                lastCommittedWordLength = 0
                isEditingInTerminalOverlay = false
            }
            // Likely deleted a backtick — decrement depth to stay in sync
            if backtickDepth > 0 {
                backtickDepth -= 1
            }
            return false
        }
    }

    private func commitWordWithBilingualCheck(client: IMKTextInput, presentationMode: PresentationMode, selection: NSRange, suffixChar: Character? = nil) -> Bool {
        guard engine.isComposing else { return false }
        let output = engine.currentOutput()
        let prefs = Preferences.shared
        let displayedLen = ((composingWord.isEmpty ? output : composingWord) as NSString).length
        let committedStartLoc: Int
        if presentationMode == .markedText && hasActiveMarkedText {
            let liveSel = client.selectedRange()
            if liveSel.location != NSNotFound && liveSel.location >= displayedLen {
                committedStartLoc = liveSel.location - displayedLen
            } else if compositionStartLocation != NSNotFound {
                committedStartLoc = compositionStartLocation
            } else if selection.location != NSNotFound && selection.location >= displayedLen {
                committedStartLoc = selection.location - displayedLen
            } else {
                committedStartLoc = NSNotFound
            }
        } else if compositionStartLocation != NSNotFound {
            committedStartLoc = compositionStartLocation
        } else if selection.location != NSNotFound && selection.location >= displayedLen {
            committedStartLoc = selection.location - displayedLen
        } else {
            committedStartLoc = NSNotFound
        }

        let candidateMacroKey = rawWord.isEmpty ? output : rawWord
        if prefs.macroEnabled, let macroExpansion = MacroEngine.shared.lookup(word: candidateMacroKey) {
            let appendStr = suffixChar != nil ? String(suffixChar!) : ""
            if presentationMode == .directReplacement {
                let wordLen = output.utf16.count
                let startLoc: Int
                if compositionStartLocation != NSNotFound {
                    startLoc = compositionStartLocation
                } else {
                    let currentLoc = selection.location != NSNotFound ? selection.location : (virtualCursorLocation != NSNotFound ? virtualCursorLocation : client.selectedRange().location)
                    startLoc = currentLoc != NSNotFound && currentLoc >= wordLen ? currentLoc - wordLen : NSNotFound
                }
                let range = startLoc != NSNotFound ? NSRange(location: startLoc, length: wordLen) : NSRange(location: NSNotFound, length: 0)
                client.insertText(macroExpansion + appendStr, replacementRange: range)
                traceLab("commitMacro", bundleID: client.bundleIdentifier(),
                         detail: "key=\(candidateMacroKey) val=\(macroExpansion) suffix=\(appendStr)",
                         selection: client.selectedRange())
                if range.location != NSNotFound {
                    virtualCursorLocation = range.location + (macroExpansion + appendStr).utf16.count
                } else if virtualCursorLocation != NSNotFound {
                    virtualCursorLocation += (macroExpansion + appendStr).utf16.count
                }
            } else if presentationMode == .terminalDirect {
                let deleteChars = String(repeating: "\u{7F}", count: output.count)
                client.insertText(deleteChars + macroExpansion + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                traceLab("commitMacro", bundleID: client.bundleIdentifier(),
                         detail: "key=\(candidateMacroKey) val=\(macroExpansion) terminal=true",
                         selection: client.selectedRange())
            } else {
                if hasActiveMarkedText {
                    client.insertText(macroExpansion + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                } else if isEditingInTerminalOverlay {
                    let priorWord = composingWord.isEmpty ? output : composingWord
                    let deleteChars = String(repeating: "\u{7F}", count: priorWord.count)
                    client.insertText(deleteChars + macroExpansion + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                } else {
                    let wordLen = (composingWord as NSString).length
                    let range = committedStartLoc != NSNotFound ? NSRange(location: committedStartLoc, length: wordLen) : NSRange(location: NSNotFound, length: 0)
                    client.insertText(macroExpansion + appendStr, replacementRange: range)
                }
                hasActiveMarkedText = false
                traceLab("commitMacro", bundleID: client.bundleIdentifier(),
                         detail: "key=\(candidateMacroKey) val=\(macroExpansion) marked=true",
                         selection: client.selectedRange())
            }
            appendContext(macroExpansion)
            engine.clearHistory()
            session.reset()
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = NSNotFound
            lastCommittedWordLength = 0
            didEditMarkedTextInComposition = false
            isEditingInTerminalOverlay = false
            return true
        }

        let isCodeBoundary = prefs.smartBilingual && suffixChar != nil && "([{".contains(suffixChar!) &&
            !SmartBilingualDetector.isExplicitTelexEscape(raw: rawWord, rendered: output)
        if !rawWord.isEmpty && rawWord.lowercased() != output.lowercased() &&
           (isCodeBoundary || (prefs.smartBilingual && rawWord.count >= 2 && SmartBilingualDetector.isEnglishWord(raw: rawWord, context: recentContext, rendered: output, genZMode: prefs.genZMode))) {
            // Restore English rawWord or code identifier
            let restoredWord = rawWord
            let appendStr = suffixChar != nil ? String(suffixChar!) : ""
            var didConsumeSuffix = true
            if presentationMode == .directReplacement {
                if composingWord == rawWord {
                    // The exact English word is already in the client buffer via inline English;
                    // let the boundary key (Space/punctuation) pass through natively without re-inserting the word.
                    didConsumeSuffix = false
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) inline=true",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                } else {
                    let wordLen = output.utf16.count
                    let startLoc: Int
                    if compositionStartLocation != NSNotFound {
                        startLoc = compositionStartLocation
                    } else {
                        let currentLoc = selection.location != NSNotFound ? selection.location : (virtualCursorLocation != NSNotFound ? virtualCursorLocation : client.selectedRange().location)
                        startLoc = currentLoc != NSNotFound && currentLoc >= wordLen ? currentLoc - wordLen : NSNotFound
                    }
                    let range = startLoc != NSNotFound ? NSRange(location: startLoc, length: wordLen) : NSRange(location: NSNotFound, length: 0)
                    client.insertText(rawWord + appendStr, replacementRange: range)
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) range=\(range.location),\(range.length)",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                    if range.location != NSNotFound {
                        virtualCursorLocation = range.location + (rawWord + appendStr).utf16.count
                    } else if virtualCursorLocation != NSNotFound {
                        virtualCursorLocation += (rawWord + appendStr).utf16.count
                    }
                }
            } else if presentationMode == .terminalDirect {
                if composingWord == rawWord {
                    didConsumeSuffix = false
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) terminal=true inline=true",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                } else {
                    let deleteCount = composingWord.count > 0 ? composingWord.count : output.count
                    let deleteChars = String(repeating: "\u{7F}", count: deleteCount)
                    client.insertText(deleteChars + rawWord + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) terminal=true",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                    if virtualCursorLocation != NSNotFound {
                        virtualCursorLocation = max(0, virtualCursorLocation - deleteCount) + (rawWord + appendStr).utf16.count
                    }
                }
            } else {
                if hasActiveMarkedText {
                    // Commit the active marked text without bundling the trailing Space/punctuation,
                    // and return false so the boundary key is processed natively (matching commitVietnamese).
                    client.insertText(rawWord, replacementRange: NSRange(location: NSNotFound, length: 0))
                    didConsumeSuffix = false
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) marked=true",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                } else if composingWord == rawWord {
                    // No active marked text and `rawWord` is already in the editor buffer (e.g. after
                    // directInsert / appendChar). Do not re-insert `rawWord` (which would duplicate it
                    // in Orca); simply let the boundary key pass through natively.
                    didConsumeSuffix = false
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) markedInline=true",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                } else if isEditingInTerminalOverlay {
                    let priorWord = composingWord.isEmpty ? output : composingWord
                    let commonPrefixCount = zip(priorWord, rawWord).prefix(while: { $0 == $1 }).count
                    let deleteCount = priorWord.count - commonPrefixCount
                    let suffixToInsert = String(rawWord.dropFirst(commonPrefixCount))
                    let deleteChars = String(repeating: "\u{7F}", count: deleteCount)
                    client.insertText(deleteChars + suffixToInsert + appendStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                    didConsumeSuffix = true
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) terminalOverlay=true",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                } else {
                    let wordLen = (composingWord as NSString).length
                    let startLoc: Int
                    if compositionStartLocation != NSNotFound {
                        startLoc = compositionStartLocation
                    } else {
                        let currentLoc = selection.location != NSNotFound ? selection.location : (virtualCursorLocation != NSNotFound ? virtualCursorLocation : client.selectedRange().location)
                        startLoc = currentLoc != NSNotFound && currentLoc >= wordLen ? currentLoc - wordLen : NSNotFound
                    }
                    let range = startLoc != NSNotFound ? NSRange(location: startLoc, length: wordLen) : NSRange(location: NSNotFound, length: 0)
                    client.insertText(rawWord, replacementRange: range)
                    didConsumeSuffix = false
                    traceLab("commitEnglish", bundleID: client.bundleIdentifier(),
                             detail: "word=\(rawWord) start=\(committedStartLoc) suffix=\(appendStr) markedFallback=true range=\(range.location),\(range.length)",
                             selection: client.selectedRange(), composingOverride: restoredWord)
                }
                hasActiveMarkedText = false
            }
            appendContext(restoredWord)
            engine.commitWord(raw: restoredWord, rendered: restoredWord)
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = committedStartLoc
            lastCommittedWordLength = (restoredWord as NSString).length
            didEditMarkedTextInComposition = false
            isEditingInTerminalOverlay = false
            return didConsumeSuffix
        } else {
            // Commit Vietnamese word
            var didConsumeVietnameseSuffix = false
            if presentationMode == .markedText && hasActiveMarkedText {
                client.insertText(output, replacementRange: NSRange(location: NSNotFound, length: 0))
            } else if !composingWord.isEmpty && composingWord != output && suffixChar == " " {
                // When the first token in a browser Omnibox was kept as raw ASCII ("thowif") so URL
                // autocomplete suggestions would not break, and the user then presses Space to type a
                // multi-word Vietnamese search query ("thời tiết"), replace the raw ASCII token (and any
                // trailing inline autocomplete selection) with the Vietnamese word + Space.
                let wordLen = (composingWord as NSString).length
                let startLoc = committedStartLoc != NSNotFound ? committedStartLoc : 0
                let liveSel = client.selectedRange()
                let extraAutocompleteLen = (liveSel.location == startLoc + wordLen && liveSel.length > 0) ? liveSel.length : 0
                let replaceRange = NSRange(location: startLoc, length: wordLen + extraAutocompleteLen)
                client.insertText(output + " ", replacementRange: replaceRange)
                didConsumeVietnameseSuffix = true
            }
            traceLab("commitVietnamese", bundleID: client.bundleIdentifier(),
                     detail: "raw=\(rawWord) output=\(output) start=\(committedStartLoc) suffix=\(suffixChar.map(String.init) ?? "")",
                     selection: client.selectedRange())
            hasActiveMarkedText = false
            engine.commitWord(raw: rawWord, rendered: output)
            appendContext(output)
            composingWord = ""
            rawWord = ""
            editCaretBack = Self.caretDisarmed
            virtualCursorLocation = NSNotFound
            compositionStartLocation = NSNotFound
            lastCommittedWordStartLocation = committedStartLoc
            lastCommittedWordLength = (output as NSString).length
            didEditMarkedTextInComposition = false
            isEditingInTerminalOverlay = false
            return didConsumeVietnameseSuffix
        }
    }

    private func appendContext(_ word: String) {
        session.appendContext(word)
    }

    @discardableResult
    private func setCompositionMarkedText(
        _ text: String,
        client: IMKTextInput,
        replacementRange: NSRange = NSRange(location: NSNotFound, length: 0),
        resolvedBundleID: String? = nil
    ) -> NSRange {
        // Calling setMarkedText synchronously updates Chromium/Electron/WebKit's
        // RenderWidgetHostViewCocoa selection and markedRange to the true DOM offset,
        // eliminating any prior native-backspace selection drift.
        resetSelectionDrift()
        if text.isEmpty {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: replacementRange)
            hasActiveMarkedText = false
            return replacementRange
        }
        // Apple-Standard Composition Attributes:
        // Use single underline + markedClauseSegment:0 — exactly what Apple's own IMEs
        // (Japanese, Pinyin, Korean) do. This ensures:
        //   1. NSTextView-based apps (Notes, Pages, TextEdit) render composition consistently
        //      using their own markedTextAttributes (single underline by default).
        //   2. WebKit/Chromium/Electron activate the W3C IME composition lifecycle
        //      (compositionstart/update/end), preventing duplicate characters, and display
        //      the standard composition underline that users expect.
        //   3. Terminal apps and third-party apps receive a well-formed composition NSAttributedString
        //      with a valid clause segment boundary, eliminating segment tracking bugs.
        // The prior zero-underline (.underlineStyle: 0) was inconsistent: NSTextView ignored it
        // and applied its own markedTextAttributes anyway; Electron respected it but the absence
        // of markedClauseSegment caused IME segment boundary issues in some editors.
        let bundleID = (resolvedBundleID ?? ClientAdapter.resolveBundleIdentifier(client.bundleIdentifier()))?.lowercased()
        let prefs = Preferences.shared
        let userExplicitlyChoseMarkedText =
            prefs.presentationModePreference == .markedText ||
            (bundleID != nil && prefs.appModeOverrides[bundleID!] == .markedText)

        var compositionAttributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .markedClauseSegment: 0
        ]
        if !userExplicitlyChoseMarkedText {
            // In Stealth Marked Text mode (Chromium/Electron automatic mode or dynamic fallback),
            // keep NSUnderlineStyle.single + markedClauseSegment:0 so the host honors the W3C
            // composition segment boundary, but set alpha to 0.004 (1/255) so Chromium renders
            // a near-invisible underline instead of falling back to a thick solid bar.
            compositionAttributes[.underlineColor] = NSColor.labelColor.withAlphaComponent(0.004)
        }
        let attrString = NSAttributedString(string: text, attributes: compositionAttributes)
        let textLen = text.utf16.count
        client.setMarkedText(attrString,
                             selectionRange: NSRange(location: textLen, length: 0),
                             replacementRange: replacementRange)
        hasActiveMarkedText = true
        if replacementRange.location != NSNotFound {
            compositionStartLocation = replacementRange.location
            virtualCursorLocation = replacementRange.location + textLen
            return NSRange(location: virtualCursorLocation, length: 0)
        } else {
            let postSel = client.selectedRange()
            if postSel.location != NSNotFound && postSel.location >= textLen {
                compositionStartLocation = postSel.location - textLen
                virtualCursorLocation = postSel.location
            }
            return postSel
        }
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        if engine.isComposing {
            if Self.isBrowserOmniboxSession && !hasActiveMarkedText {
                cancelComposition()
                return
            }
            let bundleID = ClientAdapter.resolveBundleIdentifier(client.bundleIdentifier())
            let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
            let prefs = Preferences.shared
            var mode = ClientAdapter.presentationMode(
                for: appCategory,
                bundleIdentifier: bundleID,
                terminalDirectEnabled: prefs.terminalDirectMode,
                passthroughRemoteApps: prefs.passthroughRemoteApps,
                preference: prefs.presentationModePreference,
                appOverrides: prefs.appModeOverrides
            )
            if hasActiveMarkedText && mode == .directReplacement {
                mode = .markedText
            }
            let selection = effectiveSelection(for: client.selectedRange())
            _ = commitWordWithBilingualCheck(client: client, presentationMode: mode, selection: selection)
        }
        editCaretBack = Self.caretDisarmed
        isEditingInTerminalOverlay = false
        hasActiveMarkedText = false
    }

    override func cancelComposition() {
        session.reset()
        editCaretBack = Self.caretDisarmed
        virtualCursorLocation = NSNotFound
        compositionStartLocation = NSNotFound
        lastCommittedWordStartLocation = NSNotFound
        didEditMarkedTextInComposition = false
        isEditingInTerminalOverlay = false
        resetSelectionDrift()
        hasActiveMarkedText = false
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // A focus change is the right moment to pick up an edited typing-modes.yml:
        // one stat, off the keystroke path, so a new per-app rule applies without a
        // rebuild or a relaunch.
        ClientAdapter.reloadPresentationRulesIfChanged()
        MacroEngine.shared.reloadFromDiskIfChanged()
        applyPreferences()
        session.reset()
        session.clearContext()
        editCaretBack = Self.caretDisarmed
        virtualCursorLocation = NSNotFound
        compositionStartLocation = NSNotFound
        lastCommittedWordStartLocation = NSNotFound
        didEditMarkedTextInComposition = false
        isEditingInTerminalOverlay = false
        resetSelectionDrift()
        lastClientIdentifier = nil

        if Preferences.shared.enforceABCBaseLayout, let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        }

        NSLog("VieLotusIMController: Activated")
    }

    override func deactivateServer(_ sender: Any!) {
        if Self.isBrowserOmniboxSession {
            let now = DispatchTime.now().uptimeNanoseconds
            if (now - Self.lastOmniboxShortcutTime) > 10_000_000_000 || Self.omniboxFocusTransitionsSinceShortcut > 1 {
                clearBrowserOmniboxSession()
            }
        }
        session.reset()
        session.clearContext()
        editCaretBack = Self.caretDisarmed
        virtualCursorLocation = NSNotFound
        compositionStartLocation = NSNotFound
        lastCommittedWordStartLocation = NSNotFound
        didEditMarkedTextInComposition = false
        isEditingInTerminalOverlay = false
        resetSelectionDrift()
        lastClientIdentifier = nil
        super.deactivateServer(sender)
        NSLog("VieLotusIMController: Deactivated")
    }

    // MARK: - IMKMouseHandling

    override func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint, withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!, client sender: Any!) -> Bool {
        clearBrowserOmniboxSession()
        editCaretBack = Self.caretDisarmed
        lastCommittedWordStartLocation = NSNotFound
        isEditingInTerminalOverlay = false
        resetSelectionDrift()
        if engine.isComposing {
            if let client = sender as? IMKTextInput {
                let bundleID = ClientAdapter.resolveBundleIdentifier(client.bundleIdentifier())
                let appCategory = ClientAdapter.classify(bundleIdentifier: bundleID)
                let prefs = Preferences.shared
                var mode = ClientAdapter.presentationMode(
                    for: appCategory,
                    bundleIdentifier: bundleID,
                    terminalDirectEnabled: prefs.terminalDirectMode,
                    passthroughRemoteApps: prefs.passthroughRemoteApps,
                    preference: prefs.presentationModePreference,
                    appOverrides: prefs.appModeOverrides
                )
                if hasActiveMarkedText && mode == .directReplacement {
                    mode = .markedText
                }
                if mode == .terminalDirect {
                    cancelComposition()
                } else {
                    let selection = effectiveSelection(for: client.selectedRange())
                    _ = commitWordWithBilingualCheck(client: client, presentationMode: mode, selection: selection)
                }
            } else {
                cancelComposition()
            }
        }
        session.clearContext()
        return false // Do not consume mouse clicks; allow client to position caret/selection
    }

    // MARK: - Native Menu Bar Context Menu

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Sen Việt")
        let prefs = Preferences.shared

        let telexItem = NSMenuItem(
            title: "Kiểu gõ Telex Tự Do",
            action: #selector(selectTelexInputMethod),
            keyEquivalent: ""
        )
        telexItem.target = self
        telexItem.state = (prefs.inputMethod == .telex) ? .on : .off
        menu.addItem(telexItem)

        let vniItem = NSMenuItem(
            title: "Kiểu gõ VNI Chuẩn",
            action: #selector(selectVNIInputMethod),
            keyEquivalent: ""
        )
        vniItem.target = self
        vniItem.state = (prefs.inputMethod == .vni) ? .on : .off
        menu.addItem(vniItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Cài đặt Sen Việt...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc private func selectTelexInputMethod() {
        Preferences.shared.inputMethod = .telex
        applyPreferences()
    }

    @objc private func selectVNIInputMethod() {
        Preferences.shared.inputMethod = .vni
        applyPreferences()
    }

    @objc private func openSettings() {
        SettingsWindowManager.shared.showSettingsWindow()
    }
}
