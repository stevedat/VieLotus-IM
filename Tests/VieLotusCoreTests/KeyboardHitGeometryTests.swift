#if canImport(CoreGraphics)
import XCTest
@testable import VieLotusCore

final class KeyboardHitGeometryTests: XCTestCase {
    let left = CGRect(x: 0, y: 0, width: 32, height: 48)
    let right = CGRect(x: 38, y: 0, width: 32, height: 48)

    func testExpandedNeighbourCannotClaimVisibleKeyFace() {
        let point = CGPoint(x: 20, y: 24)
        XCTAssertTrue(right.insetBy(dx: -24, dy: -16).contains(point), "Previously both keys claimed this point")
        XCTAssertTrue(KeyboardHitGeometry.accepts(point, key: left, peers: [left, right]))
        XCTAssertFalse(KeyboardHitGeometry.accepts(point, key: right, peers: [left, right]))
    }

    func testGapHasSingleNearestOwnerIndependentOfSubviewOrder() {
        for x in stride(from: 0.0, through: 70.0, by: 0.5) {
            let point = CGPoint(x: x, y: 24)
            for peers in [[left, right], [right, left]] {
                let owners = peers.filter { KeyboardHitGeometry.accepts(point, key: $0, peers: peers) }
                XCTAssertEqual(owners.count, 1, "x=\(x)")
            }
        }
        XCTAssertTrue(KeyboardHitGeometry.accepts(CGPoint(x: 34, y: 24), key: left, peers: [right, left]))
        XCTAssertTrue(KeyboardHitGeometry.accepts(CGPoint(x: 36, y: 24), key: right, peers: [left, right]))
    }

    func testOuterMarginsAndFarAwayTouches() {
        XCTAssertTrue(KeyboardHitGeometry.accepts(CGPoint(x: -10, y: 24), key: left, peers: [left, right]))
        XCTAssertFalse(KeyboardHitGeometry.accepts(CGPoint(x: -25, y: 24), key: left, peers: [left, right]))
        XCTAssertFalse(KeyboardHitGeometry.accepts(CGPoint(x: 10, y: -17), key: left, peers: [left, right]))
        XCTAssertFalse(KeyboardHitGeometry.accepts(.zero, key: .zero, peers: []))
    }

    func testUnequalWidthsAndVerticalGapRespectGeometry() {
        let lower = CGRect(x: 0, y: 54, width: 70, height: 48)
        let peers = [left, right, lower]
        let point = CGPoint(x: 20, y: 53)
        XCTAssertTrue(KeyboardHitGeometry.accepts(point, key: lower, peers: peers))
        XCTAssertFalse(KeyboardHitGeometry.accepts(point, key: left, peers: peers))
    }
}
#endif
