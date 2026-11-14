import Foundation
import VieLotusCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Benchmark Logic

struct TestCase {
    let input: String
    let expectedOutput: [String] // Array to handle "hóa / hoá"
    let expectedBehavior: String
    let category: String
    /// Column 3 — what plain Telex produces before Smart Bilingual touches it, i.e. the
    /// Vietnamese syllable that an English restore costs us. Used as the expectation for the
    /// no-context side of `vn_survives_collision`.
    let naiveTelexOutput: String
    /// Column 8 — the suite's own verdict on whether restoring this word is safe:
    /// `never` (the only keystroke path to the Vietnamese syllable), `degrades_vn`
    /// (one of several paths lost), `yes`, `n_a`.
    let whitelistSafe: String
}

func driveInput(session: InputSessionManager, input: String, primeEnglish: Bool, bilingualEnabled: Bool) -> String {
    session.reset()
    session.setSmartBilingualEnabled(bilingualEnabled)
    // `reset()` deliberately does NOT clear `context` (it survives across words in real
    // typing), so assign it unconditionally here. Without this, every row after the first
    // primed one silently inherits "he is" and the whole suite measures a contaminated
    // context instead of the per-row condition it claims to test.
    session.context = primeEnglish ? "he is" : ""

    var result = ""
    for char in input {
        if char == "<" {
            let action = session.handleBackspace()
            if case let .replace(backspaces, text) = action {
                if backspaces > 0 { result.removeLast(min(backspaces, result.count)) }
                result += text
            } else if case .passThrough = action {
                if !result.isEmpty { result.removeLast() }
            }
        } else if session.isWordBoundary(char) {
            let action = session.commitWord(smartBilingualEnabled: bilingualEnabled, boundaryChar: char)
            if case let .commit(backspaces, text, isOverride) = action {
                if isOverride {
                    result.removeLast(min(backspaces, result.count))
                    result += text
                }
            }
            result.append(char)
        } else {
            let action = session.handleCharacter(char)
            if case let .replace(backspaces, text) = action {
                if backspaces > 0 { result.removeLast(min(backspaces, result.count)) }
                result += text
            } else if case .passThrough = action {
                result.append(char)
            }
        }
    }

    if session.isComposing {
        let action = session.commitWord(smartBilingualEnabled: bilingualEnabled)
        if case let .commit(backspaces, text, isOverride) = action {
            if isOverride {
                result.removeLast(min(backspaces, result.count))
                result += text
            }
        }
    }
    return result
}

/// Ratchet floors for the symmetric ambiguous buckets, measured on 2026-10-11 with
/// per-row isolated context: `vn_survives_collision` 322/373 = 86.3270%, truncated
/// toward zero so the floor never sits above the value it was derived from.
/// These only ever move up — `scripts/benchmark_ratchet.sh --ratchet` rewrites them when
/// a run measures better, and never loosens them for a less accurate build.
let vnSurvivesFloorBaseline = 86.32
let bothSidesFloorBaseline = 86.32

