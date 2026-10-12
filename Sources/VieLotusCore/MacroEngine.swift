import Foundation

/// One macro entry item suitable for SwiftUI List/Table and data binding.
public struct MacroEntry: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Thread-safe shorthand / macro replacement engine for Vietnamese typing.
public final class MacroEngine: @unchecked Sendable {
    public static let shared = MacroEngine(autoLoadFromDisk: true)

    public static let macrosDidChangeNotification = Notification.Name("org.vielotus.inputmethod.macrosDidChange")

    private var macros: [String: String] = [:]
    public var isEnabled: Bool = true
    public var autoSaveToDisk: Bool = true
    public var storageURL: URL?
    private var fileModificationDate: Date? = nil
    private let lock = NSLock()

    public static let defaultMacros: [String: String] = [
        // Địa danh Việt Nam phổ biến
        "vn": "Việt Nam",
        "sg": "Sài Gòn",
        "hn": "Hà Nội",
        "dn": "Đà Nẵng",
        "hp": "Hải Phòng",
        "ct": "Cần Thơ",
        "dl": "Đà Lạt",
        "vt": "Vũng Tàu",
        "bd": "Bình Dương",
        "đn": "Đồng Nai",
        "qn": "Quảng Ninh",
        "hue": "Thừa Thiên Huế",
        "ntr": "Nha Trang",
        "hl": "Hạ Long",
        "hcm": "Hồ Chí Minh",
        "tphcm": "TP. Hồ Chí Minh",
        // Từ giao tiếp & đời sống
        "dc": "được",
        "đc": "được",
        "ko": "không",
        "k": "không",
        "vs": "với",
        "ng": "người",
        "ch": "chưa",
        "nt": "nhắn tin",
        "kb": "không biết",
        "tn": "thế nào",
        "bh": "bây giờ",
        "tc": "tất cả",
        // Từ công việc & văn phòng
        "cty": "công ty",
        "sđt": "số điện thoại",
        "sdt": "số điện thoại",
        "tk": "tài khoản",
        "kh": "khách hàng",
        "sp": "sản phẩm",
        "dv": "dịch vụ",
        "tg": "thời gian",
        "tt": "thông tin",
        "lh": "liên hệ",
        "kn": "kinh nghiệm",
        "pt": "phát triển",
        "nv": "nhân viên",
        "ql": "quản lý",
        "gd": "giám đốc"
    ]

