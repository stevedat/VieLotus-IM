#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

/// RGBA color value in `[0.0, 1.0]` component space, platform-agnostic (shared across iOS, iPadOS, and future Android).
public struct ThemeColorRGBA: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// Complete color specification for a built-in keyboard theme.
/// Designed for 100% offline, zero-allocation programmatic rendering with zero impact on keystroke latency.
public struct KeyboardThemePalette: Sendable, Equatable {
    public let isDark: Bool
    public let backdropColor: ThemeColorRGBA
    public let glassBorderColor: ThemeColorRGBA
    public let letterKeyBackground: ThemeColorRGBA
    public let letterKeyText: ThemeColorRGBA
    public let specialKeyBackground: ThemeColorRGBA
    public let specialKeyText: ThemeColorRGBA
    public let returnKeyBackground: ThemeColorRGBA
    public let returnKeyText: ThemeColorRGBA

    public init(
        isDark: Bool,
        backdropColor: ThemeColorRGBA,
        glassBorderColor: ThemeColorRGBA,
        letterKeyBackground: ThemeColorRGBA,
        letterKeyText: ThemeColorRGBA,
        specialKeyBackground: ThemeColorRGBA,
        specialKeyText: ThemeColorRGBA,
        returnKeyBackground: ThemeColorRGBA,
        returnKeyText: ThemeColorRGBA
    ) {
        self.isDark = isDark
        self.backdropColor = backdropColor
        self.glassBorderColor = glassBorderColor
        self.letterKeyBackground = letterKeyBackground
        self.letterKeyText = letterKeyText
        self.specialKeyBackground = specialKeyBackground
        self.specialKeyText = specialKeyText
        self.returnKeyBackground = returnKeyBackground
        self.returnKeyText = returnKeyText
    }
}

