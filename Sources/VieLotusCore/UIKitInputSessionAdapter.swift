#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

/// Protocol abstracting iOS `UITextDocumentProxy` for cross-platform decoupling and unit testability.
public protocol TextDocumentProxyProtocol: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

public extension TextDocumentProxyProtocol {
    var selectedText: String? { nil }
}

/// Optional transport capability; existing/mock/Android proxies keep direct replacement.
public protocol MarkedCompositionDocumentProxy: TextDocumentProxyProtocol {
    func setCompositionText(_ text: String, selectedRange: NSRange)
    func finishCompositionText()
}

#if canImport(UIKit)
import UIKit
// Device marked-text experiment lost input. API presence does not establish
// reliable host composition ownership; retain direct production transport.
extension UIInputViewController: TextDocumentProxyProtocol {

    public var documentContextBeforeInput: String? {
        return textDocumentProxy.documentContextBeforeInput
    }
    public var documentContextAfterInput: String? {
        return textDocumentProxy.documentContextAfterInput
    }
    public var selectedText: String? {
        return textDocumentProxy.selectedText
    }
    public func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }
    public func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }
}
#endif

/// High-performance controller bridging `InputSessionManager` with `UITextDocumentProxy` on iOS/iPadOS.
public final class UIKitInputSessionAdapter {
    public let session: InputSessionManager
    /// Experimental transport, enabled only by the dedicated profiling build.
    public var prefersMarkedComposition = false
    private var markedWord: String?

    /// Reusable probe engine for non-ASCII diacritic validation (avoids allocation per keystroke).
    private static let cachedProbeEngineLock = NSLock()
    private static let cachedProbeEngine = VietnameseEngine()

    public func finishMarkedComposition(proxy: TextDocumentProxyProtocol) {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        guard markedWord != nil else { return }
        (proxy as? MarkedCompositionDocumentProxy)?.finishCompositionText()
        markedWord = nil
    }

    private func applyMarkedReplacement(backspaces: Int, text: String,
                                        priorDisplayed: String?, proxy: TextDocumentProxyProtocol) -> Bool {
        guard prefersMarkedComposition, !literalOverrideEnabled,
              let markedProxy = proxy as? MarkedCompositionDocumentProxy,
              proxy.selectedText?.isEmpty != false else { return false }
        if let owned = markedWord {
            guard priorDisplayed == owned, backspaces <= owned.utf16.count else { return false }
            // A suffix edit must be reconstructed into the entire marked word.
            guard let start = Self.characterIndex(in: owned, trailingUTF16Count: backspaces) else { return false }
            let updated = String(owned[..<start]) + text
#if DEBUG
            debugProxyMarkCount += 1
#endif
            markedProxy.setCompositionText(updated, selectedRange: NSRange(location: updated.utf16.count, length: 0))
            markedWord = updated.isEmpty ? nil : updated
            if updated.isEmpty { markedProxy.finishCompositionText() }
            updateMarkedShadow(oldWord: owned, newWord: updated)
            return true
        }
        // Never take ownership of text committed before this composition.
        guard priorDisplayed == nil, backspaces == 0, session.isComposing, !text.isEmpty else { return false }
        if shadowBeforeInput == nil { shadowBeforeInput = proxy.documentContextBeforeInput ?? "" }
#if DEBUG
        debugProxyMarkCount += 1
#endif
        markedProxy.setCompositionText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        markedWord = text
        updateMarkedShadow(oldWord: "", newWord: text)
        return true
    }

    private func updateMarkedShadow(oldWord: String, newWord: String) {
        var before = shadowBeforeInput ?? ""
        if before.hasSuffix(oldWord) { before.removeLast(oldWord.count) }
        shadowBeforeInput = String((before + newWord).suffix(120))
        proxyIsAsynchronousXPC = true
        hasProbedProxySyncMode = true
        lastShadowMutationTime = Date().timeIntervalSince1970
    }
    public var smartBilingual: Bool = true {
        didSet {
            session.smartBilingualEnabled = smartBilingual
            session.inlineBilingualEnabled = smartBilingual
        }
    }
    public var genZMode: Bool = false {
        didSet {
            session.setGenZMode(genZMode)
        }
    }

    /// Optional callback invoked when a keystroke is rejected as a no-op by the Strict Vietnamese Guard,
    /// allowing the keyboard UI to emit a subtle visual/haptic cue so the user knows the key was guarded.
#if DEBUG
    public private(set) var debugProxyInsertCount = 0
    public private(set) var debugProxyDeleteCount = 0
    public private(set) var debugProxyMarkCount = 0
    /// Synchronous insert/delete call duration only, not host application/display.
    public private(set) var debugProxyMutationNanoseconds: UInt64 = 0
    private func resetDebugProxyCounts() {
        debugProxyInsertCount = 0
        debugProxyDeleteCount = 0
        debugProxyMarkCount = 0
        debugProxyMutationNanoseconds = 0
    }
#endif
    public var onRejectedKeyFeedback: ((Character) -> Void)?

    /// Controls Explicit Literal Intent (`Literal Override` / `ABC` mode).
    public var literalOverrideEnabled: Bool {
        get { session.literalOverrideEnabled }
        set { session.literalOverrideEnabled = newValue }
    }

    /// Controls active composition Backspace behavior (`.appleSemantic` default vs `.gboardCharacter`).
    public var backspaceStyle: BackspaceStyle {
        get { session.backspaceStyle }
        set { session.backspaceStyle = newValue }
    }

    private var needsContextSync: Bool = true
    private var shadowBeforeInput: String?
    private var lastSpacePreCommitTail: String?
    private var proxyIsAsynchronousXPC: Bool = false
    private var hasProbedProxySyncMode: Bool = false
    private var lastShadowMutationTime: TimeInterval = 0
    private let adapterLock = NSRecursiveLock()

    /// Timestamp of the last Spacebar tap eligible for the double-space period shortcut (`". "`).
    public var lastSpaceTapTime: TimeInterval = 0
    /// True when the most recent edit inserted a candidate or glide word with a trailing space (`" "`),
    /// allowing the first subsequent Space tap to arm double-space without inserting a duplicate space (`"  "`).
    public var justInsertedCandidateWithTrailingSpace: Bool = false

