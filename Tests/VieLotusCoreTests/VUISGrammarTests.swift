import XCTest
@testable import VieLotusCore

final class VUISGrammarTests: XCTestCase {

    // MARK: - Pre-vowel Profile Tests

    func testPreVowelCoreTransformations() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .preVowel

        // 1. rrung -> rủng
        XCTAssertEqual(engine.transform(Array("rrung")), "rủng")

        // 2. rrinh -> rỉnh
        XCTAssertEqual(engine.transform(Array("rrinh")), "rỉnh")

        // 3. rinh -> rinh (untouched)
        XCTAssertEqual(engine.transform(Array("rinh")), "rinh")

        // 4. cra -> cả
        XCTAssertEqual(engine.transform(Array("cra")), "cả")

        // 5. csa -> cá
        XCTAssertEqual(engine.transform(Array("csa")), "cá")

        // 6. tse -> té
        XCTAssertEqual(engine.transform(Array("tse")), "té")

        // 7. qfua -> quà
        XCTAssertEqual(engine.transform(Array("qfua")), "quà")

        // 8. qufa -> quà
        XCTAssertEqual(engine.transform(Array("qufa")), "quà")

        // 9. ddson -> đón
        XCTAssertEqual(engine.transform(Array("ddson")), "đón")

        // 10. tseet -> tết / Tseet -> Tết
        XCTAssertEqual(engine.transform(Array("tseet")), "tết")
        XCTAssertEqual(engine.transform(Array("Tseet")), "Tết")

        // 11. ngjo -> ngọ
        XCTAssertEqual(engine.transform(Array("ngjo")), "ngọ")

        // 12. thfuyeen -> thuyền
        XCTAssertEqual(engine.transform(Array("thfuyeen")), "thuyền")

