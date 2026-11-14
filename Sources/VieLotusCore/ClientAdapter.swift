import Foundation
#if canImport(AppKit)
import AppKit
#endif

@frozen public enum AppCategory: Sendable, Equatable {
    case standardAppKit
    case chromium
    case msOffice
    case terminal
    case overlay
    case remoteOrVirtualMachine
    case unknown
}

@frozen public enum PresentationMode: Sendable, Equatable {
    case directReplacement
    case markedText
    case terminalDirect
    case passthrough
}

@frozen public enum PresentationModeSource: Sendable, Equatable {
    case appOverride(PresentationModePreference)
    case globalPreference(PresentationModePreference)
    case rulesFile(PresentationModePreference)
    case dynamicFallback
    case categoryHeuristic(AppCategory)
}

@frozen public enum PresentationModePreference: String, CaseIterable, Sendable, Identifiable {
    case automatic
    case directReplacement
    case markedText
    case passthrough

    public var id: String { rawValue }
}

public struct ClientAdapter {
    /// Resolves a client identifier, falling back to `NSWorkspace.shared.frontmostApplication`
    /// executable or localized name when an unbundled process (e.g. `qemu-system-aarch64` Android Emulator)
    /// returns `nil` for `IMKTextInput.bundleIdentifier()`.
    public static func resolveBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        if let id = bundleIdentifier, !id.isEmpty {
            return id
        }
        #if canImport(AppKit)
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            if let bundleID = frontmost.bundleIdentifier, !bundleID.isEmpty {
                return bundleID
            }
            if let execName = frontmost.executableURL?.lastPathComponent, !execName.isEmpty {
                return execName
            }
            if let localName = frontmost.localizedName, !localName.isEmpty {
                return localName
            }
        }
        #endif
        return bundleIdentifier
    }

    public static func classify(bundleIdentifier: String?) -> AppCategory {
        guard let id = bundleIdentifier?.lowercased(), !id.isEmpty else {
            return .unknown
        }

        // Remote Desktop, Screen Sharing, Emulator & Virtual Machine apps:
        // Remote targets and device emulators handle their own IME / keyboard layout or forward raw scancodes.
        if id.contains("com.microsoft.rdc") ||
           id.contains("jump.mac.viewer") ||
           id.contains("apple.remotedesktop") ||
           id.contains("teamviewer") ||
           id.contains("anydesk") ||
           id.contains("parsec") ||
           id.contains("moonlight") ||
           id.contains("deskin") ||
           id.contains("youqu.todesk") ||
           (id.contains("todesk") && !id.contains("todesktop")) ||
           id.contains("sunlogin") ||
           id.contains("nomachine") ||
           id.contains("realvnc") ||
           id.contains("vmware") ||
           id.contains("parallels") ||
           id.contains("utmapp") ||
           id.contains("virtualbox") ||
           id.contains("qemu") ||
           id.contains("android.emulator") ||
           id.contains("iphonesimulator") ||
           id.contains("vnc") ||
           id.contains("citrix") ||
           id.contains("rustdesk") ||
           id.contains("splashtop") ||
           id.contains("screens") {
            return .remoteOrVirtualMachine
        }

        // Terminal / Console emulators: use prefix, domain components, or exact match
        if id == "com.apple.terminal" ||
           id.contains(".iterm") ||
           id.contains(".alacritty") ||
           id.contains(".kitty") ||
           id.contains(".ghostty") ||
           id.contains(".wezterm") ||
           id.contains("warp-terminal") ||
           id.contains(".warp") ||
           id.contains(".rio") ||
           id.contains(".hyper") ||
           id.contains(".tabby") ||
           id.hasSuffix(".terminal") {
            return .terminal
        }

        // Quick search / Overlay apps
        if id.contains("spotlight") ||
           id.contains("raycast") ||
           id.contains("alfred") ||
           id.contains("launchbar") ||
           id.contains("quicksilver") ||
           id.contains("sol-app") {
            return .overlay
        }

        // Microsoft Office
        if id.contains("com.microsoft.word") ||
           id.contains("com.microsoft.excel") ||
           id.contains("com.microsoft.powerpoint") ||
           id.contains("com.microsoft.onenote") ||
           id.contains("com.microsoft.outlook") {
            return .msOffice
        }

        // Chromium / Electron / CEF apps
        if id.contains("chrome") ||
           id.contains("brave") ||
           id.contains("edgemac") ||
           id.contains("microsoft-edge") ||
           id.contains("chromium") ||
           id.contains("thebrowser") ||
           id.contains("opera") ||
           id.contains("vivaldi") ||
           id.contains("vscode") ||
           id.contains("cursor") ||
           id.contains("windsurf") ||
           id.contains("electron") ||
           id.contains("slack") ||
           id.contains("discord") ||
           id.contains("notion") ||
           id.contains("obsidian") ||
           id.contains("logseq") ||
           id.contains("linear") ||
           id.contains("figma") ||
           id.contains("zalo") ||
           id.contains("telegram") ||
           id.contains("teams") ||
           id.contains("skype") ||
           id.contains("whatsapp") ||
           id.contains("messenger") ||
           id.contains("viber") ||
           id.contains("signal") ||
           id.contains("codex") ||
           id.contains("antigravity") ||
           id.contains("orca") ||
           id.contains("stablyai") ||
           id.contains("claude") ||
           id.contains("anthropic") ||
           id.contains("chatgpt") ||
           id.contains("openai") ||
           id.contains("trae") ||
           id.contains("genoffice") ||
           id.contains("nidooffice") ||
           id.contains("postman") {
            // Zalo, Telegram, Slack, VSCode, Orca, Cursor, GenOffice/NidoOffice, etc. use CEF/Electron/Chromium
            return .chromium
        }

        if id.contains("safari") ||
           id.contains("apple.notes") ||
           id.contains("apple.mail") ||
           id.contains("apple.iwork") ||
           id.contains("apple.dt.xcode") ||
           id.contains("apple.textedit") ||
           id.contains("apple.finder") ||
           id.contains("jetbrains") ||
           id.contains("android.studio") ||
           id.contains("sublimetext") ||
           id.contains("firefox") ||
           id.contains("dev.zed") {
            return .standardAppKit
        }

        #if canImport(AppKit)
        if isCachedElectronOrChromiumApp(bundleIdentifier: id) {
            return .chromium
        }
        #endif

        return .standardAppKit
    }

    /// Pre-warms runtime framework classification (`Electron Framework.framework` / `CEF`)
    /// on focus change (`activateServer`) so `classify(bundleIdentifier:)` on the keystroke
    /// path never performs filesystem probes (`fileExists`).
    public static func prewarmBundleClassification(bundleIdentifier: String?) {
        #if canImport(AppKit)
        guard let rawID = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty else { return }
        let id = rawID.lowercased()
        if id.hasPrefix("com.apple.") || id.hasPrefix("org.vielotus.") {
            return
        }
        _ = probeElectronOrChromiumAppOnFocus(bundleIdentifier: id)
        #endif
    }

    #if canImport(AppKit)
    private static let appFrameworkCheckLock = NSLock()
    private static var isChromiumAppCache: [String: Bool] = [:]

    private static func isCachedElectronOrChromiumApp(bundleIdentifier: String) -> Bool {
        appFrameworkCheckLock.lock()
        let cached = isChromiumAppCache[bundleIdentifier] ?? false
        appFrameworkCheckLock.unlock()
        return cached
    }

    private static func probeElectronOrChromiumAppOnFocus(bundleIdentifier: String) -> Bool {
        appFrameworkCheckLock.lock()
        if let cached = isChromiumAppCache[bundleIdentifier] {
            appFrameworkCheckLock.unlock()
            return cached
        }
        appFrameworkCheckLock.unlock()

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        var isChromium = false
        let fileManager = FileManager.default

        for app in running {
            guard let bundleURL = app.bundleURL else { continue }
            let frameworksURL = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
            let electronPath = frameworksURL.appendingPathComponent("Electron Framework.framework").path
            let cefPath = frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework").path
            if fileManager.fileExists(atPath: electronPath) || fileManager.fileExists(atPath: cefPath) {
                isChromium = true
                break
            }
        }

        appFrameworkCheckLock.lock()
        isChromiumAppCache[bundleIdentifier] = isChromium
        appFrameworkCheckLock.unlock()
        return isChromium
    }
    #endif

    private static let dynamicModeLock = NSLock()
    private static var dynamicMarkedTextBundles: Set<String> = []

    // MARK: - Data-driven rules (`typing-modes.yml`)

    private static let rulesLock = NSLock()
    private static var storedRules: PresentationRuleSet = .empty
    private static var rulesLoaded = false
    private static var rulesFileURL: URL?
    private static var rulesFileModificationDate: Date?

    /// Per-app rules loaded from `typing-modes.yml`, resolved lazily on first use.
    public static var presentationRules: PresentationRuleSet {
        rulesLock.lock()
        if !rulesLoaded {
            rulesLock.unlock()
            return reloadPresentationRules()
        }
        defer { rulesLock.unlock() }
        return storedRules
    }

    /// Re-reads `typing-modes.yml` from disk. Call after editing the file so a new rule
    /// takes effect without relaunching the input method.
    @discardableResult
    public static func reloadPresentationRules() -> PresentationRuleSet {
        let resolved = PresentationRulesLoader.load()
        let snapshot = resolved?.rules ?? PresentationRuleSet.empty
        rulesLock.lock()
        rulesLoaded = true
        storedRules = snapshot
        rulesFileURL = resolved?.url
        rulesFileModificationDate = resolved.flatMap { PresentationRulesLoader.modificationDate(of: $0.url) }
        rulesLock.unlock()
        return snapshot
    }

    /// Re-reads the rule file only when it actually changed on disk.
    ///
    /// Costs one `stat` per call, so it is safe on a focus change (`activateServer`) and
    /// must never be called from the keystroke path. This is what makes "edit a line,
    /// switch app, retest" work without a rebuild.
    public static func reloadPresentationRulesIfChanged() {
        let resolvedURL = PresentationRulesLoader.resolvedURL()
        let resolvedModificationDate = resolvedURL.flatMap { PresentationRulesLoader.modificationDate(of: $0) }

        rulesLock.lock()
        let unchanged = rulesLoaded
            && resolvedURL == rulesFileURL
            && resolvedModificationDate == rulesFileModificationDate
        rulesLock.unlock()

        if unchanged { return }
        reloadPresentationRules()
    }

    /// Installs a rule set directly. Used by tests and by the diagnostics app.
    public static func setPresentationRules(_ rules: PresentationRuleSet) {
        rulesLock.lock()
        rulesLoaded = true
        storedRules = rules
        rulesLock.unlock()
    }

    public static func forceMarkedText(for bundleIdentifier: String) {
        dynamicModeLock.lock()
        defer { dynamicModeLock.unlock() }
        dynamicMarkedTextBundles.insert(bundleIdentifier.lowercased())
    }

    public static func isForcedMarkedText(for bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier?.lowercased(), !id.isEmpty else { return false }
        dynamicModeLock.lock()
        defer { dynamicModeLock.unlock() }
        return dynamicMarkedTextBundles.contains(id)
    }

    public static func forcedMarkedTextBundles() -> Set<String> {
        dynamicModeLock.lock()
        defer { dynamicModeLock.unlock() }
        return dynamicMarkedTextBundles
    }

    public static func clearForcedMarkedText(for bundleIdentifier: String) {
        dynamicModeLock.lock()
        defer { dynamicModeLock.unlock() }
        dynamicMarkedTextBundles.remove(bundleIdentifier.lowercased())
    }

    public static func resetDynamicMarkedText() {
        dynamicModeLock.lock()
        defer { dynamicModeLock.unlock() }
        dynamicMarkedTextBundles.removeAll()
    }

    public static func resolvePresentationModeWithSource(
        for category: AppCategory,
        bundleIdentifier: String? = nil,
        terminalDirectEnabled: Bool = false,
        passthroughRemoteApps: Bool = false,
        preference: PresentationModePreference = .automatic,
        appOverrides: [String: PresentationModePreference] = [:]
    ) -> (mode: PresentationMode, source: PresentationModeSource) {
        let id = bundleIdentifier?.lowercased()
        if let id, let override = appOverrides[id], override != .automatic {
            switch override {
            case .directReplacement:
                return (.directReplacement, .appOverride(override))
            case .markedText:
                return (.markedText, .appOverride(override))
            case .passthrough:
                return (.passthrough, .appOverride(override))
            case .automatic:
                break
            }
        }

        switch preference {
        case .directReplacement:
            return (.directReplacement, .globalPreference(preference))
        case .markedText:
            return (.markedText, .globalPreference(preference))
        case .passthrough:
            return (.passthrough, .globalPreference(preference))
        case .automatic:
            break
        }

        // Data-driven rules sit BELOW the user's explicit choice (global preference or
        // per-app override) and ABOVE the built-in category heuristic, so supporting a new
        // app is a one-line edit to typing-modes.yml instead of a Swift change.
        if let dataPreference = presentationRules.preference(forBundleIdentifier: id) {
            switch dataPreference {
            case .directReplacement:
                return (.directReplacement, .rulesFile(dataPreference))
            case .markedText:
                return (.markedText, .rulesFile(dataPreference))
            case .passthrough:
                return (.passthrough, .rulesFile(dataPreference))
            case .automatic:
                break // "automatic" in the data file means the rule expresses no opinion
            }
        }

        if category == .remoteOrVirtualMachine && passthroughRemoteApps {
            return (.passthrough, .categoryHeuristic(category))
        }
        if category == .terminal {
            return (terminalDirectEnabled ? .terminalDirect : .markedText, .categoryHeuristic(category))
        }
        if category == .remoteOrVirtualMachine {
            return (.markedText, .categoryHeuristic(category))
        }
        if category == .chromium {
            // Chromium / Electron / CEF apps (Chrome, Slack, VSCode, Discord, Notion, Figma, etc.):
            // Use Stealth Composition (Zero-Underline Marked Text) to synchronize with the W3C IME
            // composition lifecycle. This completely eliminates duplicate characters ("t-ti-tiế-tiếng")
            // and swallowed keystrokes caused by asynchronous React/DOM virtual diffing.
            return (.markedText, .categoryHeuristic(category))
        }
        if let id {
            dynamicModeLock.lock()
            let isForcedMarkedText = dynamicMarkedTextBundles.contains(id)
            dynamicModeLock.unlock()
            if isForcedMarkedText {
                return (.markedText, .dynamicFallback)
            }
        }
        return (.directReplacement, .categoryHeuristic(category))
    }

    public static func presentationMode(
        for category: AppCategory,
        bundleIdentifier: String? = nil,
        terminalDirectEnabled: Bool = false,
        passthroughRemoteApps: Bool = false,
        preference: PresentationModePreference = .automatic,
        appOverrides: [String: PresentationModePreference] = [:]
    ) -> PresentationMode {
        resolvePresentationModeWithSource(
            for: category,
            bundleIdentifier: bundleIdentifier,
            terminalDirectEnabled: terminalDirectEnabled,
            passthroughRemoteApps: passthroughRemoteApps,
            preference: preference,
            appOverrides: appOverrides
        ).mode
    }

    public static func allowsDynamicMarkedTextFallback(
        bundleIdentifier: String?,
        preference: PresentationModePreference,
        appOverrides: [String: PresentationModePreference]
    ) -> Bool {
        guard preference == .automatic else { return false }
        guard let id = bundleIdentifier?.lowercased() else { return true }
        if appOverrides[id] != nil { return false }
        // A rule that pins a mode in typing-modes.yml is as authoritative as a user
        // override — the dynamic marked-text fallback must not second-guess it.
        if let pinned = presentationRules.preference(forBundleIdentifier: id), pinned != .automatic {
            return false
        }
        return true
    }

    // MARK: - Browser Address Bar (Omnibox) Autocomplete Helpers

    /// Returns `true` when the bundle identifier belongs to a known web browser
    /// (Safari, Chrome, Chromium, Brave, Edge, Arc, Dia, Vivaldi, Opera, Firefox, Zen, Orion, Cốc Cốc, DuckDuckGo, etc.).
    public static func isBrowserApp(bundleIdentifier: String?) -> Bool {
        guard let rawID = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty else {
            return false
        }
        let id = rawID.lowercased()
        return id.contains("safari") ||
            id.contains("chrome") ||
            id.contains("chromium") ||
            id.contains("brave") ||
            id.contains("edgemac") ||
            id.contains("microsoft.edge") ||
            id.contains("thebrowser.browser") ||
            id.contains("thebrowser.dia") ||
            id.contains("vivaldi") ||
            id.contains("opera") ||
            id.contains("firefox") ||
            id.contains("zen-browser") ||
            id.contains("kagi.kagimacos") ||
            id.contains("coccoc") ||
            id.contains("duckduckgo") ||
            id.contains("waterfox") ||
            id.contains("librewolf") ||
            id.contains("torbrowser") ||
            id.contains("thorium") ||
            id.contains("helium")
    }

    /// Returns `true` when the bundle identifier belongs to Microsoft Excel (`com.microsoft.Excel`).
    public static func isExcelApp(bundleIdentifier: String?) -> Bool {
        guard let rawID = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty else {
            return false
        }
        return rawID.lowercased().contains("com.microsoft.excel")
    }

    /// Returns `true` when `text` looks like a full URL or domain name that is highlighted
    /// in a browser's address bar when the user focuses it (e.g. `https://google.com`,
    /// `google.com`, `shopee.vn/cart`, `localhost:3000`, `chrome://settings`).
    public static func isHighlightedURLOrDomain(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return false }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }

        let lower = trimmed.lowercased()
        let urlSchemes = [
            "http://", "https://", "file://", "chrome://", "edge://",
            "brave://", "vivaldi://", "arc://", "opera://", "about:", " www."
        ]
        if lower.hasPrefix("www.") || urlSchemes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }

        // Localhost with port or path (e.g. "localhost:3000", "localhost/api")
        if lower.hasPrefix("localhost:") || lower.hasPrefix("localhost/") || lower == "localhost" {
            return true
        }

        // Bare domain or domain+path (e.g. "google.com", "tuoitre.vn", "docs.google.com/document")
        guard lower.allSatisfy({ $0.isASCII }) else { return false }
        let hostPart = lower.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? lower
        let hostWithoutPort = hostPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? hostPart
        let labels = hostWithoutPort.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty,
                  label.first?.isLetter == true || label.first?.isNumber == true,
                  label.last?.isLetter == true || label.last?.isNumber == true,
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                return false
            }
        }
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return true
    }

    /// Returns `true` when `selectedText` looks like a browser's inline URL autocomplete tail
    /// highlighted right after the caret (e.g. `oogle.com` in `g[oogle.com]`, `pee.vn` in `sho[pee.vn]`,
    /// `.google.com` in `docs[.google.com]`, `host:3000` in `local[host:3000]`).
    ///
    /// - Parameters:
    ///   - selectedText: The currently selected substring reported by the browser client.
    ///   - nextChar: Optional character the user just typed; when provided, verifies whether the
    ///     inline autocomplete tail starts with `nextChar` (case-insensitively).
    public static func isInlineURLAutocompleteTail(_ selectedText: String, matchingNextChar nextChar: Character? = nil) -> Bool {
        guard !selectedText.isEmpty, selectedText.count <= 512 else { return false }
        guard selectedText.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else { return false }
        guard selectedText.contains(where: { $0 == "." || $0 == "/" || $0 == ":" }) else { return false }
        guard selectedText.contains(where: { $0.isLetter || $0.isNumber }) else { return false }

        // Reject ordinary prose sentences that happen to end with a period (e.g. "word.")
        // where '.' is only the final character and there is no '/' or ':'.
        if !selectedText.contains("/") && !selectedText.contains(":") {
            let dotIndices = selectedText.indices.filter { selectedText[$0] == "." }
            if dotIndices.isEmpty { return false }
            if dotIndices.count == 1 && dotIndices.first == selectedText.index(before: selectedText.endIndex) {
                return false
            }
            // The segment after the last dot (or before the first slash) must look like a TLD (at least 2 ASCII letters)
            let hostPart = selectedText.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? selectedText
            let hostLabels = hostPart.split(separator: ".", omittingEmptySubsequences: false)
            guard let lastLabel = hostLabels.last,
                  lastLabel.count >= 2,
                  lastLabel.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                return false
            }
        }

        if let nextChar {
            guard let first = selectedText.first,
                  String(first).lowercased() == String(nextChar).lowercased() else {
                return false
            }
        }
        return true
    }
}