    public enum SpaceTapOutcome: Equatable, Sendable {
        case insertedPeriodShortcut
        case absorbedAfterCandidateTrailingSpace
        case committedComposingWord(String)
        case insertedSpace
    }

    /// Latest in-memory `documentContextBeforeInput` snapshot captured during the current adapter turn,
    /// avoiding redundant XPC reads from the UI layer immediately after a keystroke.
    public var cachedBeforeInput: String? {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        return shadowBeforeInput
    }

    public init(session: InputSessionManager = InputSessionManager()) {
        self.session = session
        self.session.smartBilingualEnabled = smartBilingual
        self.session.inlineBilingualEnabled = smartBilingual
    }

    /// Returns the most accurate `documentContextBeforeInput`, compensating for asynchronous XPC lag
    /// on real iOS devices immediately after `insertText` or `deleteBackward`.
    public func effectiveContextBeforeInput(proxy: TextDocumentProxyProtocol) -> String? {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        if proxyIsAsynchronousXPC,
           let shadow = shadowBeforeInput,
           Date().timeIntervalSince1970 - lastShadowMutationTime < 0.65 {
            return shadow
        }
        let live = proxy.documentContextBeforeInput
        return live ?? shadowBeforeInput
    }

    private static func isHostXPCProxy(_ proxy: TextDocumentProxyProtocol) -> Bool {
        #if canImport(UIKit)
        return proxy is UIInputViewController
        #else
        return false
        #endif
    }

    /// Safely reconciles Core composition state when the host-owned text diverges from `session.composingWord`.
    public func reconcileIfNeeded(proxy: TextDocumentProxyProtocol) {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        let now = Date().timeIntervalSince1970
        let inShadowWindow = (proxyIsAsynchronousXPC || Self.isHostXPCProxy(proxy)) &&
            shadowBeforeInput != nil &&
            (now - lastShadowMutationTime < 0.65)
        guard !inShadowWindow else { return }
        guard let liveBefore = proxy.documentContextBeforeInput else {
            if !session.isComposing && session.editCaretBack >= 0 {
                session.editCaretBack = InputSessionManager.caretDisarmed
            }
            return
        }
        if let existingShadow = shadowBeforeInput, !existingShadow.isEmpty, liveBefore.hasSuffix(existingShadow) {
            // Preserve bounded shadow buffer without re-copying the full document prefix
        } else if liveBefore.utf8.count > 240 {
            shadowBeforeInput = String(liveBefore.suffix(80))
        } else {
            shadowBeforeInput = liveBefore
        }
        if session.isComposing {
            let composing = session.composingWord
            let matchesSuffix: Bool
            if composing.isEmpty {
                matchesSuffix = false
            } else if liveBefore.hasSuffix(composing) {
                matchesSuffix = true
            } else {
                let tailSlice = String(liveBefore.suffix(max(composing.count * 2, 16)))
                let normalizedBefore = tailSlice.precomposedStringWithCanonicalMapping
                let normalizedComposing = composing.precomposedStringWithCanonicalMapping
                matchesSuffix = !normalizedComposing.isEmpty && normalizedBefore.hasSuffix(normalizedComposing)
            }
            if !matchesSuffix {
                session.reset()
                if liveBefore.isEmpty {
                    session.engine.clearHistory()
                    session.clearContext()
                    session.editCaretBack = InputSessionManager.caretDisarmed
                } else {
                    syncArmedWordFromContext(proxy: proxy)
                }
            }
        } else if liveBefore.isEmpty {
            session.engine.clearHistory()
            session.clearContext()
            session.editCaretBack = InputSessionManager.caretDisarmed
        } else if session.editCaretBack >= 0,
                  let lastCommitted = session.engine.lastCommittedWord {
            if !liveBefore.hasSuffix(lastCommitted) {
                let tailSlice = String(liveBefore.suffix(max(lastCommitted.count * 2, 16)))
                let normalizedBefore = tailSlice.precomposedStringWithCanonicalMapping
                let normalizedCommitted = lastCommitted.precomposedStringWithCanonicalMapping
                if !normalizedBefore.hasSuffix(normalizedCommitted) {
                    session.editCaretBack = InputSessionManager.caretDisarmed
                }
            }
        }
    }

    private func proxyInsertText(_ text: String, proxy: TextDocumentProxyProtocol) {
        guard !text.isEmpty else { return }
        finishMarkedComposition(proxy: proxy)
        let now = Date().timeIntervalSince1970
        if shadowBeforeInput == nil {
            shadowBeforeInput = proxy.documentContextBeforeInput ?? ""
        }
        let pre = shadowBeforeInput ?? ""
        let expected = pre + text
#if DEBUG
        debugProxyInsertCount += 1
        let mutationStartedAt = DispatchTime.now().uptimeNanoseconds
#endif
        proxy.insertText(text)
#if DEBUG
        debugProxyMutationNanoseconds += DispatchTime.now().uptimeNanoseconds - mutationStartedAt
#endif
        if !hasProbedProxySyncMode {
            hasProbedProxySyncMode = true
            if Self.isHostXPCProxy(proxy) {
                proxyIsAsynchronousXPC = true
                shadowBeforeInput = expected
            } else if let post = proxy.documentContextBeforeInput, post == expected {
                proxyIsAsynchronousXPC = false
                shadowBeforeInput = post
            } else {
                proxyIsAsynchronousXPC = true
                shadowBeforeInput = expected
            }
        } else {
            shadowBeforeInput = expected
        }
        if let s = shadowBeforeInput, s.utf8.count > 240 {
            shadowBeforeInput = String(s.suffix(80))
        }
        lastShadowMutationTime = now
    }

