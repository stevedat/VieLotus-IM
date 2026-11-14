#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

// MARK: - Data Contracts for Context-Aware Suggestion Engine

/// Defines how selecting a suggestion candidate modifies the text document proxy.
public enum SuggestionReplacementMode: String, Sendable, Equatable {
    /// Keeps the active composition word as-is and commits it with a trailing space (Slot 0 while composing).
    case keepComposing
    /// Replaces the currently composing syllable/prefix with `insertionText` (e.g. composing "thành" -> "thành phố ", or composing "ph" after "thành " -> "phố ").
    case replaceComposing
    /// Appends `insertionText` after the already-committed word + space (e.g. after "thành " -> inserts "phố ", preventing "thành thành phố").
    case appendNextWord
    /// Replaces the composing macro shortcut with its expanded phrase.
    case macroExpansion
    /// Appends or completes a URL/email snippet directly without adding a leading or trailing space (e.g. "https://", "www.", ".com", "@gmail.com").
    case appendDirectNoSpace
}

/// Identifies the semantic input field type reported by the host text document proxy.
public enum SuggestionFieldKind: String, Sendable, Equatable {
    case standard
    case url
    case webSearch
    case emailAddress
}

/// Identifies which linguistic generator produced a candidate.
public enum SuggestionSource: String, Sendable, Equatable {
    case composingEcho
    case macroExpansion
    case trigramContext
    case compoundCompletion
    case nextWordPrediction
    case prefixMatching
    case userVocabulary
    case sentenceStarter
    case englishCompletion
    case englishSpelling
    case urlOrEmailSnippet
}

/// High-level state of the user's cursor and composition session.
public enum SuggestionInputState: String, Sendable, Equatable {
    case emptyOrSentenceStart
    case composingSyllable
    case afterWordBoundary
    case afterSentencePunctuation
    case midSentenceEdit
    case macroCandidate
}

/// Detected language/orthographic register around the cursor.
public enum SuggestionLanguageContext: String, Sendable, Equatable {
    case vietnamese
    case englishOrTechnical
    case properNounOrTitleCase
    case mixed
}

/// Input snapshot passed from the keyboard controller to the suggestion engine.
public struct SuggestionInputContext: Sendable, Equatable {
    public enum TypingMode: Sendable, Equatable {
        case vietnamese
        case literalABC
    }

    public let beforeContext: String
    public let afterContext: String
    public let composingWord: String
    public let rawWord: String
    public let isComposing: Bool
    public let macroEnabled: Bool
    public let typingMode: TypingMode

    public init(
        beforeContext: String,
        afterContext: String = "",
        composingWord: String = "",
        rawWord: String = "",
        isComposing: Bool = false,
        macroEnabled: Bool = true,
        typingMode: TypingMode = .vietnamese
    ) {
        self.beforeContext = beforeContext
        self.afterContext = afterContext
        self.composingWord = composingWord
        self.rawWord = rawWord
        self.isComposing = isComposing
        self.macroEnabled = macroEnabled
        self.typingMode = typingMode
    }
}

/// Result of analyzing and segmenting the 2-4 syllables preceding the cursor.
public struct SegmentedContext: Sendable, Equatable {
    public let state: SuggestionInputState
    public let language: SuggestionLanguageContext
    /// Up to 4 raw syllables before the cursor within the active clause.
    public let rawTokens: [String]
    /// Phrase-segmented units using Longest-Suffix Compound Matching (e.g. ["tôi", "đang", "ở", "thành phố"]).
    public let segmentedUnits: [String]
    /// The last multi-syllable or single-syllable lexical unit before the cursor (lowercased).
    public let lastUnit: String
    /// The lexical unit immediately preceding `lastUnit` (lowercased), if any.
    public let precedingUnit: String?
    /// The raw last single syllable before the cursor (lowercased).
    public let lastSyllable: String
    /// Original casing of the last committed syllable before the cursor.
    public let lastRawTokenOriginal: String
    /// Whether the last committed syllable was capitalized (Title Case or ALL CAPS).
    public let isCapitalizedHead: Bool
    /// Whether the last committed syllable was ALL CAPS (more than 1 letter).
    public let isAllCapsHead: Bool
}

/// A ranked, actionable suggestion ready for rendering in `CandidateBarView`.
public struct SuggestionCandidate: Sendable, Equatable {
    /// Text displayed on the candidate button pill.
    public let displayText: String
    /// Exact text to insert or replace into the document when tapped.
    public let insertionText: String
    /// How the adapter should apply `insertionText` to avoid duplicate words.
    public let replacementMode: SuggestionReplacementMode
    /// Generator source that produced this candidate.
    public let source: SuggestionSource
    /// Final score from `ContextualRanker`.
    public let score: Double
    /// Whether this candidate should be visually highlighted in the bar.
    public let isPrimary: Bool

    public init(
        displayText: String,
        insertionText: String,
        replacementMode: SuggestionReplacementMode,
        source: SuggestionSource,
        score: Double,
        isPrimary: Bool = false
    ) {
        self.displayText = displayText
        self.insertionText = insertionText
        self.replacementMode = replacementMode
        self.source = source
        self.score = score
        self.isPrimary = isPrimary
    }
}

// MARK: - Ephemeral In-Memory Session Personalization Store (Rule 6 — Zero Data Collection)

/// Privacy-preserving ephemeral in-memory frequency learner.
/// Keeps candidate selection boosts strictly in RAM during the active process session
/// and never persists user typing or selection history to disk (Zero Data Collection).
public final class UserFrequencyStore: @unchecked Sendable {
    public static let shared = UserFrequencyStore()

    private struct Entry: Codable {
        var count: Double
        var lastUpdated: TimeInterval
    }

    private static let legacyStorageKey = "vielotus.suggestion.user_freq.v1"
    private let maxEntries = 512
    private let halfLifeSeconds: TimeInterval = 14.0 * 24.0 * 3600.0
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init(defaults: UserDefaults? = nil) {
        // Purge any legacy persisted frequency history to enforce strict Zero Data Collection.
        defaults?.removeObject(forKey: Self.legacyStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyStorageKey)
    }

    /// Records that the user explicitly selected `candidate` in the given `contextKey` (in-memory only).
    public func recordSelection(candidate: String, contextKey: String = "", now: TimeInterval = Date().timeIntervalSince1970) {
        let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanCandidate.isEmpty, cleanCandidate.count <= 40 else { return }

        lock.lock()
        defer { lock.unlock() }

        updateKey("u:\(cleanCandidate)", weight: 1.0, now: now)
        let cleanContext = contextKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanContext.isEmpty {
            updateKey("b:\(cleanContext)->\(cleanCandidate)", weight: 1.5, now: now)
        }

        if entries.count > maxEntries {
            let sorted = entries.sorted { decayedValue($0.value, now: now) > decayedValue($1.value, now: now) }
            var pruned: [String: Entry] = [:]
            pruned.reserveCapacity(maxEntries)
            for (k, v) in sorted.prefix(maxEntries - 64) {
                pruned[k] = v
            }
            entries = pruned
        }
    }

