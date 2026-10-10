import Foundation

/// Protocol abstracting iOS `UITextDocumentProxy` for cross-platform decoupling and unit testability.
public protocol TextDocumentProxyProtocol: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

#if canImport(UIKit)
import UIKit
extension UIInputViewController: @retroactive TextDocumentProxyProtocol {
    public var documentContextBeforeInput: String? {
        return textDocumentProxy.documentContextBeforeInput
    }
    public var documentContextAfterInput: String? {
        return textDocumentProxy.documentContextAfterInput
    }
    public func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }
    public func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }
}
#endif

/// High-performance controller bridging `InputSessionManager` with `UITextDocumentProxy` on iOS/iPadOS.
public final class UIKitInputSessionAdapter {
    public let session: InputSessionManager
    public var smartBilingual: Bool = true
    public var genZMode: Bool = false

    public init(session: InputSessionManager = InputSessionManager()) {
        self.session = session
    }

    /// Feeds a character from keyboard touch or hardware key into the session
    public func handleCharacter(_ char: Character, proxy: TextDocumentProxyProtocol) {
        if session.isWordBoundary(char) {
            commitWord(proxy: proxy, suffix: String(char))
            return
        }

        let action = session.handleCharacter(char)
        applyAction(action, proxy: proxy)
    }

    /// Handles the backspace/delete tap
    public func handleBackspace(proxy: TextDocumentProxyProtocol) {
        let action = session.handleBackspace()
        switch action {
        case .replace(let backspaces, let text):
            for _ in 0..<backspaces {
                proxy.deleteBackward()
            }
            if !text.isEmpty {
                proxy.insertText(text)
            }
        case .reset:
            proxy.deleteBackward()
        case .passThrough:
            proxy.deleteBackward()
        default:
            break
        }
    }

    /// Commits the active composition word (e.g. on Space, Return, or Punctuation)
    public func commitWord(proxy: TextDocumentProxyProtocol, suffix: String = "") {
        guard session.isComposing else {
            if !suffix.isEmpty {
                proxy.insertText(suffix)
            }
            return
        }

        let action = session.commitWord(
            smartBilingualEnabled: smartBilingual,
            genZMode: genZMode
        )
        applyAction(action, proxy: proxy, suffix: suffix)
    }

    private func applyAction(_ action: SessionAction, proxy: TextDocumentProxyProtocol, suffix: String = "") {
        switch action {
        case .replace(let backspaces, let text):
            for _ in 0..<backspaces {
                proxy.deleteBackward()
            }
            if !text.isEmpty {
                proxy.insertText(text)
            }
        case .commit(let backspaces, let text, let isOverride):
            if isOverride {
                for _ in 0..<backspaces {
                    proxy.deleteBackward()
                }
                proxy.insertText(text)
            }
            if !suffix.isEmpty {
                proxy.insertText(suffix)
            }
        case .reset:
            break
        case .passThrough, .consumed:
            break
        }
    }
}
