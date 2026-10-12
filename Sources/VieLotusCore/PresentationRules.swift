import Foundation

// MARK: - Data-driven per-app presentation rules
//
// Adding support for an application should be a DATA change, not a Swift change. The
// built-in `ClientAdapter.classify` heuristic covers the common cases, but every new app
// that guesses wrong otherwise needs a code edit, a rebuild and a release. These types
// load `typing-modes.yml` instead, so a rule can be added — and tested on a live machine
// without rebuilding — by editing one line of text.

/// One `key: mode` line from `typing-modes.yml`.
public struct PresentationRule: Sendable, Equatable {
    /// The key as written in the data file, lowercased.
    public let key: String
    public let preference: PresentationModePreference

    public init(key: String, preference: PresentationModePreference) {
        self.key = key.lowercased()
        self.preference = preference
    }

    /// Whether a bundle identifier satisfies this rule's key.
    ///
    /// A key without `*` is an exact bundle-id match. A key containing `*` is a glob whose
    /// segments must appear in order: a leading `*` releases the start anchor and a
    /// trailing `*` releases the end anchor. This mirrors the `contains` / `hasSuffix`
    /// style already used by `ClientAdapter.classify`.
    public func matches(_ bundleIdentifier: String) -> Bool {
        guard key.contains("*") else { return key == bundleIdentifier }

        let segments = key.components(separatedBy: "*")
        let anchoredAtStart = !key.hasPrefix("*")
        let anchoredAtEnd = !key.hasSuffix("*")
        var searchStart = bundleIdentifier.startIndex

        for (index, segment) in segments.enumerated() {
            if segment.isEmpty { continue }

            if index == segments.count - 1 && anchoredAtEnd {
                guard bundleIdentifier.count >= segment.count else { return false }
                let suffixStart = bundleIdentifier.index(bundleIdentifier.endIndex, offsetBy: -segment.count)
                guard suffixStart >= searchStart, bundleIdentifier.hasSuffix(segment) else {
                    return false
                }
                return true
            }

            guard let range = bundleIdentifier.range(of: segment, range: searchStart..<bundleIdentifier.endIndex) else {
                return false
            }
            if index == 0 && anchoredAtStart && range.lowerBound != bundleIdentifier.startIndex {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }
}

/// An ordered rule list. File order is priority order — the first match wins.
public struct PresentationRuleSet: Sendable, Equatable {
    public let rules: [PresentationRule]

    public init(rules: [PresentationRule]) {
        self.rules = rules
    }

    public static let empty = PresentationRuleSet(rules: [])

    public var isEmpty: Bool { rules.isEmpty }

    public func preference(forBundleIdentifier bundleIdentifier: String?) -> PresentationModePreference? {
        guard let id = bundleIdentifier?.lowercased(), !id.isEmpty, !rules.isEmpty else { return nil }
        for rule in rules where rule.matches(id) {
            return rule.preference
        }
        return nil
    }
}

public enum PresentationRulesParser {
    /// Parses the flat `key: value` subset of YAML that `typing-modes.yml` uses.
    ///
    /// Deliberately not a general YAML parser: `VieLotusCore` has no external dependencies
    /// and pulls in none here. Lines are `bundle-id: mode`, one rule per line; `#` starts a
    /// comment (whole-line or trailing); blank lines and unparseable lines are ignored so a
    /// hand-edited file can never take the input method down.
    public static func parse(_ text: String) -> PresentationRuleSet {
        var rules: [PresentationRule] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }

            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") {
                value = String(value[value.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
            }
            // A quoted value (`key: "markedText"`) is accepted so the file survives being
            // round-tripped through editors that add quotes.
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }

            guard !key.isEmpty, let preference = PresentationModePreference(rawValue: value) else { continue }
            rules.append(PresentationRule(key: key, preference: preference))
        }

        return PresentationRuleSet(rules: rules)
    }
}

public enum PresentationRulesLoader {
    public static let resourceBaseName = "typing-modes"
    public static let resourceExtension = "yml"

    /// Search order — the first file that exists wins:
    /// 1. `~/Library/Application Support/VieLotusIM/typing-modes.yml`, editable without a
    ///    rebuild. This is the contribution path: reproduce a bug, add a line, retest.
    /// 2. The running app bundle's `Resources` (the shipped copy).
    /// 3. `Bundle.module`, the SwiftPM resource used by the CLI, the tests and any library
    ///    consumer of `VieLotusCore`.
    public static func searchPaths() -> [URL] {
        var candidates: [URL] = []

        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("VieLotusIM", isDirectory: true)
                .appendingPathComponent("\(resourceBaseName).\(resourceExtension)"))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("\(resourceBaseName).\(resourceExtension)"))
        }
        if let moduleURL = Bundle.module.url(forResource: resourceBaseName, withExtension: resourceExtension) {
            candidates.append(moduleURL)
        }
        return candidates
    }

    /// The first readable candidate, i.e. the file `load()` will actually read.
    public static func resolvedURL() -> URL? {
        for url in searchPaths() where FileManager.default.isReadableFile(atPath: url.path) {
            return url
        }
        return nil
    }

    public static func modificationDate(of url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    public static func load() -> (url: URL, rules: PresentationRuleSet)? {
        guard let url = resolvedURL(), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (url, PresentationRulesParser.parse(text))
    }
}
