import XCTest
@testable import VieLotusCore

final class GlideDecodeSchedulerTests: XCTestCase {
    @MainActor
    func testInvalidatingInFlightDecodeNeverPublishes() async {
        let scheduler = GlideDecodeScheduler<Int>()
        let started = expectation(description: "Worker actually started")
        let finished = expectation(description: "Canceled worker completed")
        let published = expectation(description: "Canceled result must not publish")
        published.isInverted = true
        let release = DispatchSemaphore(value: 0)
        scheduler.submit(work: {
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            finished.fulfill()
            return 1
        }, completion: { _ in published.fulfill() })
        await fulfillment(of: [started], timeout: 2)
        scheduler.invalidate()
        release.signal()
        await fulfillment(of: [finished], timeout: 2)
        await fulfillment(of: [published], timeout: 0.2)
    }

    @MainActor
    func testNewRequestSupersedesBothRunningAndQueuedResults() async {
        let scheduler = GlideDecodeScheduler<Int>()
        let started = expectation(description: "First request running")
        let latest = expectation(description: "Only latest request delivered")
        let obsolete = expectation(description: "Obsolete requests do not publish")
        obsolete.isInverted = true
        let release = DispatchSemaphore(value: 0)
        scheduler.submit(work: {
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return 1
        }, completion: { _ in obsolete.fulfill() })
        await fulfillment(of: [started], timeout: 2)
        scheduler.submit(work: { 2 }, completion: { _ in obsolete.fulfill() })
        scheduler.submit(work: { 3 }, completion: { value in
            XCTAssertEqual(value, 3)
            XCTAssertTrue(Thread.isMainThread)
            latest.fulfill()
        })
        release.signal()
        await fulfillment(of: [latest], timeout: 2)
        await fulfillment(of: [obsolete], timeout: 0.2)
    }
}
