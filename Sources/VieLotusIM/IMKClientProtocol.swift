import Cocoa
import InputMethodKit

/// Thin 1-to-1 protocol seam over the 7 `IMKTextInput` methods used by `VieLotusIMController`.
///
/// In production, `NativeIMKClientAdapter` forwards directly to the Objective-C `IMKTextInput`
/// XPC proxy with zero behavioral divergence and zero steady-state allocations (cached per client).
/// In automated tests, a headless `IMKClientProtocol` mock can drive `VieLotusIMController`
/// directly without launching `IMKServer` or mutating real user documents.
protocol IMKClientProtocol: AnyObject {
    var clientIdentityToken: ObjectIdentifier { get }
    func bundleIdentifier() -> String!
    func selectedRange() -> NSRange
    func markedRange() -> NSRange
    func attributedSubstring(from range: NSRange) -> NSAttributedString!
    func insertText(_ string: Any!, replacementRange: NSRange)
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange)
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!)
}

final class NativeIMKClientAdapter: IMKClientProtocol {
    let rawClient: IMKTextInput
    let clientIdentityToken: ObjectIdentifier

    init(rawClient: IMKTextInput, rawSender: AnyObject) {
        self.rawClient = rawClient
        self.clientIdentityToken = ObjectIdentifier(rawSender)
    }

    func bundleIdentifier() -> String! {
        rawClient.bundleIdentifier()
    }

    func selectedRange() -> NSRange {
        rawClient.selectedRange()
    }

    func markedRange() -> NSRange {
        rawClient.markedRange()
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        rawClient.attributedSubstring(from: range)
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        rawClient.insertText(string, replacementRange: replacementRange)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        rawClient.setMarkedText(string, selectionRange: selectionRange, replacementRange: replacementRange)
    }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {
        rawClient.overrideKeyboard(withKeyboardNamed: keyboardUniqueName)
    }
}