/// Built-in theme identifiers for the VieLotus mobile keyboard (iOS, iPadOS, and future Android).
/// Stored as a single integer ID (`0...7`) on device and synchronized via Darwin notification state bits (`15...18`).
public enum KeyboardThemeID: Int, CaseIterable, Sendable, Codable, Identifiable {
    case systemAuto = 0
    case classicLight = 1
    case midnightDark = 2
    case mintGreen = 3
    case pastelRose = 4
    case oceanBlue = 5
    case royalLavender = 6
    case oledBlack = 7

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .systemAuto: return "Liquid Glass"
        case .classicLight: return "Classic Light"
        case .midnightDark: return "Midnight Dark"
        case .mintGreen: return "Mint Green"
        case .pastelRose: return "Pastel Rose"
        case .oceanBlue: return "Ocean Blue"
        case .royalLavender: return "Royal Lavender"
        case .oledBlack: return "OLED Black"
        }
    }

    public var subtitle: String {
        switch self {
        case .systemAuto: return "Tự động Sáng / Tối chuẩn Apple"
        case .classicLight: return "Giao diện sáng, tối giản"
        case .midnightDark: return "Nền tối, tương phản rõ"
        case .mintGreen: return "Xanh dịu, hiện đại"
        case .pastelRose: return "Hồng nhẹ nhàng"
        case .oceanBlue: return "Xanh biển thanh lịch"
        case .royalLavender: return "Tím pastel dịu mắt"
        case .oledBlack: return "Đen tuyền tiết kiệm pin"
        }
    }

    /// Returns the next theme in the built-in catalog for quick inline cycling on the keyboard.
    public var nextTheme: KeyboardThemeID {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .systemAuto }
        let nextIdx = (idx + 1) % all.count
        return all[nextIdx]
    }

    /// Resolves the concrete color palette for the current theme and system appearance.
    public func resolvedPalette(isDarkSystem: Bool) -> KeyboardThemePalette {
        switch self {
        case .systemAuto:
            if isDarkSystem {
                return KeyboardThemePalette(
                    isDark: true,
                    backdropColor: ThemeColorRGBA(r: 0.08, g: 0.08, b: 0.08, a: 0.16),
                    glassBorderColor: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.16),
                    letterKeyBackground: ThemeColorRGBA(r: 107.0 / 255.0, g: 107.0 / 255.0, b: 110.0 / 255.0, a: 1.0),
                    letterKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
                    specialKeyBackground: ThemeColorRGBA(r: 70.0 / 255.0, g: 70.0 / 255.0, b: 73.0 / 255.0, a: 1.0),
                    specialKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
                    returnKeyBackground: ThemeColorRGBA(r: 10.0 / 255.0, g: 132.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                    returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
                )
            } else {
                return KeyboardThemePalette(
                    isDark: false,
                    backdropColor: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.18),
                    glassBorderColor: ThemeColorRGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.10),
                    letterKeyBackground: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
                    letterKeyText: ThemeColorRGBA(r: 0.0, g: 0.0, b: 0.0, a: 1.0),
                    specialKeyBackground: ThemeColorRGBA(r: 172.0 / 255.0, g: 179.0 / 255.0, b: 188.0 / 255.0, a: 0.85),
                    specialKeyText: ThemeColorRGBA(r: 0.0, g: 0.0, b: 0.0, a: 1.0),
                    returnKeyBackground: ThemeColorRGBA(r: 0.0, g: 122.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                    returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
                )
            }

        case .classicLight:
            return KeyboardThemePalette(
                isDark: false,
                backdropColor: ThemeColorRGBA(r: 212.0 / 255.0, g: 216.0 / 255.0, b: 222.0 / 255.0, a: 0.85),
                glassBorderColor: ThemeColorRGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.10),
                letterKeyBackground: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 17.0 / 255.0, g: 24.0 / 255.0, b: 39.0 / 255.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 172.0 / 255.0, g: 179.0 / 255.0, b: 188.0 / 255.0, a: 0.90),
                specialKeyText: ThemeColorRGBA(r: 17.0 / 255.0, g: 24.0 / 255.0, b: 39.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 0.0, g: 122.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )

        case .midnightDark:
            return KeyboardThemePalette(
                isDark: true,
                backdropColor: ThemeColorRGBA(r: 22.0 / 255.0, g: 25.0 / 255.0, b: 34.0 / 255.0, a: 0.90),
                glassBorderColor: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.16),
                letterKeyBackground: ThemeColorRGBA(r: 68.0 / 255.0, g: 73.0 / 255.0, b: 86.0 / 255.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 44.0 / 255.0, g: 48.0 / 255.0, b: 58.0 / 255.0, a: 1.0),
                specialKeyText: ThemeColorRGBA(r: 235.0 / 255.0, g: 238.0 / 255.0, b: 245.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 10.0 / 255.0, g: 132.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )

        case .mintGreen:
            return KeyboardThemePalette(
                isDark: false,
                backdropColor: ThemeColorRGBA(r: 207.0 / 255.0, g: 238.0 / 255.0, b: 226.0 / 255.0, a: 0.88),
                glassBorderColor: ThemeColorRGBA(r: 16.0 / 255.0, g: 120.0 / 255.0, b: 88.0 / 255.0, a: 0.18),
                letterKeyBackground: ThemeColorRGBA(r: 247.0 / 255.0, g: 254.0 / 255.0, b: 251.0 / 255.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 13.0 / 255.0, g: 59.0 / 255.0, b: 46.0 / 255.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 165.0 / 255.0, g: 218.0 / 255.0, b: 199.0 / 255.0, a: 0.92),
                specialKeyText: ThemeColorRGBA(r: 13.0 / 255.0, g: 59.0 / 255.0, b: 46.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 16.0 / 255.0, g: 158.0 / 255.0, b: 114.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )

        case .pastelRose:
            return KeyboardThemePalette(
                isDark: false,
                backdropColor: ThemeColorRGBA(r: 248.0 / 255.0, g: 220.0 / 255.0, b: 229.0 / 255.0, a: 0.88),
                glassBorderColor: ThemeColorRGBA(r: 190.0 / 255.0, g: 60.0 / 255.0, b: 105.0 / 255.0, a: 0.18),
                letterKeyBackground: ThemeColorRGBA(r: 255.0 / 255.0, g: 250.0 / 255.0, b: 252.0 / 255.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 74.0 / 255.0, g: 21.0 / 255.0, b: 43.0 / 255.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 236.0 / 255.0, g: 188.0 / 255.0, b: 204.0 / 255.0, a: 0.92),
                specialKeyText: ThemeColorRGBA(r: 74.0 / 255.0, g: 21.0 / 255.0, b: 43.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 225.0 / 255.0, g: 75.0 / 255.0, b: 126.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )

        case .oceanBlue:
            return KeyboardThemePalette(
                isDark: false,
                backdropColor: ThemeColorRGBA(r: 212.0 / 255.0, g: 230.0 / 255.0, b: 248.0 / 255.0, a: 0.88),
                glassBorderColor: ThemeColorRGBA(r: 20.0 / 255.0, g: 95.0 / 255.0, b: 180.0 / 255.0, a: 0.18),
                letterKeyBackground: ThemeColorRGBA(r: 248.0 / 255.0, g: 252.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 15.0 / 255.0, g: 41.0 / 255.0, b: 77.0 / 255.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 173.0 / 255.0, g: 205.0 / 255.0, b: 238.0 / 255.0, a: 0.92),
                specialKeyText: ThemeColorRGBA(r: 15.0 / 255.0, g: 41.0 / 255.0, b: 77.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 14.0 / 255.0, g: 116.0 / 255.0, b: 224.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )

        case .royalLavender:
            return KeyboardThemePalette(
                isDark: false,
                backdropColor: ThemeColorRGBA(r: 229.0 / 255.0, g: 222.0 / 255.0, b: 247.0 / 255.0, a: 0.88),
                glassBorderColor: ThemeColorRGBA(r: 105.0 / 255.0, g: 70.0 / 255.0, b: 190.0 / 255.0, a: 0.18),
                letterKeyBackground: ThemeColorRGBA(r: 251.0 / 255.0, g: 249.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 43.0 / 255.0, g: 24.0 / 255.0, b: 84.0 / 255.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 199.0 / 255.0, g: 186.0 / 255.0, b: 234.0 / 255.0, a: 0.92),
                specialKeyText: ThemeColorRGBA(r: 43.0 / 255.0, g: 24.0 / 255.0, b: 84.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 114.0 / 255.0, g: 76.0 / 255.0, b: 217.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )

        case .oledBlack:
            return KeyboardThemePalette(
                isDark: true,
                backdropColor: ThemeColorRGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.96),
                glassBorderColor: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.12),
                letterKeyBackground: ThemeColorRGBA(r: 34.0 / 255.0, g: 34.0 / 255.0, b: 38.0 / 255.0, a: 1.0),
                letterKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
                specialKeyBackground: ThemeColorRGBA(r: 20.0 / 255.0, g: 20.0 / 255.0, b: 23.0 / 255.0, a: 1.0),
                specialKeyText: ThemeColorRGBA(r: 220.0 / 255.0, g: 220.0 / 255.0, b: 228.0 / 255.0, a: 1.0),
                returnKeyBackground: ThemeColorRGBA(r: 10.0 / 255.0, g: 132.0 / 255.0, b: 255.0 / 255.0, a: 1.0),
                returnKeyText: ThemeColorRGBA(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
            )
        }
    }
}
#endif
