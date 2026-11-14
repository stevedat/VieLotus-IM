#if !VIELOTUS_OPEN_CORE_MACOS && !os(Android)
import Foundation

/// Soft pastel color tags for quick phrases so users can visually locate categories
/// at a glance while panning the 2D Fisheye Honeycomb Cloud without harsh or glaring colors.
public enum QuickPhraseColorTag: String, Codable, CaseIterable, Sendable, Identifiable {
    case none       // Mặc định (Không gắn màu)
    case peach      // Hồng đào dịu
    case sage       // Xanh bạc hà dịu
    case sky        // Xanh mây dịu
    case lavender   // Tím oải hương dịu
    case sand       // Vàng kem ấm
    case rose       // Hồng phấn sen

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .peach: return "Cam đào Pastel"
        case .sage: return "Xanh bạc hà Pastel"
        case .sky: return "Xanh mây Pastel"
        case .lavender: return "Tím oải hương Pastel"
        case .sand: return "Vàng kem Pastel"
        case .rose: return "Hồng phấn Pastel"
        case .none: return "Mặc định (Không màu)"
        }
    }

    /// Soft pastel RGB components `(r, g, b)` for the indicator dot and color swatch.
    public func dotRGB(isDark: Bool) -> (r: Double, g: Double, b: Double)? {
        switch self {
        case .peach:
            return isDark ? (0.88, 0.67, 0.55) : (0.86, 0.58, 0.44)
        case .sage:
            return isDark ? (0.58, 0.80, 0.67) : (0.44, 0.71, 0.55)
        case .sky:
            return isDark ? (0.58, 0.75, 0.90) : (0.44, 0.65, 0.85)
        case .lavender:
            return isDark ? (0.73, 0.65, 0.89) : (0.62, 0.53, 0.82)
        case .sand:
            return isDark ? (0.85, 0.77, 0.53) : (0.79, 0.68, 0.41)
        case .rose:
            return isDark ? (0.87, 0.63, 0.72) : (0.82, 0.53, 0.64)
        case .none:
            return nil
        }
    }

    /// Soft pastel surface fill RGB `(r, g, b)` for the pill background (low-saturation, eye-friendly).
    public func surfaceRGB(isDark: Bool) -> (r: Double, g: Double, b: Double)? {
        switch self {
        case .peach:
            return isDark ? (0.31, 0.25, 0.23) : (0.99, 0.94, 0.90)
        case .sage:
            return isDark ? (0.22, 0.29, 0.26) : (0.91, 0.97, 0.93)
        case .sky:
            return isDark ? (0.22, 0.27, 0.33) : (0.91, 0.95, 0.99)
        case .lavender:
            return isDark ? (0.27, 0.24, 0.33) : (0.95, 0.93, 0.99)
        case .sand:
            return isDark ? (0.30, 0.28, 0.22) : (0.98, 0.96, 0.89)
        case .rose:
            return isDark ? (0.31, 0.23, 0.27) : (0.99, 0.92, 0.95)
        case .none:
            return nil
        }
    }
}

/// Represents a single ready-made quick phrase (mẫu câu sẵn) in the keyboard's `≡` menu.
public struct QuickPhraseItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var phrase: String
    public var colorTag: QuickPhraseColorTag

    public init(id: String, phrase: String, colorTag: QuickPhraseColorTag = .none) {
        self.id = id
        self.phrase = phrase
        self.colorTag = colorTag
    }

    /// Resolves the text to insert when tapped on the keyboard.
    public func resolvedText() -> String {
        phrase
    }
}

/// Manages the built-in and user-customized Quick Phrases (Mẫu câu sẵn) shared between
/// the host app and the keyboard extension via App Group UserDefaults.
public final class QuickPhraseStore: @unchecked Sendable {
    public static let shared = QuickPhraseStore()

    private let storageKey = "QuickPhrasesV2"
    private let tagStorageKey = "QuickPhraseTagsV1"
    private let defaults: UserDefaults