    /// Returns the time-decayed personalization boost `U(c)` in `[0.0, 3.0]`.
    public func userBoost(for candidate: String, contextKey: String = "", now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanCandidate.isEmpty else { return 0.0 }

        lock.lock()
        defer { lock.unlock() }

        var total = 0.0
        if let uni = entries["u:\(cleanCandidate)"] {
            total += log1p(decayedValue(uni, now: now)) * 0.7
        }
        let cleanContext = contextKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanContext.isEmpty, let bi = entries["b:\(cleanContext)->\(cleanCandidate)"] {
            total += log1p(decayedValue(bi, now: now)) * 1.4
        }
        return min(total, 3.0)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    private func updateKey(_ key: String, weight: Double, now: TimeInterval) {
        if var existing = entries[key] {
            let decayed = decayedValue(existing, now: now)
            existing.count = min(decayed + weight, 50.0)
            existing.lastUpdated = now
            entries[key] = existing
        } else {
            entries[key] = Entry(count: weight, lastUpdated: now)
        }
    }

    private func decayedValue(_ entry: Entry, now: TimeInterval) -> Double {
        let elapsed = max(0.0, now - entry.lastUpdated)
        let factor = pow(0.5, elapsed / halfLifeSeconds)
        return entry.count * factor
    }
}

// MARK: - Vietnamese Context-Aware Suggestion Engine

/// Pure Swift context-aware word suggestion and prediction engine.
///
/// Architecture:
/// `Input Engine (Telex/SenFlex) -> Context Analyzer -> Phrase & N-gram Candidate Generator -> Contextual Ranker -> Top-K UI`
public final class WordSuggestionEngine: @unchecked Sendable {
    private static let sharedLock = NSLock()
    private static var _isSharedLoaded: Bool = false
    private static var _sharedInstance: WordSuggestionEngine?

    /// Whether `WordSuggestionEngine.shared` has finished loading into memory.
    public static var isSharedLoaded: Bool {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        return _isSharedLoaded
    }

    /// Shared singleton instance loaded from the module resource bundle or injected via `loadSharedFromJSON`.
    public static var shared: WordSuggestionEngine {
        sharedLock.lock()
        if let existing = _sharedInstance {
            sharedLock.unlock()
            return existing
        }
        sharedLock.unlock()

        let engine = WordSuggestionEngine()
        sharedLock.lock()
        if _sharedInstance == nil {
            _sharedInstance = engine
            _isSharedLoaded = true
        }
        let resolved = _sharedInstance!
        sharedLock.unlock()
        return resolved
    }

