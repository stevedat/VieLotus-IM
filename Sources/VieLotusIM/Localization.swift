import Foundation
import VieLotusCore
import VieLotusTrace

extension Notification.Name {
    static let vieLotusUILanguageDidChange = Notification.Name("VieLotusIM.uiLanguageDidChange")
}

/// Thread-safe, zero-restart VI–EN localization helper for macOS VieLotusIM UI.
enum L10n {
    private static let lock = NSLock()
    private static var cachedPreference: UILanguagePreference = {
        let raw = UserDefaults.standard.string(forKey: UILanguagePreference.userDefaultsKey)
        return UILanguagePreference.fromStored(raw)
    }()

    static var preference: UILanguagePreference {
        lock.lock()
        defer { lock.unlock() }
        return cachedPreference
    }

    static func setPreference(_ pref: UILanguagePreference) {
        lock.lock()
        cachedPreference = pref
        lock.unlock()
    }

    static var isEnglish: Bool {
        preference.resolvedIsEnglish()
    }

    static func tr(_ vi: String, _ en: String) -> String {
        isEnglish ? en : vi
    }
}

extension ClipboardCharsetMode {
    var localizedMenuTitle: String {
        switch self {
        case .nfdToNFC:
            return L10n.tr(
                "Unicode tổ hợp → dựng sẵn (NFD → NFC)",
                "Decomposed Unicode → Precomposed (NFD → NFC)"
            )
        case .tcvn3ToUnicode:
            return "TCVN3 (ABC) → Unicode"
        case .vniWindowsToUnicode:
            return "VNI Windows → Unicode"
        }
    }
}

extension InputSourceStatus {
    func localizedConflictWarningText(isEnglish: Bool = L10n.isEnglish) -> String? {
        if !runningThirdPartyIMEs.isEmpty {
            let joined = runningThirdPartyIMEs.joined(separator: ", ")
            return isEnglish
                ? "\(joined) running in background — quit it to avoid keystroke conflicts"
                : "Phát hiện \(joined) đang chạy ngầm — hãy thoát để tránh xung đột phím"
        }
        if isConflictingAppleVietnameseActive {
            return isEnglish
                ? "Switch to Sen Việt from the menu bar to avoid conflicts"
                : "Chuyển sang Sen Việt trên thanh menu để tránh xung đột"
        }
        if !enabledAppleVietnameseNames.isEmpty {
            if enabledAppleVietnameseNames.count == 1 {
                let name = enabledAppleVietnameseNames[0]
                return isEnglish
                    ? "Apple IME (\(name)) is also enabled — consider disabling it"
                    : "Bộ gõ Apple (\(name)) đang bật kèm — nên tắt bớt"
            }
            return isEnglish
                ? "\(enabledAppleVietnameseNames.count) Apple Vietnamese IMEs also enabled — consider disabling them"
                : "Đang bật kèm \(enabledAppleVietnameseNames.count) bộ gõ Tiếng Việt của Apple — nên tắt bớt"
        }
        return nil
    }

    func localizedSummaryTitle(isEnglish: Bool = L10n.isEnglish) -> String {
        switch state {
        case .active:
            if !runningThirdPartyIMEs.isEmpty {
                let joined = runningThirdPartyIMEs.joined(separator: ", ")
                return isEnglish
                    ? "Sen Việt Active • Conflict: \(joined)"
                    : "Đang dùng Sen Việt • Cảnh báo \(joined)"
            }
            if !enabledAppleVietnameseNames.isEmpty {
                return isEnglish
                    ? "Sen Việt Active • Apple IME also enabled"
                    : "Đang dùng Sen Việt • Bộ gõ Apple đang bật"
            }
            return isEnglish ? "Sen Việt Active" : "Đang dùng Sen Việt"
        case .enabledAppleVietnameseActive:
            let name = activeInputSourceName ?? (isEnglish ? "Apple Vietnamese" : "Tiếng Việt Apple")
            return isEnglish
                ? "Apple IME active (\(name))"
                : "Đang chọn bộ gõ Apple (\(name))"
        case .enabledNotSelected:
            let name = activeInputSourceName ?? (isEnglish ? "Another keyboard" : "Bàn phím khác")
            return isEnglish
                ? "Enabled • Active: \(name)"
                : "Đã bật • Đang chọn \(name)"
        case .registeredNotEnabled:
            return isEnglish
                ? "Not enabled in Input Sources"
                : "Chưa bật trong Nguồn đầu vào"
        case .notRegistered:
            return isEnglish
                ? "Not registered with macOS"
                : "Chưa đăng ký với macOS"
        }
    }

    func localizedSummarySubtitle(isEnglish: Bool = L10n.isEnglish) -> String {
        if let warning = localizedConflictWarningText(isEnglish: isEnglish) {
            return warning
        }
        switch state {
        case .active:
            return isEnglish
                ? "Press Fn / 🌐 or Ctrl + Space to switch input sources"
                : "Fn / 🌐 hoặc Ctrl + Space để chuyển nhanh"
        case .enabledAppleVietnameseActive:
            return isEnglish
                ? "Switch to Sen Việt from the menu bar to avoid conflicts"
                : "Chuyển sang Sen Việt trên thanh menu để tránh xung đột"
        case .enabledNotSelected:
            return isEnglish
                ? "Press Fn / 🌐 or Ctrl + Space to switch to Sen Việt"
                : "Bấm Fn / 🌐 hoặc Ctrl + Space để chuyển sang Sen Việt"
        case .registeredNotEnabled:
            return isEnglish
                ? "Open Keyboard Settings → Input Sources to add Sen Việt"
                : "Mở Cài đặt Bàn phím → Nguồn đầu vào để thêm Sen Việt"
        case .notRegistered:
            return isEnglish
                ? "Install via VieLotusIM.pkg or log out and back in"
                : "Cài qua VieLotusIM.pkg hoặc đăng xuất / đăng nhập lại"
        }
    }
}