// MARK: - Direct In-Place Replacement Safety & Ownership Guards

/// Result of verifying whether a candidate `NSRange` in `.directReplacement` mode
/// is safely owned by the active composition session.
@frozen public enum DirectReplacementOwnership: Sendable, Equatable {
    /// The range is valid and owned by the current composition session.
    case owned
    /// The range is `NSNotFound`, negative, or empty.
    case invalidRange
    /// The range length exceeds the UTF-16 length of the active composition session.
    case exceedsOwnedSessionLength
    /// The range lies outside `[compositionStartLocation, virtualCursorLocation]`.
    case outsideCompositionBounds
    /// The host text at `replacementRange` diverged from the session's `composingWord`.
    case hostTextDiverged
}

/// Evaluation of cursor synchronization before processing a keystroke in `.directReplacement` mode.
@frozen public enum DirectReplacementCursorEvaluation: Sendable, Equatable {
    /// Selection matches `virtualCursorLocation`; proceed with direct replacement.
    case inSync
    /// Host reported `NSNotFound` for `selection.location`; fallback to `.markedText`.
    case invalidSelectionFallbackToMarkedText
    /// Host ignored the previous `replacementRange` and appended characters instead;
    /// fallback to `.markedText` for this client.
    case ignoredReplacementFallbackToMarkedText
    /// Host deleted `charsDeleted` UTF-16 code units from the end of `composingWord`.
    case prefixRetained(charsDeleted: Int)
    /// Host deleted the entire `composingWord`.
    case compositionCleared
    /// Caret jumped outside the composing word (user click / host navigation);
    /// reset the composition session without mutating host text.
    case externalCursorJumpResetSession
}

