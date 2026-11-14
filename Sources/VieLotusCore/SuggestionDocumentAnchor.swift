#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

/// Ephemeral context around the caret. Used to reject delayed candidates after
/// selection or cursor movement, including changes not yet reflected in IME caches.
public struct SuggestionDocumentAnchor: Sendable, Equatable {
    private let before: String
    private let after: String

    public init?(before: String?, after: String?) {
        guard before != nil || after != nil else { return nil }
        self.before = String((before ?? "").suffix(64))
        self.after = String((after ?? "").prefix(64))
    }

    public func matches(before: String?, after: String?, hasSelection: Bool) -> Bool {
        guard !hasSelection, (before != nil || after != nil) else { return false }
        return String((before ?? "").suffix(64)) == self.before &&
            String((after ?? "").prefix(64)) == self.after
    }
}
#endif
