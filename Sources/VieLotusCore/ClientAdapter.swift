import Foundation

public enum AppCategory: Sendable {
    case standardAppKit
    case chromium
    case msOffice
    case terminal
    case overlay
    case unknown
}

public enum PresentationMode: Sendable {
    case directReplacement
    case markedText
    case terminalDirect
}

public struct ClientAdapter {
    public static func classify(bundleIdentifier: String?) -> AppCategory {
        guard let id = bundleIdentifier?.lowercased() else { return .unknown }
        
        // Terminal / Console emulators: use prefix, domain components, or exact match
        if id == "com.apple.terminal" ||
           id.contains(".iterm") ||
           id.contains(".alacritty") ||
           id.contains(".kitty") ||
           id.contains(".ghostty") ||
           id.contains(".wezterm") ||
           id.hasSuffix(".terminal") {
            return .terminal
        }
        
        // Quick search / Overlay apps
        if id.contains("spotlight") ||
           id.contains("raycast") ||
           id.contains("alfred") {
            return .overlay
        }
        
        // Microsoft Office
        if id.contains("com.microsoft.word") ||
           id.contains("com.microsoft.excel") ||
           id.contains("com.microsoft.powerpoint") {
            return .msOffice
        }

        // Chromium / Electron apps
        if id.contains("chrome") ||
           id.contains("brave") ||
           id.contains("edge") ||
           id.contains("chromium") ||
           id.contains("vscode") ||
           id.contains("electron") ||
           id.contains("slack") ||
           id.contains("discord") ||
           id.contains("notion") ||
           id.contains("obsidian") {
            return .chromium
        }
        
        return .standardAppKit
    }
    
    private static var dynamicMarkedTextBundles: Set<String> = []

    public static func forceMarkedText(for bundleIdentifier: String) {
        dynamicMarkedTextBundles.insert(bundleIdentifier.lowercased())
    }

    public static func resetDynamicMarkedText() {
        dynamicMarkedTextBundles.removeAll()
    }

    public static func presentationMode(for category: AppCategory, bundleIdentifier: String? = nil, terminalDirectEnabled: Bool = false) -> PresentationMode {
        if category == .terminal {
            return terminalDirectEnabled ? .terminalDirect : .markedText
        }
        if let id = bundleIdentifier?.lowercased(), dynamicMarkedTextBundles.contains(id) {
            return .markedText
        }
        return .directReplacement
    }
}
