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

    /// Words labeled `whitelist_safe = never` in `test_suite.csv` that are currently allowed
    /// to lose their Vietnamese syllable. Must remain empty (`[]`) per `AGENTS.md`.
    ///
    /// Never add an entry to make an undocumented failure go away.
    private static let acceptedCriticalLosses: Set<String> = []

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

    func testRelaxedCodaAndIncompleteVietnameseSyllablesSurvive() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif

        let cases: [(raw: String, expected: String)] = [
            ("khoog", "khôg"),
            ("khogo", "khôg"),
            ("keeh", "kêh"),
            ("kehe", "kêh"),
            ("uwg", "ưg"),
            ("nhuwg", "nhưg"),
            ("cuxg", "cũg"),
            ("cuwxg", "cữg"),
            ("mifh", "mìh"),
            ("tifh", "tìh"),
            ("dduwowk", "đươk"),
            ("dduwowkj", "đượk"),
            ("truwow", "trươ"),
            ("nguwow", "ngươ"),
            ("viee", "viê")
        ]

        for (raw, expected) in cases {
            XCTAssertEqual(
                composeWithoutContext(raw),
                expected,
                "Expected relaxed-coda/incomplete Vietnamese '\(raw)' to stay '\(expected)' instead of reverting to raw ASCII"
            )
        }
    }

    func testTransformBucketCommitWithSmartBilingualDisabled() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif

        let session = InputSessionManager()
        session.smartBilingualEnabled = true
        session.context = ""
        for char in "is" { _ = session.handleCharacter(char) }
        if case let .commit(_, text, _) = session.commitWord(smartBilingualEnabled: false) {
            XCTAssertEqual(text, "í", "When smartBilingualEnabled is false, 'is' must commit as pure Telex transform 'í'")
        } else {
            XCTFail("Expected commit action for 'is'")
        }
    }

    private func composeWithContext(_ input: String, context: String) -> (inline: String, committed: String) {
        let session = InputSessionManager()
        session.setSmartBilingualEnabled(true)
        session.context = context
        for char in input { _ = session.handleCharacter(char) }
        let inline = session.currentOutput()
        guard session.isComposing else { return (inline, inline) }
        if case let .commit(_, text, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            return (inline, text)
        }
        return (inline, inline)
    }

    func testUnambiguousVietnameseTelexSurvivesAfterEnglishContext() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        SmartBilingualDetector.resetCache()

        let vietnamesePairs: [(raw: String, expected: String)] = [
            // `uoo -> uô` family (user-reported `"is" + "luoon" -> "is luôn"`)
            ("luoon", "luôn"), ("muoon", "muôn"), ("muoons", "muốn"), ("buoonf", "buồn"),
            ("cuoons", "cuốn"), ("nguoonf", "nguồn"), ("chuoonf", "chuồn"), ("khuoon", "khuôn"),
            ("uoongs", "uống"), ("xuoongs", "xuống"), ("chuoong", "chuông"), ("cuoocj", "cuộc"),
            ("buoocj", "buộc"), ("thuoocs", "thuốc"), ("suoots", "suốt"), ("ruoongj", "ruộng"),
            // `uow / uwo -> ươ` family
            ("truowngf", "trường"), ("nguowif", "người"), ("dduowcj", "được"), ("nuowcs", "nước"),
            ("duowis", "dưới"), ("huowngs", "hướng"), ("luowng", "lương"), ("phuowng", "phương"),
            ("thuowng", "thương"), ("chuowng", "chương"), ("muowif", "mười"), ("cuowif", "cười"),
            ("tuowi", "tươi"), ("truowcs", "trước"), ("buowcs", "bước"),
            // `iee / yee -> iê / yê` family
            ("tieengs", "tiếng"), ("vieetj", "việt"), ("hieenj", "hiện"), ("bieets", "biết"),
            ("dieenj", "diện"), ("kieens", "kiến"), ("tieenf", "tiền"), ("nhieeuf", "nhiều"),
            ("ddieeuf", "điều"), ("hieeur", "hiểu"), ("yeeu", "yêu"), ("quyeets", "quyết"),
            // `ooi / oong / ooc -> ôi / ông / ôc` family
            ("tooi", "tôi"), ("ddooi", "đôi"), ("ngooi", "ngôi"), ("thooi", "thôi"),
            ("tuooir", "tuổi"), ("cuoois", "cuối"), ("nuooi", "nuôi"), ("nooij", "nội"),
            ("hooij", "hội"), ("khoong", "không"), ("ddoong", "đông"), ("coong", "công"),
            ("soongs", "sống"), ("gioongs", "giống"), ("goocs", "gốc"), ("ddoocj", "độc"),
            // `aa -> â` family
            ("caan", "cân"), ("taan", "tân"), ("daan", "dân"), ("nhaan", "nhân"),
            ("chaan", "chân"), ("caafn", "cần"), ("laafn", "lần"), ("ddaafu", "đầu"), ("daafu", "dầu"),
            ("raats", "rất"), ("nhaats", "nhất"), ("chaats", "chất"), ("thaatj", "thật"),
            ("maats", "mất"), ("caay", "cây"), ("thaays", "thấy"), ("laays", "lấy"), ("vaayj", "vậy"),
            // `uw -> ư` and `aw -> ă` families
            ("nhuwng", "nhưng"), ("nhuwngx", "những"), ("tuwf", "từ"), ("nhuw", "như"),
            ("chuwa", "chưa"), ("muwa", "mưa"), ("thuwcj", "thực"), ("luwcj", "lực"),
            ("duwngf", "dừng"), ("tuwngf", "từng"), ("awn", "ăn"), ("nawm", "năm"),
            ("trawm", "trăm"), ("cawts", "cắt"), ("mawts", "mắt"), ("bawts", "bắt"),
            ("thawngs", "thắng"), ("chawcs", "chắc"), ("gawpj", "gặp"), ("tawng", "tăng"),
            // `dd- -> đ-` and common tone-marked Vietnamese words
            ("ddax", "đã"), ("ddang", "đang"), ("ddi", "đi"), ("ddos", "đó"),
            ("ddeer", "để"), ("ddeens", "đến"), ("ddungs", "đúng"), ("ddejp", "đẹp"),
            ("ddawtj", "đặt"), ("ddatj", "đạt"), ("lamf", "làm"), ("vaf", "và"), ("laf", "là"),
            ("hocj", "học"), ("banj", "bạn"), ("minhf", "mình"), ("thanhf", "thành"),
            ("hoanf", "hoàn"), ("cuar", "của"), ("phair", "phải"), ("cungx", "cũng"),
            ("ngayf", "ngày"), ("nayf", "này"), ("nhaf", "nhà"), ("quas", "quá"), ("taos", "táo")
        ]

        let contexts = ["is", "the", "this is"]
        for ctx in contexts {
            for (raw, expected) in vietnamesePairs {
                let (inline, committed) = composeWithContext(raw, context: ctx)
                XCTAssertEqual(
                    inline,
                    expected,
                    "Inline Vietnamese Telex '\(raw)' after English context '\(ctx)' must compose as '\(expected)', got '\(inline)'"
                )
                XCTAssertEqual(
                    committed,
                    expected,
                    "Committed Vietnamese Telex '\(raw)' after English context '\(ctx)' must stay '\(expected)', got '\(committed)'"
                )
            }
        }

        // Verify genuine English words after 'is' still restore to raw English
        let englishAfterIs = ["here", "there", "more", "best", "test", "tree", "room", "moon"]
        for word in englishAfterIs {
            let (_, committed) = composeWithContext(word, context: "is")
            XCTAssertEqual(
                committed,
                word,
                "English word '\(word)' after 'is' must restore to '\(word)'"
            )
        }
    }

    func testMidSentenceEnglishPhraseResumesVietnameseDiacritics() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        SmartBilingualDetector.resetCache()

        func typeSentence(_ input: String, inlineBilingual: Bool) -> String {
            let session = InputSessionManager()
            session.setSmartBilingualEnabled(true)
            session.inlineBilingualEnabled = inlineBilingual
            var screen: [UInt16] = []
            for ch in input {
                if session.isWordBoundary(ch) {
                    let act = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    if case let .commit(bs, text, isOverride) = act, isOverride {
                        if bs > 0 && bs <= screen.count { screen.removeLast(bs) }
                        screen.append(contentsOf: text.utf16)
                    }
                    screen.append(contentsOf: String(ch).utf16)
                } else {
                    let act = session.handleCharacter(ch)
                    switch act {
                    case .passThrough:
                        screen.append(contentsOf: String(ch).utf16)
                    case .consumed:
                        break
                    case .replace(let bs, let text):
                        if bs > 0 && bs <= screen.count { screen.removeLast(bs) }
                        screen.append(contentsOf: text.utf16)
                    case .commit(let bs, let text, _):
                        if bs > 0 && bs <= screen.count { screen.removeLast(bs) }
                        screen.append(contentsOf: text.utf16)
                        screen.append(contentsOf: String(ch).utf16)
                    case .reset:
                        break
                    }
                }
            }
            return String(utf16CodeUnits: screen, count: screen.count)
        }

        for inlineBilingual in [false, true] {
            XCTAssertEqual(
                typeSentence("caafn cos kijch banr plan thees nafo a good plan thees ", inlineBilingual: inlineBilingual),
                "cần có kịch bản plan thế nào a good plan thế ",
                "inlineBilingual=\(inlineBilingual)"
            )
            XCTAssertEqual(
                typeSentence("caafn cos kijch banr plan thees nafo a good plan theer ", inlineBilingual: inlineBilingual),
                "cần có kịch bản plan thế nào a good plan thể ",
                "inlineBilingual=\(inlineBilingual)"
            )
            XCTAssertEqual(
                typeSentence("a good plan thees ", inlineBilingual: inlineBilingual),
                "a good plan thế ",
                "inlineBilingual=\(inlineBilingual)"
            )
            XCTAssertEqual(
                typeSentence("a good plan theer ", inlineBilingual: inlineBilingual),
                "a good plan thể ",
                "inlineBilingual=\(inlineBilingual)"
            )
        }

        // Verify Vietnamese syllables that previously collided with NSSpellChecker or archaic dictionary entries
        // compose with full diacritics even immediately after an English phrase ("a good plan").
        let protectedPairs: [(raw: String, expected: String)] = [
            ("thees", "thế"),
            ("theer", "thể"),
            ("chungs", "chúng"),
            ("thangs", "tháng"),
            ("thanhs", "thánh"),
            ("boons", "bốn"),
            ("toons", "tốn"),
            ("toor", "tổ"),
            ("boos", "bố"),
            ("coos", "cố"),
            ("deef", "dề"),
            ("moof", "mồ"),
            ("trows", "trớ"),
            ("sown", "sơn"),
            ("mow", "mơ"),
            ("gias", "giá"),
            ("giar", "giả"),
            ("chins", "chín"),
            ("tams", "tám"),
            ("buns", "bún"),
            ("chats", "chát"),
            ("chems", "chém")
        ]
        for (raw, expected) in protectedPairs {
            let session = InputSessionManager()
            session.setSmartBilingualEnabled(true)
            session.inlineBilingualEnabled = true
            session.context = "a good plan"
            for char in raw {
                _ = session.handleCharacter(char)
            }
            XCTAssertEqual(session.composingWord, expected, "Inline composingWord for '\(raw)' after 'a good plan'")
            var committed = session.composingWord
            if case let .commit(_, text, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
                committed = text
            }
            XCTAssertEqual(committed, expected, "Committed word for '\(raw)' after 'a good plan'")
        }
    }
}
