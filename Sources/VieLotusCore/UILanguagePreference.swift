import Foundation

/// Persisted UI language preference for Sen Việt desktop and mobile surfaces.
/// Does not affect typing engine behavior, regression suites, or machine-readable CLI keys.
public enum UILanguagePreference: String, CaseIterable, Sendable, Equatable {
    case auto = "auto"
    case vietnamese = "vi"
    case english = "en"

    public static let userDefaultsKey = "VieLotusIM.uiLanguage"

    public static func fromStored(_ raw: String?) -> UILanguagePreference {
        guard let raw else { return .auto }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return UILanguagePreference(rawValue: trimmed) ?? .auto
    }

    public func resolvedIsEnglish(preferredLanguages: [String] = Locale.preferredLanguages) -> Bool {
        switch self {
        case .vietnamese:
            return false
        case .english:
            return true
        case .auto:
            guard let first = preferredLanguages.first(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else {
                return true
            }
            let primary = first
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map { String($0).lowercased() } ?? ""
            return primary != "vi"
        }
    }

    public var shortBadge: String {
        switch self {
        case .auto: return "Auto"
        case .vietnamese: return "VI"
        case .english: return "EN"
        }
    }
}
