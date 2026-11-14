#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

public struct GlidePoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let time: Double
    public init(x: Double, y: Double, time: Double = 0) {
        self.x = x; self.y = y; self.time = time
    }
}

public struct GlideCandidate: Sendable, Equatable {
    public let syllable: String
    public let score: Double
    public let toneKey: Character?
    public init(syllable: String, score: Double, toneKey: Character? = nil) {
        self.syllable = syllable; self.score = score; self.toneKey = toneKey
    }
}

/// Immutable indexes are built once, shared by decodes, and never mutated on the UI thread.
public struct GlidePathDecoder {
    private struct Entry {
        let syllable: String
        let keys: [Character]
    }
    private static let entries: [Entry] = VietnameseSyllableDictionary.shared.untonedSyllables.sorted().map {
        Entry(syllable: $0, keys: Array(baseKeys($0)))
    }
    private static let entriesByStart: [Character: [Entry]] = Dictionary(grouping: entries.filter { !$0.keys.isEmpty },
                                                                          by: { $0.keys[0] })
    private static let telexKeys = Set("sfrxjzw")

    /// Call on a background queue before the first gesture to avoid cold-index latency at lift-off.
    public static func prepare() { _ = entriesByStart }

    /// Removes vowel shape and tone marks, preserving a separate candidate for each spelling.
    public static func baseKeys(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
    }

    public static func decode(keySequence: [Character], confirmedKeys: Set<Character> = [],
                              limit: Int = 5, path: [GlidePoint] = [],
                              keyCenters: [Character: GlidePoint] = [:]) -> [GlideCandidate] {
        guard limit > 0, keySequence.count >= 2, keySequence.count <= 256 else { return [] }
        let keys = Array(String(keySequence).lowercased())
        let confirmed = Set(String(confirmedKeys).lowercased())
        let suffix = extractTelexSuffix(from: keys)
        let stripped = suffix?.base
        let observed = resample(path, count: 32)
        let entries = entriesByStart[keys[0]] ?? []
        var best: [GlideCandidate] = []
        best.reserveCapacity(min(limit, entries.count))
        for entry in entries {
            var value = sequenceScore(entry.keys, keys, confirmed)
            var toneKey: Character?
            if let stripped {
                // Suffix is an alternative interpretation, never a mandatory tone command.
                let alternative = sequenceScore(entry.keys, stripped, confirmed) - 0.03
                if alternative > value {
                    value = alternative
                    if let last = suffix?.telexKeys.last, last != "w", confirmed.contains(last) { toneKey = last }
                }
            }
            guard value > 0.4 else { continue }
            let ideal = entry.keys.compactMap { keyCenters[$0] }
            if observed.count > 1, ideal.count == entry.keys.count, ideal.count > 1 {
                let expected = resample(ideal, count: 32)
                let distance = zip(observed, expected).reduce(0.0) {
                    $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y)
                } / Double(observed.count)
                // Coordinates are measured in key widths. Shape supplements sequence evidence.
                value = value * 0.6 + exp(-distance) * 0.4
            }
            let candidate = GlideCandidate(syllable: entry.syllable, score: value, toneKey: toneKey)
            let index = best.firstIndex { $0.score < value || ($0.score == value && $0.syllable > entry.syllable) } ?? best.count
            if index < limit { best.insert(candidate, at: index) }
            if best.count > limit { best.removeLast() }
        }
        return best
    }

    public static func extractTelexSuffix(from keys: [Character]) -> (base: [Character], telexKeys: [Character])? {
        guard keys.count >= 3 else { return nil }
        var start = keys.count
        // At most one shape key and one tone key; keep at least two base keys.
        while start > 2, keys.count - start < 2, telexKeys.contains(keys[start - 1]) { start -= 1 }
        guard start < keys.count else { return nil }
        return (Array(keys[..<start]), Array(keys[start...]))
    }

    public static func score(candidate: String, keySequence: [Character], confirmedKeys: Set<Character>) -> Double {
        sequenceScore(Array(baseKeys(candidate)), Array(String(keySequence).lowercased()), confirmedKeys)
    }

    private static func sequenceScore(_ chars: [Character], _ keys: [Character], _ confirmed: Set<Character>) -> Double {
        guard !chars.isEmpty, !keys.isEmpty, chars.first == keys.first else { return 0 }
        var index = 0
        var matched = 0
        for char in chars {
            while index < keys.count && keys[index] != char { index += 1 }
            if index < keys.count { matched += 1; index += 1 }
        }
        // Partial subsequences previously accepted unrelated syllables with just one anchor.
        guard matched == chars.count else { return 0 }
        let end = chars.last == keys.last ? 0.2 : 0
        let dwell = Double(chars.filter { confirmed.contains($0) }.count) / Double(chars.count) * 0.1
        let excess = max(0, keys.count - chars.count)
        return 0.6 + end + dwell + 0.1 / Double(1 + excess)
    }

    /// Arc-length resampling makes scores independent of touch delivery frequency/speed.
    public static func resample(_ points: [GlidePoint], count: Int) -> [GlidePoint] {
        guard count > 1, let first = points.first, let last = points.last else { return [] }
        var cumulative = [0.0]
        for i in 1..<points.count {
            cumulative.append(cumulative[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        guard let length = cumulative.last, length > 0 else { return Array(repeating: first, count: count) }
        var result = [first]
        var segment = 1
        for i in 1..<(count - 1) {
            let target = length * Double(i) / Double(count - 1)
            while segment < points.count - 1 && cumulative[segment] < target { segment += 1 }
            let span = cumulative[segment] - cumulative[segment - 1]
            let t = span > 0 ? (target - cumulative[segment - 1]) / span : 0
            let a = points[segment - 1], b = points[segment]
            result.append(GlidePoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
                                     time: a.time + (b.time - a.time) * t))
        }
        result.append(last)
        return result
    }
}
#endif
