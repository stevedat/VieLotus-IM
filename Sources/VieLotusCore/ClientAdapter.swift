import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum AppCategory: Sendable, Equatable {
    case standardAppKit
    case chromium
    case msOffice
    case terminal
    case overlay
    case remoteOrVirtualMachine
    case unknown
}

public enum PresentationMode: Sendable, Equatable {
    case directReplacement
    case markedText
    case terminalDirect
    case passthrough
}

public enum PresentationModePreference: String, CaseIterable, Sendable, Identifiable {
    case automatic
    case directReplacement
    case markedText
    case passthrough

    public var id: String { rawValue }
}

public struct ClientAdapter {
    public static func classify(bundleIdentifier: String?) -> AppCategory {
        guard let id = bundleIdentifier?.lowercased() else { return .unknown }
        
        // Remote Desktop, Screen Sharing & Virtual Machine apps:
        // Remote targets handle their own keyboard layout or forward raw scancodes.
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
           id.contains("postman") {
            // Zalo, Telegram, Slack, VSCode, Orca, Cursor, GenOffice, etc. use CEF/Electron/Chromium
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
        if isElectronOrChromiumApp(bundleIdentifier: id) {
            return .chromium
        }
        #endif
        
        return .standardAppKit
    }

    #if canImport(AppKit)
    private static let appFrameworkCheckLock = NSLock()
    private static var isChromiumAppCache: [String: Bool] = [:]

    private static func isElectronOrChromiumApp(bundleIdentifier: String) -> Bool {
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

    public static func resetDynamicMarkedText() {
        dynamicModeLock.lock()
        defer { dynamicModeLock.unlock() }
        dynamicMarkedTextBundles.removeAll()
    }

    public static func presentationMode(
        for category: AppCategory,
        bundleIdentifier: String? = nil,
        terminalDirectEnabled: Bool = false,
        passthroughRemoteApps: Bool = false,
        preference: PresentationModePreference = .automatic,
        appOverrides: [String: PresentationModePreference] = [:]
    ) -> PresentationMode {
        let id = bundleIdentifier?.lowercased()
        let override = id.flatMap { appOverrides[$0] }
        let selectedPreference = override ?? preference

        switch selectedPreference {
        case .directReplacement:
            return .directReplacement
        case .markedText:
            return .markedText
        case .passthrough:
            return .passthrough
        case .automatic:
            break
        }

        // Data-driven rules sit BELOW the user's explicit choice (global preference or
        // per-app override) and ABOVE the built-in category heuristic, so supporting a new
        // app is a one-line edit to typing-modes.yml instead of a Swift change.
        if let dataPreference = presentationRules.preference(forBundleIdentifier: id) {
            switch dataPreference {
            case .directReplacement:
                return .directReplacement
            case .markedText:
                return .markedText
            case .passthrough:
                return .passthrough
            case .automatic:
                break // "automatic" in the data file means the rule expresses no opinion
            }
        }

        if category == .remoteOrVirtualMachine && passthroughRemoteApps {
            return .passthrough
        }
        if category == .terminal {
            return terminalDirectEnabled ? .terminalDirect : .markedText
        }
        if category == .remoteOrVirtualMachine {
            return .markedText
        }
        if category == .chromium {
            // Chromium / Electron / CEF apps (Chrome, Slack, VSCode, Discord, Notion, Figma, etc.):
            // Use Stealth Composition (Zero-Underline Marked Text) to synchronize with the W3C IME
            // composition lifecycle. This completely eliminates duplicate characters ("t-ti-tiế-tiếng")
            // and swallowed keystrokes caused by asynchronous React/DOM virtual diffing.
            return .markedText
        }
        if let id {
            dynamicModeLock.lock()
            let isForcedMarkedText = dynamicMarkedTextBundles.contains(id)
            dynamicModeLock.unlock()
            if isForcedMarkedText { return .markedText }
        }
        return .directReplacement
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
}
