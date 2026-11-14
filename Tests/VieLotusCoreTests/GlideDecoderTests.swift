import XCTest
@testable import VieLotusCore

final class GlideDecoderTests: XCTestCase {
    func testVietnameseShapeLettersSharePhysicalKeys() {
        XCTAssertEqual(GlidePathDecoder.baseKeys("ĐẶNG"), "dang")
        XCTAssertEqual(GlidePathDecoder.baseKeys("trường"), "truong")
        let candidates = GlidePathDecoder.decode(keySequence: Array("nhan"), limit: 30)
        XCTAssertTrue(candidates.contains { $0.syllable == "nhân" })
        XCTAssertTrue(candidates.contains { $0.syllable == "nhan" })
    }

    func testRejectsUnrelatedPathsAndInvalidLimits() {
        XCTAssertEqual(GlidePathDecoder.score(candidate: "truong", keySequence: Array("tx"), confirmedKeys: []), 0)
        XCTAssertTrue(GlidePathDecoder.decode(keySequence: Array("nhan"), limit: -1).isEmpty)
        XCTAssertTrue(GlidePathDecoder.decode(keySequence: Array(repeating: "a", count: 257)).isEmpty)
        XCTAssertTrue(GlideToneResolver.resolve(untoned: "nhan", context: "", limit: -1).isEmpty)
    }

    func testStableRankingAndBoundedResults() {
        let first = GlidePathDecoder.decode(keySequence: Array("nhan"), limit: 5)
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first, GlidePathDecoder.decode(keySequence: Array("nhan"), limit: 5))
        XCTAssertEqual(first.map(\.score), first.map(\.score).sorted(by: >))
    }

    func testArcLengthSamplingIgnoresDeliveryRate() {
        let sparse = [GlidePoint(x: 0, y: 0), GlidePoint(x: 10, y: 0)]
        let dense = (0...10).map { GlidePoint(x: Double($0), y: 0) }
        let a = GlidePathDecoder.resample(sparse, count: 16)
        let b = GlidePathDecoder.resample(dense, count: 16)
        XCTAssertEqual(a.count, b.count)
        for (left, right) in zip(a, b) {
            XCTAssertEqual(left.x, right.x, accuracy: 1e-10)
            XCTAssertEqual(left.y, right.y, accuracy: 1e-10)
        }
        XCTAssertTrue(GlidePathDecoder.resample([], count: 16).isEmpty)
        XCTAssertEqual(GlidePathDecoder.resample([sparse[0]], count: 16).count, 16)
    }

    func testContextCanPromoteSecondGeometricCandidate() {
        let candidates = [GlideCandidate(syllable: "nhan", score: 0.8), GlideCandidate(syllable: "nhân", score: 0.79)]
        let ranked = GlideToneResolver.resolve(candidates: candidates, continuations: ["nhận"])
        XCTAssertEqual(ranked.first?.syllable, "nhận")
        // A continuation deep in the list still receives positive evidence.
        let tailContext = Array(repeating: "other", count: 30) + ["nhận"]
        let tail = GlideToneResolver.resolve(candidates: [candidates[1]], continuations: tailContext)
        XCTAssertEqual(tail.first?.syllable, "nhận")
    }

    func testGeometryChangesRanking() {
        let centers: [Character: GlidePoint] = ["n": .init(x: 0, y: 0), "h": .init(x: 1, y: 1), "a": .init(x: 2, y: 0)]
        let path = [centers["n"]!, centers["h"]!, centers["a"]!, centers["n"]!]
        let near = GlidePathDecoder.decode(keySequence: Array("nhan"), limit: 30, path: path, keyCenters: centers)
        let far = GlidePathDecoder.decode(keySequence: Array("nhan"), limit: 30,
                                         path: path.map { .init(x: $0.x + 10, y: $0.y) }, keyCenters: centers)
        XCTAssertGreaterThan(near.first { $0.syllable == "nhan" }!.score,
                             far.first { $0.syllable == "nhan" }!.score)
    }

    func testSuffixIsBoundedAndOptional() {
        XCTAssertEqual(GlidePathDecoder.extractTelexSuffix(from: Array("nhans"))?.base, Array("nhan"))
        XCTAssertTrue(GlidePathDecoder.decode(keySequence: Array("nhans"), limit: 30).contains { $0.syllable == "nhan" })
        XCTAssertNil(GlidePathDecoder.extractTelexSuffix(from: Array("as")))
    }
    func testExplicitToneIsEvidenceRatherThanForcedSuffix() {
        let implicit = GlidePathDecoder.decode(keySequence: Array("nhans"), limit: 30)
        XCTAssertTrue(implicit.allSatisfy { $0.toneKey == nil })
        let explicit = GlidePathDecoder.decode(keySequence: Array("nhans"), confirmedKeys: ["s"], limit: 30)
        XCTAssertTrue(explicit.contains { $0.toneKey == "s" })
        let resolved = GlideToneResolver.resolve(candidates: [GlideCandidate(syllable: "nhân", score: 0.9, toneKey: "j")], continuations: [])
        XCTAssertEqual(resolved.first?.syllable, "nhận")
    }

    func testDecodeTimingSample() {
        let corpus = ["nhan", "truong", "dang", "nguoif", "xin", "chao", "nhans"]
        var timings: [Double] = []
        for index in 0..<35 {
            let start = ProcessInfo.processInfo.systemUptime
            let geometric = GlidePathDecoder.decode(keySequence: Array(corpus[index % corpus.count]), limit: 12)
            _ = GlideToneResolver.resolve(candidates: geometric, continuations: ["nhận", "trường"])
            timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        timings.sort()
        print("GLIDE_DEBUG_TIMING samples=35 p50_ms=\(timings[17]) p95_ms=\(timings[33]); synthetic key sequences, not device touch latency")
    }

}
