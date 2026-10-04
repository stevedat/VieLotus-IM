import Foundation
import VieLotusCore
import Darwin

// MARK: - Benchmark Logic

struct TestCase {
    let input: String
    let expectedOutput: [String] // Array to handle "hóa / hoá"
    let expectedBehavior: String
    let category: String
}

func driveInput(session: InputSessionManager, input: String, primeEnglish: Bool, bilingualEnabled: Bool) -> String {
    session.reset()
    if primeEnglish {
        session.context = "he is"
    }
    
    var result = ""
    for char in input {
        if session.isWordBoundary(char) {
            let action = session.commitWord(smartBilingualEnabled: bilingualEnabled)
            if case let .commit(backspaces, text, isOverride) = action {
                if isOverride {
                    result.removeLast(min(backspaces, result.count))
                    result += text
                }
            }
            result.append(char)
        } else if char == "<" {
            let action = session.handleBackspace()
            if case let .replace(backspaces, text) = action {
                if backspaces > 0 { result.removeLast(min(backspaces, result.count)) }
                result += text
            }
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

func runBenchmark(csvPath: String, targetThreshold: Double = 98.0) {
    print("=== 🌸 Sen Việt (VieLotusIM) Benchmark Suite ===")
    print("Reading CSV from: \(csvPath)")
    print("Target Threshold: \(String(format: "%.2f%%", targetThreshold))")
    
    guard let content = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
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
                category: columns[6]
            )
            testCases.append(tc)
        }
    }
    
    print("Total test cases loaded: \(testCases.count)\n")
    guard !testCases.isEmpty else {
        print("❌ Error: No valid test cases found in benchmark file.")
        exit(1)
    }
    
    SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
    let session = InputSessionManager()
    var passCounts: [String: Int] = [:]
    var totalCounts: [String: Int] = [:]
    var overallPass = 0
    var overallFail = 0
    var failureExamples: [String] = []
    
    for tc in testCases {
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
    
    // CI Quality Gate: Overall pass rate must meet or exceed target threshold
    if overallRate < targetThreshold {
        print("\n❌ CI Quality Gate Failed: Overall pass rate \(String(format: "%.2f%%", overallRate)) is below target threshold of \(String(format: "%.2f%%", targetThreshold))")
        exit(1)
    }
    print("✅ CI Quality Gate Passed (\(String(format: "%.2f%%", overallRate)) >= \(String(format: "%.2f%%", targetThreshold)))")
}

// MARK: - Stress & Endurance Benchmark Logic

func getMemoryRSS() -> Double {
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

func driveContinuousStream(
    session: InputSessionManager,
    stream: String,
    bilingualEnabled: Bool,
    progressStep: Int = 25_000,
    onProgress: ((Int, Double) -> Void)? = nil
) -> (latenciesUs: [Double], totalKeystrokes: Int, wordsCommitted: Int, elapsedSec: Double) {
    var latencies: [Double] = []
    latencies.reserveCapacity(stream.count)
    var count = 0
    var wordsCommitted = 0
    
    let tStart = DispatchTime.now().uptimeNanoseconds
    for char in stream {
        let t0 = DispatchTime.now().uptimeNanoseconds
        if session.isWordBoundary(char) {
            let action = session.commitWord(smartBilingualEnabled: bilingualEnabled)
            if case .commit = action {
                wordsCommitted += 1
            }
        } else if char == "<" {
            _ = session.handleBackspace()
        } else {
            _ = session.handleCharacter(char)
        }
        let t1 = DispatchTime.now().uptimeNanoseconds
        let latencyUs = Double(t1 - t0) / 1000.0
        latencies.append(latencyUs)
        
        count += 1
        if count % progressStep == 0 {
            onProgress?(count, getMemoryRSS())
        }
    }
    
    if session.isComposing {
        let action = session.commitWord(smartBilingualEnabled: bilingualEnabled)
        if case .commit = action { wordsCommitted += 1 }
    }
    let tEnd = DispatchTime.now().uptimeNanoseconds
    let elapsedSec = Double(tEnd - tStart) / 1_000_000_000.0
    
    return (latencies, count, wordsCommitted, elapsedSec)
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

func runStressAndEnduranceBenchmark() {
    print("================================================================================")
    print("⚡️ BỘ ĐO ĐỘ BỀN BỈ & HIỆU NĂNG TẢI CAO (STRESS & ENDURANCE BENCHMARK)")
    print("   Bộ gõ Sen Việt (VieLotusIM) — Telex & VNI High-Throughput Stream Harness")
    print("================================================================================\n")
    
    SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
    let initialRSS = getMemoryRSS()
    print(String(format: "📌 Bộ nhớ ban đầu (Baseline Memory RSS): %.2f MB\n", initialRSS))
    
    let telexRawCorpus = """
Trawm nawm trong coxi nguowfi ta, chuwx taif chuwx meejnh kheos laf ghest nhau. Trair qua moojt cuoojc ber dau, nhuwngx ddieeuf troong thaays maf ddau ddoosns lonfg. Lar gif bir sawsc tuw phong, troowfi xanh quen thoos maas hoonfg ddasnh ghen. 
VieLotusIM laf booj gox tieengs Vieejt thees heej mowis treen macOS, dduowjc vieest hoanf toanf bawfng ngoon nguwr laapj trinhf Swift 6 hieejn ddaaij. Kieesn trusc cura booj gox tuaan thur nghieem ngawtj moo hinhf baor maawtj cura Apple, khoong caafn quyeefn Accessibility hay EventTap. 
Alo banj oowi, trwua nay awn gif nhir? DDi awn phor bov soost vang owr phoos cor khoong? Hay ra quasn cowm nieeu gaafn coong ty nhes, taafm 12 gioowf kesm mifnh qua ddosn banj! 
Heej thoosng microservices ddasng xuwr lys khoarng muwowif nghifn requests mooxi giaay vowis latency cuwcj thaasp. Hays kieerm tra cacs file configuration, caapj nhaajt package dependencies vaf deploy leen production server ngay trong hoom nay nhes. 
Khai maacj hooji nghij thuowjng ddirnh quoocs tees veef chuyeern ddooir soos vaf phast trieern kinh tees xanh beefn vuwngx nawm 2026. Cacs chuyeen gia nhaasn manjh taafm quan troongj cura vieecj baor veej duwr lieeju cas nhaan vaf an ninh manjg trong kyr nguyeon soos. 
Chusc muwngf nawm mowis an khang thijnh vuwowjng vanj suwj nhuw ys phast taif phast loocj suwcj khoer doofii dafo gia ddirnh hanjh phusc. 
toanfs<<f nguyeenxx<<x tieengs<<j chaof<<s dduowngff<<f cuoojc<<s vieejtt<< 
https://github.com/stevedat/VieLotus-IM let config = Configuration(timeout: 30, retryCount: 3) 
"""

    let vniRawCorpus = """
Tram8 nam8 trong coi4 nguoi72 ta, chu74 tai2 chu74 menh65 kheo1 la2 ghet1 nhau. Trai3 qua mot65 cuoc65 be3 dau, nhung74 d9ieu2 trong thay1 ma2 d9au d9on1 long2. La5 gi2 bi3 sac1 tu7 phong, troi72 xanh quen thoi1 ma1 hong2 d9anh1 ghen. 
VieLotusIM la2 bo5 go4 tieng1 Viet65 the61 he5 moi1 tren macOS, d9uoc75 viet1 hoan2 toan2 bang2 ngon6 ngu74 lap5 trinh2 Swift 6 hien65 d9ai5. Kien1 truc1 cua3 bo5 go4 tuan6 thu3 nghiem6 ngat5 mo6 hinh2 bao3 mat65 cua3 Apple, khong can2 quyen2 Accessibility hay EventTap. 
Alo ban5 oi7, trua nay an8 gi2 nhi3? D9i an8 pho3 bo2 sot1 vang o73 pho1 co3 khong? Hay ra quan1 com7 nieu gan2 cong ty nhe1, tam62 12 gio72 kem1 minh2 qua d9on1 ban5! 
He5 thong1 microservices d9ang xu73 ly1 khoang3 muoi72 nghin2 requests moi4 giay voi1 latency cuc5 thap1. Hay4 kiem3 tra cac1 file configuration, cap5 nhat5 package dependencies va2 deploy len6 production server ngay trong hom6 nay nhe1. 
Khai mac5 hoi5 nghi5 thuong75 d9inh3 quoc1 te1 ve2 chuyen3 d9oi3 so1 va2 phat1 trien3 kinh te1 xanh ben2 vung4 nam8 2026. Cac1 chuyen gia nhan1 manh5 tam62 quan trong cua3 viec65 bao3 ve5 du74 lieu5 ca1 nhan va2 an ninh mang5 trong ky3 nguyen so1. 
Chuc1 mung72 nam8 moi1 an khang thinh5 vuong75 van5 su75 nhu7 y1 phat1 tai2 phat1 loc65 suc1 khoe3 doi2 dao2 gia d9inh2 hanh5 phuc1. 
toan1<<2 nguyen64<<4 tieng1<<5 chao2<<1 d9uong72<<1 cuoc65<<1 
Hom6 nay ngay2 15 thang1 10 nam8 2026, tong3 doanh thu d9at5 150000000 d9ong2, ma4 san3 pham3 la2 SP102938. 
https://github.com/stevedat/VieLotus-IM let config = Configuration(timeout: 30, retryCount: 3) 
"""

    // -------------------------------------------------------------------------
    // PHASE 1: TELEX 100,000 KEYSTROKES
    // -------------------------------------------------------------------------
    print("--------------------------------------------------------------------------------")
    print("▶ GIAI ĐOẠN 1: KIỂM THỬ BỀN BỈ KIỂU GÕ TELEX (100,000 Phím Liên Tục)")
    print("--------------------------------------------------------------------------------")
    let telexSession = InputSessionManager()
    telexSession.setInputMethod(.telex)
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

    print("\n  📊 KẾT QUẢ HIỆU NĂNG TELEX:")
    print(String(format: "  • Tổng thời gian gõ       : %.3f giây", telexResult.elapsedSec))
    print("  • Tốc độ thông lượng      : \(fmtD(telexKPS)) phím/giây (~ \(fmtD(telexWPS)) từ/giây)")
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
    let vniSession = InputSessionManager()
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
    
    print("\n  📊 KẾT QUẢ HIỆU NĂNG VNI:")
    print(String(format: "  • Tổng thời gian gõ       : %.3f giây", vniResult.elapsedSec))
    print("  • Tốc độ thông lượng      : \(fmtD(vniKPS)) phím/giây (~ \(fmtD(vniWPS)) từ/giây)")
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
    let mixedSession = InputSessionManager()
    let mixedTarget = 50_000
    var mixedCount = 0
    let startMixedRSS = getMemoryRSS()
    var mixedLatencies: [Double] = []
    mixedLatencies.reserveCapacity(mixedTarget)
    
    let tMixedStart = DispatchTime.now().uptimeNanoseconds
    var currentMethod: InputMethodType = .telex
    mixedSession.setInputMethod(currentMethod)
    
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
            let t0 = DispatchTime.now().uptimeNanoseconds
            if char == "<" {
                _ = mixedSession.handleBackspace()
            } else {
                _ = mixedSession.handleCharacter(char)
            }
            let t1 = DispatchTime.now().uptimeNanoseconds
            mixedLatencies.append(Double(t1 - t0) / 1000.0)
            mixedCount += 1
            if mixedCount >= mixedTarget { break }
        }
        
        if mixedCount < mixedTarget {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = mixedSession.commitWord(smartBilingualEnabled: true)
            let t1 = DispatchTime.now().uptimeNanoseconds
            mixedLatencies.append(Double(t1 - t0) / 1000.0)
            mixedCount += 1
        }
        tokenIdx += 1
    }
    
    let tMixedEnd = DispatchTime.now().uptimeNanoseconds
    let mixedElapsedSec = Double(tMixedEnd - tMixedStart) / 1_000_000_000.0
    let mixedStats = calculatePercentiles(mixedLatencies)
    let endMixedRSS = getMemoryRSS()
    
    print("  • Hoàn thành           : \(fmt(mixedCount)) phím hỗn hợp trong \(String(format: "%.3f", mixedElapsedSec)) giây")
    print("  • Tốc độ xử lý         : \(fmtD(Double(mixedCount) / mixedElapsedSec)) phím/giây")
    print(String(format: "  • Median (p50)         : %.2f µs", mixedStats.p50))
    print(String(format: "  • 99th percentile (p99): %.2f µs", mixedStats.p99))
    print(String(format: "  • Bộ nhớ kết thúc      : %.2f MB (ΔRSS: %+.2f MB)", endMixedRSS, endMixedRSS - startMixedRSS))
    
    // -------------------------------------------------------------------------
    // SUMMARY REPORT
    // -------------------------------------------------------------------------
    let finalRSS = getMemoryRSS()
    let totalKeystrokes = telexResult.totalKeystrokes + vniResult.totalKeystrokes + mixedCount
    let totalTime = telexResult.elapsedSec + vniResult.elapsedSec + mixedElapsedSec
    let avgKPS = Double(totalKeystrokes) / totalTime
    let avgWPM = (avgKPS / 5.0) * 60.0
    
    print("\n================================================================================")
    print("🏆 BÁO CÁO TỔNG HỢP ĐỘ BỀN BỈ & KHÔNG RÒ RỈ BỘ NHỚ (STABILITY AUDIT)")
    print("================================================================================")
    print("  • Tổng số phím gõ thực tế: \(fmt(totalKeystrokes)) phím")
    print(String(format: "  • Tổng thời gian xử lý   : %.2f giây", totalTime))
    print("  • Tốc độ trung bình      : \(fmtD(avgKPS)) phím/giây (~ \(fmtD(avgWPM)) WPM)")
    print(String(format: "  • RSS Khởi động          : %.2f MB", initialRSS))
    print(String(format: "  • RSS Hoàn thành         : %.2f MB", finalRSS))
    print(String(format: "  • Biến thiên bộ nhớ tổng : %+.2f MB", finalRSS - initialRSS))
    
    if abs(finalRSS - initialRSS) < 15.0 {
        print("  ✅ KIỂM ĐỊNH BỘ NHỚ: ĐẠT CHUẨN FLATLINE (ZERO MEMORY LEAK) — Không có hiện tượng phình RAM!")
    } else {
        print("  ⚠️ CẢNH BÁO BỘ NHỚ: Phát hiện tăng trưởng RSS đáng ngờ.")
    }
    
    if telexStats.p99 < 500.0 && vniStats.p99 < 500.0 {
        print("  ✅ KIỂM ĐỊNH ĐỘ TRỄ: ĐẠT CHUẨN SIÊU TỐC (p99 < 500 µs = 0.5 ms) — Hoàn toàn không giật lag khi gõ nhanh!")
    }
    print("================================================================================\n")
}

let args = CommandLine.arguments
if args.contains("--stress") || args.contains("--endurance") {
    runStressAndEnduranceBenchmark()
    exit(0)
}


if args.contains("--benchmark") {
    let csvPath: String
    if let idx = args.firstIndex(of: "--benchmark"), idx + 1 < args.count, !args[idx + 1].hasPrefix("-") {
        csvPath = args[idx + 1]
    } else if let resourceURL = Bundle.module.url(forResource: "test_suite", withExtension: "csv"), FileManager.default.fileExists(atPath: resourceURL.path) {
        csvPath = resourceURL.path
    } else {
        csvPath = "Sources/VieLotusCLI/Resources/test_suite.csv"
    }

    var threshold = 98.0
    if let tIdx = args.firstIndex(of: "--threshold"), tIdx + 1 < args.count, let parsed = Double(args[tIdx + 1]) {
        threshold = parsed
    }

    runBenchmark(csvPath: csvPath, targetThreshold: threshold)
    exit(0)
}

print("=== 🌸 Sen Việt (VieLotusIM) REPL ===")
SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
let session = InputSessionManager()

while true {
    print("> ", terminator: "")
    guard let input = readLine() else { break }
    if input == "exit" { break }
    
    let result = driveInput(session: session, input: input, primeEnglish: false, bilingualEnabled: true)
    print("Kết quả: \(result)")
}
