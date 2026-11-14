import Foundation
import VieLotusCore

/// Paced adapter/session replay. The proxy is in-memory: NOT a UIKit/display test.
private final class PacedTextProxy: TextDocumentProxyProtocol {
    var text = ""
    var documentContextBeforeInput: String? { String(text.suffix(120)) }
    var documentContextAfterInput: String? { nil }
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

func runMobilePacedBenchmark() -> Bool {
    SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()
    let fixtures: [(raw: String, expected: String, abc: Bool)] = [
        ("tooi ddang apple meta cos just sunworld file.rar bans conf tieengs vieetj ",
         "tôi đang apple meta có just sunworld file.rar bán còn tiếng việt ", false),
        ("sin and cos pros and cons ", "sin and cos pros and cons ", false),
        ("cos<ns ", "cón ", false),
        ("file.rar < ", "file.rar ", false),
        ("coss ", "cos ", false),
        ("cos just sunworld ", "cos just sunworld ", true)
    ]
    var allPassed = true
    for kps in [10.0, 15.0, 20.0, 30.0] {
        var processing: [Double] = []
        var scheduling: [Double] = []
        var failures = 0
        for fixture in fixtures {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setGrammarProfile(.senFlex)
            adapter.session.setGenZMode(true)
            adapter.session.setModernOrthography(true)
            adapter.session.macroEnabled = false
            adapter.smartBilingual = true
            adapter.literalOverrideEnabled = fixture.abc
            let proxy = PacedTextProxy()
            let start = ProcessInfo.processInfo.systemUptime
            for (index, key) in fixture.raw.enumerated() {
                let deadline = start + Double(index) / kps
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
                let arrived = ProcessInfo.processInfo.systemUptime
                scheduling.append(max(0, arrived - deadline) * 1000)
                if key == "<" { adapter.handleBackspace(proxy: proxy) }
                else { adapter.handleCharacter(key, proxy: proxy) }
                processing.append((ProcessInfo.processInfo.systemUptime - arrived) * 1000)
            }
            if proxy.text != fixture.expected {
                failures += 1
                // Synthetic fixture index only: never log user text.
                print("MOBILE_PACED_FIXTURE_FAILURE kps=\(Int(kps))")
            }
        }
        func percentile(_ values: [Double], _ q: Double) -> Double {
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))]
        }
        let payload: [String: Any] = [
            "raw_kps": kps, "keys": processing.count, "fixtures": fixtures.count,
            "failures": failures, "profile": "senFlex", "inline_bilingual": true,
            "provider": "local-mobile", "proxy": "in-memory", "host_ui_measured": false,
            "adapter_p50_ms": percentile(processing, 0.5),
            "adapter_p99_ms": percentile(processing, 0.99),
            "scheduler_lag_p99_ms": percentile(scheduling, 0.99),
            "scheduler_lag_max_ms": scheduling.max() ?? 0
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            print("MOBILE_PACED_SERIALIZATION_FAILURE")
            return false
        }
        print("MOBILE_PACED_JSON " + String(decoding: json, as: UTF8.self))
        allPassed = allPassed && failures == 0
    }
    print("Paced core/adapter output: \(allPassed ? "PASS" : "FAIL"). UIKit touch order and display NOT MEASURED.")
    return allPassed
}
