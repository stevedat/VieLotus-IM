import XCTest
@testable import VieLotusCore

final class SuggestionDocumentAnchorTests: XCTestCase {
    func testPendingResultRejectsCaretMoveSelectionAndUnavailableContext() {
        let anchor = SuggestionDocumentAnchor(before: "tôi đang học", after: " ở nhà")!
        XCTAssertTrue(anchor.matches(before: "tôi đang học", after: " ở nhà", hasSelection: false))
        XCTAssertFalse(anchor.matches(before: "tôi đang", after: " học ở nhà", hasSelection: false))
        XCTAssertFalse(anchor.matches(before: "tôi đang học", after: " ở trường", hasSelection: false))
        XCTAssertFalse(anchor.matches(before: "tôi đang học", after: " ở nhà", hasSelection: true))
        XCTAssertFalse(anchor.matches(before: nil, after: " ở nhà", hasSelection: false))
        XCTAssertNil(SuggestionDocumentAnchor(before: nil, after: nil))
    }

    func testHostUnicodeNormalizationAndEndOfDocumentAreAccepted() {
        let anchor = SuggestionDocumentAnchor(before: "to\u{0302}i", after: nil)!
        XCTAssertTrue(anchor.matches(before: "tôi", after: "", hasSelection: false))
    }

    func testDifferentHostContextWindowLengthsKeepSameCandidateIdentity() {
        let fullText = String(repeating: "earlier words ", count: 30) + "current word"
        let shadow = SuggestionDocumentAnchor(before: String(fullText.suffix(120)), after: nil)
        let live = SuggestionDocumentAnchor(before: fullText, after: "")
        XCTAssertEqual(shadow, live, "Proxy window clipping must not suppress otherwise current ABC candidates")
    }

    func testBoundedContextIgnoresOnlyDistantText() {
        let near = String(repeating: "á", count: 64)
        let anchor = SuggestionDocumentAnchor(before: "old " + near, after: nil)!
        XCTAssertTrue(anchor.matches(before: "new " + near, after: nil, hasSelection: false))
        XCTAssertFalse(anchor.matches(before: "new " + near + "x", after: nil, hasSelection: false))
    }
}
