import XCTest
@testable import VieLotusCore

final class ClientStallBreakerTests: XCTestCase {
    var breaker: ClientStallBreaker!

    override func setUp() {
        super.setUp()
        breaker = ClientStallBreaker()
        breaker.stallThresholdMs = 20.0
        breaker.degradationDurationSec = 0.08
    }

    override func tearDown() {
        breaker.clear()
        breaker = nil
        super.tearDown()
    }

    func testInitialStateNotDegraded() {
        XCTAssertFalse(breaker.anyDegraded)
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "com.apple.finder"))
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: nil))
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: ""))
    }

    func testExplicitMarkDegradedAndExpiration() {
        breaker.markDegraded(bundleIdentifier: "com.google.Chrome", durationSec: 0.05)
        XCTAssertTrue(breaker.anyDegraded)
        XCTAssertTrue(breaker.isDegraded(bundleIdentifier: "com.google.Chrome"))
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "com.apple.finder"))

        // Wait for expiration
        Thread.sleep(forTimeInterval: 0.07)
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "com.google.Chrome"))
        XCTAssertFalse(breaker.anyDegraded)
    }

    func testRecordLatencyThreshold() {
        breaker.recordLatency(bundleIdentifier: "com.microsoft.VSCode", operation: "insertText", durationMs: 10.0)
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "com.microsoft.VSCode"))

        breaker.recordLatency(bundleIdentifier: "com.microsoft.VSCode", operation: "insertText", durationMs: 25.0)
        XCTAssertTrue(breaker.isDegraded(bundleIdentifier: "com.microsoft.VSCode"))
    }

    func testWatchdogExecutionTracksLatency() {
        // Fast operation
        let val = breaker.executeWithWatchdog(bundleIdentifier: "com.apple.Terminal", operation: "fast") {
            return 42
        }
        XCTAssertEqual(val, 42)
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "com.apple.Terminal"))

        // Slow operation
        let slowVal = breaker.executeWithWatchdog(bundleIdentifier: "com.apple.Terminal", operation: "slow") {
            Thread.sleep(forTimeInterval: 0.03) // 30ms > 20ms threshold
            return 99
        }
        XCTAssertEqual(slowVal, 99)
        XCTAssertTrue(breaker.isDegraded(bundleIdentifier: "com.apple.Terminal"))
    }

    func testClearRemovesDegradedState() {
        breaker.markDegraded(bundleIdentifier: "app1")
        breaker.markDegraded(bundleIdentifier: "app2")
        XCTAssertTrue(breaker.anyDegraded)

        breaker.clear(bundleIdentifier: "app1")
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "app1"))
        XCTAssertTrue(breaker.isDegraded(bundleIdentifier: "app2"))

        breaker.clear()
        XCTAssertFalse(breaker.anyDegraded)
        XCTAssertFalse(breaker.isDegraded(bundleIdentifier: "app2"))
    }
}
