import XCTest
@testable import VieLotusCore

final class MockTextDocumentProxy: TextDocumentProxyProtocol {
    var buffer: String = ""

    var documentContextBeforeInput: String? {
        return buffer
    }

    var documentContextAfterInput: String? {
        return nil
    }

    func insertText(_ text: String) {
        buffer.append(text)
    }

    func deleteBackward() {
        if !buffer.isEmpty {
            buffer.removeLast()
        }
    }
}

final class UIKitInputSessionAdapterTests: XCTestCase {
    func testVietnameseTypingWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "tiếng" -> t i e e n g s
        let chars: [Character] = ["t", "i", "e", "e", "n", "g", "s"]
        for c in chars {
            adapter.handleCharacter(c, proxy: proxy)
        }

        XCTAssertEqual(proxy.buffer, "tiếng")

        // Type space -> commits word and adds space
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "tiếng ")
    }

    func testBackspaceDuringCompositionWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "toán" -> t o a n s
        for c in ["t", "o", "a", "n", "s"] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "toán")

        // Backspace once -> should become "toan"
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "toan")

        // Backspace again -> should become "toa"
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "toa")
    }

    func testMacroExpansionWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.macroEnabled = true
        let proxy = MockTextDocumentProxy()

        // Type "vn" + space
        adapter.handleCharacter("v", proxy: proxy)
        adapter.handleCharacter("n", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "vn")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam ")
    }

    func testSmartBilingualRestoreWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.smartBilingual = true
        let proxy = MockTextDocumentProxy()

        // Type "more" (m o r e) -> during typing: m -> mo -> mỏ -> mỏe
        for c in ["m", "o", "r", "e"] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }

        // On word boundary (space), Smart Bilingual restores raw English word "more"
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "more ")
    }
}