/// Pure-Swift verification helpers enforcing session ownership, UTF-16 range bounds,
/// and dynamic `.markedText` fallback when a third-party host ignores `replacementRange`
/// or reports invalid selections.
public enum DirectReplacementGuard {
    /// Verifies that `replacementRange` strictly belongs to the active composition session
    /// and never overwrites surrounding host text.
    public static func verifyRangeOwnership(
        replacementRange: NSRange,
        composingWord: String,
        compositionStartLocation: Int = NSNotFound,
        virtualCursorLocation: Int = NSNotFound,
        hostSubstring: String? = nil,
        isEditingCommittedWord: Bool = false,
        extraAutocompleteLength: Int = 0
    ) -> DirectReplacementOwnership {
        guard replacementRange.location != NSNotFound,
              replacementRange.location >= 0,
              replacementRange.length > 0 else {
            return .invalidRange
        }

        let composingUTF16 = (composingWord as NSString).length
        let clampedExtra = max(0, extraAutocompleteLength)
        let ownedLength = replacementRange.length - clampedExtra

        if !isEditingCommittedWord {
            if ownedLength <= 0 || ownedLength > composingUTF16 {
                return .exceedsOwnedSessionLength
            }
            if compositionStartLocation != NSNotFound {
                if replacementRange.location < compositionStartLocation {
                    return .outsideCompositionBounds
                }
                if virtualCursorLocation != NSNotFound &&
                   replacementRange.location + ownedLength > virtualCursorLocation {
                    return .outsideCompositionBounds
                }
            }
        }

        if let hostText = hostSubstring,
           !hostText.isEmpty,
           !isEditingCommittedWord,
           clampedExtra == 0 {
            let expectedSuffix = (composingWord as NSString).substring(from: max(0, composingUTF16 - ownedLength))
            if hostText.precomposedStringWithCanonicalMapping != expectedSuffix.precomposedStringWithCanonicalMapping {
                return .hostTextDiverged
            }
        }

        return .owned
    }