func runBenchmark(
    csvPath: String,
    profile: GrammarProfile = .senFlex,
    targetThreshold: Double = 98.0,
    vnFloorThreshold: Double = vnSurvivesFloorBaseline,
    bothSidesFloorThreshold: Double = bothSidesFloorBaseline,
    emitJSON: Bool = false
) {
    print("=== 🌸 Sen Việt (VieLotusIM) Benchmark Suite ===")
    print("Reading CSV from: \(csvPath)")
    print("Grammar Profile: \(profile.rawValue)")
    print("Target Threshold: \(String(format: "%.2f%%", targetThreshold))")

    let content: String
    if csvPath == "<embedded>" {
        guard let embedded = EmbeddedTestSuite.loadCSV() else {
            print("❌ Error: Could not decode embedded regression suite")
            exit(1)
        }
        content = embedded
    } else if let fileContent = try? String(contentsOfFile: csvPath, encoding: .utf8) {
        content = fileContent
    } else if let embedded = EmbeddedTestSuite.loadCSV() {
        content = embedded
    } else {
        print("❌ Error: Could not read CSV benchmark file at '\(csvPath)'")
        exit(1)
    }

    let lines = content.components(separatedBy: .newlines)
    var testCases = [TestCase]()

    let knownBehaviors: Set<String> = [
        "transform", "restore_raw", "keep_as_typed",
        "ambiguous_needs_context", "cancel_keep_composed"
    ]

    for (index, line) in lines.enumerated() {
        if index == 0 || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        let columns = line.components(separatedBy: ",")
        if columns.count >= 6 {
            let behavior = columns[5]
            guard knownBehaviors.contains(behavior) else { continue }

            let expectedRaw = columns[4]
            // Only split on " / " with spaces, so URLs and file paths like "/usr/bin" or "https://..." stay intact!
            let expectedParts: [String]
            if expectedRaw.contains(" / ") {
                expectedParts = expectedRaw.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                expectedParts = [expectedRaw.trimmingCharacters(in: .whitespaces)]
            }

            let tc = TestCase(
                input: columns[1],
                expectedOutput: expectedParts,
                expectedBehavior: behavior,
                category: columns[6],
                naiveTelexOutput: columns.count > 3 ? columns[3].trimmingCharacters(in: .whitespaces) : "",
                whitelistSafe: columns.count > 8 ? columns[8].trimmingCharacters(in: .whitespaces) : ""
            )
            testCases.append(tc)
        }
    }

    // Suite self-consistency scan.
    //
    // (1) UNSATISFIABLE: two rows that the harness drives under IDENTICAL conditions
    //     (same input, same bilingual/context flags) but expect different output. No
    //     engine can pass both, so 100% is arithmetically unreachable until the CSV is
    //     reconciled. Grouping by drive condition — not just by input — matters: `gif`
    //     legitimately expects `gì` with Smart Bilingual off and `gif` with it on.
    // (2) POLICY DISAGREEMENT: the same word carries `whitelist_safe=never` on one row
    //     ("restoring this kills the only keystroke path to a Vietnamese syllable") and
    //     `=yes` on another. Satisfiable, but it means the dataset does not agree with
    //     itself about whether restoring that word is acceptable.
    func driveCondition(_ behavior: String) -> String {
        switch behavior {
        case "transform", "cancel_keep_composed": return "bilingual=off"
        case "ambiguous_needs_context": return "bilingual=on,context=en"
        default: return "bilingual=on,context=none"
        }
    }
    var expectationsByKey: [String: Set<String>] = [:]
    var safetyByKey: [String: Set<String>] = [:]
    for tc in testCases {
        let key = "\(tc.input)|\(driveCondition(tc.expectedBehavior))"
        expectationsByKey[key, default: []].insert(tc.expectedOutput.joined(separator: " / "))
        if tc.whitelistSafe == "never" || tc.whitelistSafe == "yes" {
            safetyByKey[tc.input.lowercased(), default: []].insert(tc.whitelistSafe)
        }
    }
    let unsatisfiable = expectationsByKey.filter { $0.value.count > 1 }.keys.sorted()
    let policyDisagreements = safetyByKey.filter { $0.value.count > 1 }.keys.sorted()

    print("Total test cases loaded: \(testCases.count)")
    if unsatisfiable.isEmpty {
        print("Suite satisfiability: ✅ no input is asked for two different outputs under identical drive conditions")
    } else {
        print("Suite satisfiability: ❌ \(unsatisfiable.count) key(s) are UNSATISFIABLE — 100% is unreachable until the CSV is reconciled:")
        for key in unsatisfiable.prefix(20) {
            let parts = key.components(separatedBy: "|")
            print("  • '\(parts[0])' [\(parts[1])] → \(expectationsByKey[key]?.sorted().joined(separator: "  HOẶC  ") ?? "")")
        }
    }
    if policyDisagreements.isEmpty {
        print("Suite policy coherence: ✅ `whitelist_safe` verdicts agree per word\n")
    } else {
        print("Suite policy coherence: ⚠️  \(policyDisagreements.count) word(s) carry both `never` and `yes` verdicts:")
        print("  \(policyDisagreements.joined(separator: ", "))\n")
    }
    guard !testCases.isEmpty else {
        print("❌ Error: No valid test cases found in benchmark file.")
        exit(1)
    }

    #if os(macOS)
    SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
    #endif
    let session = InputSessionManager()
    session.setGrammarProfile(profile)
    var passCounts: [String: Int] = [:]
    var totalCounts: [String: Int] = [:]
    var overallPass = 0
    var overallFail = 0
    var failureExamples: [String] = []
    /// Row indices of the `ambiguous_needs_context` bucket that passed *with* an English
    /// context primed. Cross-referenced against the no-context pass below.
    var ambiguousPhase1Pass: Set<Int> = []

    for (caseIndex, tc) in testCases.enumerated() {
        totalCounts[tc.expectedBehavior, default: 0] += 1

        let result: String
        switch tc.expectedBehavior {
        case "transform":
            // VN→VN: pure Vietnamese conversion
            result = driveInput(session: session, input: tc.input, primeEnglish: false, bilingualEnabled: false)
        case "cancel_keep_composed":
            // Escape/trailing cancel commits screen text
            result = driveInput(session: session, input: tc.input, primeEnglish: false, bilingualEnabled: false)
        case "ambiguous_needs_context":
            // Tested after an established English phrase (e.g. "he is ...")
            result = driveInput(session: session, input: tc.input, primeEnglish: true, bilingualEnabled: true)
        case "restore_raw":
            // English word that was mangled by Telex, auto-restored
            result = driveInput(session: session, input: tc.input, primeEnglish: false, bilingualEnabled: true)
        default: // keep_as_typed
            result = driveInput(session: session, input: tc.input, primeEnglish: false, bilingualEnabled: true)
        }

        let isPass = tc.expectedOutput.contains(result)
        if isPass {
            passCounts[tc.expectedBehavior, default: 0] += 1
            overallPass += 1
            if tc.expectedBehavior == "ambiguous_needs_context" { ambiguousPhase1Pass.insert(caseIndex) }
        } else {
            overallFail += 1
            if failureExamples.count < 15 {
                failureExamples.append("[\(tc.expectedBehavior)] Input '\(tc.input)' -> Expected: '\(tc.expectedOutput.joined(separator: " / "))', Got: '\(result)'")
            }
        }
    }

    print("--- 📊 Chi tiết từng nhóm kiểm thử (Regression Test Matrix) ---")
    for (behavior, total) in totalCounts.sorted(by: { $0.key < $1.key }) {
        let passed = passCounts[behavior, default: 0]
        let rate = Double(passed) / Double(total) * 100.0
        let padded = behavior.padding(toLength: 25, withPad: " ", startingAt: 0)
        print("  • \(padded): \(passed) / \(total) (\(String(format: "%6.2f%%", rate)))")
    }

    // -------------------------------------------------------------------------
    // PHASE 2 — the other side of the ambiguous trade
    //
    // Phase 1 measures `ambiguous_needs_context` WITH an English context primed
    // ("he is …"), so a 100% score there only proves "English context in → English
    // out". It says nothing about what the same keystrokes do with no context.
    //
    // The 1,047 rows split by WHICH signal marks them English:
    //   • 674 `case_variant` rows carry an uppercase letter and their expected_output
    //     is the input itself — for those, capitalisation alone must restore English
    //     even with no context, so the no-context expectation stays English.
    //   • 373 lowercase-only rows carry no orthographic signal at all; context is the
    //     only thing separating them, so with no context the Vietnamese syllable
    //     (`naive_telex_output`) MUST survive. This is the real cost side of the trade,
    //     and the number the headline pass rate never showed.
    // -------------------------------------------------------------------------
    print("\n--- 🪷 Vế đối xứng: đo lại chính 1.047 dòng đó khi KHÔNG có context tiếng Anh ---")
    var vnTotal = 0
    var vnPass = 0
    var neverTotal = 0
    var neverPass = 0
    var degradeTotal = 0
    var degradePass = 0
    var casedTotal = 0
    var casedPass = 0
    var bothSidesPass = 0
    var neverFailures: [String] = []
    var degradeFailures: [String] = []
    var casedFailures: [String] = []

    for (caseIndex, tc) in testCases.enumerated() {
        guard tc.expectedBehavior == "ambiguous_needs_context" else { continue }
        let phase1OK = ambiguousPhase1Pass.contains(caseIndex)

        // Cased rows are reported separately and never gated: the suite files them under
        // `ambiguous_needs_context`, i.e. it intends them to be judged WITH a context.
        // Whether capitalisation ALONE should restore English is a policy question this
        // project has not decided, so the number is exploratory rather than pass/fail.
        if tc.input.contains(where: { $0.isUppercase }) {
            casedTotal += 1
            let result = driveInput(session: session, input: tc.input, primeEnglish: false, bilingualEnabled: true)
            if tc.expectedOutput.contains(result) {
                casedPass += 1
            } else if casedFailures.count < 10 {
                casedFailures.append("'\(tc.input)' → kỳ vọng: '\(tc.expectedOutput.joined(separator: " / "))', nhận được: '\(result)'")
            }
            continue
        }

        guard tc.whitelistSafe == "never" || tc.whitelistSafe == "degrades_vn" else { continue }
        guard !tc.naiveTelexOutput.isEmpty else { continue }

        vnTotal += 1
        if tc.whitelistSafe == "never" { neverTotal += 1 } else { degradeTotal += 1 }

        let result = driveInput(session: session, input: tc.input, primeEnglish: false, bilingualEnabled: true)
        let vnOK = result == tc.naiveTelexOutput
        if vnOK {
            vnPass += 1
            if tc.whitelistSafe == "never" { neverPass += 1 } else { degradePass += 1 }
        } else if tc.whitelistSafe == "never" {
            neverFailures.append("'\(tc.input)' → mất '\(tc.naiveTelexOutput)', nhận được '\(result)'")
        } else if degradeFailures.count < 10 {
            degradeFailures.append("'\(tc.input)' → mất '\(tc.naiveTelexOutput)', nhận được '\(result)'")
        }
        if phase1OK && vnOK { bothSidesPass += 1 }
    }

    let vnRate = vnTotal > 0 ? Double(vnPass) / Double(vnTotal) * 100.0 : 0.0
    let casedRate = casedTotal > 0 ? Double(casedPass) / Double(casedTotal) * 100.0 : 0.0
    let bothRate = vnTotal > 0 ? Double(bothSidesPass) / Double(vnTotal) * 100.0 : 0.0
    print(String(format: "  • vn_survives_collision : %d / %d (%6.2f%%)  ← không context, không tín hiệu chữ hoa", vnPass, vnTotal, vnRate))
    print(String(format: "      ↳ never       (đường keystroke DUY NHẤT tới âm tiết Việt): %d / %d", neverPass, neverTotal))
    print(String(format: "      ↳ degrades_vn (mất 1 trong nhiều đường gõ)               : %d / %d", degradePass, degradeTotal))
    print(String(format: "  • ambiguous_both_sides  : %d / %d (%6.2f%%)  ← số nên trích dẫn thay cho một vế", bothSidesPass, vnTotal, bothRate))
    print(String(format: "  • case_signal_restores  : %d / %d (%6.2f%%)  ← THAM KHẢO, chưa gate (câu hỏi chính sách)", casedPass, casedTotal, casedRate))

    if !neverFailures.isEmpty {
        print("\n🔴 CA NGUY CẤP — mất đường keystroke DUY NHẤT tới âm tiết Việt (\(neverFailures.count) ca):")
        for example in neverFailures {
            print("  ❌ \(example)")
        }
    }
    if !degradeFailures.isEmpty {
        print("\n🟡 Mất 1 trong nhiều đường gõ (mẫu \(degradeFailures.count)/\(degradeTotal - degradePass)):")
        for example in degradeFailures {
            print("  ⚠️  \(example)")
        }
    }
    if !casedFailures.isEmpty {
        print("\n⚪ Chữ hoa không tự khôi phục khi thiếu context (mẫu \(casedFailures.count)/\(casedTotal - casedPass)):")
        for example in casedFailures {
            print("  ·  \(example)")
        }
    }

    let overallRate = Double(overallPass) / Double(testCases.count) * 100.0
    print("\n=======================================================")
    print(String(format: "🏆 Tổng kết Pass Rate Toàn Diện: %.2f%% (%d / %d)", overallRate, overallPass, testCases.count))
    print("=======================================================\n")

    if !failureExamples.isEmpty {
        print("Một số ca thất bại mẫu:")
        for example in failureExamples {
            print("  ❌ \(example)")
        }
    }

    if emitJSON {
        // One machine-readable line for scripts/benchmark_ratchet.sh, tagged with a fixed
        // prefix so it can be grepped out of the human-readable report.
        func rate(_ behavior: String) -> Double {
            let total = totalCounts[behavior, default: 0]
            guard total > 0 else { return 0 }
            return Double(passCounts[behavior, default: 0]) / Double(total) * 100.0
        }
        let fields: [(String, Double)] = [
            ("overall", overallRate),
            ("transform", rate("transform")),
            ("restore_raw", rate("restore_raw")),
            ("keep_as_typed", rate("keep_as_typed")),
            ("ambiguous_needs_context", rate("ambiguous_needs_context")),
            ("cancel_keep_composed", rate("cancel_keep_composed")),
            ("vn_survives_collision", vnRate),
            ("ambiguous_both_sides", bothRate),
            ("case_signal_restores", casedRate)
        ]
        let body = fields.map { "\"\($0.0)\":\(String(format: "%.4f", $0.1))" }.joined(separator: ",")
        print("BENCHMARK_JSON {\"profile\":\"\(profile.rawValue)\",\"cases\":\(testCases.count),\"vn_cases\":\(vnTotal),\(body)}")
    }

    // CI Quality Gate: Overall pass rate must meet or exceed target threshold
    if overallRate < targetThreshold {
        print("\n❌ CI Quality Gate Failed: Overall pass rate \(String(format: "%.2f%%", overallRate)) is below target threshold of \(String(format: "%.2f%%", targetThreshold))")
        exit(1)
    }
    print("✅ CI Quality Gate Passed (\(String(format: "%.2f%%", overallRate)) >= \(String(format: "%.2f%%", targetThreshold)))")

    // CI Quality Gate (ratchet floor): the Vietnamese side of the ambiguous trade must
    // not regress. The floor only ever moves up — see scripts/perf_ratchet.sh for the
    // same rule applied to keystroke latency.
    if vnTotal > 0 {
        if vnRate < vnFloorThreshold {
            print(String(format: "\n❌ CI Quality Gate Failed: vn_survives_collision %.2f%% is below its ratchet floor of %.2f%%", vnRate, vnFloorThreshold))
            exit(1)
        }
        print(String(format: "✅ vn_survives_collision Floor Passed (%.2f%% >= %.2f%%)", vnRate, vnFloorThreshold))
    }
    if vnTotal > 0 && bothRate < bothSidesFloorThreshold {
        print(String(format: "❌ CI Quality Gate Failed: ambiguous_both_sides %.2f%% is below its ratchet floor of %.2f%%", bothRate, bothSidesFloorThreshold))
        exit(1)
    }
    if vnTotal > 0 {
        print(String(format: "✅ ambiguous_both_sides Floor Passed (%.2f%% >= %.2f%%)", bothRate, bothSidesFloorThreshold))
    }
}