    private func proxyDeleteBackward(proxy: TextDocumentProxyProtocol, hadKnownSelection: Bool = false) {
        finishMarkedComposition(proxy: proxy)
        let now = Date().timeIntervalSince1970
        let hadSelection = hadKnownSelection
        if shadowBeforeInput == nil {
            shadowBeforeInput = proxy.documentContextBeforeInput ?? ""
        }
        let pre = shadowBeforeInput ?? ""
        var expected = pre
        if !hadSelection && !expected.isEmpty {
            expected.removeLast()
        }
#if DEBUG
        debugProxyDeleteCount += 1
        let mutationStartedAt = DispatchTime.now().uptimeNanoseconds
#endif
        proxy.deleteBackward()
#if DEBUG
        debugProxyMutationNanoseconds += DispatchTime.now().uptimeNanoseconds - mutationStartedAt
#endif
        if hadSelection {
            if !Self.isHostXPCProxy(proxy), let post = proxy.documentContextBeforeInput {
                shadowBeforeInput = post
            } else {
                shadowBeforeInput = expected
            }
        } else if !hasProbedProxySyncMode {
            hasProbedProxySyncMode = true
            if Self.isHostXPCProxy(proxy) {
                proxyIsAsynchronousXPC = true
                shadowBeforeInput = expected
            } else if let post = proxy.documentContextBeforeInput, !pre.isEmpty, post == expected {
                proxyIsAsynchronousXPC = false
                shadowBeforeInput = post
            } else {
                proxyIsAsynchronousXPC = true
                shadowBeforeInput = expected
            }
        } else {
            shadowBeforeInput = expected
        }
        lastShadowMutationTime = now
    }

    /// Notifies the adapter that the host selection may have changed (`selectionWillChange`),
    /// ensuring the next keystroke checks `selectedText` and `documentContextBeforeInput` immediately.
    public func notifySelectionMayHaveChanged() {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        lastShadowMutationTime = 0
        lastSpaceTapTime = 0
        lastSpacePreCommitTail = nil
        justInsertedCandidateWithTrailingSpace = false
    }

    /// Returns `true` when the adapter has a pending first-space or candidate-trailing-space state whose
    /// `shadowBeforeInput` still matches the live `proxy` context (or its lagging XPC pre-space stem),
    /// ensuring delayed UIKit `selectionWillChange` / `textDidChange` XPC callbacks after 120ms do not wipe Double-Space.
    public func isPendingDoubleSpaceContextIntact(
        proxy: TextDocumentProxyProtocol,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        guard !session.isComposing else { return false }
        guard (lastSpaceTapTime > 0 && now - lastSpaceTapTime < 0.70) || justInsertedCandidateWithTrailingSpace else {
            return false
        }
        guard proxy.selectedText?.isEmpty ?? true else { return false }
        guard let shadow = shadowBeforeInput, Self.canApplyDoubleSpacePeriod(to: shadow) else {
            return false
        }
        if let live = proxy.documentContextBeforeInput {
            let shadowTail = String(shadow.suffix(40))
            if Self.canApplyDoubleSpacePeriod(to: live),
               !shadowTail.isEmpty,
               (live.hasSuffix(shadowTail) || shadow.hasSuffix(live)) {
                return true
            }
            if (proxyIsAsynchronousXPC || Self.isHostXPCProxy(proxy)),
               now - lastShadowMutationTime < 0.70,
               Self.isAsyncPendingSpaceStem(live: live, shadowWithSpace: shadow, preCommitTail: lastSpacePreCommitTail) {
                return true
            }
            return false
        }
        return (proxyIsAsynchronousXPC || Self.isHostXPCProxy(proxy)) && (now - lastShadowMutationTime < 0.70)
    }

    /// Handles UIKit's `selectionWillChange` callback. Preserves `lastSpaceTapTime` and
    /// `justInsertedCandidateWithTrailingSpace` across both immediate (< 120ms) and delayed (< 700ms) XPC cursor echoes
    /// when `proxy` confirms the pending space context is still intact, while immediately resetting state on genuine external cursor/selection changes.
    @discardableResult
    public func handleSelectionWillChange(
        isInternalEcho: Bool,
        proxy: TextDocumentProxyProtocol? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        if let proxy = proxy {
            if !(proxy.selectedText?.isEmpty ?? true) {
                notifySelectionMayHaveChanged()
                return false
            }
            if isPendingDoubleSpaceContextIntact(proxy: proxy, now: now) {
                return true
            }
            if isInternalEcho {
                if let shadow = shadowBeforeInput, let live = proxy.documentContextBeforeInput, !live.isEmpty {
                    let shadowTail = String(shadow.suffix(40))
                    if !shadowTail.isEmpty && !live.hasSuffix(shadowTail) && !shadow.hasSuffix(live) &&
                       !Self.isAsyncPendingSpaceStem(live: live, shadowWithSpace: shadow, preCommitTail: lastSpacePreCommitTail) {
                        notifySelectionMayHaveChanged()
                        return false
                    }
                }
                return true
            }
            notifySelectionMayHaveChanged()
            return false
        }
        guard !isInternalEcho else { return true }
        notifySelectionMayHaveChanged()
        return false
    }