    /// Evaluates cursor position before a keystroke in `.directReplacement` mode to detect:
    /// - `NSNotFound` selections,
    /// - hosts that silently ignored the previous `replacementRange` (leaving old characters + appending suffix),
    /// - external Backspace deletions within the composing word,
    /// - external cursor jumps outside the composing word.
    public static func evaluateCursorState(
        selection: NSRange,
        virtualCursorLocation: Int,
        compositionStartLocation: Int,
        composingWordUTF16Length: Int,
        lastReplacementLength: Int = 0,
        hostWindowSubstring: String? = nil,
        expectedIgnoredWindowText: String? = nil
    ) -> DirectReplacementCursorEvaluation {
        if selection.location == NSNotFound {
            return .invalidSelectionFallbackToMarkedText
        }
        guard virtualCursorLocation != NSNotFound, composingWordUTF16Length > 0 else {
            return .inSync
        }
        if selection.location == virtualCursorLocation {
            return .inSync
        }

        let charsDeleted = virtualCursorLocation - selection.location
        if charsDeleted > 0 && charsDeleted < composingWordUTF16Length {
            return .prefixRetained(charsDeleted: charsDeleted)
        }
        if charsDeleted == composingWordUTF16Length && composingWordUTF16Length > 0 {
            return .compositionCleared
        }

        // If the cursor advanced beyond `virtualCursorLocation` by `lastReplacementLength`,
        // the host ignored `replacementRange` on the previous step and appended instead of replacing.
        if lastReplacementLength > 0 && selection.location == virtualCursorLocation + lastReplacementLength {
            if let hostWindow = hostWindowSubstring, let expectedIgnored = expectedIgnoredWindowText {
                if hostWindow.precomposedStringWithCanonicalMapping == expectedIgnored.precomposedStringWithCanonicalMapping {
                    return .ignoredReplacementFallbackToMarkedText
                }
                return .externalCursorJumpResetSession
            }
            return .ignoredReplacementFallbackToMarkedText
        }

        return .externalCursorJumpResetSession
    }