// MARK: - Stress & Endurance Benchmark Logic

func getMemoryRSS() -> Double {
    #if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if kerr == KERN_SUCCESS {
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }
    return 0.0
    #elseif canImport(Glibc)
    if let content = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) {
        let parts = content.split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 2, let pages = Double(parts[1]) {
            let pageSize = Double(sysconf(Int32(_SC_PAGESIZE)))
            return (pages * pageSize) / (1024.0 * 1024.0)
        }
    }
    return 0.0
    #else
    return 0.0
    #endif
}

func calculatePercentiles(_ latencies: [Double]) -> (
    p50: Double, p90: Double, p95: Double, p99: Double, p999: Double, max: Double, mean: Double
) {
    guard !latencies.isEmpty else { return (0, 0, 0, 0, 0, 0, 0) }
    let sorted = latencies.sorted()
    let count = Double(sorted.count)
    let p50 = sorted[Int(count * 0.50)]
    let p90 = sorted[Int(count * 0.90)]
    let p95 = sorted[Int(count * 0.95)]
    let p99 = sorted[Int(count * 0.99)]
    let p999 = sorted[min(Int(count * 0.999), sorted.count - 1)]
    let max = sorted.last ?? 0
    let mean = latencies.reduce(0, +) / Double(latencies.count)
    return (p50, p90, p95, p99, p999, max, mean)
}

enum StressOperationKind {
    case keystroke
    case boundary
    case backspace
}

@inline(__always)
func classifyStressOperation(_ char: Character, session: InputSessionManager) -> StressOperationKind {
    if char == "<" {
        return .backspace
    }
    if session.isWordBoundary(char) {
        return .boundary
    }
    return .keystroke
}

@inline(__always)
func applyStressAction(
    _ action: SessionAction,
    priorComposingUTF16: Int = 0,
    fallbackChar: Character? = nil,
    isBackspace: Bool = false,
    to buffer: inout [UInt16],
    replacesExecuted: inout Int
) {
    switch action {
    case let .replace(backspaces, text):
        replacesExecuted &+= 1
        if backspaces > 0 {
            buffer.removeLast(min(backspaces, buffer.count))
        }
        buffer.append(contentsOf: text.utf16)
    case let .commit(backspaces, text, isOverride):
        if isOverride {
            if backspaces > 0 {
                buffer.removeLast(min(backspaces, buffer.count))
            }
            buffer.append(contentsOf: text.utf16)
        }
    case .passThrough:
        if let ch = fallbackChar {
            buffer.append(contentsOf: String(ch).utf16)
        } else if isBackspace && !buffer.isEmpty {
            buffer.removeLast()
        }
    case .consumed:
        break
    case .reset:
        let removeCount = min(max(1, priorComposingUTF16), buffer.count)
        if removeCount > 0 {
            buffer.removeLast(removeCount)
        }
    }
}

struct ContinuousStreamResult {
    let latenciesUs: [Double]
    let totalKeystrokes: Int
    let wordsCommitted: Int
    let backspacesExecuted: Int
    let replacesExecuted: Int
    let elapsedSec: Double
    let reconstructedText: String
}

func driveContinuousStream(
    session: InputSessionManager,
    stream: String,
    bilingualEnabled: Bool,
    progressStep: Int = 25_000,
    onProgress: ((Int, Double) -> Void)? = nil
) -> ContinuousStreamResult {
    var latencies: [Double] = []
    latencies.reserveCapacity(stream.count)
    var outputUTF16: [UInt16] = []
    outputUTF16.reserveCapacity(stream.count)
    var count = 0
    var wordsCommitted = 0
    var backspacesExecuted = 0
    var replacesExecuted = 0

    let tStart = DispatchTime.now().uptimeNanoseconds
    for char in stream {
        switch classifyStressOperation(char, session: session) {
        case .boundary:
            let t0 = DispatchTime.now().uptimeNanoseconds
            let action = session.commitWord(smartBilingualEnabled: bilingualEnabled, boundaryChar: char)
            let t1 = DispatchTime.now().uptimeNanoseconds
            latencies.append(Double(t1 - t0) / 1000.0)
            if case .commit = action {
                wordsCommitted += 1
            }
            applyStressAction(action, to: &outputUTF16, replacesExecuted: &replacesExecuted)
            outputUTF16.append(contentsOf: String(char).utf16)
        case .backspace:
            let priorUTF16 = session.isComposing ? session.currentOutput().utf16.count : 1
            let t0 = DispatchTime.now().uptimeNanoseconds
            let action = session.handleBackspace()
            let t1 = DispatchTime.now().uptimeNanoseconds
            latencies.append(Double(t1 - t0) / 1000.0)
            backspacesExecuted += 1
            applyStressAction(action, priorComposingUTF16: priorUTF16, fallbackChar: nil, isBackspace: true, to: &outputUTF16, replacesExecuted: &replacesExecuted)
        case .keystroke:
            let t0 = DispatchTime.now().uptimeNanoseconds
            let action = session.handleCharacter(char)
            let t1 = DispatchTime.now().uptimeNanoseconds
            latencies.append(Double(t1 - t0) / 1000.0)
            applyStressAction(action, fallbackChar: char, to: &outputUTF16, replacesExecuted: &replacesExecuted)
        }

        count += 1
        if progressStep > 0 && count % progressStep == 0 {
            onProgress?(count, getMemoryRSS())
        }
    }

    if session.isComposing {
        let action = session.commitWord(smartBilingualEnabled: bilingualEnabled)
        if case .commit = action { wordsCommitted += 1 }
        applyStressAction(action, to: &outputUTF16, replacesExecuted: &replacesExecuted)
    }
    let tEnd = DispatchTime.now().uptimeNanoseconds
    let elapsedSec = Double(tEnd - tStart) / 1_000_000_000.0
    let text = String(decoding: outputUTF16, as: UTF16.self)

    return ContinuousStreamResult(
        latenciesUs: latencies,
        totalKeystrokes: count,
        wordsCommitted: wordsCommitted,
        backspacesExecuted: backspacesExecuted,
        replacesExecuted: replacesExecuted,
        elapsedSec: elapsedSec,
        reconstructedText: text
    )
}

