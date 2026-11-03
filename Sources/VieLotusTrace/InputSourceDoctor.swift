import Foundation
#if os(macOS)
import Carbon.HIToolbox
#endif

public enum InputSourceHealthState: String, Codable, Equatable, Sendable {
    /// VieLotusIM is registered, enabled, and currently selected as the active input source.
    case active = "active"
    /// VieLotusIM is enabled, but Apple's built-in Vietnamese IME is currently selected instead.
    case enabledAppleVietnameseActive = "enabled_apple_vietnamese_active"
    /// VieLotusIM is enabled, and another non-Vietnamese layout (e.g. ABC) is currently selected.
    case enabledNotSelected = "enabled_not_selected"
    /// VieLotusIM is installed and registered with TIS, but not enabled in Input Sources.
    case registeredNotEnabled = "registered_not_enabled"
    /// VieLotusIM is not yet registered with macOS Text Input Sources.
    case notRegistered = "not_registered"
}

public struct InputSourceStatus: Codable, Equatable, Sendable {
    public static let defaultBundleID = "org.vielotus.inputmethod.VieLotusIM"

    public let bundleID: String
    public let isInstalledOnDisk: Bool
    public let installedPath: String?
    public let isRegistered: Bool
    public let isEnabled: Bool
    public let isActive: Bool
    public let matchedInputSourceIDs: [String]
    public let activeInputSourceID: String?
    public let activeInputSourceName: String?
    public let isConflictingAppleVietnameseActive: Bool
    public let state: InputSourceHealthState

    public init(
        bundleID: String = InputSourceStatus.defaultBundleID,
        isInstalledOnDisk: Bool,
        installedPath: String?,
        isRegistered: Bool,
        isEnabled: Bool,
        isActive: Bool,
        matchedInputSourceIDs: [String],
        activeInputSourceID: String?,
        activeInputSourceName: String?
    ) {
        self.bundleID = bundleID
        self.isInstalledOnDisk = isInstalledOnDisk
        self.installedPath = installedPath
        self.isRegistered = isRegistered
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.matchedInputSourceIDs = matchedInputSourceIDs
        self.activeInputSourceID = activeInputSourceID
        self.activeInputSourceName = activeInputSourceName

        let conflict = Self.isAppleBuiltInVietnameseInputSource(id: activeInputSourceID)
        self.isConflictingAppleVietnameseActive = !isActive && conflict
        self.state = Self.classifyState(
            isRegistered: isRegistered,
            isEnabled: isEnabled,
            isActive: isActive,
            isConflictingAppleVietnameseActive: !isActive && conflict
        )
    }

    public static func isAppleBuiltInVietnameseInputSource(id: String?) -> Bool {
        guard let lowered = id?.lowercased(), !lowered.isEmpty else { return false }
        return lowered.hasPrefix("com.apple.inputmethod.vietnameseim")
            || lowered.hasPrefix("com.apple.keylayout.vietnamese")
    }

    public static func classifyState(
        isRegistered: Bool,
        isEnabled: Bool,
        isActive: Bool,
        isConflictingAppleVietnameseActive: Bool
    ) -> InputSourceHealthState {
        if isActive {
            return .active
        }
        if isEnabled {
            return isConflictingAppleVietnameseActive ? .enabledAppleVietnameseActive : .enabledNotSelected
        }
        if isRegistered {
            return .registeredNotEnabled
        }
        return .notRegistered
    }

    public var summaryTitle: String {
        switch state {
        case .active:
            return "Đang dùng Sen Việt"
        case .enabledAppleVietnameseActive:
            let name = activeInputSourceName ?? "Tiếng Việt Apple"
            return "Đang chọn bộ gõ Apple (\(name))"
        case .enabledNotSelected:
            let name = activeInputSourceName ?? "Bàn phím khác"
            return "Đã bật • Đang chọn \(name)"
        case .registeredNotEnabled:
            return "Chưa bật trong Nguồn đầu vào"
        case .notRegistered:
            return "Chưa đăng ký với macOS"
        }
    }

