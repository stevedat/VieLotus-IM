import Foundation

/// BoundedKeystrokeBuffer is an inline zero-heap buffer for up to 32 keystrokes
/// with automatic overflow preservation for arbitrary-length tokens (URLs, base64, identifiers).
/// Provides exact provenance tracking mapping output character indices to raw keystroke indices.
internal struct BoundedKeystrokeBuffer: Sendable, Equatable {
    internal static let inlineCapacity: Int = 32

    /// Inline storage for raw ASCII/scalar bytes (zero-heap hot path)
    internal private(set) var bytes: [UInt8]
    internal private(set) var count: Int = 0

    /// Fallback storage if token exceeds inlineCapacity (overflow preservation policy)
    private var overflowChars: [Character]? = nil

    /// Provenance tracking: maps output character index -> raw keystroke index
    internal private(set) var provenance: [Int8]
    internal private(set) var provenanceCount: Int = 0

    internal init() {
        self.bytes = [UInt8](repeating: 0, count: Self.inlineCapacity)
        self.provenance = [Int8](repeating: -1, count: Self.inlineCapacity)
    }

    internal var isEmpty: Bool {
        return count == 0
    }

    internal var isFull: Bool {
        // With overflow preservation, the buffer safely expands rather than dropping input
        return false
    }

    /// Appends a raw character byte.
    @discardableResult
    internal mutating func append(_ byte: UInt8) -> Bool {
        if count < Self.inlineCapacity && overflowChars == nil {
            bytes[count] = byte
            count += 1
            return true
        }

        // Transition to overflow preservation
        let ch = Character(UnicodeScalar(byte))
        return append(ch)
    }

    /// Appends a Character, preserving full string fidelity.
    @discardableResult
    internal mutating func append(_ char: Character) -> Bool {
        if count < Self.inlineCapacity && overflowChars == nil, let ascii = char.asciiValue {
            bytes[count] = ascii
            count += 1
            return true
        }

        // Overflow mode
        if overflowChars == nil {
            var chars = [Character]()
            chars.reserveCapacity(Self.inlineCapacity + 16)
            if count > 0 {
                chars.append(contentsOf: String(decoding: bytes[0..<count], as: UTF8.self))
            }
            overflowChars = chars
        }
        overflowChars?.append(char)
        count += 1
        return true
    }

    /// Removes the last keystroke. Returns true if removed, false if empty.
    @discardableResult
    internal mutating func popLast() -> Bool {
        guard count > 0 else { return false }

        if let _ = overflowChars {
            overflowChars?.removeLast()
            count -= 1
            if count <= Self.inlineCapacity {
                // Re-sync back to inline bytes and clear heap storage
                if let ov = overflowChars {
                    for (i, ch) in ov.enumerated() {
                        if let ascii = ch.asciiValue, i < Self.inlineCapacity {
                            bytes[i] = ascii
                        }
                    }
                }
                overflowChars = nil
            }
            return true
        }

        count -= 1
        bytes[count] = 0
        return true
    }

    /// Clears all entries without releasing pre-allocated capacity.
    internal mutating func reset() {
        count = 0
        provenanceCount = 0
        overflowChars = nil
    }

    /// Subscript to access raw bytes
    internal subscript(index: Int) -> UInt8 {
        get {
            precondition(index >= 0 && index < count, "Index out of range in BoundedKeystrokeBuffer")
            if let ov = overflowChars {
                return ov[index].asciiValue ?? 0
            }
            return bytes[index]
        }
        set {
            precondition(index >= 0 && index < count, "Index out of range in BoundedKeystrokeBuffer")
            if overflowChars != nil {
                overflowChars?[index] = Character(UnicodeScalar(newValue))
            } else {
                bytes[index] = newValue
            }
        }
    }

    /// Sets provenance for a given output character index
    internal mutating func setProvenance(outIndex: Int, rawIndex: Int) {
        guard outIndex >= 0 else { return }
        if outIndex >= provenance.count {
            provenance.append(contentsOf: repeatElement(-1, count: max(outIndex + 1 - provenance.count, 16)))
        }
        provenance[outIndex] = Int8(clamping: rawIndex)
        if outIndex >= provenanceCount {
            provenanceCount = outIndex + 1
        }
    }

    /// Retrieves raw keystroke index for an output character index
    internal func rawIndex(for outIndex: Int) -> Int? {
        guard outIndex >= 0 && outIndex < provenanceCount else { return nil }
        let idx = Int(provenance[outIndex])
        return idx >= 0 ? idx : nil
    }

    /// Returns raw string representation
    internal func asString() -> String {
        guard count > 0 else { return "" }
        if let ov = overflowChars {
            return String(ov)
        }
        return String(decoding: bytes[0..<count], as: UTF8.self)
    }

    /// Returns raw characters array
    internal func asCharacters() -> [Character] {
        if let ov = overflowChars {
            return ov
        }
        return Array(asString())
    }
}
