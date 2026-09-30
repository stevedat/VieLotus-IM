import Foundation
import VieLotusCore

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

let args = CommandLine.arguments
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