    /// Feeds a character from keyboard touch or hardware key into the session
    public func handleCharacter(_ char: Character, proxy: TextDocumentProxyProtocol) {
#if DEBUG
        resetDebugProxyCounts()
#endif
        adapterLock.lock()
        defer { adapterLock.unlock() }
        lastSpaceTapTime = 0
        lastSpacePreCommitTail = nil
        justInsertedCandidateWithTrailingSpace = false

        let now = Date().timeIntervalSince1970
        let inActiveTypingWindow = Self.isHostXPCProxy(proxy) && shadowBeforeInput != nil && (now - lastShadowMutationTime < 0.65)
        let hasActiveSelection = inActiveTypingWindow ? false : !(proxy.selectedText?.isEmpty ?? true)
        if hasActiveSelection {
            proxyIsAsynchronousXPC = false
            lastShadowMutationTime = 0
            let before = proxy.documentContextBeforeInput ?? ""
            shadowBeforeInput = before
            session.reset()
            session.editCaretBack = InputSessionManager.caretDisarmed
            needsContextSync = false

            if let onset = DirectReplacementGuard.extractAdoptableOnsetPrefix(
                beforeCaret: before,
                nextChar: char,
                hasActiveSelection: true,
                charAfterCaret: nil,
                isVNI: session.inputMethod == .vni
            ) {
                // Delete the highlighted partial-word suffix first so subsequent UTF-16 diff
                // replacements operate cleanly on the unselected consonant onset.
                proxyDeleteBackward(proxy: proxy, hadKnownSelection: true)
                session.setCompositionPrefix(onset)
            } else if session.isWordBoundary(char) {
                proxyInsertText(String(char), proxy: proxy)
                return
            }
        } else {
            reconcileIfNeeded(proxy: proxy)
            if !session.isComposing {
                if needsContextSync {
                    syncArmedWordFromContext(proxy: proxy)
                    needsContextSync = false
                }
                if !literalOverrideEnabled,
                   (session.editCaretBack < 0 || session.inputMethod == .vni),
                   !session.precededByTechnicalDelimiter {
                    let before = shadowBeforeInput ?? effectiveContextBeforeInput(proxy: proxy) ?? ""
                    if before.last?.isLetter == true,
                       DirectReplacementGuard.extractAdoptableOnsetPrefix(
                           beforeCaret: before,
                           nextChar: char,
                           hasActiveSelection: false,
                           charAfterCaret: nil,
                           isVNI: session.inputMethod == .vni
                       ) != nil {
                        let charAfterCaret = proxy.documentContextAfterInput?.first
                        if let onset = DirectReplacementGuard.extractAdoptableOnsetPrefix(
                            beforeCaret: before,
                            nextChar: char,
                            hasActiveSelection: false,
                            charAfterCaret: charAfterCaret,
                            isVNI: session.inputMethod == .vni
                        ) {
                            session.setCompositionPrefix(onset)
                        }
                    }
                }
            }
        }

        if session.isWordBoundary(char) {
            commitWord(proxy: proxy, suffix: String(char))
            return
        }

        // Support direct Vietnamese diacritic character selection from long-press callouts
        // (e.g. `đ`, `ă`, `ắ`, `ê`, `ế`, `ể`, `ệ`, `ô`, `ơ`, `ư`).
        // Never allow consecutive accented selections (like `ế` then `ể`, `đ` then `đ`, or `k` then `ă`)
        // to collapse into raw Telex keystrokes (`eeseer`, `dd`, `kaw`).
        if !char.isASCII && char.isLetter {
            let priorComposing = session.isComposing ? session.composingWord : ""
            let candidateWord = priorComposing + String(char)
            let candidateRaw = VietnameseEngine.rawKeys(for: candidateWord, inputMethod: session.inputMethod)

            let probeRendered: String = {
                Self.cachedProbeEngineLock.lock()
                defer { Self.cachedProbeEngineLock.unlock() }
                Self.cachedProbeEngine.inputMethod = session.inputMethod
                Self.cachedProbeEngine.grammarProfile = session.grammarProfile
                Self.cachedProbeEngine.modernOrthography = true
                Self.cachedProbeEngine.simpleTelex = session.simpleTelex
                return Self.cachedProbeEngine.transform(Array(candidateRaw))
            }()

            if probeRendered == candidateWord {
                let priorDisplayed: String? = session.isComposing ? priorComposing : nil
                session.setCompositionPrefix(candidateWord)
                session.hasExplicitAccentSelection = true
                if let priorDisplayed {
                    let backspaces = priorDisplayed.utf16.count
                    performReplace(backspaces: backspaces, text: candidateWord, priorDisplayed: priorDisplayed, proxy: proxy)
                } else {
                    proxyInsertText(String(char), proxy: proxy)
                }
                return
            }

            // `candidateWord` is not a single valid syllable (e.g. `ế` + `ể` -> `ếể`, `đ` + `đ` -> `đđ`, `k` + `ă` -> `kă`):
            // Commit `priorComposing` as-is on screen (without English revert) and start fresh from `char`.
            if session.isComposing {
                session.appendContext(priorComposing)
                session.engine.commitWord(raw: priorComposing, rendered: priorComposing)
                session.reset()
            }

            let singleCharStr = String(char)
            let singleRaw = VietnameseEngine.rawKeys(for: singleCharStr, inputMethod: session.inputMethod)
            let singleProbe: String = {
                Self.cachedProbeEngineLock.lock()
                defer { Self.cachedProbeEngineLock.unlock() }
                return Self.cachedProbeEngine.transform(Array(singleRaw))
            }()
            if singleProbe == singleCharStr {
                session.setCompositionPrefix(singleCharStr)
                session.hasExplicitAccentSelection = true
            } else {
                session.reset()
            }
            proxyInsertText(singleCharStr, proxy: proxy)
            return
        }

        let priorDisplayed: String? = session.isComposing
            ? session.composingWord
            : (session.editCaretBack == 0 ? session.engine.lastCommittedWord : nil)

        let action = session.handleCharacter(char)
        if session.lastFeedWasRejectedNoOp {
            onRejectedKeyFeedback?(char)
        }
        applyAction(action, priorDisplayed: priorDisplayed, proxy: proxy)
    }

    /// Feeds a character literally into the active composition without Telex/VNI transformation
    /// (e.g. from long-press literal selection or `ABC` override mode), without requiring Space + Backspace.
    public func handleLiteralCharacter(_ char: Character, proxy: TextDocumentProxyProtocol) {
#if DEBUG
        resetDebugProxyCounts()
#endif
        adapterLock.lock()
        defer { adapterLock.unlock() }
        lastSpaceTapTime = 0
        lastSpacePreCommitTail = nil
        justInsertedCandidateWithTrailingSpace = false
        reconcileIfNeeded(proxy: proxy)
        if !session.isComposing && needsContextSync {
            syncArmedWordFromContext(proxy: proxy)
            needsContextSync = false
        }

        if session.isWordBoundary(char) {
            commitWord(proxy: proxy, suffix: String(char))
            return
        }

        if !char.isASCII && char.isLetter {
            handleCharacter(char, proxy: proxy)
            return
        }

        let priorDisplayed: String? = session.isComposing ? session.composingWord : nil
        let action = session.handleLiteralCharacter(char)
        applyAction(action, priorDisplayed: priorDisplayed, proxy: proxy)
    }

