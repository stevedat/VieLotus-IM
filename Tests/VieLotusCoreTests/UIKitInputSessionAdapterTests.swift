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

        // Type "ddc" (đc) + space -> "được "
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("c", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam đc")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được ")

        // Type "sddt" (sđt) + space -> "số điện thoại "
        adapter.handleCharacter("s", proxy: proxy)
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("t", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được sđt")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được số điện thoại ")

        // Type "cty" + space -> "công ty "
        adapter.handleCharacter("c", proxy: proxy)
        adapter.handleCharacter("t", proxy: proxy)
        adapter.handleCharacter("y", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được số điện thoại cty")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được số điện thoại công ty ")
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

    func testEmojiInsertionAfterComposingWord() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "việt" -> v i e e t j (still composing)
        for c in ["v", "i", "e", "e", "t", "j"] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertTrue(adapter.session.isComposing)
        XCTAssertEqual(proxy.buffer, "việt")

        // User taps emoji "🇻🇳" -> commits active word first, then inserts emoji
        adapter.commitWord(proxy: proxy)
        proxy.insertText("🇻🇳")

        XCTAssertFalse(adapter.session.isComposing)
        XCTAssertEqual(proxy.buffer, "việt🇻🇳")
    }

    func testEmojiInsertionAndBackspace() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "chào " -> c h a o f + space
        for c in ["c", "h", "a", "o", "f", " "] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "chào ")

        // Insert emoji "😊"
        proxy.insertText("😊")
        XCTAssertEqual(proxy.buffer, "chào 😊")

        // Backspace removes the emoji
        proxy.deleteBackward()
        XCTAssertEqual(proxy.buffer, "chào ")
    }

    func testMultiScalarEmojiInsertion() {
        let proxy = MockTextDocumentProxy()

        let emojis = ["🇻🇳", "❤️", "🎉", "😮‍💨", "☕️"]
        for emoji in emojis {
            proxy.insertText(emoji)
        }

        XCTAssertEqual(proxy.buffer, "🇻🇳❤️🎉😮‍💨☕️")
    }
}
