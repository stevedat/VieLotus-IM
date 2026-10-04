import Foundation

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
}

public enum PresentationModePreference: String, CaseIterable, Sendable, Identifiable {
    case automatic
    case directReplacement
    case markedText

    public var id: String { rawValue }
}

public struct ClientAdapter {
    public static func classify(bundleIdentifier: String?) -> AppCategory {
        guard let id = bundleIdentifier?.lowercased() else { return .unknown }
        
        // Remote Desktop, Screen Sharing & Virtual Machine apps:
        // Remote targets handle their own keyboard layout or forward raw scancodes.
        if id.contains("com.microsoft.rdc") ||
           id.contains("teamviewer") ||
           id.contains("anydesk") ||
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
           id.contains("antigravity") {
            // Zalo, Telegram, Slack, VSCode, etc. use CEF/Electron/Chromium
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
        
        return .standardAppKit
    }
    
    private static let dynamicModeLock = NSLock()
    private static var dynamicMarkedTextBundles: Set<String> = []

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
        case .automatic:
            break
        }

        if category == .terminal {
            return terminalDirectEnabled ? .terminalDirect : .markedText
        }
        if category == .remoteOrVirtualMachine {
            return .markedText
        }
        if ["com.google.antigravity", "com.openai.codex"].contains(bundleIdentifier?.lowercased() ?? "") {
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
        return appOverrides[id] == nil
    }
}
