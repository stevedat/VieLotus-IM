#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

/// Immutable SCOWL index for local English recognition and suggestions. No system IPC.
public final class LocalEnglishLexicon: Sendable {
    public static let shared = LocalEnglishLexicon()
    private struct Entry: Sendable {
        let word: String
        let rank: Int
    }
    private let entries: [Entry]
    public let isLoaded: Bool

    public init() {
        let bundle = Bundle.vieLotusCore
        let url = bundle.url(forResource: "scowl-en", withExtension: "txt", subdirectory: "English")
            ?? bundle.url(forResource: "scowl-en", withExtension: "txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        entries = text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let rank = line.first?.wholeNumberValue else { return nil }
            let word = String(line.dropFirst())
            guard !word.isEmpty, word.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
            return Entry(word: word, rank: rank)
        }.sorted { $0.word < $1.word }
        isLoaded = !entries.isEmpty
    }

    private func lowerBound(_ word: String) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].word < word { low = mid + 1 } else { high = mid }
        }
        return low
    }

    public func contains(_ word: String) -> Bool {
        let key = word.lowercased()
        let index = lowerBound(key)
        return index < entries.count && entries[index].word == key
    }

    public static func isEligible(_ word: String) -> Bool {
        guard (1...32).contains(word.utf8.count),
              let first = word.utf8.first, (65...90).contains(first) || (97...122).contains(first) else { return false }
        return word.utf8.dropFirst().allSatisfy { (97...122).contains($0) }
    }

    private func preferred(_ a: Entry, _ b: Entry) -> Bool {
        if a.rank != b.rank { return a.rank < b.rank }
        if a.word.count != b.word.count { return a.word.count < b.word.count }
        return a.word < b.word
    }

    public func candidates(for word: String) -> [SuggestionCandidate] {
        guard word.count >= 2, Self.isEligible(word) else { return [] }
        let key = word.lowercased()
        var index = lowerBound(key)
        let known = index < entries.count && entries[index].word == key
        if known { index += 1 }
        var best: [Entry] = []
        while index < entries.count && entries[index].word.hasPrefix(key) {
            best.append(entries[index])
            best.sort(by: preferred)
            if best.count > 2 { best.removeLast() }
            index += 1
        }
        var source: SuggestionSource = .englishCompletion
        if best.isEmpty && !known && key.count >= 3 {
            var correction: Entry?
            func consider(_ value: String) {
                guard value != key else { return }
                let i = lowerBound(value)
                guard i < entries.count, entries[i].word == value else { return }
                if correction == nil || preferred(entries[i], correction!) { correction = entries[i] }
            }
            let chars = Array(key)
            for i in 0..<(chars.count - 1) {
                var swapped = chars
                swapped.swapAt(i, i + 1)
                consider(String(swapped))
            }
            // Match Android: prefer common adjacent transpositions (e.g. teh -> the).
            if correction?.rank != 0 {
                for i in 0...chars.count {
                    let left = String(chars.prefix(i))
                    let right = String(chars.dropFirst(i))
                    if !right.isEmpty { consider(left + right.dropFirst()) }
                    for letter in "abcdefghijklmnopqrstuvwxyz" {
                        consider(left + String(letter) + right)
                        if !right.isEmpty { consider(left + String(letter) + right.dropFirst()) }
                    }
                }
            }
            if let correction { best = [correction]; source = .englishSpelling }
        }
        return best.enumerated().map { index, entry in
            let display = word.first?.isUppercase == true
                ? entry.word.prefix(1).uppercased() + entry.word.dropFirst() : entry.word
            return SuggestionCandidate(displayText: display, insertionText: display,
                                       replacementMode: .replaceComposing, source: source,
                                       score: Double(2 - index))
        }
    }
}

#endif