    /// Handles the backspace/delete tap
    public func handleBackspace(proxy: TextDocumentProxyProtocol) {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        lastSpaceTapTime = 0
        lastSpacePreCommitTail = nil
        justInsertedCandidateWithTrailingSpace = false
        let inActiveTypingWindow = Self.isHostXPCProxy(proxy) && shadowBeforeInput != nil && (Date().timeIntervalSince1970 - lastShadowMutationTime < 0.65)
        if !inActiveTypingWindow && !(proxy.selectedText?.isEmpty ?? true) {
            session.reset()
            session.editCaretBack = InputSessionManager.caretDisarmed
            proxyDeleteBackward(proxy: proxy, hadKnownSelection: true)
            syncArmedWordFromContext(proxy: proxy)
            needsContextSync = false
            return
        }
        reconcileIfNeeded(proxy: proxy)
        if !session.isComposing && needsContextSync {
            syncArmedWordFromContext(proxy: proxy)
            needsContextSync = false
        }

        let priorDisplayed: String? = session.isComposing
            ? session.composingWord
            : (session.editCaretBack == 0 ? session.engine.lastCommittedWord : nil)

        let action = session.handleBackspace()
        switch action {
        case .replace(let backspaces, let text):
            performReplace(backspaces: backspaces, text: text, priorDisplayed: priorDisplayed, proxy: proxy)
        case .reset:
            proxyDeleteBackward(proxy: proxy)
        case .passThrough:
            proxyDeleteBackward(proxy: proxy)
        default:
            break
        }

        if !session.isComposing {
            syncArmedWordFromContext(proxy: proxy)
            needsContextSync = false
        }
    }

    /// Commits the active composition word (e.g. on Space, Return, or Punctuation)
    public func commitWord(proxy: TextDocumentProxyProtocol, suffix: String = "") {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        needsContextSync = false
        let boundaryChar = suffix.first
        guard session.isComposing else {
            _ = session.commitWord(
                smartBilingualEnabled: smartBilingual,
                genZMode: genZMode,
                boundaryChar: boundaryChar
            )
            session.editCaretBack = InputSessionManager.caretDisarmed
            if !suffix.isEmpty {
                proxyInsertText(suffix, proxy: proxy)
            }
            return
        }

        let priorDisplayed = session.composingWord
        let action = session.commitWord(
            smartBilingualEnabled: smartBilingual,
            genZMode: genZMode,
            boundaryChar: boundaryChar
        )
        applyAction(action, priorDisplayed: priorDisplayed, proxy: proxy, suffix: suffix)
    }

    /// Explicitly selects an active composition candidate (e.g. toggling between provisional `"mix"` and `"mĩ"`,
    /// or `"of"` and `"ò"`) without committing a trailing space, locking explicit selection stability so subsequent
    /// keys respect the chosen interpretation (`select("mĩ") + x -> "mix"` vs `select("or") + m -> "orm"`).
    public func selectCompositionCandidate(_ candidate: String, proxy: TextDocumentProxyProtocol) {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        needsContextSync = false
        let priorDisplayed = session.isComposing ? session.composingWord : nil
        let action = session.selectCompositionCandidate(candidate)
        applyAction(action, priorDisplayed: priorDisplayed, proxy: proxy)
    }

    /// Commits a selected candidate from the suggestion bar and records its trailing token for post-commit editing.
    public func commitCandidate(_ candidate: String, proxy: TextDocumentProxyProtocol, trailingSpace: Bool = true) {
        let mode: SuggestionReplacementMode = session.isComposing ? .replaceComposing : .appendNextWord
        let item = SuggestionCandidate(
            displayText: candidate,
            insertionText: candidate,
            replacementMode: mode,
            source: .compoundCompletion,
            score: 1.0
        )
        commitSuggestion(item, proxy: proxy, trailingSpace: trailingSpace)
    }

