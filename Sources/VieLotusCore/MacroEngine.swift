import Foundation

/// Thread-safe shorthand / macro replacement engine for Vietnamese typing.
public final class MacroEngine: @unchecked Sendable {
    public static let shared = MacroEngine()

    private var macros: [String: String] = [:]
    public var isEnabled: Bool = true
    private let lock = NSLock()

    public static let defaultMacros: [String: String] = [
        "vn": "Việt Nam",
        "sg": "Sài Gòn",
        "hn": "Hà Nội",
        "dc": "được",
        "đc": "được",
        "ko": "không",
        "vs": "với",
        "ng": "người",
        "ch": "chưa",
        "nt": "nhắn tin",
        "kb": "không biết",
        "tn": "thế nào"
    ]

    public init(initialMacros: [String: String]? = nil) {
        self.macros = initialMacros ?? Self.defaultMacros
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

    /// Sets or updates a macro shorthand
    public func setMacro(key: String, value: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty && !cleanVal.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        macros[cleanKey] = cleanVal
    }

    /// Removes a macro shorthand
    public func removeMacro(key: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        defer { lock.unlock() }
        macros.removeValue(forKey: cleanKey)
    }

    /// Retrieves a snapshot of all active macros
    public func getAllMacros() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return macros
    }

    /// Replaces the entire macro dictionary
    public func replaceAllMacros(_ newMacros: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        macros = newMacros
    }

    /// Resets macros to the standard factory defaults
    public func resetToDefaults() {
        lock.lock()
        defer { lock.unlock() }
        macros = Self.defaultMacros
    }

    /// Exports macros dictionary to JSON Data
    public func exportJSON() throws -> Data {
        lock.lock()
        let copy = macros
        lock.unlock()
        return try JSONSerialization.data(withJSONObject: copy, options: [.prettyPrinted, .sortedKeys])
    }

    /// Imports macros from JSON Data
    public func importJSON(data: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw NSError(domain: "MacroEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid macro JSON format"])
        }
        lock.lock()
        defer { lock.unlock() }
        for (k, v) in obj {
            let cleanK = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cleanV = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanK.isEmpty && !cleanV.isEmpty {
                macros[cleanK] = cleanV
            }
        }
    }
}