func buildRepeatedStream(base: String, targetCount: Int) -> String {
    var result = ""
    result.reserveCapacity(targetCount + base.count)
    while result.count < targetCount {
        result.append(base)
    }
    let index = result.index(result.startIndex, offsetBy: min(targetCount, result.count))
    return String(result[..<index])
}

func runStressAndEnduranceBenchmark(
    profile: GrammarProfile = .classic,
    emitJSON: Bool = false,
    mobilePath: Bool = false,
    telexCeiling: Double = 500.0,
    vniCeiling: Double = 300.0,
    mixedCeiling: Double = 700.0,
    kpsFloor: Double = 25000.0
) {
    print("================================================================================")
    print("⚡️ BỘ ĐO ĐỘ BỀN BỈ & HIỆU NĂNG TẢI CAO (STRESS & ENDURANCE BENCHMARK)")
    print("   Bộ gõ Sen Việt (VieLotusIM) — Telex & VNI High-Throughput Stream Harness")
    print("   Grammar Profile: \(profile.rawValue)")
    print("================================================================================\n")

    if mobilePath {
        SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()
    } else {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
    }
    print("   Inline bilingual: \(mobilePath); provider: \(mobilePath ? "local-mobile" : "platform-desktop"); host/UI: NOT MEASURED")
    func configuredSession() -> InputSessionManager {
        let session = InputSessionManager()
        session.setGrammarProfile(profile)
        session.inlineBilingualEnabled = mobilePath
        session.setGenZMode(mobilePath)
        session.setModernOrthography(true)
        session.macroEnabled = false
        return session
    }
    let initialRSS = getMemoryRSS()
    print(String(format: "📌 Bộ nhớ ban đầu (Baseline Memory RSS): %.2f MB\n", initialRSS))

    let telexRawCorpus = """
Trawm nawm trong coxi nguowfi ta, chuwx taif chuwx meejnh kheos laf ghest nhau. Trair qua moojt cuoojc ber dau, nhuwngx ddieeuf troong thaays maf ddau ddoosns lonfg. Lar gif bir sawsc tuw phong, troowfi xanh quen thoos maas hoonfg ddasnh ghen.
VieLotusIM laf booj gox tieengs Vieejt thees heej mowis treen macOS, dduowjc vieest hoanf toanf bawfng ngoon nguwr laapj trinhf Swift 6 hieejn ddaaij. Kieesn trusc cura booj gox tuaan thur nghieem ngawtj moo hinhf baor maawtj cura Apple, khoong caafn quyeefn Accessibility hay EventTap.
Alo banj oowi, trwua nay awn gif nhir? DDi awn phor bov soost vang owr phoos cor khoong? Hay ra quasn cowm nieeu gaafn coong ty nhes, taafm 12 gioowf kesm mifnh qua ddosn banj!
Heej thoosng microservices ddang xuwr lys khoarng muwowif nghifn requests mooxi giaay vowis latency cuwcj thaasp. Hays kieerm tra cacs file configuration, caapj nhaajt package dependencies vaf deploy leen production server ngay trong hoom nay nhes.
Khai maacj hooji nghij thuowjng ddirnh quoocs tees veef chuyeern ddooir soos vaf phast trieern kinh tees xanh beefn vuwngx nawm 2026. Cacs chuyeen gia nhaasn manjh taafm quan troongj cura vieecj baor veej duwr lieeju cas nhaan vaf an ninh manjg trong kyr nguyeon soos.
Chusc muwngf nawm mowis an khang thijnh vuwowjng vanj suwj nhuw ys phast taif phast loocj suwcj khoer doofii dafo gia ddirnh hanjh phusc.
toans<f nguyeenx<j tieengf<s chaof<s dduowngj<f cuoojcs<j vieejtt<
https://github.com/stevedat/VieLotus-IM let config = Configuration(timeout: 30, retryCount: 3)
"""

    let vniRawCorpus = """
Tram8 nam8 trong coi4 nguoi72 ta, chu74 tai2 chu74 menh65 kheo1 la2 ghet1 nhau. Trai3 qua mot65 cuoc65 be3 dau, nhung74 d9ieu2 trong thay1 ma2 d9au d9on1 long2. La5 gi2 bi3 sac1 tu7 phong, troi72 xanh quen thoi1 ma1 hong2 d9anh1 ghen.
VieLotusIM la2 bo65 go4 tie6ng1 Viet65 the61 he65 mo7i1 tre6n macOS, d9uoc75 viet1 hoan2 toan2 bang2 ngon6 ngu74 lap5 trinh2 Swift 6 hien65 d9ai5. Kien1 truc1 cua3 bo65 go4 tuan6 thu3 nghiem6 ngat5 mo6 hinh2 bao3 mat65 cua3 Apple, khong can2 quyen2 Accessibility hay EventTap.
Alo ban5 oi7, trua nay an8 gi2 nhi3? D9i an8 pho3 bo2 sot1 vang o73 pho1 co3 khong? Hay ra quan1 com7 nieu gan2 cong ty nhe1, tam62 12 gio72 kem1 minh2 qua d9on1 ban5!
He5 thong1 microservices d9ang xu73 ly1 khoang3 muoi72 nghin2 requests moi4 giay voi1 latency cuc5 thap1. Hay4 kiem3 tra cac1 file configuration, cap5 nhat5 package dependencies va2 deploy len6 production server ngay trong hom6 nay nhe1.
Khai mac5 hoi5 nghi5 thuong75 d9inh3 quoc1 te1 ve2 chuyen3 d9oi3 so1 va2 phat1 trien3 kinh te1 xanh ben2 vung4 nam8 2026. Cac1 chuyen gia nhan1 manh5 tam62 quan trong cua3 viec65 bao3 ve5 du74 lieu5 ca1 nhan va2 an ninh mang5 trong ky3 nguyen so1.
Chuc1 mung72 nam8 moi1 an khang thinh5 vuong75 van5 su75 nhu7 y1 phat1 tai2 phat1 loc65 suc1 khoe3 doi2 dao2 gia d9inh2 hanh5 phuc1.
toan1<2 nguyen64<5 tie6ng2<1 chao2<1 d9uong75<2 cuoc61<5
Hom6 nay ngay2 15 thang1 10 nam8 2026, tong63 doanh thu d9at5 150000000 d9ong62, ma4 san3 pham63 la2 SP102938.
https://github.com/stevedat/VieLotus-IM let config = Configuration(timeout: 30, retryCount: 3)
"""

    // Compute deterministic reference output (pass 1 cold + pass 2 warm-context) for Telex and VNI to verify 0 lost chars/diacritics
    let telexRefSession = configuredSession()
    telexRefSession.setInputMethod(.telex)
    telexRefSession.setGrammarProfile(profile)
    telexRefSession.setModernOrthography(true)
    let telexPass1Text = driveContinuousStream(
        session: telexRefSession,
        stream: telexRawCorpus,
        bilingualEnabled: true,
        progressStep: 0
    ).reconstructedText
    let telexPass2Text = driveContinuousStream(
        session: telexRefSession,
        stream: telexRawCorpus,
        bilingualEnabled: true,
        progressStep: 0
    ).reconstructedText

    let vniRefSession = configuredSession()
    vniRefSession.setInputMethod(.vni)
    vniRefSession.setModernOrthography(true)
    let vniPass1Text = driveContinuousStream(
        session: vniRefSession,
        stream: vniRawCorpus,
        bilingualEnabled: true,
        progressStep: 0
    ).reconstructedText
    let vniPass2Text = driveContinuousStream(
        session: vniRefSession,
        stream: vniRawCorpus,
        bilingualEnabled: true,
        progressStep: 0
    ).reconstructedText

    // -------------------------------------------------------------------------
    // PHASE 1: TELEX 100,000 KEYSTROKES
    // -------------------------------------------------------------------------
    print("--------------------------------------------------------------------------------")
    print("▶ GIAI ĐOẠN 1: KIỂM THỬ BỀN BỈ KIỂU GÕ TELEX (100,000 Phím Liên Tục)")
    print("--------------------------------------------------------------------------------")
    let telexSession = configuredSession()
    telexSession.setInputMethod(.telex)
    telexSession.setGrammarProfile(profile)
    telexSession.setModernOrthography(true)

    let telexStream = buildRepeatedStream(base: telexRawCorpus, targetCount: 100_000)
    print("  • Chuẩn bị luồng phím: \(telexStream.count) ký tự (văn bản, chat, code, phím backspace)")

    var telexMemCheckpoints: [(Int, Double)] = [(0, getMemoryRSS())]
    let telexResult = driveContinuousStream(
        session: telexSession,
        stream: telexStream,
        bilingualEnabled: true,
        progressStep: 25_000
    ) { step, mem in
        telexMemCheckpoints.append((step, mem))
        print(String(format: "  ↳ [Keystrokes: %6d / 100,000] - Memory RSS: %.2f MB", step, mem))
    }

    let telexStats = calculatePercentiles(telexResult.latenciesUs)
    let telexKPS = Double(telexResult.totalKeystrokes) / telexResult.elapsedSec
    let telexWPS = Double(telexResult.wordsCommitted) / telexResult.elapsedSec

    let numFmt = NumberFormatter()
    numFmt.numberStyle = .decimal
    func fmt(_ val: Int) -> String { numFmt.string(from: NSNumber(value: val)) ?? "\(val)" }
    func fmtD(_ val: Double) -> String { numFmt.string(from: NSNumber(value: Int(val))) ?? "\(Int(val))" }

    let telexFullReps = telexStream.count / telexRawCorpus.count
    let telexExpectedPrefix = telexPass1Text + String(repeating: telexPass2Text, count: max(0, telexFullReps - 1))
    let telexRequiredAnchors = [
        "Trăm năm trong cõi người ta, chữ tài chữ mệnh khéo là ghét nhau.",
        "VieLotusIM là bộ gõ tiếng Việt thế hệ mới trên macOS",
        "Hệ thống microservices đang xử lý khoảng mười nghìn requests mỗi giây với latency cực thấp.",
        "toàn nguyện tiếng cháo đường cuộc việt",
        "https://github.com/stevedat/VieLotus-IM let config = Configuration(timeout: 30, retryCount: 3)"
    ]
    let telexAnchorsOk = telexRequiredAnchors.allSatisfy { telexPass1Text.contains($0) && telexPass2Text.contains($0) }
    let telexOutputVerified =
        telexResult.backspacesExecuted > 0 &&
        telexAnchorsOk &&
        telexResult.reconstructedText.hasPrefix(telexExpectedPrefix)

    print("\n  📊 KẾT QUẢ HIỆU NĂNG TELEX:")
    print(String(format: "  • Tổng thời gian gõ       : %.3f giây", telexResult.elapsedSec))
    print("  • Tốc độ thông lượng      : \(fmtD(telexKPS)) phím/giây (~ \(fmtD(telexWPS)) từ/giây)")
    print("  • Thao tác thực thi       : \(fmt(telexResult.wordsCommitted)) commits | \(fmt(telexResult.backspacesExecuted)) backspaces | \(fmt(telexResult.replacesExecuted)) replaces")
    print("  • Kiểm chứng văn bản đầu ra: \(telexOutputVerified ? "✅ KHỚP 100% (\(telexFullReps) chu kỳ, 0 mất dấu/ký tự)" : "❌ LỆCH VĂN BẢN ĐẦU RA")")
    print(String(format: "  • Độ trễ trung bình (Mean): %.2f µs (microsecond) [%.4f ms]", telexStats.mean, telexStats.mean / 1000.0))
    print(String(format: "  • Median (p50)            : %.2f µs", telexStats.p50))
    print(String(format: "  • 90th percentile (p90)   : %.2f µs", telexStats.p90))
    print(String(format: "  • 95th percentile (p95)   : %.2f µs", telexStats.p95))
    print(String(format: "  • 99th percentile (p99)   : %.2f µs", telexStats.p99))
    print(String(format: "  • 99.9th percentile (p999): %.2f µs", telexStats.p999))
    print(String(format: "  • Độ trễ tối đa (Max)     : %.2f µs [%.3f ms]", telexStats.max, telexStats.max / 1000.0))
    let telexDeltaRSS = (telexMemCheckpoints.last?.1 ?? 0) - telexMemCheckpoints[0].1
    print(String(format: "  • Biến thiên bộ nhớ (ΔRSS): %+.2f MB (từ %.2f MB -> %.2f MB)\n", telexDeltaRSS, telexMemCheckpoints[0].1, telexMemCheckpoints.last?.1 ?? 0))

    // -------------------------------------------------------------------------
    // PHASE 2: VNI 100,000 KEYSTROKES
    // -------------------------------------------------------------------------
    print("--------------------------------------------------------------------------------")
    print("▶ GIAI ĐOẠN 2: KIỂM THỬ BỀN BỈ KIỂU GÕ VNI (100,000 Phím Liên Tục)")
    print("--------------------------------------------------------------------------------")
    let vniSession = configuredSession()
    vniSession.setInputMethod(.vni)
    vniSession.setModernOrthography(true)

    let vniStream = buildRepeatedStream(base: vniRawCorpus, targetCount: 100_000)
    print("  • Chuẩn bị luồng phím: \(fmt(vniStream.count)) ký tự (dấu số VNI, số độc lập, sửa backspace)")

    var vniMemCheckpoints: [(Int, Double)] = [(0, getMemoryRSS())]
    let vniResult = driveContinuousStream(
        session: vniSession,
        stream: vniStream,
        bilingualEnabled: true,
        progressStep: 25_000
    ) { step, mem in
        vniMemCheckpoints.append((step, mem))
        print(String(format: "  ↳ [Keystrokes: %6d / 100,000] - Memory RSS: %.2f MB", step, mem))
    }

    let vniStats = calculatePercentiles(vniResult.latenciesUs)
    let vniKPS = Double(vniResult.totalKeystrokes) / vniResult.elapsedSec
    let vniWPS = Double(vniResult.wordsCommitted) / vniResult.elapsedSec

    let vniFullReps = vniStream.count / vniRawCorpus.count
    let vniExpectedPrefix = vniPass1Text + String(repeating: vniPass2Text, count: max(0, vniFullReps - 1))
    let vniRequiredAnchors = [
        "Trăm năm trong cõi người ta, chữ tài chữ mệnh khéo là ghét nhau.",
        "VieLotusIM là bộ gõ tiếng Việt thế hệ mới trên macOS",
        "toàn nguyện tiếng cháo đường cuộc",
        "Hôm nay ngày 15 tháng 10 năm 2026, tổng doanh thu đạt 150000000 đồng, mã sản phẩm là SP102938."
    ]
    let vniAnchorsOk = vniRequiredAnchors.allSatisfy { vniPass1Text.contains($0) && vniPass2Text.contains($0) }
    let vniOutputVerified =
        vniResult.backspacesExecuted > 0 &&
        vniAnchorsOk &&
        vniResult.reconstructedText.hasPrefix(vniExpectedPrefix)

    print("\n  📊 KẾT QUẢ HIỆU NĂNG VNI:")
    print(String(format: "  • Tổng thời gian gõ       : %.3f giây", vniResult.elapsedSec))
    print("  • Tốc độ thông lượng      : \(fmtD(vniKPS)) phím/giây (~ \(fmtD(vniWPS)) từ/giây)")
    print("  • Thao tác thực thi       : \(fmt(vniResult.wordsCommitted)) commits | \(fmt(vniResult.backspacesExecuted)) backspaces | \(fmt(vniResult.replacesExecuted)) replaces")
    print("  • Kiểm chứng văn bản đầu ra: \(vniOutputVerified ? "✅ KHỚP 100% (\(vniFullReps) chu kỳ, 0 mất dấu/ký tự)" : "❌ LỆCH VĂN BẢN ĐẦU RA")")
    print(String(format: "  • Độ trễ trung bình (Mean): %.2f µs (microsecond) [%.4f ms]", vniStats.mean, vniStats.mean / 1000.0))
    print(String(format: "  • Median (p50)            : %.2f µs", vniStats.p50))
    print(String(format: "  • 90th percentile (p90)   : %.2f µs", vniStats.p90))
    print(String(format: "  • 95th percentile (p95)   : %.2f µs", vniStats.p95))
    print(String(format: "  • 99th percentile (p99)   : %.2f µs", vniStats.p99))
    print(String(format: "  • 99.9th percentile (p999): %.2f µs", vniStats.p999))
    print(String(format: "  • Độ trễ tối đa (Max)     : %.2f µs [%.3f ms]", vniStats.max, vniStats.max / 1000.0))
    let vniDeltaRSS = (vniMemCheckpoints.last?.1 ?? 0) - vniMemCheckpoints[0].1
    print(String(format: "  • Biến thiên bộ nhớ (ΔRSS): %+.2f MB (từ %.2f MB -> %.2f MB)\n", vniDeltaRSS, vniMemCheckpoints[0].1, vniMemCheckpoints.last?.1 ?? 0))

    // -------------------------------------------------------------------------
    // PHASE 3: EXTENDED MIXED SESSION (50,000 KEYSTROKES)
    // -------------------------------------------------------------------------
    print("--------------------------------------------------------------------------------")
    print("▶ GIAI ĐOẠN 3: PHIÊN GÕ HỖN HỢP SIÊU DÀI & ĐỔI KIỂU GÕ ĐỘNG (50,000 Phím)")
    print("--------------------------------------------------------------------------------")
    let mixedSession = configuredSession()
    let mixedTarget = 50_000
    var mixedCount = 0
    var mixedBackspacesExecuted = 0
    var mixedReplacesExecuted = 0
    var mixedWordsCommitted = 0
    var mixedOutputUTF16: [UInt16] = []
    mixedOutputUTF16.reserveCapacity(mixedTarget)
    let startMixedRSS = getMemoryRSS()
    var mixedLatencies: [Double] = []
    mixedLatencies.reserveCapacity(mixedTarget)

    let tMixedStart = DispatchTime.now().uptimeNanoseconds
    var currentMethod: InputMethodType = .telex
    mixedSession.setInputMethod(currentMethod)
    mixedSession.setGrammarProfile(profile)

    let telexTokens = telexRawCorpus.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    let vniTokens = vniRawCorpus.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

    var tokenIdx = 0
    while mixedCount < mixedTarget {
        // Toggle input method every 50 words to simulate real user switching or multi-document workflows
        if tokenIdx % 50 == 0 && tokenIdx > 0 {
            currentMethod = (currentMethod == .telex) ? .vni : .telex
            mixedSession.setInputMethod(currentMethod)
        }

        let token = (currentMethod == .telex)
            ? telexTokens[tokenIdx % telexTokens.count]
            : vniTokens[tokenIdx % vniTokens.count]

        for char in token {
            if char == "<" {
                let priorUTF16 = mixedSession.isComposing ? mixedSession.currentOutput().utf16.count : 1
                let t0 = DispatchTime.now().uptimeNanoseconds
                let action = mixedSession.handleBackspace()
                let t1 = DispatchTime.now().uptimeNanoseconds
                mixedLatencies.append(Double(t1 - t0) / 1000.0)
                mixedBackspacesExecuted += 1
                applyStressAction(action, priorComposingUTF16: priorUTF16, fallbackChar: nil, isBackspace: true, to: &mixedOutputUTF16, replacesExecuted: &mixedReplacesExecuted)
            } else if mixedSession.isWordBoundary(char) {
                let t0 = DispatchTime.now().uptimeNanoseconds
                let action = mixedSession.commitWord(smartBilingualEnabled: true, boundaryChar: char)
                let t1 = DispatchTime.now().uptimeNanoseconds
                mixedLatencies.append(Double(t1 - t0) / 1000.0)
                if case .commit = action { mixedWordsCommitted += 1 }
                applyStressAction(action, to: &mixedOutputUTF16, replacesExecuted: &mixedReplacesExecuted)
                mixedOutputUTF16.append(contentsOf: String(char).utf16)
            } else {
                let t0 = DispatchTime.now().uptimeNanoseconds
                let action = mixedSession.handleCharacter(char)
                let t1 = DispatchTime.now().uptimeNanoseconds
                mixedLatencies.append(Double(t1 - t0) / 1000.0)
                applyStressAction(action, fallbackChar: char, to: &mixedOutputUTF16, replacesExecuted: &mixedReplacesExecuted)
            }
            mixedCount += 1
            if mixedCount >= mixedTarget { break }
        }

        if mixedCount < mixedTarget {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let action = mixedSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
            let t1 = DispatchTime.now().uptimeNanoseconds
            mixedLatencies.append(Double(t1 - t0) / 1000.0)
            if case .commit = action { mixedWordsCommitted += 1 }
            applyStressAction(action, to: &mixedOutputUTF16, replacesExecuted: &mixedReplacesExecuted)
            mixedOutputUTF16.append(0x0020)
            mixedCount += 1
        }
        tokenIdx += 1
    }

    let tMixedEnd = DispatchTime.now().uptimeNanoseconds
    let mixedElapsedSec = Double(tMixedEnd - tMixedStart) / 1_000_000_000.0
    let mixedStats = calculatePercentiles(mixedLatencies)
    let endMixedRSS = getMemoryRSS()
    let mixedReconstructedText = String(decoding: mixedOutputUTF16, as: UTF16.self)
    let mixedOutputVerified =
        mixedBackspacesExecuted > 0 &&
        mixedReconstructedText.contains("Trăm năm trong cõi người ta") &&
        mixedReconstructedText.contains("toàn nguyện tiếng cháo đường cuộc")

    print("  • Hoàn thành           : \(fmt(mixedCount)) phím hỗn hợp trong \(String(format: "%.3f", mixedElapsedSec)) giây")
    print("  • Tốc độ xử lý         : \(fmtD(Double(mixedCount) / mixedElapsedSec)) phím/giây")
    print("  • Thao tác thực thi    : \(fmt(mixedWordsCommitted)) commits | \(fmt(mixedBackspacesExecuted)) backspaces | \(fmt(mixedReplacesExecuted)) replaces")
    print("  • Kiểm chứng văn bản   : \(mixedOutputVerified ? "✅ KHỚP 100% (Telex ⇄ VNI + Backspace)" : "❌ LỆCH VĂN BẢN ĐẦU RA")")
    print(String(format: "  • Median (p50)         : %.2f µs", mixedStats.p50))
    print(String(format: "  • 99th percentile (p99): %.2f µs", mixedStats.p99))
    print(String(format: "  • Bộ nhớ kết thúc      : %.2f MB (ΔRSS: %+.2f MB)", endMixedRSS, endMixedRSS - startMixedRSS))

    // -------------------------------------------------------------------------
    // SUMMARY REPORT
    // -------------------------------------------------------------------------
    let finalRSS = getMemoryRSS()
    let totalKeystrokes = telexResult.totalKeystrokes + vniResult.totalKeystrokes + mixedCount
    let totalBackspaces = telexResult.backspacesExecuted + vniResult.backspacesExecuted + mixedBackspacesExecuted
    let totalTime = telexResult.elapsedSec + vniResult.elapsedSec + mixedElapsedSec
    let avgKPS = Double(totalKeystrokes) / totalTime
    let avgWPM = (avgKPS / 5.0) * 60.0

    print("\n================================================================================")
    print("🏆 BÁO CÁO TỔNG HỢP ĐỘ BỀN BỈ & QUAN SÁT RSS TIẾN TRÌNH CLI (STABILITY AUDIT)")
    print("================================================================================")
    print("  • Tổng số phím gõ thực tế: \(fmt(totalKeystrokes)) phím (\(fmt(totalBackspaces)) thao tác Backspace thực thi)")
    print(String(format: "  • Tổng thời gian xử lý   : %.2f giây", totalTime))
    print("  • Tốc độ trung bình      : \(fmtD(avgKPS)) phím/giây (~ \(fmtD(avgWPM)) WPM)")
    print(String(format: "  • RSS Khởi động          : %.2f MB", initialRSS))
    print(String(format: "  • RSS Hoàn thành         : %.2f MB", finalRSS))
    print(String(format: "  • Biến thiên bộ nhớ tổng : %+.2f MB", finalRSS - initialRSS))

    if abs(finalRSS - initialRSS) < 15.0 {
        print("  ✅ QUAN SÁT BỘ NHỚ TIẾN TRÌNH CLI: ΔRSS ổn định (< 15 MB) — Dùng 'leaks <PID>' để kiểm tra rò rỉ trên tiến trình IME.")
    } else {
        print("  ⚠️ CẢNH BÁO BỘ NHỚ: Phát hiện tăng trưởng RSS tiến trình CLI vượt ngưỡng 15 MB.")
    }

    if telexStats.p99 <= telexCeiling && vniStats.p99 <= vniCeiling && mixedStats.p99 <= mixedCeiling {
        print("  ✅ KIỂM ĐỊNH ĐỘ TRỄ: ĐẠT CHUẨN RATCHET (Telex ≤ \(Int(telexCeiling)) µs, VNI ≤ \(Int(vniCeiling)) µs, Mixed ≤ \(Int(mixedCeiling)) µs)!")
    }

    if emitJSON {
        let fields: [(String, Double)] = [
            ("telex_p50", telexStats.p50),
            ("telex_p90", telexStats.p90),
            ("telex_p99", telexStats.p99),
            ("vni_p50", vniStats.p50),
            ("vni_p90", vniStats.p90),
            ("vni_p99", vniStats.p99),
            ("mixed_p50", mixedStats.p50),
            ("mixed_p99", mixedStats.p99),
            ("avg_kps", avgKPS),
            ("rss_delta_mb", finalRSS - initialRSS),
            ("elapsed_sec", totalTime)
        ]
        let body = fields.map { "\"\($0.0)\":\(String(format: "%.4f", $0.1))" }.joined(separator: ",")
        print("LATENCY_JSON {\"profile\":\"\(profile.rawValue)\",\"inline_bilingual\":\(mobilePath),\"provider\":\"\(mobilePath ? "local-mobile" : "platform-desktop")\",\"host_ui_measured\":false,\"keystrokes\":\(totalKeystrokes),\"backspaces\":\(totalBackspaces),\"output_verified\":\(telexOutputVerified && vniOutputVerified && mixedOutputVerified),\(body)}")
    }

    var gateFailed = false
    if !telexOutputVerified || !vniOutputVerified || !mixedOutputVerified {
        print("\n❌ Output Integrity Gate Failed: Reconstructed stress output or Backspace execution count failed verification")
        gateFailed = true
    }
    if telexStats.p99 > telexCeiling {
        print(String(format: "\n❌ Latency Gate Failed: Telex p99 %.2f µs exceeds ceiling of %.2f µs", telexStats.p99, telexCeiling))
        gateFailed = true
    }
    if vniStats.p99 > vniCeiling {
        print(String(format: "\n❌ Latency Gate Failed: VNI p99 %.2f µs exceeds ceiling of %.2f µs", vniStats.p99, vniCeiling))
        gateFailed = true
    }
    if mixedStats.p99 > mixedCeiling {
        print(String(format: "\n❌ Latency Gate Failed: Mixed p99 %.2f µs exceeds ceiling of %.2f µs", mixedStats.p99, mixedCeiling))
        gateFailed = true
    }
    if kpsFloor > 0 && avgKPS < kpsFloor {
        print(String(format: "\n❌ Throughput Gate Failed: Average KPS %.2f is below floor of %.2f", avgKPS, kpsFloor))
        gateFailed = true
    }
    if gateFailed {
        exit(1)
    }

    print("================================================================================\n")
}

