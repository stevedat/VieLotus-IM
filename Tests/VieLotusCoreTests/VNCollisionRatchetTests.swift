import XCTest
@testable import VieLotusCore

/// Ratchet guard for the Vietnamese side of the English/Vietnamese ambiguity trade.
///
/// `VieLotusCLI --benchmark` reports `vn_survives_collision`: the lowercase
/// `ambiguous_needs_context` rows replayed with NO English context, where the expected
/// result is the Vietnamese syllable rather than the English word. That bucket is the
/// cost side of Smart Bilingual and the headline pass rate does not show it.
///
/// This test pins the set of words that currently lose their Vietnamese syllable so the
/// set can only shrink. A new loss fails the build even when every headline number still
/// looks green; a healed word also fails, forcing the accepted list down.
final class VNCollisionRatchetTests: XCTestCase {

    /// Words whose ONLY keystroke path to a Vietnamese syllable (`whitelist_safe = never`)
    /// is currently lost to an English restore. Measured 2026-10-11 on a release build
    /// with the macOS spell checker active — 21 of 180 `never` probes.
    ///
    /// Delete entries as the engine improves. Never add one to make a failure go away.
    private static let acceptedCriticalLosses: Set<String> = [
        "burns", "dir", "her", "par", "parts", "per", "refer", "refers", "reset",
        "rest", "rims", "rosa", "rust", "sics", "sofa", "sur", "terms", "texts",
        "town", "tys", "verse"
    ]

    private struct Probe {
        let input: String
        let vietnamese: String
        let safety: String
    }

    /// Reads the same CSV the CLI benchmark uses, so the two never drift apart.
    private func loadProbes() throws -> [Probe] {
        let csvURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VieLotusCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Sources/VieLotusCLI/Resources/test_suite.csv")
        let content = try String(contentsOf: csvURL, encoding: .utf8)

        var probes: [Probe] = []
        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            guard index > 0, !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let columns = line.components(separatedBy: ",")
            guard columns.count >= 9, columns[5] == "ambiguous_needs_context" else { continue }
            guard columns[8] == "never" || columns[8] == "degrades_vn" else { continue }

            let input = columns[1]
            // Cased rows are excluded on purpose: capitalisation is itself an English
            // signal, and whether it should restore without a context is an open policy
            // question, not a defect. See the `case_signal_restores` bucket in the CLI.
            guard !input.isEmpty, !input.contains(where: { $0.isUppercase }) else { continue }
            guard !columns[3].isEmpty else { continue }

            probes.append(Probe(input: input, vietnamese: columns[3], safety: columns[8]))
        }
        return probes
    }

    /// Replays one word with an empty context and Smart Bilingual enabled, mirroring
    /// `driveInput(primeEnglish: false, bilingualEnabled: true)` in the CLI harness.
    private func composeWithoutContext(_ input: String) -> String {
        let session = InputSessionManager()
        session.context = ""
        for char in input { _ = session.handleCharacter(char) }
        guard session.isComposing else { return session.currentOutput() }
        if case let .commit(_, text, _) = session.commitWord(smartBilingualEnabled: true) {
            return text
        }
        return session.currentOutput()
    }

    func testCriticalVietnameseLossesDoNotGrow() throws {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()

        let probes = try loadProbes()
        XCTAssertGreaterThan(probes.count, 300, "Expected the full lowercase ambiguous probe set from test_suite.csv")

        var criticalLosses: Set<String> = []
        var allLosses: Set<String> = []
        for probe in probes {
            guard composeWithoutContext(probe.input) != probe.vietnamese else { continue }
            allLosses.insert(probe.input)
            if probe.safety == "never" { criticalLosses.insert(probe.input) }
        }

        let newLosses = criticalLosses.subtracting(Self.acceptedCriticalLosses)
        XCTAssertTrue(
            newLosses.isEmpty,
            """
            NEW words lost their only keystroke path to a Vietnamese syllable: \
            \(newLosses.sorted().joined(separator: ", ")).
            Fix the engine — do not add them to acceptedCriticalLosses.
            """
        )

        let healed = Self.acceptedCriticalLosses.subtracting(criticalLosses)
        XCTAssertTrue(
            healed.isEmpty,
            """
            These words now keep their Vietnamese syllable: \
            \(healed.sorted().joined(separator: ", ")).
            Delete them from acceptedCriticalLosses so the ratchet moves down.
            """
        )

        // Non-critical losses are reported, not gated: those rows keep at least one other
        // keystroke path to the Vietnamese syllable (`degrades_vn`).
        let degraded = allLosses.subtracting(criticalLosses).sorted()
        if !degraded.isEmpty {
            print("vn_survives_collision — \(degraded.count) `degrades_vn` words restored to English without context: \(degraded.joined(separator: ", "))")
        }
        #endif
    }
}