    /// Commits a structured `SuggestionCandidate` according to its `replacementMode`, preventing duplicate word insertion.
    public func commitSuggestion(_ candidate: SuggestionCandidate, proxy: TextDocumentProxyProtocol, trailingSpace: Bool = true) {
        needsContextSync = false
        let savedPendingDotPrefix = session.pendingDotPrefix
        session.pendingDotPrefix = nil
        session.activeDotPrefix = nil
        session.pendingSpacePrefix = nil
        session.activeSpacePrefix = nil
        let effectiveTrailingSpace = (candidate.replacementMode == .appendDirectNoSpace) ? false : trailingSpace
        let suffix = effectiveTrailingSpace ? " " : ""
        let targetText = candidate.insertionText

        switch candidate.replacementMode {
        case .keepComposing, .replaceComposing, .macroExpansion:
            if session.isComposing {
                let priorDisplayed = session.composingWord
                let backspaces = priorDisplayed.utf16.count
                performReplace(backspaces: backspaces, text: targetText + suffix, priorDisplayed: priorDisplayed, proxy: proxy)
                session.reset()
            } else {
                proxyInsertText(targetText + suffix, proxy: proxy)
            }
        case .appendNextWord:
            if session.isComposing {
                let priorDisplayed = session.composingWord
                let backspaces = priorDisplayed.utf16.count
                performReplace(backspaces: backspaces, text: targetText + suffix, priorDisplayed: priorDisplayed, proxy: proxy)
                session.reset()
            } else {
                // Ensure there is a space before appending if the preceding character is a letter
                if let before = effectiveContextBeforeInput(proxy: proxy), let lastChar = before.last, !lastChar.isWhitespace {
                    proxyInsertText(" " + targetText + suffix, proxy: proxy)
                } else {
                    proxyInsertText(targetText + suffix, proxy: proxy)
                }
            }
        case .appendDirectNoSpace:
            if session.isComposing {
                let priorDisplayed = session.composingWord
                let rawASCII = session.rawWord.isEmpty ? priorDisplayed : session.rawWord
                let backspaces = priorDisplayed.utf16.count
                if WordSuggestionEngine.closingBracketTokens.contains(targetText) {
                    // User was composing inside `(việt` and tapped `)` -> keep `việt` and append `)` directly
                    performReplace(backspaces: backspaces, text: priorDisplayed + targetText, priorDisplayed: priorDisplayed, proxy: proxy)
                } else if targetText.hasPrefix(".") || targetText.hasPrefix("@") || targetText.hasPrefix("/") {
                    // User was typing the stem before `.com` / `@gmail.com` / `/` (e.g. `vnexpress` + `.net` -> `vnexpress.net`)
                    let cleanStem: String = {
                        if let lead = targetText.first, rawASCII.last == lead {
                            return String(rawASCII.dropLast())
                        }
                        return rawASCII
                    }()
                    performReplace(backspaces: backspaces, text: cleanStem + targetText, priorDisplayed: priorDisplayed, proxy: proxy)
                } else if let atIndex = rawASCII.lastIndex(of: "@"), !targetText.contains("@") {
                    let prefixThroughAt = String(rawASCII[...atIndex])
                    performReplace(backspaces: backspaces, text: prefixThroughAt + targetText, priorDisplayed: priorDisplayed, proxy: proxy)
                } else {
                    performReplace(backspaces: backspaces, text: targetText, priorDisplayed: priorDisplayed, proxy: proxy)
                }
                session.reset()
            } else {
                let before = effectiveContextBeforeInput(proxy: proxy) ?? ""
                if WordSuggestionEngine.closingBracketTokens.contains(targetText),
                   justInsertedCandidateWithTrailingSpace,
                   before.hasSuffix(" ") {
                    performReplace(backspaces: 1, text: targetText, priorDisplayed: " ", proxy: proxy)
                } else if targetText.hasPrefix("."),
                   let dotPrefix = savedPendingDotPrefix,
                   dotPrefix.raw != dotPrefix.rendered,
                   before.hasSuffix(dotPrefix.rendered + ".") {
                    let backspaces = dotPrefix.rendered.utf16.count + 1
                    performReplace(backspaces: backspaces, text: dotPrefix.raw + targetText, priorDisplayed: dotPrefix.rendered + ".", proxy: proxy)
                } else if let lead = targetText.first, [".", "@", "/"].contains(lead), before.last == lead {
                    proxyInsertText(String(targetText.dropFirst()), proxy: proxy)
                } else if !WordSuggestionEngine.closingBracketTokens.contains(targetText),
                          !targetText.contains("@"),
                          !targetText.hasPrefix("."),
                          !targetText.hasPrefix("/"),
                          before.last?.isWhitespace != true,
                          let lastToken = before.split(whereSeparator: \.isWhitespace).last,
                          let atIdx = lastToken.lastIndex(of: "@") {
                    let afterAt = String(lastToken[lastToken.index(after: atIdx)...])
                    if !afterAt.isEmpty, targetText.lowercased().hasPrefix(afterAt.lowercased()) {
                        performReplace(backspaces: afterAt.utf16.count, text: targetText, priorDisplayed: afterAt, proxy: proxy)
                    } else {
                        proxyInsertText(targetText, proxy: proxy)
                    }
                } else {
                    proxyInsertText(targetText, proxy: proxy)
                }
            }
        }

        let tokens = targetText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for tok in tokens {
            session.appendContext(tok)
        }
        if let lastToken = tokens.last, !lastToken.isEmpty {
            let isMacroOrKeep = (candidate.replacementMode == .macroExpansion || candidate.replacementMode == .keepComposing || candidate.replacementMode == .appendDirectNoSpace)
            let raw = VietnameseEngine.rawKeys(for: lastToken, inputMethod: session.inputMethod)
            session.engine.commitWord(raw: raw, rendered: lastToken, isOfficialSuggestion: !isMacroOrKeep)
        }
        session.editCaretBack = effectiveTrailingSpace ? -1 : InputSessionManager.caretDisarmed
        lastSpaceTapTime = 0
        justInsertedCandidateWithTrailingSpace = effectiveTrailingSpace
    }

    /// Synchronizes session state when the host app externally changes selection or clears the text field.
    public func handleExternalTextChange(proxy: TextDocumentProxyProtocol) {
        finishMarkedComposition(proxy: proxy)
        adapterLock.lock()
        defer { adapterLock.unlock() }
        proxyIsAsynchronousXPC = false
        lastShadowMutationTime = 0
        lastSpaceTapTime = 0
        justInsertedCandidateWithTrailingSpace = false
        let priorPendingDot = session.pendingDotPrefix
        let priorPendingSpace = session.pendingSpacePrefix
        session.pendingDotPrefix = nil
        session.activeDotPrefix = nil
        session.pendingSpacePrefix = nil
        session.activeSpacePrefix = nil
        let rawBefore = proxy.documentContextBeforeInput
        shadowBeforeInput = rawBefore
        let before = rawBefore ?? ""
        if session.isComposing {
            // If the host app transiently reports nil context over XPC, do not kill an active composition.
            guard rawBefore != nil else { return }
            let composing = session.composingWord
            let normalizedBefore = before.precomposedStringWithCanonicalMapping
            let normalizedComposing = composing.precomposedStringWithCanonicalMapping
            if normalizedComposing.isEmpty || !normalizedBefore.hasSuffix(normalizedComposing) {
                session.reset()
                if before.isEmpty {
                    session.engine.clearHistory()
                    session.clearContext()
                }
            }
        }
        if !session.isComposing {
            if !before.isEmpty {
                let words = before
                    .components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                    .filter { !$0.isEmpty && $0.contains(where: { $0.isLetter }) }
                session.context = words.suffix(3).joined(separator: " ")
                let normalizedBefore = before.precomposedStringWithCanonicalMapping
                if let pendingSpace = priorPendingSpace,
                   normalizedBefore.hasSuffix((pendingSpace.rendered + " ").precomposedStringWithCanonicalMapping) {
                    session.pendingSpacePrefix = pendingSpace
                }
                if let pendingDot = priorPendingDot,
                   normalizedBefore.hasSuffix((pendingDot.rendered + ".").precomposedStringWithCanonicalMapping) {
                    session.pendingDotPrefix = pendingDot
                }
            } else {
                session.engine.clearHistory()
                session.clearContext()
            }
            syncArmedWordFromContext(proxy: proxy)
            needsContextSync = (rawBefore == nil)
        }
    }

    /// Returns `true` iff `contextBefore` ends with a single space (`" "`) immediately preceded by a non-whitespace,
    /// non-sentence-punctuation character eligible for the double-space period shortcut (`". "`).
    public static func canApplyDoubleSpacePeriod(to contextBefore: String) -> Bool {
        guard contextBefore.hasSuffix(" "),
              !contextBefore.hasSuffix("  "),
              let charBeforeSpace = contextBefore.dropLast().last,
              !charBeforeSpace.isWhitespace,
              ![".", "!", "?", ",", ";", ":"].contains(charBeforeSpace) else {
            return false
        }
        return true
    }