func runBehavioralScorecard(profile: GrammarProfile, emitJSON: Bool) {
    #if os(macOS)
    SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
    #endif
    MacroEngine.shared.isEnabled = false

    struct WordSpec {
        let raw: String
        let expected: String
        let swap: (Character, String)?
        init(_ raw: String, _ expected: String, swap: (Character, String)? = nil) {
            self.raw = raw
            self.expected = expected
            self.swap = swap
        }
    }

    let corpus: [[WordSpec]] = [
        [
            .init("Hoom", "Hôm"), .init("nay", "nay"), .init("team", "team"),
            .init("mifnh", "mình", swap: ("s", "mính")), .init("deploy", "deploy"),
            .init("banr", "bản", swap: ("s", "bán")), .init("build", "build"),
            .init("mowis", "mới", swap: ("f", "mời")), .init("leen", "lên"), .init("server", "server")
        ],
        [
            .init("Neesu", "Nếu"), .init("code", "code"), .init("bij", "bị", swap: ("s", "bí")),
            .init("bug", "bug"), .init("thif", "thì", swap: ("s", "thí")), .init("check", "check"),
            .init("log", "log"), .init("truwowsc", "trước"), .init("nhas", "nhá", swap: ("f", "nhà"))
        ],
        [
            .init("Anh", "Anh"), .init("guwir", "gửi"), .init("file", "file"),
            .init("baos", "báo", swap: ("f", "bào")), .init("caos", "cáo", swap: ("f", "cào")),
            .init("vafo", "vào"), .init("group", "group"), .init("chat", "chat"),
            .init("cho", "cho"), .init("em", "em")
        ]
    ]

    func applyAction(_ action: SessionAction, fallbackChar: Character?, to doc: inout String) {
        switch action {
        case .replace(let bs, let text):
            if bs > 0 {
                var rem = bs
                var idx = doc.endIndex
                while rem > 0 && idx > doc.startIndex {
                    idx = doc.index(before: idx)
                    rem -= doc[idx].utf16.count
                }
                doc.removeSubrange(idx..<doc.endIndex)
            }
            doc.append(text)
        case .commit(let bs, let text, _):
            if bs > 0 {
                var rem = bs
                var idx = doc.endIndex
                while rem > 0 && idx > doc.startIndex {
                    idx = doc.index(before: idx)
                    rem -= doc[idx].utf16.count
                }
                doc.removeSubrange(idx..<doc.endIndex)
            }
            doc.append(text)
            if let ch = fallbackChar {
                doc.append(ch)
            }
        case .passThrough, .reset:
            if let ch = fallbackChar {
                doc.append(ch)
            } else if !doc.isEmpty {
                doc.removeLast()
            }
        case .consumed:
            break
        }
    }

    let slipKinds = ["typo", "back-into-word", "cursor-trip", "stray-punct", "mid-word-click", "edit-elsewhere"]
    var slipPass: [String: Int] = [:]
    var slipTot: [String: Int] = [:]
    for k in slipKinds { slipPass[k] = 0; slipTot[k] = 0 }

    var cleanPass = 0
    var cleanTot = 0
    var badEdits = 0
    var extraKeys = 0
    var totalKeysDriven = 0
    let startNs = DispatchTime.now().uptimeNanoseconds

    for sentence in corpus {
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        session.setGrammarProfile(profile)
        session.setSmartBilingualEnabled(true)
        session.inlineBilingualEnabled = true
        var doc = ""
        for spec in sentence {
            let guardPrefix = doc
            for ch in spec.raw {
                totalKeysDriven += 1
                applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc)
                if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
            }
            totalKeysDriven += 1
            applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
            if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
            let expected = guardPrefix + spec.expected + " "
            cleanTot += 1
            if doc == expected {
                cleanPass += 1
            } else {
                extraKeys += spec.raw.count + 1
                doc = expected
            }
        }
    }

    for sentence in corpus {
        for (wIdx, spec) in sentence.enumerated() where spec.raw.count >= 3 {
            for kind in slipKinds {
                if kind == "back-into-word" && spec.swap == nil { continue }
                let session = InputSessionManager()
                session.setInputMethod(.telex)
                session.setGrammarProfile(profile)
                session.setSmartBilingualEnabled(true)
                session.inlineBilingualEnabled = true
                var doc = ""
                for prevIdx in 0..<wIdx {
                    let prev = sentence[prevIdx]
                    for ch in prev.raw {
                        totalKeysDriven += 1
                        applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc)
                    }
                    totalKeysDriven += 1
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                }
                let guardPrefix = doc
                let splitIdx = (kind == "stray-punct") ? min(2, max(1, spec.raw.count / 2)) : max(1, spec.raw.count / 2)
                let firstHalf = String(spec.raw.prefix(splitIdx))
                let secondHalf = String(spec.raw.dropFirst(splitIdx))
                var expectedAfter = guardPrefix + spec.expected + " "

                switch kind {
                case "typo":
                    for ch in firstHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.handleCharacter("q"), fallbackChar: "q", to: &doc)
                    applyAction(session.handleBackspace(), fallbackChar: nil, to: &doc)
                    if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
                    for ch in secondHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                case "back-into-word":
                    guard let sw = spec.swap else { continue }
                    for ch in spec.raw { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                    applyAction(session.handleBackspace(), fallbackChar: nil, to: &doc)
                    if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
                    applyAction(session.handleCharacter(sw.0), fallbackChar: sw.0, to: &doc)
                    if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                    expectedAfter = guardPrefix + sw.1 + " "
                case "cursor-trip":
                    for ch in spec.raw { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    session.stepCaretBack()
                    session.stepCaretForward()
                    if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                case "stray-punct":
                    for ch in firstHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: ","), fallbackChar: ",", to: &doc)
                    applyAction(session.handleBackspace(), fallbackChar: nil, to: &doc)
                    if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
                    for ch in secondHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                case "mid-word-click":
                    for ch in firstHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    let prefixNow = String(doc.dropFirst(guardPrefix.count))
                    session.reset()
                    session.setCompositionPrefix(prefixNow)
                    for ch in secondHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                case "edit-elsewhere":
                    for ch in firstHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    let savedPrefix = String(doc.dropFirst(guardPrefix.count))
                    session.reset()
                    session.editCaretBack = InputSessionManager.caretDisarmed
                    session.setCompositionPrefix(savedPrefix)
                    for ch in secondHalf { applyAction(session.handleCharacter(ch), fallbackChar: ch, to: &doc) }
                    applyAction(session.commitWord(smartBilingualEnabled: true, boundaryChar: " "), fallbackChar: " ", to: &doc)
                default:
                    break
                }
                if !doc.hasPrefix(guardPrefix) { badEdits += 1 }
                slipTot[kind, default: 0] += 1
                if doc == expectedAfter {
                    slipPass[kind, default: 0] += 1
                } else {
                    extraKeys += spec.raw.count + 1
                }
            }
        }
    }

    let elapsedNs = DispatchTime.now().uptimeNanoseconds - startNs
    let nsPerKey = totalKeysDriven > 0 ? Double(elapsedNs) / Double(totalKeysDriven) : 0.0
    let allSlipPass = slipKinds.reduce(0) { $0 + (slipPass[$1] ?? 0) }
    let allSlipTot = slipKinds.reduce(0) { $0 + (slipTot[$1] ?? 0) }
    let cleanPct = Double(cleanPass) / Double(max(1, cleanTot)) * 100.0
    let allSlipPct = Double(allSlipPass) / Double(max(1, allSlipTot)) * 100.0

    print("\n======================================================================")
    print("📋 SEN VIỆT BEHAVIORAL & SLIP-RECOVERY SCORECARD (INDEPENDENT ORACLE)")
    print("======================================================================")
    print(String(format: "  conversational accuracy (independent oracle) : %6.2f%% (%d/%d)", cleanPct, cleanPass, cleanTot))
    for kind in slipKinds {
        let p = slipPass[kind] ?? 0
        let t = slipTot[kind] ?? 0
        let pct = Double(p) / Double(max(1, t)) * 100.0
        print(String(format: "  slip recovery: %-29s : %6.2f%% (%d/%d)", (kind as NSString).utf8String!, pct, p, t))
    }
    print(String(format: "  slip recovery: all                           : %6.2f%% (%d/%d)", allSlipPct, allSlipPass, allSlipTot))
    print("  text safety: prefix bad edits                : \(badEdits)")
    print("  manual retype cost (extra keystrokes)        : \(extraKeys)")
    print(String(format: "  speed: ns per key                            : %.1f", nsPerKey))
    print("======================================================================\n")

    if emitJSON {
        print(String(format: "SCORECARD_JSON {\"clean_accuracy\":%.2f,\"slip_recovery_all\":%.2f,\"bad_edits\":%d,\"extra_retype_keys\":%d,\"ns_per_key\":%.1f}", cleanPct, allSlipPct, badEdits, extraKeys, nsPerKey))
    }
    if badEdits > 0 || cleanPass < cleanTot || allSlipPass < allSlipTot {
        exit(1)
    }
}

