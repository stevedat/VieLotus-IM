import XCTest
@testable import VieLotusCore

final class BoundedKeystrokeBufferTests: XCTestCase {

    func testBufferBasics() {
        var buffer = BoundedKeystrokeBuffer()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertFalse(buffer.isFull)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.asString(), "")

        // Append characters
        XCTAssertTrue(buffer.append("t"))
        XCTAssertTrue(buffer.append("r"))
        XCTAssertTrue(buffer.append("u"))
        XCTAssertTrue(buffer.append("o"))
        XCTAssertTrue(buffer.append("n"))
        XCTAssertTrue(buffer.append("g"))

        XCTAssertEqual(buffer.count, 6)
        XCTAssertEqual(buffer.asString(), "truong")
        XCTAssertEqual(buffer.asCharacters(), Array("truong"))

        // Subscript access
        XCTAssertEqual(buffer[0], UInt8(ascii: "t"))
        XCTAssertEqual(buffer[5], UInt8(ascii: "g"))

        // Pop last
        XCTAssertTrue(buffer.popLast())
        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.asString(), "truon")

        // Reset
        buffer.reset()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.asString(), "")
    }

    func testOverflowPreservation() {
        var buffer = BoundedKeystrokeBuffer()
        for i in 0..<32 {
            XCTAssertTrue(buffer.append(UInt8(ascii: "a") + UInt8(i % 26)))
        }
        XCTAssertEqual(buffer.count, 32)

        // 33rd and subsequent characters must be preserved safely via overflow preservation policy
        XCTAssertTrue(buffer.append("z"))
        XCTAssertTrue(buffer.append("1"))
        XCTAssertEqual(buffer.count, 34)
        XCTAssertTrue(buffer.asString().hasSuffix("z1"))

        // Pop last shrinks count back
        XCTAssertTrue(buffer.popLast())
        XCTAssertEqual(buffer.count, 33)
        XCTAssertTrue(buffer.asString().hasSuffix("z"))
    }

    func testProvenanceTracking() {
        var buffer = BoundedKeystrokeBuffer()
        // Simulate typing "cra" -> "cả"
        // Raw: c (0), r (1), a (2)
        // Output: c (0), ả (1)
        buffer.append("c") // 0
        buffer.append("r") // 1
        buffer.append("a") // 2

        buffer.setProvenance(outIndex: 0, rawIndex: 0) // 'c' from raw 0 ('c')
        buffer.setProvenance(outIndex: 1, rawIndex: 2) // 'ả' from raw 2 ('a')

        XCTAssertEqual(buffer.rawIndex(for: 0), 0)
        XCTAssertEqual(buffer.rawIndex(for: 1), 2)
        XCTAssertNil(buffer.rawIndex(for: 2))
    }
}
