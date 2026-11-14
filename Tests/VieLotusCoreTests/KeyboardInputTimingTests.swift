import XCTest
@testable import VieLotusCore

final class KeyboardInputTimingTests: XCTestCase {
    func testFlushUsesTriggerEventAndOriginalOwnersDownTime() {
        var tracker = KeyboardInputTimingTracker<Int>()
        tracker.touchDown(owner: 1, timestamp: 10)
        tracker.touchDown(owner: 2, timestamp: 10.1)
        let first = tracker.commit(owner: 1, triggerTimestamp: 10.1,
                                   handlerEnteredAt: 10.12, source: .rollover)
        XCTAssertEqual(first.keyDownTimestamp, 10)
        XCTAssertEqual(first.triggerTimestamp, 10.1)
        XCTAssertEqual(first.handlerEnteredAt, 10.12)
        XCTAssertEqual(first.sequence, 1)
        let second = tracker.commit(owner: 2, triggerTimestamp: 10.2,
                                    handlerEnteredAt: 10.22, source: .touchUpInside)
        XCTAssertEqual(second.keyDownTimestamp, 10.1)
        XCTAssertEqual(second.sequence, 2)
    }

    func testMissingEventCannotReusePreviousTimestampOrConsumedOwner() {
        var tracker = KeyboardInputTimingTracker<Int>()
        tracker.touchDown(owner: 1, timestamp: 10)
        _ = tracker.commit(owner: 1, triggerTimestamp: 10.2,
                           handlerEnteredAt: 10.22, source: .touchUpInside)
        let next = tracker.commit(owner: 1, triggerTimestamp: nil,
                                  handlerEnteredAt: 11, source: .specialFlush)
        XCTAssertNil(next.triggerTimestamp)
        XCTAssertNil(next.keyDownTimestamp)
        XCTAssertEqual(KeyboardInputTiming.milliseconds(since: next.triggerTimestamp, now: 11.1), -1)
    }

    func testCancellationAndAbsentTouchDownAreNotFabricated() {
        var tracker = KeyboardInputTimingTracker<Int>()
        tracker.touchDown(owner: 1, timestamp: 10)
        tracker.cancel(owner: 1)
        let next = tracker.commit(owner: 1, triggerTimestamp: 10.3,
                                  handlerEnteredAt: 10.32, source: .touchUpOutside)
        XCTAssertNil(next.keyDownTimestamp)
        XCTAssertEqual(KeyboardInputTiming.milliseconds(since: 10, now: 10.025), 25, accuracy: 0.0001)
        XCTAssertEqual(KeyboardInputTiming.milliseconds(since: 11, now: 10), -1)
    }
}
