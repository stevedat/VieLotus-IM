import XCTest
import VieLotusTrace

final class LabTraceSpoolTests: XCTestCase {
    func testTraceEventsCanBeDrainedIncrementallyAndRemoved() throws {
        let traceID = UUID().uuidString
        try LabTraceSpool.prepare(traceID: traceID)
        defer { LabTraceSpool.remove(traceID: traceID) }

        var offset: UInt64 = 0
        let first = event(traceID: traceID, event: "keyDown", key: "d", monotonic: 1)
        try LabTraceSpool.append(first)
        XCTAssertEqual(try LabTraceSpool.read(traceID: traceID, offset: &offset).map(\.event), ["keyDown"])
        XCTAssertTrue(try LabTraceSpool.read(traceID: traceID, offset: &offset).isEmpty)

        try LabTraceSpool.append(event(traceID: traceID, event: "feed", key: "d", monotonic: 2))
        XCTAssertEqual(try LabTraceSpool.read(traceID: traceID, offset: &offset).map(\.event), ["feed"])
    }

    func testSpoolRejectsNonUUIDTraceIDs() {
        XCTAssertThrowsError(try LabTraceSpool.prepare(traceID: "not-a-uuid"))
    }

    func testCleanupStaleTracesRunsSafely() {
        LabTraceSpool.cleanupStaleTraces(maxAge: 3600)
    }

    private func event(traceID: String, event: String, key: String, monotonic: UInt64) -> LabTraceEvent {
        LabTraceEvent(traceID: traceID, event: event, key: key, raw: key, composing: key,
                      detail: "client=org.example.test", time: "2026-10-01T00:00:00Z",
                      monotonic: monotonic)
    }
}