    /// Extracts a pure-ASCII Vietnamese consonant onset (`c`, `ch`, `qu`, `q`, `ngh`, `gi`, `d`, etc.)
    /// immediately preceding a partial-word selection or post-deletion caret so replacing a word's rhyme
    /// (e.g. `"cùng"` -> highlight `"ùng"` -> type `"uoois"` -> `"cuối"`, `"chúng"` -> highlight `"úng"` -> type `"ojn"` -> `"chọn"`)
    /// composes seamlessly with the unselected initial consonant without ever corrupting non-Vietnamese prefixes.
    public static func extractAdoptableOnsetPrefix(
        beforeCaret precedingText: String,
        nextChar: Character,
        hasActiveSelection: Bool,
        charAfterCaret: Character? = nil,
        isVNI: Bool = false
    ) -> String? {
        if !hasActiveSelection, let after = charAfterCaret, after.isLetter {
            return nil
        }
        let isVNIDStrokeDigit = isVNI && nextChar == "9"
        guard nextChar.isASCII && (nextChar.isLetter || isVNIDStrokeDigit), !precedingText.isEmpty else {
            return nil
        }

        var idx = precedingText.endIndex
        var letterCount = 0
        while idx > precedingText.startIndex {
            let prev = precedingText.index(before: idx)
            if precedingText[prev].isLetter {
                idx = prev
                letterCount += 1
                if letterCount > 3 {
                    return nil
                }
            } else {
                break
            }
        }
        guard letterCount >= 1 && letterCount <= 3 else {
            return nil
        }

        if idx > precedingText.startIndex {
            let boundaryChar = precedingText[precedingText.index(before: idx)]
            let isCleanWordBoundary = boundaryChar.isWhitespace ||
                boundaryChar == "(" || boundaryChar == "[" || boundaryChar == "{" ||
                boundaryChar == "\"" || boundaryChar == "'" || boundaryChar == "“" ||
                boundaryChar == "‘" || boundaryChar == "<"
            guard isCleanWordBoundary else {
                return nil
            }
        }

        let onset = String(precedingText[idx...])
        guard onset.unicodeScalars.allSatisfy(\.isASCII) else {
            return nil
        }
        let lowerOnset = onset.lowercased()
        guard VietnameseSyllableDictionary.adoptablePureASCIIOnsets.contains(lowerOnset) else {
            return nil
        }

        if isVNIDStrokeDigit {
            return lowerOnset == "d" ? onset : nil
        }

        let lowerNext = Character(nextChar.lowercased())
        if lowerOnset == "q" {
            return lowerNext == "u" ? onset : nil
        }
        if lowerNext == "a" || lowerNext == "e" || lowerNext == "i" ||
           lowerNext == "o" || lowerNext == "u" || lowerNext == "y" || (!isVNI && lowerNext == "w") {
            return onset
        }
        if !isVNI && lowerOnset == "d" && lowerNext == "d" {
            return onset
        }
        if !isVNI && lowerOnset == "gi" && (lowerNext == "s" || lowerNext == "f" || lowerNext == "r" || lowerNext == "x" || lowerNext == "j") {
            return onset
        }
        if lowerNext == "h" && (lowerOnset == "c" || lowerOnset == "g" || lowerOnset == "k" ||
                                lowerOnset == "n" || lowerOnset == "p" || lowerOnset == "t" || lowerOnset == "ng") {
            return onset
        }
        if lowerOnset == "n" && lowerNext == "g" {
            return onset
        }
        if lowerOnset == "t" && lowerNext == "r" {
            return onset
        }
        return nil
    }
}
