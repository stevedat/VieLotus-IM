import Cocoa
import InputMethodKit
import VieLotusCore

/// Thin 1-to-1 protocol seam over the 7 `IMKTextInput` methods used by `VieLotusIMController`.
///
/// In production, `NativeIMKClientAdapter` forwards directly to the Objective-C `IMKTextInput`
/// XPC proxy with zero behavioral divergence and zero steady-state allocations (cached per client),
/// wrapped by `WatchdogIMKClientAdapter` to measure synchronous IPC latency via `ClientStallBreaker`.
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

final class WatchdogIMKClientAdapter: IMKClientProtocol {
    let base: IMKClientProtocol
    private var cachedRawBundleID: String?
    private var cachedBundleID: String?
    private var didResolveBundleID = false

    init(base: IMKClientProtocol) {
        self.base = base
    }

    var clientIdentityToken: ObjectIdentifier {
        base.clientIdentityToken
    }

    private var resolvedBundleID: String? {
        if !didResolveBundleID {
            didResolveBundleID = true
            let raw = base.bundleIdentifier()
            cachedRawBundleID = raw
            cachedBundleID = ClientAdapter.resolveBundleIdentifier(raw)
        }
        return cachedBundleID
    }

    func bundleIdentifier() -> String! {
        if !didResolveBundleID {
            didResolveBundleID = true
            let raw = base.bundleIdentifier()
            cachedRawBundleID = raw
            cachedBundleID = ClientAdapter.resolveBundleIdentifier(raw)
        }
        return cachedRawBundleID
    }

    func selectedRange() -> NSRange {
        ClientStallBreaker.shared.executeWithWatchdog(
            bundleIdentifier: resolvedBundleID,
            operation: "selectedRange"
        ) {
            base.selectedRange()
        }
    }

    func markedRange() -> NSRange {
        ClientStallBreaker.shared.executeWithWatchdog(
            bundleIdentifier: resolvedBundleID,
            operation: "markedRange"
        ) {
            base.markedRange()
        }
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        ClientStallBreaker.shared.executeWithWatchdog(
            bundleIdentifier: resolvedBundleID,
            operation: "attributedSubstring"
        ) {
            base.attributedSubstring(from: range)
        }
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        ClientStallBreaker.shared.executeWithWatchdog(
            bundleIdentifier: resolvedBundleID,
            operation: "insertText"
        ) {
            base.insertText(string, replacementRange: replacementRange)
        }
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        ClientStallBreaker.shared.executeWithWatchdog(
            bundleIdentifier: resolvedBundleID,
            operation: "setMarkedText"
        ) {
            base.setMarkedText(string, selectionRange: selectionRange, replacementRange: replacementRange)
        }
    }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {
        ClientStallBreaker.shared.executeWithWatchdog(
            bundleIdentifier: resolvedBundleID,
            operation: "overrideKeyboard"
        ) {
            base.overrideKeyboard(withKeyboardNamed: keyboardUniqueName)
        }
    }
}

final class NativeIMKClientAdapter: IMKClientProtocol {
    let rawClient: IMKTextInput
    let clientIdentityToken: ObjectIdentifier
    private var cachedRawBundleID: String?
    private var didCacheRawBundleID = false

    init(rawClient: IMKTextInput, rawSender: AnyObject) {
        self.rawClient = rawClient
        self.clientIdentityToken = ObjectIdentifier(rawSender)
    }

    func bundleIdentifier() -> String! {
        if !didCacheRawBundleID {
            didCacheRawBundleID = true
            cachedRawBundleID = rawClient.bundleIdentifier()
        }
        return cachedRawBundleID
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
