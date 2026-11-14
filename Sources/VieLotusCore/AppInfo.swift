import Foundation

public struct AppInfo {
    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    public static var gitCommit: String {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "local-dev"
    }

    public static var buildDate: String {
        Bundle.main.infoDictionary?["BuildTimestamp"] as? String ?? "local-build"
    }

    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "org.vielotus.inputmethod.VieLotusIM"
    }

    public static var osVersionString: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public static var architecture: String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return "unknown"
        #endif
    }

    public static var systemSummary: String {
        "macOS \(osVersionString) · \(architecture) · v\(appVersion) (\(buildNumber)) [\(gitCommit)]"
    }

    public static var defaultPlatformSlug: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    /// Builds the official web feedback URL (`https://stevedat.github.io/VieLotus-IM/feedback.html`)
    /// pre-populated with platform, app version, build number, OS version, and optional typing context.
    public static func feedbackURL(
        platform: String = defaultPlatformSlug,
        inputMethod: String? = nil,
        smartBilingual: Bool? = nil,
        typedKeys: String? = nil,
        actualOutput: String? = nil,
        expectedOutput: String? = nil
    ) -> URL {
        var components = URLComponents(string: "https://stevedat.github.io/VieLotus-IM/feedback.html")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "v", value: appVersion),
            URLQueryItem(name: "build", value: buildNumber),
            URLQueryItem(name: "os", value: osVersionString)
        ]
        if let im = inputMethod?.trimmingCharacters(in: .whitespacesAndNewlines), !im.isEmpty {
            items.append(URLQueryItem(name: "im", value: im.lowercased()))
        }
        if let bilingual = smartBilingual {
            items.append(URLQueryItem(name: "bilingual", value: bilingual ? "1" : "0"))
        }
        if let keys = typedKeys?.trimmingCharacters(in: .whitespacesAndNewlines), !keys.isEmpty {
            items.append(URLQueryItem(name: "keys", value: keys))
        }
        if let actual = actualOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !actual.isEmpty {
            items.append(URLQueryItem(name: "actual", value: actual))
        }
        if let expected = expectedOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty {
            items.append(URLQueryItem(name: "expected", value: expected))
        }
        components.queryItems = items
        return components.url ?? URL(string: "https://stevedat.github.io/VieLotus-IM/feedback.html")!
    }

    public static func formattedConfiguration(
        inputMethod: String,
        smartBilingual: Bool,
        modernOrthography: Bool,
        developerMode: Bool? = nil,
        terminalDirectMode: Bool? = nil,
        quickTelex: Bool? = nil,
        relaxedCoda: Bool? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("- **Kiểu gõ:** \(inputMethod)")
        lines.append("- **Nhận diện tiếng Anh (Smart Bilingual):** \(smartBilingual ? "Bật" : "Tắt")")
        lines.append("- **Dấu chuẩn mới (oà/uý):** \(modernOrthography ? "Bật" : "Tắt")")
        if let dev = developerMode {
            lines.append("- **Chế độ Lập trình viên:** \(dev ? "Bật" : "Tắt")")
        }
        if let term = terminalDirectMode {
            lines.append("- **Tối ưu Terminal Direct:** \(term ? "Bật" : "Tắt")")
        }
        if let qt = quickTelex {
            lines.append("- **Quick Telex:** \(qt ? "Bật" : "Tắt")")
        }
        if let rc = relaxedCoda {
            lines.append("- **Viết tắt phụ âm cuối:** \(rc ? "Bật" : "Tắt")")
        }
        return lines.joined(separator: "\n")
    }
}