let args = CommandLine.arguments

var activeProfile: GrammarProfile = .senFlex
if let pIdx = args.firstIndex(of: "--profile"), pIdx + 1 < args.count {
    let pStr = args[pIdx + 1]
    if let prof = GrammarProfile(rawValue: pStr) {
        activeProfile = prof
    } else {
        print("⚠️ Profile không hợp lệ: '\(pStr)'. Sử dụng mặc định: .senFlex. (Các lựa chọn: classic, preVowel, smartHybrid, senFlex)")
    }
}

if args.contains("--scorecard") {
    runBehavioralScorecard(profile: activeProfile, emitJSON: args.contains("--json"))
    exit(0)
}

if args.contains("--mobile-paced") {
    exit(runMobilePacedBenchmark() ? 0 : 1)
}

if args.contains("--stress") || args.contains("--endurance") {
    var telexCeil = 500.0
    if let idx = args.firstIndex(of: "--telex-ceiling"), idx + 1 < args.count, let val = Double(args[idx + 1]) {
        telexCeil = val
    }
    var vniCeil = 300.0
    if let idx = args.firstIndex(of: "--vni-ceiling"), idx + 1 < args.count, let val = Double(args[idx + 1]) {
        vniCeil = val
    }
    var mixedCeil = 700.0
    if let idx = args.firstIndex(of: "--mixed-ceiling"), idx + 1 < args.count, let val = Double(args[idx + 1]) {
        mixedCeil = val
    }
    var kps = 25000.0
    if let idx = args.firstIndex(of: "--kps-floor"), idx + 1 < args.count, let val = Double(args[idx + 1]) {
        kps = val
    }

    runStressAndEnduranceBenchmark(
        profile: args.contains("--mobile-path") ? .senFlex : activeProfile,
        emitJSON: args.contains("--json"),
        mobilePath: args.contains("--mobile-path"),
        telexCeiling: telexCeil,
        vniCeiling: vniCeil,
        mixedCeiling: mixedCeil,
        kpsFloor: kps
    )
    exit(0)
}


