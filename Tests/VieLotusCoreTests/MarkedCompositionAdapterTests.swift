import XCTest
@testable import VieLotusCore

final class MarkedCompositionAdapterTests: XCTestCase {
    private final class Proxy: MarkedCompositionDocumentProxy {
        var buffer = ""
        var markedRange: Range<String.Index>?
        var marks = 0
        var deletes = 0
        var inserts = 0
        var documentContextBeforeInput: String? { buffer }
        var documentContextAfterInput: String? { nil }
        func insertText(_ text: String) { inserts += 1; buffer += text }
        func deleteBackward() { deletes += 1; if !buffer.isEmpty { buffer.removeLast() } }
        func setCompositionText(_ text: String, selectedRange: NSRange) {
            XCTAssertEqual(selectedRange, NSRange(location: text.utf16.count, length: 0))
            marks += 1
            let start = markedRange?.lowerBound ?? buffer.endIndex
            buffer.replaceSubrange(start..<buffer.endIndex, with: text)
            markedRange = text.isEmpty ? nil : start..<buffer.endIndex
        }
        func finishCompositionText() { markedRange = nil }
    }

    private func drive(_ raw: String, marked: Bool) -> (String, Proxy) {
        let proxy = Proxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.macroEnabled = false
        adapter.prefersMarkedComposition = marked
        for ch in raw {
            if ch == "<" { adapter.handleBackspace(proxy: proxy) }
            else { adapter.handleCharacter(ch, proxy: proxy) }
        }
        adapter.finishMarkedComposition(proxy: proxy)
        return (proxy.buffer, proxy)
    }

    func testMarkedAndDirectTextOutcomesMatchAcrossEditingAndLanguageSwitches() {
        for raw in ["cos ", "coss ", "tooi ", "tieengs Vieetj ", "sunworld ",
                    "apple meta cos ", "sin and cos ", "pros and cons ",
                    "file.rar ", "file.rar< ", "cos<ns ", "toois<<f ",
                    "hello, cos! ", "co< ", "a<< ", "ddawngj ", "😀 cos "] {
            XCTAssertEqual(drive(raw, marked: true).0, drive(raw, marked: false).0, raw)
        }
    }

    func testPerKeyParityIncludingToneRelocationEscapeAndBoundary() {
        for raw in ["tieengs vieetj ", "coosng ", "sunworld ", "apple meta cons ",
                    "file.rar ", "cos<ns ", "coss ", "rrung rrinh ", "hòa😀 cos "] {
            let directProxy = Proxy()
            let markedProxy = Proxy()
            let direct = UIKitInputSessionAdapter()
            let marked = UIKitInputSessionAdapter()
            marked.prefersMarkedComposition = true
            direct.session.macroEnabled = false
            marked.session.macroEnabled = false
            for ch in raw {
                if ch == "<" {
                    direct.handleBackspace(proxy: directProxy)
                    marked.handleBackspace(proxy: markedProxy)
                } else {
                    direct.handleCharacter(ch, proxy: directProxy)
                    marked.handleCharacter(ch, proxy: markedProxy)
                }
                XCTAssertEqual(markedProxy.buffer, directProxy.buffer, "\(raw) after \(ch)")
            }
        }
    }

    func testToneUsesMarkedReplacementWithoutDeleteInsert() {
        let (output, proxy) = drive("cos ", marked: true)
        XCTAssertEqual(output, "có ")
        XCTAssertEqual(proxy.deletes, 0)
        XCTAssertEqual(proxy.inserts, 1, "Only the boundary should be appended literally")
        XCTAssertEqual(proxy.marks, 3)
        XCTAssertNil(proxy.markedRange)
    }

    func testExternalEditReleasesOwnershipBeforeStartingNewComposition() {
        let proxy = Proxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.prefersMarkedComposition = true
        for ch in "cos" { adapter.handleCharacter(ch, proxy: proxy) }
        adapter.handleExternalTextChange(proxy: proxy)
        XCTAssertNil(proxy.markedRange)
        proxy.buffer = "other "
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "cos " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "other có ")
    }

    func testABCFinalizesMarkAndKeepsLiteralInput() {
        let proxy = Proxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.prefersMarkedComposition = true
        for ch in "cos" { adapter.handleCharacter(ch, proxy: proxy) }
        adapter.finishMarkedComposition(proxy: proxy)
        adapter.literalOverrideEnabled = true
        for ch in " just " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "có just ")
        XCTAssertNil(proxy.markedRange)
    }

    func testMacroOverrideAndExplicitCandidateCommitReleaseMark() {
        let proxy = Proxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.prefersMarkedComposition = true
        adapter.session.macroEngine = MacroEngine(initialMacros: ["hn": "Hà Nội"])
        adapter.session.macroEnabled = true
        for ch in "hn " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "Hà Nội ")
        XCTAssertNil(proxy.markedRange)
        adapter.session.macroEnabled = false
        for ch in "cos" { adapter.handleCharacter(ch, proxy: proxy) }
        adapter.selectCompositionCandidate("cos", proxy: proxy)
        adapter.commitWord(proxy: proxy, suffix: " ")
        XCTAssertEqual(proxy.buffer, "Hà Nội cos ")
        XCTAssertNil(proxy.markedRange)
    }

    func testUnsupportedProxyRetainsDirectReplacement() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.prefersMarkedComposition = true
        for ch in "cos " { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "có ")
    }
}