    /// Verifies whether a live `documentContextBeforeInput` snapshot that does not yet include the trailing `" "`
    /// is a genuine lagging XPC echo of `shadowWithSpace` (supporting both short buffers, >240-byte truncated 80-char
    /// shadow buffers, and word-commit overrides), while rejecting external host mutations such as `"hello "` -> `"helloX"`.
    public static func isAsyncPendingSpaceStem(
        live: String,
        shadowWithSpace: String,
        preCommitTail: String? = nil
    ) -> Bool {
        guard !live.isEmpty, shadowWithSpace.hasSuffix(" ") else { return false }
        let shadowStem = String(shadowWithSpace.dropLast())
        guard !shadowStem.isEmpty else { return false }
        if shadowStem.hasSuffix(live) {
            return true
        }
        let shadowStemTail = String(shadowStem.suffix(40))
        if !shadowStemTail.isEmpty && live.hasSuffix(shadowStemTail) {
            return true
        }
        if let rawTail = preCommitTail, !rawTail.isEmpty, live.hasSuffix(rawTail) {
            return true
        }
        return false
    }

    /// Synchronously deletes a single trailing space before punctuation (e.g. after selecting a suggestion candidate)
    /// while keeping the adapter's XPC shadow buffer in sync. Returns `true` if a trailing space was verified and deleted.
    @discardableResult
    public func deleteTrailingSpaceBeforePunctuation(proxy: TextDocumentProxyProtocol) -> Bool {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        if !(proxy.selectedText?.isEmpty ?? true) {
            return false
        }
        if let live = proxy.documentContextBeforeInput {
            let asyncPendingSpace: Bool
            if (proxyIsAsynchronousXPC || Self.isHostXPCProxy(proxy)),
               let shadow = shadowBeforeInput,
               shadow.hasSuffix(" "),
               Date().timeIntervalSince1970 - lastShadowMutationTime < 0.70,
               Self.isAsyncPendingSpaceStem(live: live, shadowWithSpace: shadow, preCommitTail: lastSpacePreCommitTail) {
                asyncPendingSpace = true
            } else {
                asyncPendingSpace = false
            }
            guard live.hasSuffix(" ") || asyncPendingSpace else {
                shadowBeforeInput = live
                return false
            }
        } else {
            guard shadowBeforeInput?.hasSuffix(" ") == true else {
                return false
            }
        }
        proxyDeleteBackward(proxy: proxy)
        lastSpacePreCommitTail = nil
        session.editCaretBack = InputSessionManager.caretDisarmed
        session.pendingDotPrefix = nil
        session.activeDotPrefix = nil
        session.pendingSpacePrefix = nil
        session.activeSpacePrefix = nil
        return true
    }

    /// Executes the double-space auto-period shortcut (`" " -> ". "`) while keeping the adapter's XPC shadow buffer
    /// in sync and distinguishing auto-inserted sentence periods from directly typed `.` characters.
    /// Verifies against live/shadow context so stale cache state (e.g. host mutated `"hello "` to `"helloX"`) never deletes a non-space character.
    @discardableResult
    public func applyDoubleSpacePeriodShortcut(
        proxy: TextDocumentProxyProtocol,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        guard !session.isComposing else { return false }
        if !(proxy.selectedText?.isEmpty ?? true) {
            return false
        }
        if let live = proxy.documentContextBeforeInput {
            if Self.canApplyDoubleSpacePeriod(to: live) {
                if live.utf8.count > 240 {
                    shadowBeforeInput = String(live.suffix(80))
                } else {
                    shadowBeforeInput = live
                }
            } else if (proxyIsAsynchronousXPC || Self.isHostXPCProxy(proxy)),
                      let shadow = shadowBeforeInput,
                      Self.canApplyDoubleSpacePeriod(to: shadow),
                      now - lastShadowMutationTime < 0.70,
                      Self.isAsyncPendingSpaceStem(live: live, shadowWithSpace: shadow, preCommitTail: lastSpacePreCommitTail) {
                // Async XPC has not yet echoed the first space insertion, and `live` still matches the pre-space stem.
            } else {
                shadowBeforeInput = live
                return false
            }
        } else {
            guard let shadow = shadowBeforeInput, Self.canApplyDoubleSpacePeriod(to: shadow) else {
                return false
            }
        }
        proxyDeleteBackward(proxy: proxy)
        proxyInsertText(". ", proxy: proxy)
        lastSpacePreCommitTail = nil
        session.editCaretBack = InputSessionManager.caretDisarmed
        session.pendingDotPrefix = nil
        session.activeDotPrefix = nil
        session.pendingSpacePrefix = nil
        session.activeSpacePrefix = nil
        return true
    }