        // 13. qusyeet -> quyết
        XCTAssertEqual(engine.transform(Array("qusyeet")), "quyết")
    }

    func testFlexibleModifierPlacement() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .preVowel

        // "trường" variants:
        // trfuowng (pre-vowel tone + uow)
        XCTAssertEqual(engine.transform(Array("trfuowng")), "trường")
        // trwfuong (pre-vowel horn w + grave f + uong)
        XCTAssertEqual(engine.transform(Array("trwfuong")), "trường")
        // truowfng (infix tone f)
        XCTAssertEqual(engine.transform(Array("truowfng")), "trường")

        // "nướng" variants:
        // nsuowng (pre-vowel acute s + uow)
        XCTAssertEqual(engine.transform(Array("nsuowng")), "nướng")
        // nwsuong (pre-vowel horn w + acute s + uong)
        XCTAssertEqual(engine.transform(Array("nwsuong")), "nướng")
        // nsuongw (pre-vowel acute s + uong + trailing w)
        XCTAssertEqual(engine.transform(Array("nsuongw")), "nướng")

        // "gương" variants:
        // guowng (standard uow)
        XCTAssertEqual(engine.transform(Array("guowng")), "gương")
        // gwuong (pre-vowel horn w + uong)
        XCTAssertEqual(engine.transform(Array("gwuong")), "gương")
        // guongw (uong + trailing horn w)
        XCTAssertEqual(engine.transform(Array("guongw")), "gương")
    }

    // MARK: - Smart Hybrid Profile Tests

    func testSmartHybridProfile() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .smartHybrid

        // Pre-vowel works
        XCTAssertEqual(engine.transform(Array("rrung")), "rủng")
        XCTAssertEqual(engine.transform(Array("cra")), "cả")
        XCTAssertEqual(engine.transform(Array("qfua")), "quà")
        XCTAssertEqual(engine.transform(Array("tseet")), "tết")

        // Trailing tone works when Vietnamese markers or valid Vietnamese syllables exist
        XCTAssertEqual(engine.transform(Array("truowngf")), "trường")
        XCTAssertEqual(engine.transform(Array("quyeets")), "quyết")
        XCTAssertEqual(engine.transform(Array("nuowngs")), "nướng")
        XCTAssertEqual(engine.transform(Array("ddons")), "đón")
        XCTAssertEqual(engine.transform(Array("teets")), "tết")
        XCTAssertEqual(engine.transform(Array("thuyeenf")), "thuyền")
        XCTAssertEqual(engine.transform(Array("quaf")), "quà")
    }

    // MARK: - English Collision Preservation Tests

    func testEnglishCollisionProtectionInPreVowelAndHybrid() {
        let preVowelEngine = VietnameseEngine()
        preVowelEngine.grammarProfile = .preVowel

        let hybridEngine = VietnameseEngine()
        hybridEngine.grammarProfile = .smartHybrid

        // In pure Pre-Vowel mode, trailing tones (s, f, r, etc.) are never interpreted as tones.
        // Therefore words like "car", "has", "is", "as", "us", "if", "of", "cas", "tes" naturally remain raw!
        let preVowelEnglishWords = ["car", "cas", "tes", "has", "is", "as", "us", "if", "of", "boss", "error", "pass", "crash", "class", "test"]
        for word in preVowelEnglishWords {
            let chars = Array(word)
            XCTAssertEqual(preVowelEngine.transform(chars), word, "Pre-vowel must preserve '\(word)' as raw")
        }

        // In Smart Hybrid, impossible codas or double-modifier cancellations remain raw:
        let hybridRawWords = ["boss", "error", "pass", "crash", "class", "test"]
        for word in hybridRawWords {
            let chars = Array(word)
            XCTAssertEqual(hybridEngine.transform(chars), word, "Smart Hybrid must preserve '\(word)' as raw")
        }

        // In Smart Hybrid, standard trailing tones MUST produce Vietnamese syllables:
        XCTAssertEqual(hybridEngine.transform(Array("as")), "á")
        XCTAssertEqual(hybridEngine.transform(Array("is")), "í")
        XCTAssertEqual(hybridEngine.transform(Array("us")), "ú")
        XCTAssertEqual(hybridEngine.transform(Array("if")), "ì")
        XCTAssertEqual(hybridEngine.transform(Array("of")), "ò")
        XCTAssertEqual(hybridEngine.transform(Array("cas")), "cá")
        XCTAssertEqual(hybridEngine.transform(Array("car")), "cả")
        XCTAssertEqual(hybridEngine.transform(Array("tes")), "té")
        XCTAssertEqual(hybridEngine.transform(Array("has")), "há")
    }

    // MARK: - Deterministic Negative Boundary Tests

    func testDeterministicBoundaries() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .smartHybrid

        // 1. qsueet does NOT have 'y', so it must NOT become "quyết"
        let qsueet = engine.transform(Array("qsueet"))
        XCTAssertNotEqual(qsueet, "quyết", "qsueet must not hallucinate missing 'y'")

        // 2. chuonwg and chuongw do NOT have 'x', so they must NOT become "chưỡng" (they should be "chương")
        XCTAssertEqual(engine.transform(Array("chuonwg")), "chương")
        XCTAssertEqual(engine.transform(Array("chuongw")), "chương")
        XCTAssertNotEqual(engine.transform(Array("chuonwg")), "chưỡng")
        XCTAssertNotEqual(engine.transform(Array("chuongw")), "chưỡng")

        // 3. tra must remain "tra" (onset digraph 'tr' maximal munch), not "tả"
        XCTAssertEqual(engine.transform(Array("tra")), "tra")
        XCTAssertNotEqual(engine.transform(Array("tra")), "tả")
    }

    // MARK: - Full Sentence Integration Test

    func testFullCorpusSentenceIntegration() {
        // Sentence: "Rủng rỉnh rinh quà đón Tết Đoan Ngọ bên trường thuyền quyết nướng gương."
        let engine = VietnameseEngine()
        engine.grammarProfile = .smartHybrid

        let rawTokens = [
            "rrung",      // Rủng
            "rrinh",      // rỉnh
            "rinh",       // rinh
            "qfua",       // quà
            "ddson",      // đón
            "Tseet",      // Tết
            "Ddoan",      // Đoan
            "ngjo",       // Ngọ
            "been",       // bên
            "trwfuong",   // trường
            "thfuyeen",   // thuyền
            "qusyeet",    // quyết
            "nwsuong",    // nướng
            "guowng"      // gương
        ]

        let expectedTokens = [
            "rủng",
            "rỉnh",
            "rinh",
            "quà",
            "đón",
            "Tết",
            "Đoan",
            "ngọ",
            "bên",
            "trường",
            "thuyền",
            "quyết",
            "nướng",
            "gương"
        ]

        for (raw, expected) in zip(rawTokens, expectedTokens) {
            let actual = engine.transform(Array(raw))
            XCTAssertEqual(actual, expected, "Token '\(raw)' expected '\(expected)', got '\(actual)'")
        }
    }

    // MARK: - SEN VIỆT Flex v1 (OPRSC-v2.1) Tests

    func testSenVietFlexMultiOrderConvergence() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .senFlex

        // 1. rủng: rrung, rungr
        XCTAssertEqual(engine.transform(Array("rrung")), "rủng")
        XCTAssertEqual(engine.transform(Array("rungr")), "rủng")

        // 2. rỉnh: rrinh, rinhr
        XCTAssertEqual(engine.transform(Array("rrinh")), "rỉnh")
        XCTAssertEqual(engine.transform(Array("rinhr")), "rỉnh")

        // 3. cùng: cfung, cungf
        XCTAssertEqual(engine.transform(Array("cfung")), "cùng")
        XCTAssertEqual(engine.transform(Array("cungf")), "cùng")

        // 4. cái: csai, cais
        XCTAssertEqual(engine.transform(Array("csai")), "cái")
        XCTAssertEqual(engine.transform(Array("cais")), "cái")

        // 5. một: mjoot, mootj
        XCTAssertEqual(engine.transform(Array("mjoot")), "một")
        XCTAssertEqual(engine.transform(Array("mootj")), "một")

        // 6. đón: ddson, ddons
        XCTAssertEqual(engine.transform(Array("ddson")), "đón")
        XCTAssertEqual(engine.transform(Array("ddons")), "đón")

        // 7. quà: qfua, quaf
        XCTAssertEqual(engine.transform(Array("qfua")), "quà")
        XCTAssertEqual(engine.transform(Array("quaf")), "quà")

        // 8. trường: trwfuong, trfuowng, truowfng, truowngf
        XCTAssertEqual(engine.transform(Array("trwfuong")), "trường")
        XCTAssertEqual(engine.transform(Array("trfuowng")), "trường")
        XCTAssertEqual(engine.transform(Array("truowfng")), "trường")
        XCTAssertEqual(engine.transform(Array("truowngf")), "trường")

        // 9. trưởng: trwruong, truowngr
        XCTAssertEqual(engine.transform(Array("trwruong")), "trưởng")
        XCTAssertEqual(engine.transform(Array("truowngr")), "trưởng")

        // 10. trượng: trwjuong, truowngj
        XCTAssertEqual(engine.transform(Array("trwjuong")), "trượng")
        XCTAssertEqual(engine.transform(Array("truowngj")), "trượng")

        // 11. trưỡng: trwxuong, truowngx
        XCTAssertEqual(engine.transform(Array("trwxuong")), "trưỡng")
        XCTAssertEqual(engine.transform(Array("truowngx")), "trưỡng")

        // 12. nướng: nwsuong, nsuongw, nuowngs
        XCTAssertEqual(engine.transform(Array("nwsuong")), "nướng")
        XCTAssertEqual(engine.transform(Array("nsuongw")), "nướng")
        XCTAssertEqual(engine.transform(Array("nuowngs")), "nướng")

        // 13. gương: gwuong, guongw, guowng
        XCTAssertEqual(engine.transform(Array("gwuong")), "gương")
        XCTAssertEqual(engine.transform(Array("guongw")), "gương")
        XCTAssertEqual(engine.transform(Array("guowng")), "gương")
    }

    func testSenVietFlexDualRoleAndEnglishPreservation() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .senFlex

        // tra -> tra (Raw priority: onset digraph "tr", not "tả")
        XCTAssertEqual(engine.transform(Array("tra")), "tra")

        // cra -> cả (VN priority: "cr" is not a Vietnamese onset, "r" is hook tone)
        XCTAssertEqual(engine.transform(Array("cra")), "cả")

        // car -> cả (Classic trailing path: c + a + r -> cả. English "car" is restored via SmartBilingual context)
        XCTAssertEqual(engine.transform(Array("car")), "cả")

        // teen -> tên (Classic path: t + ee + n -> tên. English "teen" is restored via SmartBilingual context)
        XCTAssertEqual(engine.transform(Array("teen")), "tên")

        // crash -> crash (Raw priority: English word with -sh coda)
        XCTAssertEqual(engine.transform(Array("crash")), "crash")

        // class -> class (Raw priority: English word with -ss double consonant)
        XCTAssertEqual(engine.transform(Array("class")), "class")

        // test -> test (Raw priority: English word with -st coda)
        XCTAssertEqual(engine.transform(Array("test")), "test")
    }

    func testTypingFlowReversibilityAndBackspace() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .senFlex

        // Forward typing simulation: c -> cr -> cra -> cras -> crash
        _ = engine.feed("c")
        XCTAssertEqual(engine.currentOutput(), "c")

        _ = engine.feed("r")
        XCTAssertEqual(engine.currentOutput(), "cr")

        _ = engine.feed("a")
        XCTAssertEqual(engine.currentOutput(), "cả", "cra should render as 'cả' via pre-vowel hook tone")

        _ = engine.feed("s")
        // cras intermediate state
        XCTAssertFalse(engine.currentOutput().isEmpty)

        _ = engine.feed("h")
        XCTAssertEqual(engine.currentOutput(), "crash", "crash should flip to raw English word")

        // Backward unwinding simulation via Backspace:
        // 1. "crash" (raw English) -> removes 'h' -> re-evaluates "cras" as "cá"
        _ = engine.backspace()
        XCTAssertEqual(engine.currentOutput(), "cá", "Backspace on raw 'crash' removes 'h' and re-evaluates 'cras' -> 'cá'")

        // 2. "cá" -> semantic backspace strips acute tone -> "ca"
        _ = engine.backspace()
        XCTAssertEqual(engine.currentOutput(), "ca", "Backspace on 'cá' strips acute tone, leaving 'ca'")

        // 3. "ca" -> deletes 'a' -> "c"
        _ = engine.backspace()
        XCTAssertEqual(engine.currentOutput(), "c", "Backspace on 'ca' deletes 'a', leaving 'c'")

        // 4. "c" -> deletes 'c' -> empty
        _ = engine.backspace()
        XCTAssertEqual(engine.currentOutput(), "")
    }

    func testSenVietFlexFullSentenceIntegration() {
        let engine = VietnameseEngine()
        engine.grammarProfile = .senFlex

        let sentenceTokens = [
            ("rrung", "rủng"),
            ("rrinh", "rỉnh"),
            ("rinh", "rinh"),
            ("qfua", "quà"),
            ("ddson", "đón"),
            ("Tseet", "Tết"),
            ("Ddoan", "Đoan"),
            ("ngjo", "ngọ"),
            ("been", "bên"),
            ("trwfuong", "trường"),
            ("thfuyeen", "thuyền"),
            ("qusyeet", "quyết"),
            ("nwsuong", "nướng"),
            ("guowng", "gương")
        ]

        for (raw, expected) in sentenceTokens {
            let actual = engine.transform(Array(raw))
            XCTAssertEqual(actual, expected, "senFlex: token '\(raw)' expected '\(expected)', got '\(actual)'")
        }
    }

    func testDoubleKeyTelexEscapesInSmartHybridAndSenFlex() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif

        for profile in [GrammarProfile.smartHybrid, GrammarProfile.senFlex] {
            let engine = VietnameseEngine()
            engine.grammarProfile = profile

            // Simple Telex standalone 'w' and double-w horn escapes
            XCTAssertEqual(engine.transform(Array("w")), "w", "\(profile): w -> w")
            XCTAssertEqual(engine.transform(Array("W")), "W", "\(profile): W -> W")
            XCTAssertEqual(engine.transform(Array("ww")), "ww", "\(profile): ww -> ww")
            XCTAssertEqual(engine.transform(Array("aww")), "aw", "\(profile): aww -> aw")
            XCTAssertEqual(engine.transform(Array("uww")), "uw", "\(profile): uww -> uw")
            XCTAssertEqual(engine.transform(Array("oww")), "ow", "\(profile): oww -> ow")

            // Double tone key escapes (e.g. hits -> hít, hitss -> hits)
            XCTAssertEqual(engine.transform(Array("hits")), "hít", "\(profile): hits -> hít")
            XCTAssertEqual(engine.transform(Array("hitss")), "hits", "\(profile): hitss -> hits")
            XCTAssertEqual(engine.transform(Array("carr")), "car", "\(profile): carr -> car")
            XCTAssertEqual(engine.transform(Array("giff")), "gif", "\(profile): giff -> gif")
            XCTAssertEqual(engine.transform(Array("sexx")), "sex", "\(profile): sexx -> sex")

            // Double and triple tone key escapes (as -> á, ass -> as, asss -> ass, off -> of, offf -> off)
            XCTAssertEqual(engine.transform(Array("as")), "á", "\(profile): as -> á")
            XCTAssertEqual(engine.transform(Array("ass")), "as", "\(profile): ass -> as")
            XCTAssertEqual(engine.transform(Array("asss")), "ass", "\(profile): asss -> ass")
            XCTAssertEqual(engine.transform(Array("off")), "of", "\(profile): off -> of")
            XCTAssertEqual(engine.transform(Array("offf")), "off", "\(profile): offf -> off")
            XCTAssertEqual(engine.transform(Array("ddooo")), "đoo", "\(profile): ddooo -> đoo")
            XCTAssertEqual(engine.transform(Array("nhuwngs")), "nhứng", "\(profile): nhuwngs -> nhứng")

            // Trailing characters after double-key tone escape (carrs -> cars, hairrs -> hairs, giffs -> gifs, iffs -> ifs)
            XCTAssertEqual(engine.transform(Array("carrs")), "cars", "\(profile): carrs -> cars")
            XCTAssertEqual(engine.transform(Array("hairr")), "hair", "\(profile): hairr -> hair")
            XCTAssertEqual(engine.transform(Array("hairrs")), "hairs", "\(profile): hairrs -> hairs")
            XCTAssertEqual(engine.transform(Array("giffs")), "gifs", "\(profile): giffs -> gifs")
            XCTAssertEqual(engine.transform(Array("iffs")), "ifs", "\(profile): iffs -> ifs")
            XCTAssertEqual(engine.transform(Array("iffss")), "ifs", "\(profile): iffss -> ifs")
            XCTAssertEqual(engine.transform(Array("iffsss")), "ifss", "\(profile): iffsss -> ifss")

            // SmartBilingualDetector must NOT revert escaped "hits", "as", "ass", "of", "off", "cars", "hairs", "gifs", "ifs", "w" on Space
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ww", context: "", rendered: "w"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "aww", context: "", rendered: "aw"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "hitss", context: "", rendered: "hits"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ass", context: "", rendered: "as"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "ass", context: "if ask asks", rendered: "as"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "asss", context: "", rendered: "ass"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "off", context: "", rendered: "of"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "offf", context: "", rendered: "off"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "carrs", context: "", rendered: "cars"))
            XCTAssertFalse(SmartBilingualDetector.isInlineEnglishWord(raw: "carrs", rendered: "cars"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "hairr", context: "", rendered: "hair"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "hairrs", context: "", rendered: "hairs"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "giffs", context: "", rendered: "gifs"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "iffs", context: "", rendered: "ifs"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "iffss", context: "", rendered: "ifs"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "nhuwngs", context: "", rendered: "nhứng"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "eer", context: "", rendered: "ể"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "er", context: "", rendered: "ẻ"))
            // P0.7 Section 1: standalone `or` defaults to English, while Vietnamese collocation (`thẻ ỏ`) preserves `ỏ`.
            XCTAssertTrue(SmartBilingualDetector.isEnglishWord(raw: "or", context: "", rendered: "ỏ"))
            XCTAssertFalse(SmartBilingualDetector.isEnglishWord(raw: "or", context: "thẻ", rendered: "ỏ"))

            // Post-commit editing: "hits" ("hít") + commit + Backspace + 's' -> "hits"
            engine.reset()
            for ch in "hits" { _ = engine.feed(ch) }
            XCTAssertEqual(engine.currentOutput(), "hít")
            engine.commitWord(raw: "hits", rendered: "hít")
            let diff = engine.editAt(caretBack: 0, char: "s")
            XCTAssertNotNil(diff)
            XCTAssertEqual(engine.currentOutput(), "hits")

            // Post-commit editing & trailing 'd' stroke toggle: "ddooir" ("đổi") + 'd' -> "dổi"
            XCTAssertEqual(engine.transform(Array("ddooird")), "dổi")
            engine.reset()
            for ch in "ddooir" { _ = engine.feed(ch) }
            XCTAssertEqual(engine.currentOutput(), "đổi")
            engine.commitWord(raw: "ddooir", rendered: "đổi")
            let diffD = engine.editAt(caretBack: 0, char: "d")
            XCTAssertNotNil(diffD)
            XCTAssertEqual(engine.currentOutput(), "dổi")
            engine.commitWord(raw: "dooir", rendered: "dổi")
            let diffD2 = engine.editAt(caretBack: 0, char: "d")
            XCTAssertNotNil(diffD2)
            XCTAssertEqual(engine.currentOutput(), "đổi")
            engine.commitWord(raw: "ddooir", rendered: "đổi")
            XCTAssertNil(engine.editAt(caretBack: 0, char: "b"), "Non-modifier consonant must not corrupt 'đổi' into 'đôỉb'")

            // Sentence punctuation ('.', ':') must NOT revert Vietnamese words to raw Telex
            let session = InputSessionManager()
            session.setGrammarProfile(profile)
            session.bilingualNoContextPolicy = .standardVietnameseFirst
            for (raw, expected) in [("dduocwj", "được"), ("theer", "thể"), ("nhunwgx", "những"), ("as", "á"), ("gaf", "gà")] {
                session.reset()
                for ch in raw { _ = session.handleCharacter(ch) }
                guard case let .commit(_, committedDot, isOverrideDot) = session.commitWord(smartBilingualEnabled: true, boundaryChar: ".") else {
                    return XCTFail("Expected commit on '.' for \(raw)")
                }
                XCTAssertEqual(committedDot, expected)
                XCTAssertFalse(isOverrideDot)
            }
        }
    }

    func testZAndWInitialInlinePreservationAcrossAllProfilesAndGenZMode() {
        for profile in GrammarProfile.allCases {
            for genZ in [false, true] {
                let engine = VietnameseEngine()
                engine.grammarProfile = profile
                engine.genZMode = genZ

                // 1. "zalo" and "zebra": 'z' must NEVER disappear on keystroke 2 ("za", "ze") or get mangled mid-word
                let zWords = ["zalo", "zebra", "Zalo", "Zebra", "facebook", "folder", "java"]
                for word in zWords {
                    engine.reset()
                    var expectedPrefix = ""
                    for ch in word {
                        expectedPrefix.append(ch)
                        _ = engine.feed(ch)
                        XCTAssertEqual(
                            engine.currentOutput(),
                            expectedPrefix,
                            "profile=\(profile) genZ=\(genZ): typing '\(word)' at prefix '\(expectedPrefix)' must keep initial intact"
                        )
                    }
                }

                // 2. Genuine Gen-Z teen-code syllables still transform when genZMode == true
                if genZ && profile != .preVowel {
                    XCTAssertEqual(engine.transform(Array("fair")), "fải", "profile=\(profile): fair -> fải in Gen-Z mode")
                    XCTAssertEqual(engine.transform(Array("fongf")), "fòng", "profile=\(profile): fongf -> fòng in Gen-Z mode")
                    XCTAssertEqual(engine.transform(Array("zaayj")), "zậy", "profile=\(profile): zaayj -> zậy in Gen-Z mode")
                    XCTAssertEqual(engine.transform(Array("zif")), "zì", "profile=\(profile): zif -> zì in Gen-Z mode")
                }

                // 3. Simple Telex standalone 'w' -> 'w' while 'w'-initial Vietnamese words preserve "ư..."
                XCTAssertEqual(engine.transform(Array("w")), "w", "profile=\(profile): w -> w")
                XCTAssertEqual(engine.transform(Array("W")), "W", "profile=\(profile): W -> W")
                XCTAssertEqual(engine.transform(Array("ww")), "ww", "profile=\(profile): ww -> ww")
                XCTAssertEqual(engine.transform(Array("www")), "www", "profile=\(profile): www -> www")
                XCTAssertEqual(engine.transform(Array("wa")), "wa", "profile=\(profile): wa -> wa")
                XCTAssertEqual(engine.transform(Array("wu")), "wu", "profile=\(profile): wu -> wu")
                XCTAssertEqual(engine.transform(Array("uwa")), "ưa", "profile=\(profile): uwa -> ưa")
                XCTAssertEqual(engine.transform(Array("uwu")), "ưu", "profile=\(profile): uwu -> ưu")
                XCTAssertEqual(engine.transform(Array("uwaa")), "ưaa", "profile=\(profile): uwaa -> ưaa")
                XCTAssertEqual(engine.transform(Array("cswap")), "cswap", "profile=\(profile): cswap -> cswap")
                if profile != .preVowel {
                    XCTAssertEqual(engine.transform(Array("ws")), "ứ", "profile=\(profile): ws -> ứ")
                    XCTAssertEqual(engine.transform(Array("wr")), "ử", "profile=\(profile): wr -> ử")
                    XCTAssertEqual(engine.transform(Array("was")), genZ ? "wá" : "ứa", "profile=\(profile): was -> wá in GenZ, ứa otherwise")
                    XCTAssertEqual(engine.transform(Array("wus")), "ứu", "profile=\(profile): wus -> ứu")
                }

                // 4. 'w'-initial English words resolve immediately to literal 'w...' inline on 2nd/3rd keystroke
                let wWords2ndKeystroke = ["web", "website", "wifi", "window", "windows", "whatsapp", "work", "world", "week", "well", "welcome"]
                for word in wWords2ndKeystroke {
                    engine.reset()
                    var idx = 0
                    var prefix = ""
                    for ch in word {
                        idx += 1
                        prefix.append(ch)
                        _ = engine.feed(ch)
                        if idx >= 2 {
                            XCTAssertEqual(
                                engine.currentOutput(),
                                prefix,
                                "profile=\(profile) genZ=\(genZ): '\(word)' at keystroke \(idx) ('\(prefix)') must resolve to raw 'w...'"
                            )
                        }
                    }
                }

                let wWords3rdKeystroke = ["write", "wrong", "water", "watch", "wall", "want", "way", "wait"]
                for word in wWords3rdKeystroke {
                    engine.reset()
                    var idx = 0
                    var prefix = ""
                    for ch in word {
                        idx += 1
                        prefix.append(ch)
                        _ = engine.feed(ch)
                        if idx >= 3 {
                            XCTAssertEqual(
                                engine.currentOutput(),
                                prefix,
                                "profile=\(profile) genZ=\(genZ): '\(word)' at keystroke \(idx) ('\(prefix)') must resolve to raw 'w...'"
                            )
                        }
                    }
                }
            }
        }
    }

    func testDoubleWEscapeAndMidWordEnglishFlickerSuppression() {
        for profile in GrammarProfile.allCases {
            for genZ in [false, true] {
                let session = InputSessionManager()
                session.setGrammarProfile(profile)
                session.setGenZMode(genZ)
                session.smartBilingualEnabled = true
                session.inlineBilingualEnabled = true

                // 1. "ww" and "ww" + continuation must produce literal "w..." without double-w restore on commit
                let wwCases: [(input: String, expected: String)] = [
                    ("ww", "ww"),
                    ("WW", "WW"),
                    ("www", "www"),
                    ("wwa", "wa"),
                    ("wweb", "web"),
                    ("wwifi", "wifi"),
                    ("wwater", "water"),
                    ("wws", "ws"),
                    ("wwf", "wf"),
                    ("wwork", "work")
                ]
                for tc in wwCases {
                    session.reset()
                    for ch in tc.input {
                        _ = session.handleCharacter(ch)
                    }
                    XCTAssertEqual(
                        session.currentOutput(),
                        tc.expected,
                        "profile=\(profile) genZ=\(genZ): inline output for '\(tc.input)' must be '\(tc.expected)'"
                    )
                    guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                        return XCTFail("Expected commit for '\(tc.input)'")
                    }
                    XCTAssertEqual(
                        committedText,
                        tc.expected,
                        "profile=\(profile) genZ=\(genZ): commitWord() for '\(tc.input)' must keep '\(tc.expected)'"
                    )
                    XCTAssertFalse(
                        isOverride,
                        "profile=\(profile) genZ=\(genZ): commitWord() for '\(tc.input)' must not override with doubled 'ww'"
                    )
                }

                // 2. Mid-word English diacritic flickering must be suppressed immediately once prefix is non-plausible Vietnamese
                // e.g. "restrict": "r" -> "r", "re" -> "re", "res" -> "ré" (or "res" in preVowel), "rest" -> "rest", "restr" -> "restr", "restri" -> "restri", "restric" -> "restric", "restrict" -> "restrict"
                let flickerCases: [(word: String, rawFromIndex: Int)] = [
                    ("restrict", 5), // "rest" is valid VN "rét"; at step 5 "restr" immediately restores to raw (never "rẻt", "rẻti")
                    ("service", 4),  // "serv", "servi", "servic", "service" (never "sẻv", "sẻvi")
                    ("vayaj", 5),    // "vayaj" (never "vạya")
                    ("gix", 3)       // "gix" (never "gĩ")
                ]
                for tc in flickerCases {
                    session.reset()
                    var prefix = ""
                    for (i, ch) in tc.word.enumerated() {
                        prefix.append(ch)
                        _ = session.handleCharacter(ch)
                        let step = i + 1
                        if step >= tc.rawFromIndex {
                            let effectiveScreenText = session.currentOutput()
                            XCTAssertEqual(
                                effectiveScreenText,
                                prefix,
                                "profile=\(profile) genZ=\(genZ): '\(tc.word)' at step \(step) ('\(prefix)') must display raw '\(prefix)', got '\(effectiveScreenText)'"
                            )
                        }
                    }
                }
            }
        }
    }

    func testFreeOrderUuDiphthongTelexAndVNITransformations() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            for genZ in [false, true] {
                let session = InputSessionManager()
                session.setGrammarProfile(profile)
                session.setGenZMode(genZ)
                session.smartBilingualEnabled = true
                session.inlineBilingualEnabled = true

                // All free-order Telex ways to type "cứu" and other -ưu syllables
                var cuuCases: [(String, String)] = [
                    ("cuwus", "cứu"),
                    ("cuuws", "cứu"),
                    ("cuusw", "cứu"),
                    ("cuwsu", "cứu"),
                    ("Cuwus", "Cứu"),
                    ("Cuuws", "Cứu"),
                    ("Cuusw", "Cứu"),
                    ("CUWUS", "CỨU"),
                    ("CUUWS", "CỨU"),
                    ("CUUSW", "CỨU"),
                    ("cuwu", "cưu"),
                    ("cuuw", "cưu"),
                    ("cuwuf", "cừu"),
                    ("cuuwf", "cừu"),
                    ("cuufw", "cừu"),
                    ("cuwur", "cửu"),
                    ("cuuwr", "cửu"),
                    ("cuurw", "cửu"),
                    ("cuwuj", "cựu"),
                    ("cuuwj", "cựu"),
                    ("cuujw", "cựu"),
                    ("luwu", "lưu"),
                    ("luuw", "lưu"),
                    ("huwu", "hưu"),
                    ("huuw", "hưu"),
                    ("huwux", "hữu"),
                    ("huuwx", "hữu"),
                    ("huuxw", "hữu"),
                    ("muwu", "mưu"),
                    ("muuw", "mưu"),
                    ("suwu", "sưu"),
                    ("suuw", "sưu"),
                    ("truwuf", "trừu"),
                    ("truuwf", "trừu"),
                    ("truufw", "trừu")
                ]

                if profile == .smartHybrid || profile == .senFlex {
                    cuuCases.append(contentsOf: [
                        ("cwuus", "cứu"),
                        ("csuwu", "cứu"),
                        ("csuuw", "cứu"),
                        ("cwsuu", "cứu")
                    ])
                }

                for (input, expected) in cuuCases {
                    session.reset()
                    for ch in input {
                        _ = session.handleCharacter(ch)
                    }
                    XCTAssertEqual(
                        session.currentOutput(),
                        expected,
                        "profile=\(profile) genZ=\(genZ): inline output for '\(input)' must be '\(expected)'"
                    )
                    guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                        return XCTFail("Expected commit for '\(input)'")
                    }
                    XCTAssertEqual(
                        committedText,
                        expected,
                        "profile=\(profile) genZ=\(genZ): commitWord() for '\(input)' must keep '\(expected)'"
                    )
                    XCTAssertFalse(
                        isOverride,
                        "profile=\(profile) genZ=\(genZ): commitWord() for '\(input)' must not override to English"
                    )
                }
            }
        }

        // Also verify VNI free-order: cu7u1, cuu71, cuu17 -> cứu
        let vniEngine = VietnameseEngine()
        vniEngine.inputMethod = .vni
        XCTAssertEqual(vniEngine.transform(Array("cu7u1")), "cứu")
        XCTAssertEqual(vniEngine.transform(Array("cuu71")), "cứu")
        XCTAssertEqual(vniEngine.transform(Array("cuu17")), "cứu")
    }

    func testVUISPostCodaModifierUndoAndMultiOrderTelex() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let session = InputSessionManager()
            session.setGrammarProfile(profile)
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true

            // 1. Multi-order Telex target cases (Classic + VUIS)
            var multiOrderCases: [(String, String)] = [
                ("rinhr", "rỉnh"),
                ("rirnh", "rỉnh"),
                ("thuongwr", "thưởng"),
                ("thuowrng", "thưởng"),
                ("thuowngr", "thưởng"),
                ("thuwongr", "thưởng"),
                ("thuwowngr", "thưởng"),
                ("truongwr", "trưởng"),
                ("truowrng", "trưởng"),
                ("truowngr", "trưởng"),
                ("truwongr", "trưởng"),
                ("truwowngr", "trưởng"),
                ("dduwocj", "được"),
                ("nuwocs", "nước"),
                ("nguwoif", "người"),
                ("ruouwj", "rượu"),
                ("buouws", "bướu"),
                ("huouw", "hươu"),
                ("dodongf", "đồng"),
                ("doongfd", "đồng"),
                ("doongdf", "đồng"),
                ("dudowcj", "được"),
                ("duowcjd", "được"),
                ("dinhjd", "định"),
                ("dadauf", "đầu"),
                ("dedens", "đến"),
                ("nhaanj", "nhận"),
                ("nhanaj", "nhận"),
                ("tieengs", "tiếng"),
                ("tieesng", "tiếng")
            ]
            if profile != .classic {
                multiOrderCases.append(contentsOf: [
                    ("rrinh", "rỉnh"),
                    ("ssinh", "sính"),
                    ("Ssinh", "Sính"),
                    ("ssanh", "sánh"),
                    ("sfinh", "sình"),
                    ("srinh", "sỉnh"),
                    ("ssan", "sán"),
                    ("sfan", "sàn"),
                    ("sxung", "sũng"),
                    ("sjan", "sạn"),
                    ("ssao", "sáo"),
                    ("xxinh", "xĩnh"),
                    ("xsinh", "xính"),
                    ("lsinh", "lính"),
                    ("hfinh", "hình"),
                    ("ksinh", "kính"),
                    ("bsinh", "bính"),
                    ("dsinh", "dính"),
                    ("vxinh", "vĩnh"),
                    ("chsinh", "chính"),
                    ("nhsinh", "nhính"),
                    ("khrinh", "khỉnh"),
                    ("phsinh", "phính"),
                    ("ghsinh", "ghính"),
                    ("nghxinh", "nghĩnh"),
                    ("sswuong", "sướng"),
                    ("swsuong", "sướng"),
                    ("thrwuong", "thưởng")
                ])
            }

            for (input, expected) in multiOrderCases {
                session.reset()
                for ch in input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(
                    session.currentOutput(),
                    expected,
                    "profile=\(profile): inline output for '\(input)' must be '\(expected)'"
                )
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(input)'")
                }
                XCTAssertEqual(committedText, expected, "profile=\(profile): commitWord() for '\(input)'")
                XCTAssertFalse(isOverride, "profile=\(profile): '\(input)' must not be overridden as English")
            }

            // 2. Post-coda modifier semantic saturation + literal fallback, vowel reshape, and trailing vowel extension (no raw Telex keystroke leak!)
            var postCodaCases: [(String, String)] = [
                // nhận + a -> nhậna (semantic saturation + literal fallback, never raw nhaanja)
                ("nhaanja", "nhậna"),
                ("nhanaja", "nhậna"),
                ("nhaanjra", "nhẩna"),
                // thưởng + w -> thưởngw (semantic saturation + literal fallback)
                ("thuongwrw", "thưởngw"),
                ("thuowngrw", "thưởngw"),
                ("thuowrngw", "thưởngw"),
                ("thuwongrw", "thưởngw"),
                ("thuwowngrw", "thưởngw"),
                // thưởng + o -> thuổng, thưởng + oo -> thuổngo
                ("thuongwro", "thuổng"),
                ("thuowngro", "thuổng"),
                ("thuongwroo", "thuổngo"),
                ("thuwongro", "thuổng"),
                ("thuwowngro", "thuổng"),
                // thưởng + u -> thưởngu (never thuonwrgu)
                ("thuonwrgu", "thưởngu"),
                ("thuongwru", "thưởngu"),
                ("thuowngru", "thưởngu"),
                // trưởng + o / oo / w / u -> truổng / truổngo / trưởngw / trưởngu
                ("truowngro", "truổng"),
                ("truongwro", "truổng"),
                ("truwongro", "truổng"),
                ("truwowngro", "truổng"),
                ("truongwroo", "truổngo"),
                ("truowngrw", "trưởngw"),
                ("truongwrw", "trưởngw"),
                ("truwongrw", "trưởngw"),
                ("truwowngrw", "trưởngw"),
                ("truowngru", "trưởngu"),
                ("truongwru", "trưởngu"),
                // nước / được / phượng + o -> nuốc / đuộc / phuộng
                ("nuowcso", "nuốc"),
                ("nuwocso", "nuốc"),
                ("dduowcjo", "đuộc"),
                ("dduwocjo", "đuộc"),
                ("phuowngjo", "phuộng"),
                // tiếng / việc / bệnh / mệnh / miệng + e -> tiếnge / việce / bệnhe / mệnhe / miệnge (semantic saturation)
                ("tieengse", "tiếnge"),
                ("tieesnge", "tiếnge"),
                ("vieecje", "việce"),
                ("beenhje", "bệnhe"),
                ("meenhje", "mệnhe"),
                ("meenjhe", "mệnhe"),
                ("mieengje", "miệnge"),
                ("mieenjge", "miệnge"),
                // muốn / cuộc / huống + o -> muốno / cuộco / huốngo (semantic saturation)
                ("muoonso", "muốno"),
                ("cuoocjo", "cuộco"),
                ("huoongso", "huốngo"),
                ("huoosngo", "huốngo"),
                // sớm / cửa / mưa / rượu / người + w / o / u
                ("sowmsw", "sớmw"),
                ("cuwarw", "cửaw"),
                ("muwaw", "mưaw"),
                ("ruouwjw", "rượuw"),
                ("ruouwjo", "ruộu"),
                ("ruouwju", "rượuu"),
                ("nguowifw", "ngườiw"),
                ("nguowifo", "nguồi"),
                ("nguowifu", "ngườiu"),
                // Semivowel-offglide circumflex saturation: tuổi + o -> tuổio, nhiều + e -> nhiềue, đầu + a -> đầua, thấy + a -> thấya, tối + o -> tốio, nếu + e -> nếue
                ("tuooiro", "tuổio"),
                ("nhieeufe", "nhiềue"),
                ("ddaaufa", "đầua"),
                ("thaaysa", "thấya"),
                ("tooiso", "tốio"),
                ("neeuse", "nếue"),
                // nhện + e -> nhệne, mếm + e -> mếme, mồng + o -> mồngo
                ("nheejne", "nhệne"),
                ("nheenje", "nhệne"),
                ("meemse", "mếme"),
                ("moongfo", "mồngo"),
                // Multi-order & repeated modifiers matrix
                ("Truowngrw", "Trưởngw"),
                ("keenhe", "kênhe"),
                ("hoongfo", "hồngo"),
                ("hoonfgo", "hồngo"),
                ("kinhsi", "kínhi"),
                ("kisnhi", "kínhi"),
                ("muwngfu", "mừngu"),
                ("mungwfu", "mừngu"),
                ("dduowngfu", "đườngu"),
                ("dduongwfu", "đườngu"),
                ("dduowngfo", "đuồng"),
                ("dduongwfo", "đuồng"),
                ("dduongwfoo", "đuồngo"),
                ("truonwgfswo", "trướngwo"),
                ("truowngfxwf", "trưỡngwf"),
                ("congror", "cổngr"),
                // Related toned coda syllables without w/dd/aa/ee/oo
                ("tinhsi", "tínhi"),
                ("minhfi", "mìnhi"),
                ("chungsu", "chúngu"),
                ("cungxu", "cũngu"),
                ("quynhfy", "quỳnhy"),
                ("lamfi", "làmi"),
                ("hocja", "họca")
            ]
            if profile != .classic {
                postCodaCases.append(contentsOf: [
                    ("thrwuongw", "thưởngw"),
                    ("thrwuongo", "thuổng"),
                    ("thrwuongoo", "thuổngo"),
                    ("thrwuongu", "thưởngu")
                ])
            }

            for (input, expected) in postCodaCases {
                session.reset()
                for ch in input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(
                    session.currentOutput(),
                    expected,
                    "profile=\(profile): inline output for '\(input)' must be '\(expected)' (never raw keystroke dump)"
                )
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(input)'")
                }
                XCTAssertEqual(
                    committedText,
                    expected,
                    "profile=\(profile): commitWord() for '\(input)' must preserve '\(expected)'"
                )
                XCTAssertFalse(isOverride, "profile=\(profile): '\(input)' must not override to raw buffer")
            }

            // 3. Sticky post-coda consonant overflow & stop-coda tone lock (UkEngine CharForm = NonVn parity):
            //    - 'hieernt' -> 'hiểnt' (never explodes to 'hieernt')
            //    - 'hij' -> 'hị' (complete 6-tone 'hi' paradigm)
            //    - 'hieernthij' -> 'hiểnthij' (missed space in 'hiển thị': trailing 'j' never mutates 'hiển' into 'hiệnthi')
            //    - 'dduowcjrooif' -> 'đượcrooif' ('r' rejected on stop coda '-c', locking 'được' + literal 'rooif')
            //    - 'vieecjlamf' -> 'việclamf' (locks 'việc' + literal 'lamf')
            let stickyOverflowCases: [(String, String)] = [
                ("hij", "hị"),
                ("hieernt", "hiểnt"),
                ("Hieernt", "Hiểnt"),
                ("hieernthij", "hiểnthij"),
                ("vieecjg", "việcg"),
                ("vieecjlamf", "việclamf"),
                ("dduowcjk", "đượck"),
                ("dduowcjrooif", "đượcrooif"),
                ("tieengsv", "tiếngv"),
                ("truowngrk", "trưởngk"),
                ("dduowngft", "đườngt"),
                ("muwngfk", "mừngk"),
                ("nhaanst", "nhấnt")
            ]

            for (input, expected) in stickyOverflowCases {
                session.reset()
                for ch in input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(
                    session.currentOutput(),
                    expected,
                    "profile=\(profile): sticky overflow inline output for '\(input)' must be '\(expected)'"
                )
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(input)'")
                }
                XCTAssertEqual(
                    committedText,
                    expected,
                    "profile=\(profile): sticky overflow commitWord() for '\(input)' must preserve '\(expected)'"
                )
                XCTAssertFalse(isOverride, "profile=\(profile): '\(input)' must not override to raw buffer")
            }
        }
    }

    func testChuanAndPhonotacticToneGapFamiliesNoJumpingOrClumping() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(profile)
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true

            // 1. All 6 tones on "chuân" ("chuaan", "chuaans", "chuaanx", "chuaanf", "chuaanj", "chuaanr")
            //    and similar syllable families where TuDien.txt only lists a subset of tones ("khuân", "nhuân", "thuân", "luân", "xuân", "huân", "truân")
            var toneGapCases: [(String, String)] = [
                ("chuaan", "chuân"),
                ("chuaans", "chuấn"),
                ("chuaanx", "chuẫn"),
                ("chuaanf", "chuần"),
                ("chuaanj", "chuận"),
                ("chuaanr", "chuẩn"),
                ("chuana", "chuân"),
                ("chuanas", "chuấn"),
                ("chuanax", "chuẫn"),
                ("chuanaf", "chuần"),
                ("chuanaj", "chuận"),
                ("chuanar", "chuẩn"),
                ("chuansa", "chuấn"),
                ("chuanxa", "chuẫn"),
                ("chuanfa", "chuần"),
                ("chuanja", "chuận"),
                ("chuanra", "chuẩn"),
                ("khuaan", "khuân"),
                ("khuaans", "khuấn"),
                ("khuaanx", "khuẫn"),
                ("khuaanf", "khuần"),
                ("khuaanj", "khuận"),
                ("khuaanr", "khuẩn"),
                ("nhuaan", "nhuân"),
                ("nhuaans", "nhuấn"),
                ("nhuaanx", "nhuẫn"),
                ("nhuaanf", "nhuần"),
                ("nhuaanj", "nhuận"),
                ("nhuaanr", "nhuẩn"),
                ("thuaan", "thuân"),
                ("thuaans", "thuấn"),
                ("thuaanr", "thuẩn"),
                ("luaanx", "luẫn"),
                ("luaanf", "luần"),
                ("xuaans", "xuấn"),
                ("xuaanf", "xuần"),
                ("xuaanx", "xuẫn"),
                ("xuaanj", "xuận"),
                // Double-tap tone cancellation on modified Vietnamese stems (must keep â/ê/ô/ư/ơ/đ, never explode to aa/ee/oo/uw/ow/dd)
                ("chuaanss", "chuâns"),
                ("chuaanxx", "chuânx"),
                ("chuaanff", "chuânf"),
                ("chuaanjj", "chuânj"),
                ("chuaanrr", "chuânr"),
                ("tieengss", "tiêngs"),
                ("buoonff", "buônf"),
                ("caayss", "câys"),
                // Explicit 'z' tone clear on modified Vietnamese stems
                ("chuaansz", "chuân"),
                ("chuaanxz", "chuân"),
                ("chuaanfz", "chuân"),
                ("chuaanjz", "chuân"),
                ("chuaanrz", "chuân"),
                ("tieengsz", "tiêng"),
                // Post-coda circumflex saturation & literal append on "chuân" / "chuấn" / "chuẩn"
                ("chuaana", "chuâna"),
                ("chuaansa", "chuấna"),
                ("chuaanra", "chuẩna"),
                ("chuaanaa", "chuânaa"),
                ("chuaansaa", "chuấnaa"),
                ("chuaanraa", "chuẩnaa"),
                // Sticky overflow after "chuân" / "chuấn" / "chuẩn"
                ("chuaant", "chuânt"),
                ("chuaanst", "chuấnt"),
                ("chuaanrt", "chuẩnt")
            ]

            if profile != .classic {
                toneGapCases.append(contentsOf: [
                    ("chuaasn", "chuấn"),
                    ("chuaaxn", "chuẫn"),
                    ("chuaafn", "chuần"),
                    ("chuaajn", "chuận"),
                    ("chuaarn", "chuẩn")
                ])
            }

            for (input, expected) in toneGapCases {
                session.reset()
                for ch in input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(
                    session.currentOutput(),
                    expected,
                    "profile=\(profile): inline output for '\(input)' must be '\(expected)'"
                )
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(input)'")
                }
                XCTAssertEqual(
                    committedText,
                    expected,
                    "profile=\(profile): commitWord() for '\(input)' must preserve '\(expected)'"
                )
                XCTAssertFalse(isOverride, "profile=\(profile): '\(input)' must not override to raw buffer")
            }

            // 2. Sequential tone cycling on "chuân" (s -> x -> f -> j -> r -> s) must smoothly replace the tone mark
            //    at every single keystroke without ever jumping to raw "chuaansxfj..."
            session.reset()
            for ch in "chuaan" {
                _ = session.handleCharacter(ch)
            }
            XCTAssertEqual(session.currentOutput(), "chuân")

            let toneCycle: [(Character, String)] = [
                ("s", "chuấn"),
                ("x", "chuẫn"),
                ("f", "chuần"),
                ("j", "chuận"),
                ("r", "chuẩn"),
                ("s", "chuấn"),
                ("r", "chuẩn")
            ]
            for (toneKey, expectedWord) in toneCycle {
                _ = session.handleCharacter(toneKey)
                XCTAssertEqual(
                    session.currentOutput(),
                    expectedWord,
                    "profile=\(profile): cycling tone '\(toneKey)' on 'chuân' must render '\(expectedWord)' without character jumping"
                )
            }
        }
    }

    func testGenZFreeOrderTypingSuite() {
        for profile in [GrammarProfile.senFlex, .smartHybrid] {
            let session = InputSessionManager()
            session.setGrammarProfile(profile)
            session.setGenZMode(true)
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true

            let telexCases: [(input: String, expected: String)] = [
                // 1. fải (all keystroke orders)
                ("fair", "fải"),
                ("fari", "fải"),
                ("frai", "fải"),
                ("Fair", "Fải"),
                // 2. wá & w-initial Gen-Z words (all keystroke orders)
                ("was", "wá"),
                ("wsa", "wá"),
                ("wwas", "wá"),
                ("Was", "Wá"),
                ("war", "wả"),
                ("wra", "wả"),
                ("waf", "wà"),
                ("wfa", "wà"),
                ("wax", "wã"),
                ("wxa", "wã"),
                ("waj", "wạ"),
                ("wja", "wạ"),
                ("wans", "wán"),
                ("wasn", "wán"),
                ("wsan", "wán"),
                ("wais", "wái"),
                ("wsai", "wái"),
                ("waayj", "wậy"),
                ("wayaj", "wậy"),
                ("waajy", "wậy"),
                ("wjaay", "wậy"),
                ("wees", "wế"),
                ("wsee", "wế"),
                ("wys", "wý"),
                ("wsy", "wý"),
                // 3. zẻ (all keystroke orders)
                ("zer", "zẻ"),
                ("zre", "zẻ"),
                ("Zer", "Zẻ"),
                // 4. zời (all 12 free-order permutations of z + o/i + w + f)
                ("zowif", "zời"),
                ("zowfi", "zời"),
                ("zoiwf", "zời"),
                ("zoifw", "zời"),
                ("zofwi", "zời"),
                ("zofiw", "zời"),
                ("zwoif", "zời"),
                ("zwofi", "zời"),
                ("zwfoi", "zời"),
                ("zfwoi", "zời"),
                ("zfowi", "zời"),
                ("zfoiw", "zời"),
                ("Zowif", "Zời"),
                // 5. zé (all keystroke orders)
                ("zes", "zé"),
                ("zse", "zé"),
                ("Zes", "Zé"),
                // 6. zậy (all 7 free-order permutations)
                ("zaayj", "zậy"),
                ("zaajy", "zậy"),
                ("zayaj", "zậy"),
                ("zayja", "zậy"),
                ("zajay", "zậy"),
                ("zjaay", "zậy"),
                ("zjaya", "zậy"),
                ("Zaayj", "Zậy"),
                // 7. zúp (all keystroke orders)
                ("zups", "zúp"),
                ("zusp", "zúp"),
                ("zsup", "zúp"),
                ("Zups", "Zúp"),
                // 8. Additional common Gen-Z syllables
                ("zif", "zì"),
                ("zfi", "zì"),
                ("fongf", "fòng"),
                ("ffong", "fòng"),
                ("faans", "fấn"),
                ("fanas", "fấn"),
                ("fsaan", "fấn"),
                ("jowf", "jờ"),
                ("jwof", "jờ"),
                ("jfow", "jờ"),
                ("jups", "júp"),
                ("jsup", "júp"),
                ("zaats", "zất"),
                ("zsaat", "zất")
            ]

            for (input, expected) in telexCases {
                session.reset()
                for ch in input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(
                    session.currentOutput(),
                    expected,
                    "profile=\(profile): Gen-Z inline output for '\(input)' must be '\(expected)'"
                )
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected commit for '\(input)'")
                }
                XCTAssertEqual(
                    committedText,
                    expected,
                    "profile=\(profile): Gen-Z commitWord() for '\(input)' must preserve '\(expected)'"
                )
                XCTAssertFalse(
                    isOverride,
                    "profile=\(profile): Gen-Z commitWord() for '\(input)' must not revert to raw English"
                )
            }

            // VNI Gen-Z verification
            session.setInputMethod(.vni)
            let vniCases: [(input: String, expected: String)] = [
                ("fai3", "fải"),
                ("fa3i", "fải"),
                ("wa1", "wá"),
                ("ze3", "zẻ"),
                ("zo72i", "zời"),
                ("zoi72", "zời"),
                ("ze1", "zé"),
                ("za65y", "zậy"),
                ("zay65", "zậy"),
                ("zup1", "zúp"),
                ("zu1p", "zúp")
            ]
            for (input, expected) in vniCases {
                session.reset()
                for ch in input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(session.currentOutput(), expected, "VNI Gen-Z inline for '\(input)'")
                guard case let .commit(_, committedText, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                    return XCTFail("Expected VNI commit for '\(input)'")
                }
                XCTAssertEqual(committedText, expected, "VNI Gen-Z commit for '\(input)'")
                XCTAssertFalse(isOverride)
            }
        }
    }
}