    public var summarySubtitle: String {
        switch state {
        case .active:
            return "Fn / 🌐 hoặc Ctrl + Space để chuyển nhanh"
        case .enabledAppleVietnameseActive:
            return "Chuyển sang Sen Việt trên thanh menu để tránh xung đột"
        case .enabledNotSelected:
            return "Bấm Fn / 🌐 hoặc Ctrl + Space để chuyển sang Sen Việt"
        case .registeredNotEnabled:
            return "Mở Cài đặt Bàn phím → Nguồn đầu vào để thêm Sen Việt"
        case .notRegistered:
            return "Cài qua VieLotusIM.pkg hoặc đăng xuất / đăng nhập lại"
        }
    }

    public func humanReadableReport() -> String {
        var lines: [String] = []
        lines.append("Sen Việt (VieLotusIM) — Input Source Status")
        lines.append("  Bundle ID        : \(bundleID)")
        lines.append("  Installed on disk: \(isInstalledOnDisk ? "yes" : "no")\(installedPath.map { " (\($0))" } ?? "")")
        lines.append("  TIS registered   : \(isRegistered ? "yes" : "no")")
        lines.append("  TIS enabled      : \(isEnabled ? "yes" : "no")")
        lines.append("  Currently active : \(isActive ? "yes" : "no")")
        if let activeID = activeInputSourceID {
            let label = activeInputSourceName.map { "\($0) [\(activeID)]" } ?? activeID
            lines.append("  Active keyboard  : \(label)")
        }
        if isConflictingAppleVietnameseActive {
            lines.append("  Warning          : Apple built-in Vietnamese IME is active instead of Sen Việt")
        }
        lines.append("  Health state     : \(state.rawValue) — \(summaryTitle)")
        return lines.joined(separator: "\n")
    }

    public func jsonReport() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"state\":\"\(state.rawValue)\"}"
        }
        return text
    }
}

public enum InputSourceDoctor {
    #if os(macOS)
    public static var selectedInputSourceChangedNotification: Notification.Name {
        Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
    }

    public static var enabledInputSourcesChangedNotification: Notification.Name {
        Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
    }

    /// Read-only inspection of macOS Text Input Sources (`Carbon.HIToolbox`).
    /// Never mutates system preferences or triggers TCC / TIS authorization prompts.
    public static func inspect(bundleID: String = InputSourceStatus.defaultBundleID) -> InputSourceStatus {
        let targetLower = bundleID.lowercased()

        let candidatePaths = [
            "/Library/Input Methods/VieLotusIM.app",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Input Methods/VieLotusIM.app").path
        ]
        let foundPath = candidatePaths.first { FileManager.default.fileExists(atPath: $0) }

        var isRegistered = false
        var isEnabled = false
        var matchedIDs: [String] = []

        if let rawList = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] {
            for source in rawList {
                let srcBundleID = stringProperty(source, key: kTISPropertyBundleID)
                let srcID = stringProperty(source, key: kTISPropertyInputSourceID)
                let matchesBundle = srcBundleID?.lowercased() == targetLower
                let matchesID = srcID?.lowercased().hasPrefix(targetLower) == true
                guard matchesBundle || matchesID else { continue }

                isRegistered = true
                if let srcID, !matchedIDs.contains(srcID) {
                    matchedIDs.append(srcID)
                }
                if boolProperty(source, key: kTISPropertyInputSourceIsEnabled) {
                    isEnabled = true
                }
            }
        }

        var activeID: String?
        var activeName: String?
        var isActive = false

        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            activeID = stringProperty(current, key: kTISPropertyInputSourceID)
            activeName = stringProperty(current, key: kTISPropertyLocalizedName)
            let activeBundle = stringProperty(current, key: kTISPropertyBundleID)
            if activeBundle?.lowercased() == targetLower ||
               activeID?.lowercased().hasPrefix(targetLower) == true {
                isActive = true
                isRegistered = true
                isEnabled = true
            }
        }

        matchedIDs.sort()
        return InputSourceStatus(
            bundleID: bundleID,
            isInstalledOnDisk: foundPath != nil,
            installedPath: foundPath,
            isRegistered: isRegistered,
            isEnabled: isEnabled,
            isActive: isActive,
            matchedInputSourceIDs: matchedIDs,
            activeInputSourceID: activeID,
            activeInputSourceName: activeName
        )
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        let cfValue = Unmanaged<CFTypeRef>.fromOpaque(ptr).takeUnretainedValue()
        return cfValue as? String
    }

    private static func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        let cfValue = Unmanaged<CFTypeRef>.fromOpaque(ptr).takeUnretainedValue()
        if let num = cfValue as? NSNumber {
            return num.boolValue
        }
        return false
    }
    #endif
}