    /// Default path for macros.json (App Group on iOS, Application Support on macOS)
    public static var defaultStorageURL: URL? {
        #if os(iOS)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.vietlotus.keyboard") {
            return containerURL.appendingPathComponent("macros.json")
        }
        #endif
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("VieLotusIM", isDirectory: true).appendingPathComponent("macros.json")
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }

    public init(
        initialMacros: [String: String]? = nil,
        autoLoadFromDisk: Bool = false,
        storageURL: URL? = nil,
        autoSaveToDisk: Bool? = nil
    ) {
        self.storageURL = storageURL
        self.autoSaveToDisk = autoSaveToDisk ?? (Self.isRunningTests ? false : true)

        if let initial = initialMacros {
            self.macros = initial
        } else if autoLoadFromDisk && !Self.isRunningTests {
            self.macros = Self.defaultMacros
            _ = self.loadFromDisk()
        } else {
            self.macros = Self.defaultMacros
        }
    }

    /// Looks up a shorthand key and returns the expanded value with intelligent case adaptation.
    public func lookup(word: String) -> String? {
        guard isEnabled && !word.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        // 1. Direct match
        if let direct = macros[word] {
            return direct
        }

        // 2. Case-insensitive lookup with casing transformation
        let lowerKey = word.lowercased()
        guard let expansion = macros[lowerKey] else { return nil }

        // All-uppercase word (e.g. "VN" -> "VIỆT NAM")
        if word == word.uppercased() && word.count >= 2 {
            return expansion.uppercased()
        }

        // Titlecase word (e.g. "Vn" -> "Việt Nam")
        if let first = word.first, first.isUppercase {
            return expansion.prefix(1).uppercased() + expansion.dropFirst()
        }

        return expansion
    }

    /// Sets or updates a macro shorthand.
    public func setMacro(key: String, value: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty && !cleanVal.isEmpty else { return }

        lock.lock()
        macros[cleanKey] = cleanVal
        lock.unlock()

        NotificationCenter.default.post(name: Self.macrosDidChangeNotification, object: self)
        if autoSaveToDisk {
            try? saveToDisk()
        }
    }

    /// Removes a macro shorthand.
    public func removeMacro(key: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        let removed = macros.removeValue(forKey: cleanKey) != nil
        lock.unlock()

        if removed {
            NotificationCenter.default.post(name: Self.macrosDidChangeNotification, object: self)
            if autoSaveToDisk {
                try? saveToDisk()
            }
        }
    }

    /// Retrieves a snapshot of all active macros.
    public func getAllMacros() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return macros
    }

    /// Returns all macro entries sorted alphabetically by shorthand key.
    public func getMacroEntries() -> [MacroEntry] {
        lock.lock()
        defer { lock.unlock() }
        return macros.map { MacroEntry(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// Replaces the entire macro dictionary.
    public func replaceAllMacros(_ newMacros: [String: String]) {
        lock.lock()
        macros = newMacros
        lock.unlock()

        NotificationCenter.default.post(name: Self.macrosDidChangeNotification, object: self)
        if autoSaveToDisk {
            try? saveToDisk()
        }
    }

    /// Resets macros to the standard factory defaults.
    public func resetToDefaults() {
        lock.lock()
        macros = Self.defaultMacros
        lock.unlock()

        NotificationCenter.default.post(name: Self.macrosDidChangeNotification, object: self)
        if autoSaveToDisk {
            try? saveToDisk()
        }
    }

    /// Exports macros dictionary to JSON Data.
    public func exportJSON() throws -> Data {
        lock.lock()
        let copy = macros
        lock.unlock()
        return try JSONSerialization.data(withJSONObject: copy, options: [.prettyPrinted, .sortedKeys])
    }

    /// Imports macros from JSON Data.
    public func importJSON(data: Data, replaceAll: Bool = false) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw NSError(domain: "MacroEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid macro JSON format"])
        }
        lock.lock()
        if replaceAll {
            macros = [:]
        }
        for (k, v) in obj {
            let cleanK = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cleanV = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanK.isEmpty && !cleanV.isEmpty {
                macros[cleanK] = cleanV
            }
        }
        lock.unlock()

        NotificationCenter.default.post(name: Self.macrosDidChangeNotification, object: self)
        if autoSaveToDisk {
            try? saveToDisk()
        }
    }

    /// Loads macros from disk. Returns true if successfully read from file.
    @discardableResult
    public func loadFromDisk(url: URL? = nil) -> Bool {
        let targetURL = url ?? storageURL ?? Self.defaultStorageURL
        guard let targetURL = targetURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            return false
        }
        do {
            let data = try Data(contentsOf: targetURL)
            let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
            let mtime = attrs?[.modificationDate] as? Date

            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                return false
            }
            lock.lock()
            var newMacros: [String: String] = [:]
            for (k, v) in obj {
                let cleanK = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let cleanVal = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanK.isEmpty && !cleanVal.isEmpty {
                    newMacros[cleanK] = cleanVal
                }
            }
            self.macros = newMacros
            self.fileModificationDate = mtime
            lock.unlock()

            NotificationCenter.default.post(name: Self.macrosDidChangeNotification, object: self)
            return true
        } catch {
            return false
        }
    }

    /// Saves macros to disk as pretty-printed JSON atomically.
    public func saveToDisk(url: URL? = nil) throws {
        let targetURL = url ?? storageURL ?? Self.defaultStorageURL
        guard let targetURL = targetURL else { return }

        let data = try exportJSON()
        let parentDir = targetURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: targetURL, options: .atomic)

        let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
        let mtime = attrs?[.modificationDate] as? Date

        lock.lock()
        self.fileModificationDate = mtime
        lock.unlock()
    }

    /// Re-reads macros from disk only when modification date has changed.
    @discardableResult
    public func reloadFromDiskIfChanged(url: URL? = nil) -> Bool {
        let targetURL = url ?? storageURL ?? Self.defaultStorageURL
        guard let targetURL = targetURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            return false
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return false
        }

        lock.lock()
        let unchanged = (fileModificationDate != nil && fileModificationDate == mtime)
        lock.unlock()

        if unchanged { return false }

        return loadFromDisk(url: targetURL)
    }
}