    /// Injects or reloads the shared suggestion dictionary from a JSON string (`[String: [String]]`),
    /// used on platforms like Android where `TuDienTuGhep.json` is packaged inside APK assets.
    @discardableResult
    public static func loadSharedFromJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]],
              !parsed.isEmpty else {
            return false
        }
        let engine = WordSuggestionEngine(dictionary: parsed)
        sharedLock.lock()
        _sharedInstance = engine
        _isSharedLoaded = true
        sharedLock.unlock()
        return true
    }

    /// Warms up `WordSuggestionEngine.shared` on a background queue so the UIKit main thread
    /// never blocks on cold keyboard launch.
    public static func warmUpAsync(completion: (@MainActor @Sendable () -> Void)? = nil) {
        if isSharedLoaded {
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.shared
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    /// In-memory bigram dictionary mapping single-syllable headwords to frequency-ranked continuations.
    public let bigrams: [String: [String]]

    /// Multi-syllable compound head index (e.g. "thành phố" -> ["hồ chí minh", "hà nội", ...]).
    public let compoundBigrams: [String: [String]]

    /// Set of known 2-to-3 syllable compound words used by `segmentContext` (Longest-Suffix MaxMatch).
    private let knownCompounds: Set<String>

    /// User personalization store.
    public let userStore: UserFrequencyStore

    /// Total number of unique single-syllable headwords in the dictionary.
    public var count: Int {
        bigrams.count
    }

    /// Whether the dictionary contains any entries.
    public var isEmpty: Bool {
        bigrams.isEmpty
    }

    // MARK: - Curated Multi-Syllable Conversational N-Grams & Linguistic Knowledge

    /// Canonical proper noun capitalization map (Rule 5).
    private static let properNounCasing: [String: String] = [
        "việt nam": "Việt Nam",
        "hà nội": "Hà Nội",
        "hồ chí minh": "Hồ Chí Minh",
        "tp hồ chí minh": "TP Hồ Chí Minh",
        "sài gòn": "Sài Gòn",
        "đà nẵng": "Đà Nẵng",
        "đà lạt": "Đà Lạt",
        "hải phòng": "Hải Phòng",
        "cần thơ": "Cần Thơ",
        "nha trang": "Nha Trang",
        "vũng tàu": "Vũng Tàu",
        " phú quốc": "Phú Quốc",
        "phú quốc": "Phú Quốc",
        "hà tĩnh": "Hà Tĩnh",
        "hà giang": "Hà Giang",
        "hà nam": "Hà Nam",
        "hà đông": "Hà Đông",
        "hà lan": "Hà Lan",
        "bình dương": "Bình Dương",
        "đồng nai": "Đồng Nai",
        "quảng ninh": "Quảng Ninh",
        "nghệ an": "Nghệ An",
        "thanh hóa": "Thanh Hóa",
        "thừa thiên huế": "Thừa Thiên Huế",
        "tiếng anh": "tiếng Anh",
        "tiếng việt": "tiếng Việt",
        "tiếng pháp": "tiếng Pháp",
        "tiếng trung": "tiếng Trung",
        "tiếng nhật": "tiếng Nhật",
        "tiếng hàn": "tiếng Hàn",
        "châu âu": "châu Âu",
        "châu á": "châu Á",
        "hoa kỳ": "Hoa Kỳ",
        "nhật bản": "Nhật Bản",
        "hàn quốc": "Hàn Quốc",
        "trung quốc": "Trung Quốc",
        "nguyễn du": "Nguyễn Du",
        "nguyễn huệ": "Nguyễn Huệ",
        "nguyễn trãi": "Nguyễn Trãi",
        "bác hồ": "Bác Hồ",
        "chợ rẫy": "Chợ Rẫy",
        "bạch mai": "Bạch Mai",
        "nhi đồng": "Nhi Đồng",
        "bách khoa": "Bách Khoa",
        "quốc gia": "Quốc gia"
    ]

    /// Proper-noun single-word continuations when the preceding headword is capitalized (e.g. "Hà " -> "Nội", "Lan").
    private static let capitalizedProperContinuations: [String: [String]] = [
        "hà": ["Nội", "Lan", "Giang", "Tĩnh", "Nam", "Đông"],
        "việt": ["Nam", "Kiều"],
        "sài": ["Gòn"],
        "đà": ["Nẵng", "Lạt"],
        "hồ": ["Chí Minh", "Tây", "Gươm"],
        "nguyễn": ["Du", "Huệ", "Trãi", "Ái Quốc"],
        "trần": ["Hưng Đạo", "Phú", "Nhân Tông"],
        "lê": ["Lợi", "Thánh Tông", "Duẩn"],
        "lý": ["Thường Kiệt", "Thái Tổ"],
        "anh": ["Minh", "Tuấn", "Dũng", "Khoa", "Nam"],
        "chị": ["Lan", "Hương", "Mai", "Thảo", "Ngọc"],
        "bình": ["Dương", "Định", "Phước", "Thuận"],
        "quảng": ["Ninh", "Nam", "Ngãi", "Bình", "Trị"],
        "hải": ["Phòng", "Dương"],
        "cần": ["Thơ"],
        "nha": ["Trang"],
        "vũng": ["Tàu"],
        "phú": ["Quốc", "Thọ", "Yên"],
        "đồng": ["Nai", "Tháp"],
        "thanh": ["Hóa", "Xuân"],
        "nghệ": ["An"]
    ]

    /// High-priority Trigram / Multi-Syllable Context predictions (Rule 1 & Rule 2).
    /// Keys are 2-to-4 syllable suffixes before the cursor; values are ordered next-word/phrase predictions.
    private static let contextualMultiGrams: [String: [String]] = [
        // Disambiguating "học" by preceding context (Rule 1 showcase)
        "đi học": ["tiếng Anh", "ở trường", "thêm", "về", "sớm"],
        "đang đi học": ["tiếng Anh", "ở trường", "thêm", "về"],
        "tôi học": ["bài", "được", "về", "tiếng Anh", "lớp"],
        "hôm nay tôi học": ["bài", "được", "về", "tiếng Anh"],
        "em học": ["bài", "lớp", "tiếng Anh", "được", "ở trường"],
        "đang học": ["bài", "lớp", "tiếng Anh", "đại học", "online"],
        "trường tiểu học": ["Nguyễn Du", "này", "của tôi", "quốc tế", "công lập"],
        "tiểu học": ["Nguyễn Du", "này", "của tôi", "quốc tế", "công lập"],
        "trường đại học": ["Quốc gia", "Bách Khoa", "Kinh tế", "Sư phạm", "Y Dược"],
        "đại học": ["Quốc gia", "Bách Khoa", "Kinh tế", "Sư phạm", "công nghệ"],
        "trường mầm non": ["này", "quốc tế", "của bé", "công lập"],
        "mầm non": ["quốc tế", "công lập", "này", "tư thục"],
        "học sinh": ["đang", "của", "lớp", "có", "giỏi"],

        // Disambiguating "thành" vs "thành phố" vs "tôi thành" (Rule 1 & Rule 2)
        "thành phố": ["Hồ Chí Minh", "Hà Nội", "Đà Nẵng", "này", "lớn"],
        "ở thành phố": ["Hồ Chí Minh", "Hà Nội", "Đà Nẵng", "này"],
        "tại thành phố": ["Hồ Chí Minh", "Hà Nội", "Đà Nẵng", "này"],
        "tôi thành": ["công", "thật", "thạo", "lập"],
        "đã thành": ["công", "thói quen", "hình", "lập", "hiện thực"],
        "trở thành": ["một", "người", "hiện thực", "đối tác", "thành viên"],
        "hoàn thành": ["công việc", "nhiệm vụ", "tốt", "xong", "đúng hạn"],

        // Disambiguating "công ty", "giáo viên", "bệnh viện", "điện thoại" (Rule 2)
        "công ty": ["tôi", "chúng tôi", "đang", "có", "cổ phần"],
        "ở công ty": ["tôi", "chúng tôi", "đang", "có", "mới"],
        "công việc": ["của", "hiện tại", "kinh doanh", "hàng ngày", "mới"],
        "công nghệ": ["thông tin", "mới", "cao", "số", "hiện đại"],
        "giáo viên": ["chủ nhiệm", "tiếng Anh", "mầm non", "dạy", "của"],
        "giáo dục": ["đào tạo", "mầm non", "phổ thông", "đại học", "hiện đại"],
        "bệnh viện": ["đa khoa", "Chợ Rẫy", "Bạch Mai", "Nhi Đồng", "tuyến trên"],
        "bệnh nhân": ["đang", "được", "này", "cần", "nặng"],
        "điện thoại": ["di động", "của tôi", "thông minh", "bàn", "liên hệ"],

        // Pronouns + Modal verbs (Conversational flow)
        "tôi muốn": ["hỏi", "biết", "mua", "đi", "làm"],
        "tôi đang": ["ở", "làm", "đi", "học", "cần"],
        "tôi là": ["người", "nhân viên", "học sinh", "sinh viên", "một"],
        "tôi có": ["thể", "một", "nhiều", "việc", "câu hỏi"],
        "tôi không": ["biết", "thể", "có", "muốn", "hiểu"],
        "tôi sẽ": ["đi", "làm", "gửi", "liên hệ", "cố gắng"],
        "tôi đã": ["nhận được", "hoàn thành", "làm", "gửi", "thấy"],
        "chúng tôi": ["đang", "sẽ", "đã", "muốn", "có", "rất"],
        "chúng ta": ["cần", "sẽ", "đang", "có thể", "nên", "hãy"],
        "mình muốn": ["hỏi", "nhờ", "mua", "đi", "tìm"],
        "mình đang": ["ở", "làm", "bận", "đi", "cần"],
        "bạn có": ["thể", "biết", "muốn", "rảnh", "ở"],
        "bạn đang": ["làm gì", "ở đâu", "đi", "học", "làm"],
        "anh chị": ["ơi", "cho em hỏi", "có", "đang", "vui lòng"],
        "cho em": ["hỏi", "xin", "gửi", "biết", "đăng ký"],
        "cho mình": ["hỏi", "xin", "biết", "đặt", "xem"],
        "cho tôi": ["hỏi", "biết", "xin", "xem", "một"],

        // Common greetings, time expressions, and connectors
        "xin chào": ["bạn", "anh chị", "mọi người", "các bạn", "quý khách"],
        "cảm ơn": ["bạn", "anh", "chị", "nhiều", "mọi người"],
        "xin lỗi": ["bạn", "anh", "chị", "vì", "nhé"],
        "hôm nay": ["tôi", "mình", "bạn", "trời", "đi làm"],
        "ngày mai": ["tôi", "mình", "sẽ", "đi", "có"],
        "hiện nay": ["đang", "có", "nhiều", "chúng tôi", "trên"],
        "hiện tại": ["tôi", "mình", "đang", "chưa", "có"],
        "cộng đồng": ["mạng", "quốc tế", "người Việt", "doanh nghiệp", "xã hội"],
        "việt nam": ["đất nước", "chúng ta", "hiện nay", "phát triển", "vô địch"],
        "hà nội": ["Việt Nam", "hôm nay", "mùa thu", "của tôi"],
        "hồ chí minh": ["Việt Nam", "thành phố", "hôm nay"],
        "có thể": ["giúp", "làm", "cho", "sẽ", "không"],
        "không thể": ["nào", "chấp nhận", "tin được", "thiếu", "quên"],
        "không có": ["gì", "thời gian", "vấn đề", "ai", "nhiều"],
        "chúc mừng": ["năm mới", "sinh nhật", "bạn", "anh chị", "thành công"]
    ]

    /// High-quality sentence starters shown when the text field is empty or right after sentence punctuation.
    public static let defaultSentenceStarters: [String] = [
        "Tôi", "Bạn", "Xin chào", "Cảm ơn", "Hôm nay"
    ]

    /// Common modal/pronoun words before a verb/adjective that shift `thành` toward `công/thật` rather than `phố`.
    private static let verbalPrecedingMarkers: Set<String> = [
        "tôi", "mình", "bạn", "anh", "chị", "em", "họ", "nó", "chúng",
        "đã", "đang", "sẽ", "vẫn", "cũng", "rất", "khá", "chưa", "không",
        "trở", "biến", "tạo", "đạt", "chuyển", "hình", "tán", "đồng"
    ]

    // MARK: - Initialization

    /// Initializes the suggestion engine by loading the dictionary from a resource `Bundle`.
    public init(bundle: Bundle? = nil, userStore: UserFrequencyStore = .shared) {
        self.userStore = userStore
        let targetBundle: Bundle = bundle ?? Bundle.vieLotusCore
        #if canImport(ObjectiveC)
        let (loadedBigrams, compounds, compoundMap): ([String: [String]], Set<String>, [String: [String]]) = autoreleasepool {
            let dict: [String: [String]]
            if let jsonURL = targetBundle.url(forResource: "TuDienTuGhep", withExtension: "json"),
               let data = try? Data(contentsOf: jsonURL, options: .mappedIfSafe),
               !data.isEmpty,
               let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
                dict = parsed
            } else if let txtURL = targetBundle.url(forResource: "TuDienTuGhep", withExtension: "txt") {
                dict = Self.parse(fileURL: txtURL)
            } else {
                dict = [:]
            }
            let (c, m) = Self.buildCompoundStructures(from: dict)
            return (dict, c, m)
        }
        #else
        let loadedBigrams: [String: [String]]
        if let jsonURL = targetBundle.url(forResource: "TuDienTuGhep", withExtension: "json"),
           let data = try? Data(contentsOf: jsonURL, options: .mappedIfSafe),
           !data.isEmpty,
           let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
            loadedBigrams = parsed
        } else if let txtURL = targetBundle.url(forResource: "TuDienTuGhep", withExtension: "txt") {
            loadedBigrams = Self.parse(fileURL: txtURL)
        } else {
            loadedBigrams = [:]
        }
        let (compounds, compoundMap) = Self.buildCompoundStructures(from: loadedBigrams)
        #endif
        self.bigrams = loadedBigrams
        self.knownCompounds = compounds
        self.compoundBigrams = compoundMap
    }

    /// Initializes the suggestion engine with an in-memory dictionary.
    public init(dictionary: [String: [String]], userStore: UserFrequencyStore = .shared) {
        self.userStore = userStore
        self.bigrams = dictionary
        let (compounds, compoundMap) = Self.buildCompoundStructures(from: dictionary)
        self.knownCompounds = compounds
        self.compoundBigrams = compoundMap
    }

    /// Initializes the suggestion engine by parsing a text or JSON file at the given URL.
    public init(fileURL: URL, userStore: UserFrequencyStore = .shared) {
        self.userStore = userStore
        let loadedBigrams: [String: [String]]
        if fileURL.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
               let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
                loadedBigrams = parsed
            } else {
                loadedBigrams = [:]
            }
        } else {
            loadedBigrams = Self.parse(fileURL: fileURL)
        }
        self.bigrams = loadedBigrams
        let (compounds, compoundMap) = Self.buildCompoundStructures(from: loadedBigrams)
        self.knownCompounds = compounds
        self.compoundBigrams = compoundMap
    }

    /// Initializes the suggestion engine by parsing raw text.
    public init(parsingText text: String, userStore: UserFrequencyStore = .shared) {
        self.userStore = userStore
        let loadedBigrams = Self.parse(text: text)
        self.bigrams = loadedBigrams
        let (compounds, compoundMap) = Self.buildCompoundStructures(from: loadedBigrams)
        self.knownCompounds = compounds
        self.compoundBigrams = compoundMap
    }

    /// Builds the multi-syllable compound set and 2-syllable compound continuation index from single-head bigrams + curated N-grams.
    private static func buildCompoundStructures(
        from singleBigrams: [String: [String]]
    ) -> (Set<String>, [String: [String]]) {
        var compounds = Set<String>(minimumCapacity: 16384)
        var multiMap: [String: [String]] = [:]
        multiMap.reserveCapacity(2048)

        // Seed curated multi-grams first (highest priority)
        for (key, values) in contextualMultiGrams {
            compounds.insert(key)
            multiMap[key] = values
        }

        // Extract 2-syllable compounds and 3+ syllable continuations from TuDienTuGhep
        for (head, tails) in singleBigrams {
            var singleIdx = 0
            var multiIdx = 0
            for tail in tails {
                let parts = tail.split(whereSeparator: { $0.isWhitespace })
                if parts.count == 1 {
                    // Top 25 2-syllable compounds per head are registered for MaxMatch segmentation
                    if singleIdx < 25 {
                        compounds.insert("\(head) \(parts[0])")
                    }
                    singleIdx += 1
                } else if parts.count >= 2 {
                    let twoSyllableHead = "\(head) \(parts[0])"
                    let remainder = parts.dropFirst().joined(separator: " ")
                    if multiIdx < 40 {
                        compounds.insert(twoSyllableHead)
                    }
                    var list = multiMap[twoSyllableHead] ?? []
                    if list.count < 12 && !list.contains(where: { $0.caseInsensitiveCompare(remainder) == .orderedSame }) {
                        list.append(remainder)
                        multiMap[twoSyllableHead] = list
                    }
                    multiIdx += 1
                }
            }
        }
        return (compounds, multiMap)
    }

    // MARK: - Legacy & File Parsing APIs

    /// Parses a file at the specified URL into a bigram dictionary.
    public static func parse(fileURL: URL) -> [String: [String]] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return [:]
        }
        return parse(text: content)
    }

    /// Parses string text into a bigram dictionary.
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

    // MARK: - Core 5-Stage Context-Aware Pipeline

    /// Main entry point for the Vietnamese Context-Aware Suggestion Engine.
    ///
    /// Executes:
    /// `detectInputState -> detectLanguage -> segmentContext -> generateCandidates -> score & filter -> topK`
    public func suggest(context: SuggestionInputContext, limit: Int = 5) -> [SuggestionCandidate] {
        guard limit > 0, context.typingMode == .vietnamese else { return [] }

        let fullBefore: String = {
            if context.isComposing, !context.composingWord.isEmpty, !context.beforeContext.hasSuffix(context.composingWord) {
                return context.beforeContext + context.composingWord
            }
            return context.beforeContext
        }()
        let activeCloser = Self.unclosedBracketClosers(in: fullBefore).first

        func withClosingBracketIfNeeded(_ items: [SuggestionCandidate]) -> [SuggestionCandidate] {
            guard let closer = activeCloser else { return items }
            if items.contains(where: { $0.displayText == closer }) { return items }
            let closerCand = SuggestionCandidate(
                displayText: closer,
                insertionText: closer,
                replacementMode: .appendDirectNoSpace,
                source: .urlOrEmailSnippet,
                score: 8.5,
                isPrimary: items.isEmpty
            )
            var out = items
            if out.count < limit {
                out.append(closerCand)
            } else if limit >= 2 {
                out[limit - 1] = closerCand
            }
            return out
        }

        let segmented = analyzeAndSegment(context)

        // When the user is at an empty field or sentence start, return high-quality sentence starters
        switch segmented.state {
        case .emptyOrSentenceStart:
            let starters = Self.defaultSentenceStarters.prefix(limit).enumerated().map { idx, word in
                SuggestionCandidate(
                    displayText: word,
                    insertionText: word,
                    replacementMode: .appendNextWord,
                    source: .sentenceStarter,
                    score: 10.0 - Double(idx) * 0.5,
                    isPrimary: false
                )
            }
            return withClosingBracketIfNeeded(starters)
        case .afterSentencePunctuation:
            let starters = Self.defaultSentenceStarters.prefix(limit).enumerated().map { idx, word in
                SuggestionCandidate(
                    displayText: word,
                    insertionText: word,
                    replacementMode: .appendNextWord,
                    source: .sentenceStarter,
                    score: 9.0 - Double(idx) * 0.5,
                    isPrimary: false
                )
            }
            return withClosingBracketIfNeeded(starters)
        default:
            break
        }

        // Rule 5: If the user just finished an English/technical word after Space, do not pollute the bar with random Vietnamese words
        if !context.isComposing && segmented.language == .englishOrTechnical {
            return withClosingBracketIfNeeded([])
        }

        let rawCandidates = generateCandidates(context: context, segmented: segmented)
        guard !rawCandidates.isEmpty else { return withClosingBracketIfNeeded([]) }

        // Deduplicate preserving highest-scored entry per normalized displayText, while keeping Slot 0 pinned when composing
        var pinnedFirst: SuggestionCandidate?
        var pool: [SuggestionCandidate] = []
        pool.reserveCapacity(rawCandidates.count)

        for cand in rawCandidates {
            if cand.replacementMode == .keepComposing && pinnedFirst == nil {
                pinnedFirst = cand
            } else if isValid(cand, for: context, segmented: segmented) {
                pool.append(cand)
            }
        }

        // Sort pool by contextual ranker score descending
        pool.sort { a, b in
            if abs(a.score - b.score) > 1e-6 {
                return a.score > b.score
            }
            return a.displayText.count < b.displayText.count
        }

        var finalResults: [SuggestionCandidate] = []
        var seenDisplay = Set<String>()

        if let pinned = pinnedFirst {
            finalResults.append(pinned)
            seenDisplay.insert(pinned.displayText.lowercased())
        }

        let minimumConfidenceScore = 1.25
        for cand in pool {
            guard finalResults.count < limit else { break }
            guard cand.score >= minimumConfidenceScore else { continue }
            let key = cand.displayText.lowercased()
            guard !seenDisplay.contains(key) else { continue }
            seenDisplay.insert(key)
            finalResults.append(cand)
        }

        // Highlight first candidate if composing or if top prediction has very high confidence
        if !finalResults.isEmpty && !context.isComposing {
            let first = finalResults[0]
            let shouldHighlight = first.score >= 5.5
            finalResults[0] = SuggestionCandidate(
                displayText: first.displayText,
                insertionText: first.insertionText,
                replacementMode: first.replacementMode,
                source: first.source,
                score: first.score,
                isPrimary: shouldHighlight
            )
        }

        return withClosingBracketIfNeeded(finalResults)
    }

    // MARK: - Stage 1, 2 & 3: Context Analyzer & Phrase Segmenter

    /// Analyzes the text around the cursor and segments the last 2-4 syllables into Vietnamese lexical units.
    public func analyzeAndSegment(_ context: SuggestionInputContext) -> SegmentedContext {
        let before = context.beforeContext
        let composing = context.composingWord.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract active clause (after the last sentence-ending punctuation)
        let sentenceBreakChars: Set<Character> = [".", "!", "?", "\n", ";"]
        var activeClause = before
        if !context.isComposing {
            let trimmedRight = before.trimmingCharacters(in: .whitespaces)
            if trimmedRight.isEmpty {
                return SegmentedContext(
                    state: .emptyOrSentenceStart,
                    language: .vietnamese,
                    rawTokens: [],
                    segmentedUnits: [],
                    lastUnit: "",
                    precedingUnit: nil,
                    lastSyllable: "",
                    lastRawTokenOriginal: "",
                    isCapitalizedHead: false,
                    isAllCapsHead: false
                )
            }
            if let lastChar = trimmedRight.last, sentenceBreakChars.contains(lastChar) {
                return SegmentedContext(
                    state: .afterSentencePunctuation,
                    language: .vietnamese,
                    rawTokens: [],
                    segmentedUnits: [],
                    lastUnit: "",
                    precedingUnit: nil,
                    lastSyllable: "",
                    lastRawTokenOriginal: "",
                    isCapitalizedHead: false,
                    isAllCapsHead: false
                )
            }
        }

        // Strip active composingWord suffix from `before` if `beforeContext` already includes it
        if context.isComposing, !composing.isEmpty, activeClause.hasSuffix(composing) {
            activeClause = String(activeClause.dropLast(composing.count))
        }

        if let lastPunctIdx = activeClause.lastIndex(where: { sentenceBreakChars.contains($0) }) {
            activeClause = String(activeClause[activeClause.index(after: lastPunctIdx)...])
        }

        // Tokenize clause into last 6 words max
        let rawWords = activeClause
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        let tailRawOriginal = Array(rawWords.suffix(4))
        let tailLower = tailRawOriginal.map { $0.lowercased() }

        // Longest-Suffix MaxMatch Segmentation (up to 3-syllable compounds)
        let segmentedUnits = segmentTokensMaxMatch(tailLower)
        let lastUnit = segmentedUnits.last ?? ""
        let precedingUnit: String? = segmentedUnits.count >= 2 ? segmentedUnits[segmentedUnits.count - 2] : nil
        let lastSyllable = tailLower.last ?? ""
        let lastOriginal = tailRawOriginal.last ?? ""

        let isAllCaps = lastOriginal.count > 1 && lastOriginal == lastOriginal.uppercased() && lastOriginal != lastOriginal.lowercased()
        let isCap = !lastOriginal.isEmpty && lastOriginal.first?.isUppercase == true

        // Determine input state
        let state: SuggestionInputState
        if context.isComposing && !composing.isEmpty {
            if context.macroEnabled && MacroEngine.shared.lookup(word: composing) != nil {
                state = .macroCandidate
            } else {
                state = .composingSyllable
            }
        } else if !context.afterContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .midSentenceEdit
        } else if tailLower.isEmpty {
            state = .emptyOrSentenceStart
        } else {
            state = .afterWordBoundary
        }

        // Determine language register (Rule 5)
        let targetWordForLang = context.isComposing ? composing : lastOriginal
        let language = detectLanguageRegister(word: targetWordForLang, isCapitalized: isCap)

        return SegmentedContext(
            state: state,
            language: language,
            rawTokens: tailLower,
            segmentedUnits: segmentedUnits,
            lastUnit: lastUnit,
            precedingUnit: precedingUnit,
            lastSyllable: lastSyllable,
            lastRawTokenOriginal: lastOriginal,
            isCapitalizedHead: isCap,
            isAllCapsHead: isAllCaps
        )
    }

    /// Segments an array of lowercased Vietnamese syllables into compound lexical units using greedy right-to-left MaxMatch.
    public func segmentTokensMaxMatch(_ tokens: [String]) -> [String] {
        guard !tokens.isEmpty else { return [] }
        var units: [String] = []
        var idx = tokens.count
        while idx > 0 {
            if idx >= 3 {
                let tri = "\(tokens[idx - 3]) \(tokens[idx - 2]) \(tokens[idx - 1])"
                if knownCompounds.contains(tri) {
                    units.append(tri)
                    idx -= 3
                    continue
                }
            }
            if idx >= 2 {
                let bi = "\(tokens[idx - 2]) \(tokens[idx - 1])"
                if knownCompounds.contains(bi) {
                    units.append(bi)
                    idx -= 2
                    continue
                }
            }
            units.append(tokens[idx - 1])
            idx -= 1
        }
        return units.reversed()
    }

    /// Detects whether a token is Vietnamese, English/technical, or Proper Noun/Title Case.
    private func detectLanguageRegister(word: String, isCapitalized: Bool) -> SuggestionLanguageContext {
        let cleaned = word.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .vietnamese }
        let lower = cleaned.lowercased()

        // Mixed-case mid-word capitals like "OpenAI", "iOS", "macOS", "ViewModel" -> technical
        if cleaned.count > 1 && cleaned.dropFirst().contains(where: { $0.isUppercase }) && cleaned != cleaned.uppercased() {
            return .englishOrTechnical
        }

        // Non-ASCII Vietnamese diacritics immediately confirm Vietnamese
        if lower.unicodeScalars.contains(where: { $0.value > 127 }) {
            return isCapitalized ? .properNounOrTitleCase : .vietnamese
        }

        // Known headword in Vietnamese dictionary or known syllable
        if bigrams[lower] != nil || VietnameseSyllableDictionary.shared.isValidSyllable(lower) {
            return isCapitalized ? .properNounOrTitleCase : .vietnamese
        }

        // ASCII letters with English orthographic patterns (f, j, w, z, or length >= 4 not in VN dictionary)
        if lower.contains(where: { "fjwz".contains($0) }) || cleaned.count >= 5 {
            return .englishOrTechnical
        }

        return isCapitalized ? .properNounOrTitleCase : .vietnamese
    }

    // MARK: - Stage 4: Multi-Source Candidate Generator & Stage 5: Contextual Ranker

    private func generateCandidates(
        context: SuggestionInputContext,
        segmented: SegmentedContext
    ) -> [SuggestionCandidate] {
        var candidates: [SuggestionCandidate] = []
        let now = Date().timeIntervalSince1970

        if context.isComposing {
            let composing = context.composingWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !composing.isEmpty else { return [] }
            let lowerComposing = composing.lowercased()

            // 1. Rule 3: Always preserve exact user input in Slot 0
            candidates.append(
                SuggestionCandidate(
                    displayText: composing,
                    insertionText: composing,
                    replacementMode: .keepComposing,
                    source: .composingEcho,
                    score: 100.0,
                    isPrimary: true
                )
            )

            // 2. Macro shortcut check (Rule 4 / Section 4)
            if context.macroEnabled, let expanded = MacroEngine.shared.lookup(word: composing) {
                candidates.append(
                    SuggestionCandidate(
                        displayText: expanded,
                        insertionText: expanded,
                        replacementMode: .macroExpansion,
                        source: .macroExpansion,
                        score: 90.0,
                        isPrimary: false
                    )
                )
            }

            // 2a. P0.3 Bilingual Intent Twin Candidate (`sẽ <-> sex`, `í <-> is`, `hí <-> his`, `á <-> as`, `ì <-> if`, `rét <-> rest`, `thêm <-> theme`, `cân <-> cana`)
            // Ensures both the Vietnamese Telex syllable and the English raw literal remain 1 tap away in the suggestion bar.
            if let bilingualTwin = BilingualIntentArbiter.bilingualTwinCandidate(
                composingWord: composing,
                rawWord: context.rawWord,
                context: context.beforeContext
            ), bilingualTwin.displayText.lowercased() != lowerComposing {
                candidates.append(
                    SuggestionCandidate(
                        displayText: bilingualTwin.displayText,
                        insertionText: bilingualTwin.displayText,
                        replacementMode: .replaceComposing,
                        source: .prefixMatching,
                        score: max(89.0, bilingualTwin.score),
                        isPrimary: false
                    )
                )
            }

            // 2b. Relaxed-coda full-syllable completion (e.g. `khôg` -> `không`, `kêh` -> `kênh`, `ưg` -> `ưng`, `mìh` -> `mình`)
            let expandedSyllables = VietnameseSyllableDictionary.shared.expandedRelaxedCodaSyllables(lowerComposing)
            for (idx, expSyllable) in expandedSyllables.prefix(2).enumerated() {
                let formattedExp = formatCandidateText(
                    expSyllable,
                    headOriginal: composing,
                    isAllCaps: composing.count > 1 && composing == composing.uppercased() && composing != composing.lowercased(),
                    forceTitleCase: composing.first?.isUppercase == true
                )
                candidates.append(
                    SuggestionCandidate(
                        displayText: formattedExp,
                        insertionText: formattedExp,
                        replacementMode: .replaceComposing,
                        source: .prefixMatching,
                        score: 88.0 - Double(idx) * 2.0,
                        isPrimary: false
                    )
                )
            }

            // 3. If user is typing a prefix after a preceding word (e.g. "thành " + composing "ph"),
            // match continuations of `lastUnit` or `lastSyllable` that start with `lowerComposing`!
            if !segmented.lastSyllable.isEmpty && lowerComposing.count <= 5 {
                let contextSources = lookupContinuationsForSegmented(segmented)
                for (rankIdx, item) in contextSources.enumerated() where rankIdx < 25 {
                    let tailLower = item.text.lowercased()
                    if tailLower != lowerComposing && tailLower.hasPrefix(lowerComposing) {
                        let formatted = formatCandidateText(
                            item.text,
                            headOriginal: composing,
                            isAllCaps: composing.count > 1 && composing == composing.uppercased() && composing != composing.lowercased(),
                            forceTitleCase: composing.first?.isUppercase == true
                        )
                        let s = scoreCandidate(
                            candidateLower: tailLower,
                            baseLogProb: item.baseLogProb - Double(rankIdx) * 0.12,
                            popularity: item.popularity,
                            prefixMatchBoost: 1.8,
                            contextKey: segmented.lastUnit,
                            lastSyllable: segmented.lastSyllable,
                            now: now
                        )
                        candidates.append(
                            SuggestionCandidate(
                                displayText: formatted,
                                insertionText: formatted,
                                replacementMode: .replaceComposing,
                                source: .prefixMatching,
                                score: s
                            )
                        )
                    }
                }
            }

            // 4. Compound completions where `composingWord` is the first syllable of a compound (e.g. "thành" -> "thành phố", "thành công")
            if segmented.language != .englishOrTechnical {
                let compIsAllCaps = composing.count > 1 && composing == composing.uppercased() && composing != composing.lowercased()
                let compIsCap = composing.first?.isUppercase == true

                if compIsCap && !compIsAllCaps, let properTails = Self.capitalizedProperContinuations[lowerComposing] {
                    for (idx, properTail) in properTails.prefix(3).enumerated() {
                        let fullCompound = "\(composing) \(properTail)"
                        let s = scoreCandidate(
                            candidateLower: fullCompound.lowercased(),
                            baseLogProb: 3.4 - Double(idx) * 0.2,
                            popularity: 2.2,
                            prefixMatchBoost: 1.2,
                            contextKey: lowerComposing,
                            lastSyllable: segmented.lastSyllable,
                            now: now
                        )
                        candidates.append(
                            SuggestionCandidate(
                                displayText: fullCompound,
                                insertionText: fullCompound,
                                replacementMode: .replaceComposing,
                                source: .compoundCompletion,
                                score: s
                            )
                        )
                    }
                }

                let tails = contextualBigramsForHead(lowerComposing, precedingSyllable: segmented.lastSyllable)
                for (idx, tail) in tails.prefix(8).enumerated() {
                    let formattedTail = formatTailForComposingHead(composing: composing, headLower: lowerComposing, tailLower: tail)
                    let fullCompound = "\(composing) \(formattedTail)"
                    let s = scoreCandidate(
                        candidateLower: fullCompound.lowercased(),
                        baseLogProb: 3.1 - Double(idx) * 0.22,
                        popularity: max(0.5, 2.0 - Double(idx) * 0.15),
                        prefixMatchBoost: 1.0,
                        contextKey: lowerComposing,
                        lastSyllable: segmented.lastSyllable,
                        now: now
                    )
                    candidates.append(
                        SuggestionCandidate(
                            displayText: fullCompound,
                            insertionText: fullCompound,
                            replacementMode: .replaceComposing,
                            source: .compoundCompletion,
                            score: s
                        )
                    )
                }
            }

            return candidates
        }

        // --- Post-Space / Idle Prediction Mode (`isComposing == false`) ---
        guard !segmented.lastSyllable.isEmpty else { return [] }

        // 1. Check 3/4-syllable & 2-syllable compound context matches first (Rule 1 & Rule 2)
        let multiItems = lookupContinuationsForSegmented(segmented)
        for (idx, item) in multiItems.enumerated() {
            let formatted = formatPostSpaceCandidate(item.text, segmented: segmented)
            let s = scoreCandidate(
                candidateLower: item.text.lowercased(),
                baseLogProb: item.baseLogProb - Double(idx) * 0.18,
                popularity: item.popularity,
                prefixMatchBoost: 0.0,
                contextKey: segmented.lastUnit,
                lastSyllable: segmented.lastSyllable,
                now: now
            )
            candidates.append(
                SuggestionCandidate(
                    displayText: formatted,
                    insertionText: formatted,
                    replacementMode: .appendNextWord,
                    source: item.source,
                    score: s
                )
            )
        }

        return candidates
    }

    private struct RawContinuation {
        let text: String
        let baseLogProb: Double
        let popularity: Double
        let source: SuggestionSource
    }

    /// Generates raw continuations ordered from most specific context (3-gram / 2-syllable compound) down to 1-syllable headword backoff.
    private func lookupContinuationsForSegmented(_ segmented: SegmentedContext) -> [RawContinuation] {
        var results: [RawContinuation] = []
        let tokens = segmented.rawTokens

        // 1. 3-syllable suffix lookup (4-gram prediction)
        if tokens.count >= 3 {
            let triKey = "\(tokens[tokens.count - 3]) \(tokens[tokens.count - 2]) \(tokens[tokens.count - 1])"
            if let matches = Self.contextualMultiGrams[triKey] {
                for (i, m) in matches.enumerated() {
                    results.append(RawContinuation(text: m, baseLogProb: 4.2 - Double(i) * 0.15, popularity: 2.5, source: .trigramContext))
                }
            }
        }

        // 2. 2-syllable suffix lookup (Trigram / 2-syllable Compound Head prediction, e.g. "thành phố", "tôi muốn", "đi học", "công ty")
        if tokens.count >= 2 {
            let biKey = "\(tokens[tokens.count - 2]) \(tokens[tokens.count - 1])"
            if let matches = Self.contextualMultiGrams[biKey] {
                for (i, m) in matches.enumerated() {
                    results.append(RawContinuation(text: m, baseLogProb: 3.9 - Double(i) * 0.15, popularity: 2.4, source: .trigramContext))
                }
            }
            if let compoundMatches = compoundBigrams[biKey] {
                for (i, m) in compoundMatches.prefix(8).enumerated() {
                    results.append(RawContinuation(text: m, baseLogProb: 3.4 - Double(i) * 0.16, popularity: 2.0, source: .nextWordPrediction))
                }
            }
        }

        // 3. Rule 5: Proper Noun / Capitalized Headword lookup (e.g. "Hà " -> "Nội", "Lan")
        if segmented.isCapitalizedHead && !segmented.isAllCapsHead,
           let properMatches = Self.capitalizedProperContinuations[segmented.lastSyllable] {
            for (i, m) in properMatches.prefix(5).enumerated() {
                results.append(RawContinuation(text: m, baseLogProb: 3.7 - Double(i) * 0.18, popularity: 2.3, source: .compoundCompletion))
            }
        }

        // 4. 1-syllable headword lookup with verbal-context adjustment (e.g. "tôi thành " -> "công" before "phố")
        let precedingSyllable: String = tokens.count >= 2 ? tokens[tokens.count - 2] : ""
        let singleMatches = contextualBigramsForHead(segmented.lastSyllable, precedingSyllable: precedingSyllable)
        // If `segmented.lastUnit` is ALREADY a complete 2-syllable compound (e.g. "thành phố", "công ty", "học sinh"),
        // lower the weight of raw 1-syllable backoff on the second syllable ("phố", "ty", "sinh") so compound predictions win!
        let isAlreadyCompound = segmented.lastUnit.contains(" ")
        let singleBaseProb = isAlreadyCompound ? 1.9 : 3.0

        for (i, m) in singleMatches.prefix(12).enumerated() {
            results.append(
                RawContinuation(
                    text: m,
                    baseLogProb: singleBaseProb - Double(i) * 0.18,
                    popularity: max(0.4, 2.0 - Double(i) * 0.14),
                    source: .compoundCompletion
                )
            )
        }

        return results
    }

    /// Returns continuations for a 1-syllable headword, dynamically re-ordering when preceded by a verbal/pronoun marker (Rule 2).
    private func contextualBigramsForHead(_ head: String, precedingSyllable: String) -> [String] {
        guard var list = bigrams[head], !list.isEmpty else { return [] }
        if head == "thành" && Self.verbalPrecedingMarkers.contains(precedingSyllable) {
            let verbalPreferred = ["công", "thật", "thạo", "lập", "tích", "đạt"]
            let front = verbalPreferred.filter { list.contains($0) }
            let rest = list.filter { !front.contains($0) }
            list = front + rest
        }
        return list
    }

    // MARK: - Stage 5: Probabilistic Scoring & Filtering (Rule 4)

    /// Evaluates `S(c) = alpha * log P(c | context) + beta * F(c) + gamma * U(c) + delta * M(c) - lambda * R(c)`.
    private func scoreCandidate(
        candidateLower: String,
        baseLogProb: Double,
        popularity: Double,
        prefixMatchBoost: Double,
        contextKey: String,
        lastSyllable: String,
        now: TimeInterval
    ) -> Double {
        let alpha = 1.35
        let beta = 0.85
        let gamma = 1.25
        let delta = 1.00
        let lambda = 1.50

        let userBoost = userStore.userBoost(for: candidateLower, contextKey: contextKey, now: now)

        // Penalty R(c) for repeating the last syllable or overly long generic tails
        var penalty = 0.0
        let wordCount = candidateLower.split(whereSeparator: { $0.isWhitespace }).count
        if candidateLower == lastSyllable {
            penalty += 3.0
        }
        if wordCount >= 4 || (wordCount == 3 && Self.properNounCasing[candidateLower] == nil) {
            penalty += Double(wordCount - 2) * 0.35
        }

        return alpha * baseLogProb
            + beta * popularity
            + gamma * userBoost
            + delta * prefixMatchBoost
            - lambda * penalty
    }

    private func isValid(_ candidate: SuggestionCandidate, for context: SuggestionInputContext, segmented: SegmentedContext) -> Bool {
        let text = candidate.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let lower = text.lowercased()
        // Never suggest exact duplicate of the last committed syllable in post-space mode
        if !context.isComposing && lower == segmented.lastSyllable {
            return false
        }
        return true
    }

    // MARK: - Casing & Proper Noun Formatting Helpers

    private func formatTailForComposingHead(composing: String, headLower: String, tailLower: String) -> String {
        if composing.count > 1 && composing == composing.uppercased() && composing != composing.lowercased() {
            return tailLower.uppercased()
        }
        let fullLower = "\(headLower) \(tailLower)"
        if let properFull = Self.properNounCasing[fullLower] {
            let parts = properFull.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                return String(parts[1])
            }
        }
        if let properTail = Self.properNounCasing[tailLower] {
            return properTail
        }
        return Self.applyCasing(of: composing, to: tailLower)
    }

    private func formatPostSpaceCandidate(_ rawCandidate: String, segmented: SegmentedContext) -> String {
        if segmented.isAllCapsHead {
            return rawCandidate.uppercased()
        }
        let lower = rawCandidate.lowercased()
        if let proper = Self.properNounCasing[lower] {
            return proper
        }
        let combinedLower = "\(segmented.lastSyllable) \(lower)"
        if let properCombined = Self.properNounCasing[combinedLower] {
            let parts = properCombined.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                return String(parts[1])
            }
        }
        return rawCandidate
    }

    private func formatCandidateText(
        _ rawCandidate: String,
        headOriginal: String,
        isAllCaps: Bool,
        forceTitleCase: Bool
    ) -> String {
        if isAllCaps {
            return rawCandidate.uppercased()
        }
        let lower = rawCandidate.lowercased()
        if let proper = Self.properNounCasing[lower] {
            return proper
        }
        if forceTitleCase, let first = rawCandidate.first {
            return String(first).uppercased() + rawCandidate.dropFirst()
        }
        return Self.applyCasing(of: headOriginal, to: rawCandidate)
    }

    // MARK: - Backward-Compatible Public Query Methods

    /// Queries next-word suggestions for a given committed word or phrase.
    ///
    /// Supports both single-syllable headwords ("thành" -> ["phố", "công", ...]) and
    /// multi-syllable phrases ("thành phố" -> ["hồ chí minh", ...], with fallback to the last syllable).
    public func suggestions(for word: String, limit: Int? = nil) -> [String] {
        let rawKey = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rawKey.isEmpty else { return [] }

        let trimmedKey = rawKey.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

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

    /// Applies the casing pattern of a source word (e.g. ALL CAPS) to a candidate suggestion.
    public static func applyCasing(of source: String, to target: String) -> String {
        guard !source.isEmpty, !target.isEmpty else { return target }
        if source == source.uppercased() && source != source.lowercased() {
            return target.uppercased()
        }
        return target
    }

    /// Queries next-word suggestions for a given committed word, preserving uppercase styling.
    public func nextWordSuggestions(for word: String, limit: Int? = nil) -> [String] {
        let results = suggestions(for: word, limit: limit)
        return results.map { Self.applyCasing(of: word, to: $0) }
    }

    /// Generates full compound suggestions for an in-composition word.
    public func compoundSuggestions(for composingWord: String, limit: Int? = 4) -> [String] {
        let tails = suggestions(for: composingWord, limit: limit)
        guard !tails.isEmpty else { return [] }
        return tails.map { tail in
            let formattedTail = Self.applyCasing(of: composingWord, to: tail)
            return "\(composingWord) \(formattedTail)"
        }
    }

    /// Checks whether the dictionary contains suggestions for the given word.
    public func hasSuggestions(for word: String) -> Bool {
        !suggestions(for: word, limit: 1).isEmpty
    }

    /// Subscript access to suggestions for a given word.
    public subscript(word: String) -> [String] {
        suggestions(for: word)
    }

    /// Canonical 5 quick email domain completions offered when the user types `@` in any text field.
    public static let quickEmailDomains: [String] = [
        "gmail.com", "icloud.com", "outlook.com", "yahoo.com", "live.com"
    ]

    /// Opening-to-closing bracket pairs supported for instant 1-tap closing suggestions.
    public static let openingToClosingBracket: [Character: String] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "<": ">"
    ]

    /// Set of closing bracket tokens that attach directly without spaces.
    public static let closingBracketTokens: Set<String> = [")", "]", "}", ">"]

    /// Scans the active line of `text` before the cursor and returns any unclosed closing bracket delimiters
    /// in inner-to-outer order (e.g. `"("` -> `[")"]`, `"([hello"` -> `["]", ")"]`).
    public static func unclosedBracketClosers(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let currentLine = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? Substring(text)
        let recent = currentLine.suffix(64)
        var stack: [String] = []
        for ch in recent {
            if let closer = openingToClosingBracket[ch] {
                stack.append(closer)
            } else {
                let s = String(ch)
                if closingBracketTokens.contains(s), let idx = stack.lastIndex(of: s) {
                    stack.removeSubrange(idx..<stack.count)
                }
            }
        }
        return Array(stack.reversed())
    }

    /// Generates zero-latency URL / WebSearch / Email / Bracket snippet suggestions.
    /// Works across all fields (including `.standard` when the user types `@` or an opening bracket `(`, `[`, `{`, `<`).
    /// Returns `nil` when the field should fall through to standard Vietnamese / bilingual word suggestions.
    public static func contextualFieldSuggestions(
        fieldKind: SuggestionFieldKind,
        beforeContext: String,
        composingWord: String,
        rawWord: String,
        isComposing: Bool
    ) -> [SuggestionCandidate]? {
        let activeStem = isComposing ? (rawWord.isEmpty ? composingWord : rawWord) : ""
        let fullText: String = {
            if isComposing, !composingWord.isEmpty, beforeContext.hasSuffix(composingWord) {
                return String(beforeContext.dropLast(composingWord.count)) + activeStem
            }
            if isComposing, !activeStem.isEmpty, beforeContext.hasSuffix(activeStem) {
                return beforeContext
            }
            return beforeContext + activeStem
        }()
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        func makeSnippets(_ items: [String], maxCount: Int = 3) -> [SuggestionCandidate] {
            items.prefix(maxCount).enumerated().map { idx, text in
                SuggestionCandidate(
                    displayText: text,
                    insertionText: text,
                    replacementMode: .appendDirectNoSpace,
                    source: .urlOrEmailSnippet,
                    score: 1.0 - Double(idx) * 0.1,
                    isPrimary: idx == 0
                )
            }
        }

        // 1. Universal Opening Bracket `(`, `[`, `{`, `<` -> Immediate Closing Bracket `)`, `]`, `}`, `>`
        if !isComposing, let lastChar = fullText.last, let primaryCloser = openingToClosingBracket[lastChar] {
            var closers: [String] = [primaryCloser]
            for c in unclosedBracketClosers(in: fullText) where !closers.contains(c) {
                closers.append(c)
            }
            return makeSnippets(closers, maxCount: 3)
        }

        // 2. Universal `@` Email Domain Suggestions (`gmail.com`, `icloud.com`, `outlook.com`, `yahoo.com`, `live.com`)
        let endsWithWhitespace = fullText.last?.isWhitespace == true
        let activeToken = endsWithWhitespace ? "" : String(fullText.split(whereSeparator: \.isWhitespace).last ?? "")
        if !activeToken.isEmpty, activeToken.contains("@") {
            let afterAt = String(activeToken.split(separator: "@", omittingEmptySubsequences: false).last ?? "").lowercased()
            if afterAt.isEmpty {
                return makeSnippets(quickEmailDomains, maxCount: 5)
            }
            if !afterAt.contains(".") {
                let allEmailDomains = quickEmailDomains + ["hotmail.com", "edu.vn", "fpt.edu.vn"]
                let matches = allEmailDomains.filter { $0.hasPrefix(afterAt) && $0 != afterAt }
                if !matches.isEmpty {
                    var results = matches
                    if fieldKind == .emailAddress {
                        for fallback in [".com", ".vn", ".edu.vn"] where results.count < 3 && !results.contains(fallback) {
                            results.append(fallback)
                        }
                    }
                    return makeSnippets(results, maxCount: 5)
                }
            }
        }

        switch fieldKind {
        case .standard:
            return nil

        case .emailAddress:
            if trimmed.isEmpty {
                return makeSnippets(["@gmail.com", "@icloud.com", "@outlook.com"])
            }
            let lastToken = String(trimmed.split(whereSeparator: \.isWhitespace).last ?? "")
            if !lastToken.contains("@") {
                return makeSnippets(["@gmail.com", "@icloud.com", "@outlook.com"])
            }
            let afterAt = String(lastToken.split(separator: "@", omittingEmptySubsequences: false).last ?? "").lowercased()
            if afterAt.isEmpty {
                return makeSnippets(quickEmailDomains, maxCount: 5)
            }
            if afterAt.contains(".") {
                if afterAt.hasSuffix(".com") || afterAt.hasSuffix(".edu") || afterAt.hasSuffix(".gov") || afterAt.hasSuffix(".org") {
                    return makeSnippets([".vn", ".com", ".net"])
                }
                return makeSnippets([".com", ".vn", ".edu.vn"])
            }
            return makeSnippets([".com", ".vn", ".edu.vn"])

        case .url, .webSearch:
            if trimmed.isEmpty {
                return makeSnippets(["https://", "www.", ".com"])
            }
            // Once the user types a space, treat it as a multi-word search query and use normal Vietnamese suggestions
            if fullText.contains(where: \.isWhitespace) {
                return nil
            }
            let lowerFull = trimmed.lowercased()
            let lowerStem = activeStem.lowercased()

            if lowerFull == "https://" || lowerFull == "http://" {
                return makeSnippets(["www.", ".com", ".vn"])
            }
            if lowerFull.hasSuffix("www.") {
                return makeSnippets([".com", ".vn", ".net"])
            }
            if !lowerFull.contains("://") && !lowerFull.contains(".") {
                if "https://".hasPrefix(lowerFull) && (fieldKind == .url || lowerFull.count >= 2) {
                    return makeSnippets(["https://", "www.", ".com"])
                }
                if "http://".hasPrefix(lowerFull) && lowerFull.count >= 4 {
                    return makeSnippets(["http://", "https://", "www."])
                }
                if "www.".hasPrefix(lowerFull) && (fieldKind == .url || lowerFull.count >= 2) {
                    return makeSnippets(["www.", "https://", ".com"])
                }
            }
            let hasURLStructure = lowerFull.contains("://") || lowerFull.hasPrefix("www.") || lowerFull.contains(".") || lowerFull.contains("/")
            if fieldKind == .webSearch && !hasURLStructure {
                let candidateCheck = composingWord.isEmpty ? lowerFull : composingWord.lowercased()
                if !candidateCheck.allSatisfy(\.isASCII) || VietnameseSyllableDictionary.shared.isValidSyllable(candidateCheck) {
                    return nil
                }
            }
            if lowerFull.hasSuffix(".com") || lowerFull.hasSuffix(".net") || lowerFull.hasSuffix(".org") || lowerFull.hasSuffix(".edu") || lowerFull.hasSuffix(".gov") {
                return makeSnippets([".vn", "/", ".html"])
            }
            if lowerFull.hasSuffix(".vn") || lowerFull.hasSuffix(".app") || lowerFull.hasSuffix(".io") || lowerFull.hasSuffix(".dev") {
                return makeSnippets(["/", ".com", ".html"])
            }
            if lowerFull.hasSuffix("/") {
                return makeSnippets(["index.html", "login", "search"])
            }
            if !lowerStem.isEmpty && "www".hasPrefix(lowerStem) && (lowerFull.hasPrefix("https://") || lowerFull.hasPrefix("http://")) && !lowerFull.contains("www.") {
                return makeSnippets(["www.", ".com", ".vn"])
            }
            return makeSnippets([".com", ".vn", ".net"])
        }
    }
}
#endif