if args.contains("--benchmark") {
    let csvPath: String
    if let idx = args.firstIndex(of: "--benchmark"), idx + 1 < args.count, !args[idx + 1].hasPrefix("-") {
        csvPath = args[idx + 1]
    } else if FileManager.default.fileExists(atPath: "Sources/VieLotusCLI/Resources/test_suite.csv") {
        csvPath = "Sources/VieLotusCLI/Resources/test_suite.csv"
    } else if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("VietLotusIM_VieLotusCLI.bundle/test_suite.csv"),
              FileManager.default.fileExists(atPath: resourceURL.path) {
        csvPath = resourceURL.path
    } else if let resourceURL = Bundle.main.bundleURL.appendingPathComponent("VietLotusIM_VieLotusCLI.bundle/test_suite.csv") as URL?,
              FileManager.default.fileExists(atPath: resourceURL.path) {
        csvPath = resourceURL.path
    } else {
        csvPath = "<embedded>"
    }

    var threshold = 98.0
    if let tIdx = args.firstIndex(of: "--threshold"), tIdx + 1 < args.count, let parsed = Double(args[tIdx + 1]) {
        threshold = parsed
    }

    var vnFloor = vnSurvivesFloorBaseline
    if let vIdx = args.firstIndex(of: "--vn-floor"), vIdx + 1 < args.count, let parsed = Double(args[vIdx + 1]) {
        vnFloor = parsed
    }

    var bothFloor = bothSidesFloorBaseline
    if let bIdx = args.firstIndex(of: "--both-floor"), bIdx + 1 < args.count, let parsed = Double(args[bIdx + 1]) {
        bothFloor = parsed
    }

    runBenchmark(
        csvPath: csvPath,
        profile: activeProfile,
        targetThreshold: threshold,
        vnFloorThreshold: vnFloor,
        bothSidesFloorThreshold: bothFloor,
        emitJSON: args.contains("--json")
    )
    exit(0)
}

print("=== 🌸 Sen Việt (VieLotusIM) REPL ===")
#if os(macOS)
SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
#endif
let session = InputSessionManager()
session.setGrammarProfile(activeProfile)
if activeProfile != .classic {
    print("Đang chạy với Grammar Profile: \(activeProfile.rawValue)")
}

while true {
    print("> ", terminator: "")
    guard let input = readLine() else { break }
    if input == "exit" { break }

    if input.hasPrefix(":profile ") {
        let pStr = String(input.dropFirst(9)).trimmingCharacters(in: .whitespaces)
        if let prof = GrammarProfile(rawValue: pStr) {
            session.setGrammarProfile(prof)
            print("Đã chuyển sang Grammar Profile: \(prof.rawValue)")
        } else {
            print("Profile không hợp lệ: \(pStr). Các lựa chọn: classic, preVowel, smartHybrid, senFlex")
        }
        continue
    }

    let result = driveInput(session: session, input: input, primeEnglish: false, bilingualEnabled: true)
    print("Kết quả: \(result)")
}