    public static let defaultRows: [[QuickPhraseItem]] = [
        // Hàng 1: Chào hỏi & Cảm ơn
        [
            QuickPhraseItem(id: "r1_0", phrase: "Chúc bạn ngày mới tốt lành!"),
            QuickPhraseItem(id: "r1_1", phrase: "Xin chào bạn!"),
            QuickPhraseItem(id: "r1_2", phrase: "Cảm ơn bạn nhiều nhé!"),
            QuickPhraseItem(id: "r1_3", phrase: "Xin lỗi, mình phản hồi trễ nhé."),
            QuickPhraseItem(id: "r1_4", phrase: "Rất vui được hợp tác cùng bạn.")
        ],
        // Hàng 2: Di chuyển & Thời gian
        [
            QuickPhraseItem(id: "r2_0", phrase: "Mình sắp tới nơi rồi nhé."),
            QuickPhraseItem(id: "r2_1", phrase: "Đợi mình một chút nhé."),
            QuickPhraseItem(id: "r2_2", phrase: "Mình đang trên đường tới nhé."),
            QuickPhraseItem(id: "r2_3", phrase: "Mình đang bận, lát gọi lại nhé."),
            QuickPhraseItem(id: "r2_4", phrase: "Gọi lại cho mình khi rảnh nhé.")
        ],
        // Hàng 3: Công việc & Xác nhận
        [
            QuickPhraseItem(id: "r3_0", phrase: "Để mình kiểm tra lại nhé."),
            QuickPhraseItem(id: "r3_1", phrase: "Đồng ý, cứ làm như vậy nhé!"),
            QuickPhraseItem(id: "r3_2", phrase: "Mình đã hoàn thành xong rồi nhé."),
            QuickPhraseItem(id: "r3_3", phrase: "Gửi vị trí cho mình nhé."),
            QuickPhraseItem(id: "r3_4", phrase: "Mình đã về đến nhà an toàn rồi.")
        ],
        // Hàng 4: Hẹn gặp & Nhờ hỗ trợ
        [
            QuickPhraseItem(id: "r4_0", phrase: "Trưa nay đi ăn cùng mình không?"),
            QuickPhraseItem(id: "r4_1", phrase: "Bạn đang ở đâu thế?"),
            QuickPhraseItem(id: "r4_2", phrase: "Khi nào rảnh đi cà phê nhé!"),
            QuickPhraseItem(id: "r4_3", phrase: "Nhờ bạn giúp mình việc này với ạ."),
            QuickPhraseItem(id: "r4_4", phrase: "Chúc bạn buổi tối vui vẻ nhé!")
        ]
    ]

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else {
            self.defaults = UserDefaults(suiteName: KeyboardPreferences.defaultSuiteName) ?? .standard
        }
    }

    public func loadRows() -> [[QuickPhraseItem]] {
        let customMap: [String: String] = {
            guard let data = defaults.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }()
        let customTagMap: [String: String] = {
            guard let data = defaults.data(forKey: tagStorageKey),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }()

        return Self.defaultRows.map { row in
            row.map { item in
                var copy = item
                if let custom = customMap[item.id], !custom.isEmpty {
                    copy.phrase = custom
                }
                if let rawTag = customTagMap[item.id],
                   let tag = QuickPhraseColorTag(rawValue: rawTag) {
                    copy.colorTag = tag
                }
                return copy
            }
        }
    }

    public func updatePhrase(forID id: String, newPhrase: String, colorTag: QuickPhraseColorTag? = nil) {
        var customMap: [String: String] = [:]
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            customMap = decoded
        }
        let trimmed = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customMap.removeValue(forKey: id)
        } else {
            customMap[id] = trimmed
        }
        if let encoded = try? JSONEncoder().encode(customMap) {
            defaults.set(encoded, forKey: storageKey)
        }

        if let colorTag {
            var customTagMap: [String: String] = [:]
            if let data = defaults.data(forKey: tagStorageKey),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                customTagMap = decoded
            }
            customTagMap[id] = colorTag.rawValue
            if let encodedTags = try? JSONEncoder().encode(customTagMap) {
                defaults.set(encodedTags, forKey: tagStorageKey)
            }
        }

        postDidChangeNotification()
    }

    public func resetToDefaults() {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: tagStorageKey)
        postDidChangeNotification()
    }

    private func postDidChangeNotification() {
        #if os(iOS) || os(macOS)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(KeyboardPreferences.preferencesDidChangeDarwinNotification as CFString),
            nil,
            nil,
            true
        )
        #endif
    }
}
#endif