    /// Unified Spacebar tap state machine shared between `KeyboardViewController` and unit tests:
    /// - Converts a second Space tap within `0.70s` into `". "` when `periodShortcutEnabled` and verified by `applyDoubleSpacePeriodShortcut`.
    /// - Absorbs the first Space tap immediately after a candidate/glide insertion that already appended a trailing space (`" "`),
    ///   arming `lastSpaceTapTime` without inserting a duplicate `"  "`.
    /// - Otherwise commits the active composition word (or inserts `" "` when idle) and arms `lastSpaceTapTime`.
    @discardableResult
    public func handleSpaceTap(
        proxy: TextDocumentProxyProtocol,
        periodShortcutEnabled: Bool = true,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SpaceTapOutcome {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        let wasCandidateTrailingSpace = justInsertedCandidateWithTrailingSpace
        justInsertedCandidateWithTrailingSpace = false

        if periodShortcutEnabled &&
           !session.isComposing &&
           now - lastSpaceTapTime < 0.70 &&
           applyDoubleSpacePeriodShortcut(proxy: proxy, now: now) {
            lastSpaceTapTime = 0
            return .insertedPeriodShortcut
        }

        lastSpaceTapTime = now
        if wasCandidateTrailingSpace && !session.isComposing {
            lastShadowMutationTime = now
            return .absorbedAfterCandidateTrailingSpace
        }

        if session.isComposing {
            let priorComposing = session.composingWord
            lastSpacePreCommitTail = priorComposing
            commitWord(proxy: proxy, suffix: " ")
            lastShadowMutationTime = now
            let lastCommitted = session.engine.lastCommittedWord ?? ""
            let finalWord = lastCommitted.isEmpty ? priorComposing : lastCommitted
            return .committedComposingWord(finalWord)
        } else {
            lastSpacePreCommitTail = nil
            commitWord(proxy: proxy, suffix: " ")
            lastShadowMutationTime = now
            return .insertedSpace
        }
    }

    /// Reconstructs and arms the word immediately preceding the cursor in `documentContextBeforeInput`
    /// when idle, enabling seamless post-commit tone edits and backspacing after cursor movement or multi-word deletion.
    private func syncArmedWordFromContext(proxy: TextDocumentProxyProtocol) {
        guard !session.isComposing,
              let before = shadowBeforeInput ?? effectiveContextBeforeInput(proxy: proxy) else {
            if !session.isComposing {
                session.editCaretBack = InputSessionManager.caretDisarmed
            }
            return
        }
        guard !before.isEmpty else {
            session.engine.clearHistory()
            session.clearContext()
            session.editCaretBack = InputSessionManager.caretDisarmed
            return
        }
        if session.context.isEmpty {
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
            if !words.isEmpty {
                session.context = words.suffix(3).joined(separator: " ")
            }
        }
        guard let lastChar = before.last, lastChar.isLetter else {
            session.editCaretBack = InputSessionManager.caretDisarmed
            return
        }
        let trailingLetters = before.reversed().prefix(while: { $0.isLetter })
        let trailingWord = String(trailingLetters.reversed())
        guard !trailingWord.isEmpty, trailingWord.count <= 15 else {
            session.editCaretBack = InputSessionManager.caretDisarmed
            return
        }
        if !(session.engine.lastCommittedWord?.unicodeScalars.elementsEqual(trailingWord.unicodeScalars) ?? false) {
            let raw = VietnameseEngine.rawKeys(for: trailingWord, inputMethod: session.inputMethod)
            session.engine.commitWord(raw: raw, rendered: trailingWord)
        }
        session.editCaretBack = 0
    }

    /// Minimizes `deleteBackward()` + `insertText()` calls by stripping the common prefix
    /// using the in-memory `priorDisplayed` word first (zero XPC latency), falling back to `documentContextBeforeInput` only if needed.
    private func performReplace(backspaces: Int, text: String, priorDisplayed: String? = nil, proxy: TextDocumentProxyProtocol) {
        if applyMarkedReplacement(backspaces: backspaces, text: text, priorDisplayed: priorDisplayed, proxy: proxy) { return }
        finishMarkedComposition(proxy: proxy)
        if backspaces == 0 {
            if !text.isEmpty {
                proxyInsertText(text, proxy: proxy)
            }
            return
        }

        if let prior = priorDisplayed,
           let replaceStartIdx = Self.characterIndex(in: prior, trailingUTF16Count: backspaces) {
            let oldSlice = prior[replaceStartIdx...]
            var oldIdx = oldSlice.startIndex
            var newIdx = text.startIndex
            while oldIdx < oldSlice.endIndex && newIdx < text.endIndex &&
                  oldSlice[oldIdx] == text[newIdx] &&
                  oldSlice[oldIdx].unicodeScalars.elementsEqual(text[newIdx].unicodeScalars) {
                oldIdx = oldSlice.index(after: oldIdx)
                newIdx = text.index(after: newIdx)
            }
            let effectiveBackspaces = oldSlice[oldIdx...].count
            let effectiveText = String(text[newIdx...])
            for _ in 0..<effectiveBackspaces {
                proxyDeleteBackward(proxy: proxy)
            }
            if !effectiveText.isEmpty {
                proxyInsertText(effectiveText, proxy: proxy)
            }
            return
        }

        if let before = shadowBeforeInput ?? effectiveContextBeforeInput(proxy: proxy),
           let replaceStartIdx = Self.characterIndex(in: before, trailingUTF16Count: backspaces) {
            let oldSlice = before[replaceStartIdx...]
            var oldIdx = oldSlice.startIndex
            var newIdx = text.startIndex
            while oldIdx < oldSlice.endIndex && newIdx < text.endIndex &&
                  oldSlice[oldIdx] == text[newIdx] &&
                  oldSlice[oldIdx].unicodeScalars.elementsEqual(text[newIdx].unicodeScalars) {
                oldIdx = oldSlice.index(after: oldIdx)
                newIdx = text.index(after: newIdx)
            }
            let effectiveBackspaces = oldSlice[oldIdx...].count
            let effectiveText = String(text[newIdx...])
            for _ in 0..<effectiveBackspaces {
                proxyDeleteBackward(proxy: proxy)
            }
            if !effectiveText.isEmpty {
                proxyInsertText(effectiveText, proxy: proxy)
            }
            return
        }

        for _ in 0..<backspaces {
            proxyDeleteBackward(proxy: proxy)
        }
        if !text.isEmpty {
            proxyInsertText(text, proxy: proxy)
        }
    }

    private static func characterIndex(in string: String, trailingUTF16Count: Int) -> String.Index? {
        guard trailingUTF16Count > 0 else { return string.endIndex }
        var remaining = trailingUTF16Count
        var idx = string.endIndex
        while remaining > 0 && idx > string.startIndex {
            idx = string.index(before: idx)
            let unitCount = string[idx].utf16.count
            remaining -= unitCount
        }
        return remaining == 0 ? idx : nil
    }

    private func applyAction(_ action: SessionAction, priorDisplayed: String? = nil, proxy: TextDocumentProxyProtocol, suffix: String = "") {
        switch action {
        case .replace(let backspaces, let text):
            performReplace(backspaces: backspaces, text: text, priorDisplayed: priorDisplayed, proxy: proxy)
        case .commit(let backspaces, let text, let isOverride):
            if markedWord != nil {
                if isOverride { performReplace(backspaces: backspaces, text: text, priorDisplayed: priorDisplayed, proxy: proxy) }
                finishMarkedComposition(proxy: proxy)
                if !suffix.isEmpty { proxyInsertText(suffix, proxy: proxy) }
                return
            }
            if isOverride {
                performReplace(backspaces: backspaces, text: text, priorDisplayed: priorDisplayed, proxy: proxy)
            }
            if !suffix.isEmpty {
                proxyInsertText(suffix, proxy: proxy)
            }
        case .reset:
            break
        case .passThrough, .consumed:
            break
        }
    }
}
#endif
