import Foundation

/// Pure Swift word suggestion and prediction engine using bigram compound dictionaries.
///
/// Loads and indexes Vietnamese compound phrases (e.g. from `TuDienTuGhep`) into an efficient
/// in-memory bigram lookup map (`[String: [String]]`) to predict next words following a committed word.
public final class WordSuggestionEngine: @unchecked Sendable {
    /// Shared singleton instance loaded from the module resource bundle.
    public static let shared = WordSuggestionEngine()

    /// In-memory bigram dictionary mapping headwords to possible next words / phrases.
    public let bigrams: [String: [String]]

    /// Total number of unique headwords in the dictionary.
    public var count: Int {
        bigrams.count
    }

    /// Whether the dictionary contains any entries.
    public var isEmpty: Bool {
        bigrams.isEmpty
    }

    /// Initializes the suggestion engine by loading the dictionary from a resource `Bundle`.
    ///
    /// Checks for a pre-compiled JSON version (`TuDienTuGhep.json`) first for fast startup (~30ms),
    /// falling back to the raw plain text file (`TuDienTuGhep.txt`).
    ///
    /// - Parameter bundle: The resource bundle containing the dictionary (defaults to `Bundle.module`).
    public init(bundle: Bundle? = nil) {
        let targetBundle: Bundle
        if let bundle = bundle {
            targetBundle = bundle
        } else {
            targetBundle = Bundle.module
        }
        if let jsonURL = targetBundle.url(forResource: "TuDienTuGhep", withExtension: "json"),
           let data = try? Data(contentsOf: jsonURL),
           let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
            self.bigrams = parsed
        } else if let txtURL = targetBundle.url(forResource: "TuDienTuGhep", withExtension: "txt") {
            self.bigrams = Self.parse(fileURL: txtURL)
        } else {
            self.bigrams = [:]
        }
    }

    /// Initializes the suggestion engine with an in-memory dictionary.
    ///
    /// - Parameter dictionary: Bigram mapping dictionary.
    public init(dictionary: [String: [String]]) {
        self.bigrams = dictionary
    }

    /// Initializes the suggestion engine by parsing a text file at the given URL.
    ///
    /// - Parameter fileURL: File URL to the dictionary file.
    public init(fileURL: URL) {
        if fileURL.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: fileURL),
               let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
                self.bigrams = parsed
            } else {
                self.bigrams = [:]
            }
        } else {
            self.bigrams = Self.parse(fileURL: fileURL)
        }
    }

    /// Initializes the suggestion engine by parsing raw text.
    ///
    /// - Parameter text: Raw string content formatted like `TuDienTuGhep.txt`.
    public init(parsingText text: String) {
        self.bigrams = Self.parse(text: text)
    }

    /// Parses a file at the specified URL into a bigram dictionary.
    ///
    /// - Parameter fileURL: File URL to `TuDienTuGhep.txt` or equivalent compound phrase list.
    /// - Returns: In-memory bigram dictionary mapping headword to candidate continuations.
    public static func parse(fileURL: URL) -> [String: [String]] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return [:]
        }
        return parse(text: content)
    }

    /// Parses string text into a bigram dictionary.
    ///
    /// Lines containing phrases (e.g. "cộng đồng", "cộng đồng quốc tế") are split on the first whitespace.
    /// The first line is skipped if it is a numeric entry count.
    ///
    /// - Parameter text: Raw dictionary text.
    /// - Returns: In-memory bigram dictionary mapping headword to candidate continuations.
    public static func parse(text: String) -> [String: [String]] {
        var cleanText = text
        if cleanText.hasPrefix("\u{FEFF}") {
            cleanText.removeFirst()
        }
        var result: [String: [String]] = [:]
        result.reserveCapacity(5000)

        var isFirstLine = true
        cleanText.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if isFirstLine {
                isFirstLine = false
                if Int(trimmed) != nil {
                    return
                }
            }

            if let spaceIndex = trimmed.firstIndex(where: { $0.isWhitespace }) {
                let head = String(trimmed[..<spaceIndex]).lowercased()
                let tail = String(trimmed[trimmed.index(after: spaceIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                guard !tail.isEmpty else { return }
                result[head, default: []].append(tail)
            }
        }
        return result
    }

    /// Queries next-word suggestions for a given committed word.
    ///
    /// - Parameters:
    ///   - word: The preceding word or phrase just committed.
    ///   - limit: Optional maximum number of suggestions to return.
    /// - Returns: Array of suggested next words or phrases, or empty array if none found.
    public func suggestions(for word: String, limit: Int? = nil) -> [String] {
        let rawKey = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rawKey.isEmpty else { return [] }

        let trimmedKey = rawKey.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = bigrams[rawKey] ?? bigrams[trimmedKey]
        if candidates == nil {
            let normalized = trimmedKey.replacingOccurrences(of: "-", with: " ")
            let tokens = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let lastWord = tokens.last, !lastWord.isEmpty {
                let cleanedLast = lastWord.trimmingCharacters(in: .punctuationCharacters)
                candidates = bigrams[lastWord] ?? bigrams[cleanedLast]
            }
        }

        guard let candidates, !candidates.isEmpty else {
            return []
        }
        if let limit = limit {
            guard limit > 0 else { return [] }
            return Array(candidates.prefix(limit))
        }
        return candidates
    }

    /// Convenience alias for `suggestions(for:limit:)`.
    public func nextWordSuggestions(for word: String, limit: Int? = nil) -> [String] {
        suggestions(for: word, limit: limit)
    }

    /// Checks whether the dictionary contains suggestions for the given word.
    public func hasSuggestions(for word: String) -> Bool {
        !suggestions(for: word, limit: 1).isEmpty
    }

    /// Subscript access to suggestions for a given word.
    public subscript(word: String) -> [String] {
        suggestions(for: word)
    }
}
