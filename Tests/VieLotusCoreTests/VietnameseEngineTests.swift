import XCTest
@testable import VieLotusCore

final class VietnameseEngineTests: XCTestCase {
    func testTelexBasicTransform() {
        let engine = VietnameseEngine()
        engine.inputMethod = .telex

        let inputs = ["t", "o", "o", "i"]
        for char in inputs {
            _ = engine.feed(Character(char))
        }
        XCTAssertEqual(engine.currentOutput(), "tôi")
    }

    func testVniBasicTransform() {
        let engine = VietnameseEngine()
        engine.inputMethod = .vni

        let inputs = ["t", "o", "i", "6"]
        for char in inputs {
            _ = engine.feed(Character(char))
        }
        XCTAssertEqual(engine.currentOutput(), "tôi")
    }

    func testToneCancellation() {
        let engine = VietnameseEngine()
        engine.inputMethod = .telex

        let inputs = ["t", "o", "a", "n", "s"]
        for char in inputs { _ = engine.feed(Character(char)) }
        XCTAssertEqual(engine.currentOutput(), "toán")

        // Repeating the same tone key ('s') cancels the acute tone and restores the literal key ('toans')
        _ = engine.feed("s")
        XCTAssertEqual(engine.currentOutput(), "toans")

        // In Telex, typing 'z' cancels the active diacritic back to base ('toan')
        let engineZ = VietnameseEngine()
        engineZ.inputMethod = .telex
        for char in ["t", "o", "a", "n", "s", "z"] { _ = engineZ.feed(Character(char)) }
        XCTAssertEqual(engineZ.currentOutput(), "toan")
    }

    func testToneKeyCanAppearBeforeFinalConsonant() {
        for input in ["toost", "toots"] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), "tốt", input)
        }
    }

    func testFreeToneWProducesChuongInEitherPosition() {
        for input in ["chuongw", "chuowng"] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), "chương", input)
        }
    }

    func testTripleWAtWordStartIsLiteralWebPrefix() {
        for (input, expected) in [("w", "w"), ("W", "W"), ("ww", "ww"), ("www", "www"), ("wwww", "wwww")] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), expected, input)
        }
    }

    func testRepeatedToneKeysCanEscapeEnglishSAndR() {
        for (input, expected) in [("usserr", "user"), ("usserrss", "users")] {
            let engine = VietnameseEngine()
            for char in input { _ = engine.feed(char) }
            XCTAssertEqual(engine.currentOutput(), expected, input)
        }
    }

    func testBackspaceRecomputesCompositionFromRemainingRawKeys() {
        let session = InputSessionManager()
        for character in "ddoois" {
            _ = session.handleCharacter(character)
        }
        XCTAssertEqual(session.currentOutput(), "đối")

        var outputs: [String] = []
        for _ in 0..<6 {
            _ = session.handleBackspace()
            outputs.append(session.currentOutput())
        }
        XCTAssertEqual(outputs, ["đôi", "đoi", "đo", "đ", "d", ""])

        // Verify re-typing after semantic backspace on "đối" -> "đôi" -> "đoi" -> "đo" -> "đ" -> "đi"
        for character in "ddoois" {
            _ = session.handleCharacter(character)
        }
        _ = session.handleBackspace()
        XCTAssertEqual(session.currentOutput(), "đôi")
        _ = session.handleBackspace()
        XCTAssertEqual(session.currentOutput(), "đoi")
        _ = session.handleBackspace()
        XCTAssertEqual(session.currentOutput(), "đo")
        _ = session.handleCharacter("m")
        XCTAssertEqual(session.currentOutput(), "đom")

        // Backspace down to "đ", then type "i" -> "đi"
        _ = session.handleBackspace()
        _ = session.handleBackspace()
        XCTAssertEqual(session.currentOutput(), "đ")
        _ = session.handleCharacter("i")
        XCTAssertEqual(session.currentOutput(), "đi")
    }

    func testBackspaceThatChangesNoVisibleTextKeepsCompositionActive() {
        let session = InputSessionManager()
        session.smartBilingualEnabled = false
        for character in "ass" {
            _ = session.handleCharacter(character)
        }
        XCTAssertEqual(session.currentOutput(), "as")

        let action = session.handleBackspace()
        guard case let .replace(backspaces, text) = action else {
            return XCTFail("Expected the last visible character 's' to be removed")
        }
        XCTAssertEqual(backspaces, 1)
        XCTAssertEqual(text, "")
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.rawWord, "a")
        XCTAssertEqual(session.currentOutput(), "a")

        let resetAction = session.handleBackspace()
        guard case .reset = resetAction else {
            return XCTFail("Expected .reset when deleting the last character")
        }
        XCTAssertEqual(session.currentOutput(), "")
    }

    func testWordCommitOnNewlineWithoutSpaceInInputSessionManager() {
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        for char in "vieejt" {
            _ = session.handleCharacter(char)
        }
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "việt")

        // Simulate Shift+Enter / Return (\n) boundary
        XCTAssertTrue(session.isWordBoundary("\n"))
        let action = session.commitWord(smartBilingualEnabled: true)
        guard case let .commit(_, text, isOverride) = action else {
            return XCTFail("Expected commit action on newline")
        }
        XCTAssertEqual(text, "việt")
        XCTAssertFalse(isOverride)
        XCTAssertFalse(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "")
    }

    func testEnglishWordRestoreOnNewlineWithoutSpace() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        for char in "there" {
            _ = session.handleCharacter(char)
        }
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "thẻe")

        // Simulate Shift+Enter / Return (\n) boundary
        XCTAssertTrue(session.isWordBoundary("\n"))
        let action = session.commitWord(smartBilingualEnabled: true)
        guard case let .commit(_, text, isOverride) = action else {
            return XCTFail("Expected commit action on newline")
        }
        XCTAssertEqual(text, "there")
        XCTAssertTrue(isOverride)
        XCTAssertFalse(session.isComposing)
    }

    func testVniWordCommitOnNewlineWithoutSpace() {
        let session = InputSessionManager()
        session.setInputMethod(.vni)
        for char in "viet65" {
            _ = session.handleCharacter(char)
        }
        XCTAssertTrue(session.isComposing)
        XCTAssertEqual(session.currentOutput(), "việt")

        XCTAssertTrue(session.isWordBoundary("\n"))
        let action = session.commitWord(smartBilingualEnabled: true)
        guard case let .commit(_, text, isOverride) = action else {
            return XCTFail("Expected commit action on newline")
        }
        XCTAssertEqual(text, "việt")
        XCTAssertFalse(isOverride)
        XCTAssertFalse(session.isComposing)
    }

    func testPartialDeletionPrefixRetentionAndResumeComposition() {
        // Test case 1: "đổi" deleted back to "đ", then typing "uocwj" -> "được"
        let engine1 = VietnameseEngine()
        engine1.setCompositionPrefix("đ")
        XCTAssertEqual(engine1.currentOutput(), "đ")
        for char in "uocwj" {
            _ = engine1.feed(char)
        }
        XCTAssertEqual(engine1.currentOutput(), "được")

        // Test case 2: "trường" deleted back to "tr", then typing "uowngr" -> "trưởng"
        let engine2 = VietnameseEngine()
        engine2.setCompositionPrefix("tr")
        XCTAssertEqual(engine2.currentOutput(), "tr")
        for char in "uowngr" {
            _ = engine2.feed(char)
        }
        XCTAssertEqual(engine2.currentOutput(), "trưởng")

        // Test case 3: "những" deleted back to "nh", then typing "unwg" -> "nhưng"
        let engine3 = VietnameseEngine()
        engine3.setCompositionPrefix("nh")
        XCTAssertEqual(engine3.currentOutput(), "nh")
        for char in "unwg" {
            _ = engine3.feed(char)
        }
        XCTAssertEqual(engine3.currentOutput(), "nhưng")

        // Test case 4: "thể" deleted back to "th", then typing "ieenf" -> "thiền"
        let engine4 = VietnameseEngine()
        engine4.setCompositionPrefix("th")
        XCTAssertEqual(engine4.currentOutput(), "th")
        for char in "ieenf" {
            _ = engine4.feed(char)
        }
        XCTAssertEqual(engine4.currentOutput(), "thiền")

        // Test case 5: "thụ" deleted back to "th", then typing "ungx" -> "thũng"
        let engine5 = VietnameseEngine()
        engine5.setCompositionPrefix("th")
        XCTAssertEqual(engine5.currentOutput(), "th")
        for char in "ungx" {
            _ = engine5.feed(char)
        }
        XCTAssertEqual(engine5.currentOutput(), "thũng")
    }

    func testRawKeysForVietnamesePrefixes() {
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "đ", inputMethod: .telex), "dd")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "đ", inputMethod: .vni), "d9")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "tr", inputMethod: .telex), "tr")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "nh", inputMethod: .telex), "nh")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "th", inputMethod: .telex), "th")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "toá", inputMethod: .telex), "toas")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "toá", inputMethod: .vni), "toa1")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "trưởng", inputMethod: .telex), "truowngr")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "trưởng", inputMethod: .vni), "truo7ng3")
        XCTAssertEqual(VietnameseEngine.rawKeys(for: "được", inputMethod: .telex), "dduowcj")
    }

    func testPostCommitWordReactivationToneChange() {
        let engine = VietnameseEngine()
        for c in "ddoori" { _ = engine.feed(c) }
        XCTAssertEqual(engine.currentOutput(), "đổi")
        _ = engine.commit()
        XCTAssertFalse(engine.isComposing)

        // User typed Backspace (deleting space), now types 'f' (dấu huyền)
        let diffF = engine.editAt(caretBack: 0, char: "f")
        XCTAssertNotNil(diffF)
        XCTAssertEqual(engine.currentOutput(), "đồi")
        XCTAssertTrue(engine.isComposing)

        // Continue modifying while session is resurrected: type 's' -> 'đối'
        _ = engine.feed("s")
        XCTAssertEqual(engine.currentOutput(), "đối")

        // Type 'j' -> 'đội'
        _ = engine.feed("j")
        XCTAssertEqual(engine.currentOutput(), "đội")

        // Type 'z' -> 'đôi' (xóa dấu)
        _ = engine.feed("z")
        XCTAssertEqual(engine.currentOutput(), "đôi")
    }

    func testPostCommitWordReactivationMultiBackspace() {
        let engine = VietnameseEngine()
        for c in "ddoori" { _ = engine.feed(c) }
        XCTAssertEqual(engine.currentOutput(), "đổi")
        _ = engine.commit()

        // Backspace into committed word: 'đổi' -> 'đổ'
        let diffBs = engine.editBackspaceAt(caretBack: 0)
        XCTAssertNotNil(diffBs)
        XCTAssertEqual(engine.currentOutput(), "đổ")
        XCTAssertTrue(engine.isComposing)

        // Now type 'm' -> 'đổm'
        _ = engine.feed("m")
        XCTAssertEqual(engine.currentOutput(), "đổm")
        _ = engine.commit()

        // Word where tone key was typed last: "toans" -> "toán"
        for c in "toans" { _ = engine.feed(c) }
        XCTAssertEqual(engine.currentOutput(), "toán")
        _ = engine.commit()

        // Backspace into committed word deletes 'n' (not tone 's'): "toán" -> "toá"
        let diffBs2 = engine.editBackspaceAt(caretBack: 0)
        XCTAssertNotNil(diffBs2)
        XCTAssertEqual(engine.currentOutput(), "toá")
        XCTAssertTrue(engine.isComposing)

        // Type 'm' -> "toám"
        _ = engine.feed("m")
        XCTAssertEqual(engine.currentOutput(), "toám")
    }

    func testInputSessionManagerPostCommitWordReactivation() {
        let session = InputSessionManager()
        for c in "ddoori" { _ = session.handleCharacter(c) }
        XCTAssertEqual(session.composingWord, "đổi")

        // User commits with space
        guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected commit")
        }
        XCTAssertEqual(committed, "đổi")
        XCTAssertFalse(session.isComposing)

        // User hits Backspace once (deleting space)
        let bsAction = session.handleBackspace()
        guard case .passThrough = bsAction else {
            return XCTFail("Expected .passThrough on idle backspace")
        }
        XCTAssertFalse(session.isComposing)

        // User types 'f' -> modifies 'đổi' to 'đồi'
        let editAction = session.handleCharacter("f")
        guard case let .replace(backspaces, _) = editAction else {
            return XCTFail("Expected .replace action on post-commit edit")
        }
        XCTAssertTrue(backspaces > 0)
        XCTAssertEqual(session.composingWord, "đồi")
        XCTAssertTrue(session.isComposing)

        // User types 's' -> changes to 'đối'
        _ = session.handleCharacter("s")
        XCTAssertEqual(session.composingWord, "đối")

        // User commits with space again
        guard case let .commit(_, committed2, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected second commit")
        }
        XCTAssertEqual(committed2, "đối")
    }

    func testInputSessionManagerVniPostCommitWordReactivation() {
        let session = InputSessionManager()
        session.engine.setInputMethod(.vni)
        for c in "d9o6i3" { _ = session.handleCharacter(c) }
        XCTAssertEqual(session.composingWord, "đổi")

        // Commit with space
        guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected VNI commit")
        }
        XCTAssertEqual(committed, "đổi")

        // Backspace deletes space
        _ = session.handleBackspace()

        // Type '2' (huyền) -> 'đồi'
        let editAction = session.handleCharacter("2")
        guard case .replace = editAction else {
            return XCTFail("Expected .replace on VNI edit")
        }
        XCTAssertEqual(session.composingWord, "đồi")
    }

    func testPostCommitToneReplacementInSmartHybrid() {
        let session = InputSessionManager()
        session.setGrammarProfile(.smartHybrid)

        // 1. Type "cas" -> "cá"
        for c in "cas" { _ = session.handleCharacter(c) }
        XCTAssertEqual(session.composingWord, "cá")

        // User commits with space: "cá "
        guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected commit")
        }
        XCTAssertEqual(committed, "cá")
        XCTAssertFalse(session.isComposing)

        // User hits Backspace once (deleting space)
        let bsAction = session.handleBackspace()
        guard case .passThrough = bsAction else {
            return XCTFail("Expected .passThrough on idle backspace")
        }
        XCTAssertFalse(session.isComposing)

        // User types 'f' (huyền) -> replaces tone on 'cá' to 'cà'
        let editAction = session.handleCharacter("f")
        guard case let .replace(backspaces, replacement) = editAction else {
            return XCTFail("Expected .replace action on post-commit edit")
        }
        XCTAssertEqual(backspaces, 2, "Must backspace entire word 'cá' (length 2)")
        XCTAssertEqual(replacement, "cà", "Must replace with 'cà'")
        XCTAssertEqual(session.composingWord, "cà")
        XCTAssertTrue(session.isComposing)

        // User types 's' (sắc) -> replaces tone on 'cà' to 'cá'
        _ = session.handleCharacter("s")
        XCTAssertEqual(session.composingWord, "cá")

        // User types 'z' -> removes tone on 'cá' to 'ca'
        _ = session.handleCharacter("z")
        XCTAssertEqual(session.composingWord, "ca")

        // User commits with space
        guard case let .commit(_, committedFinal, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected commit")
        }
        XCTAssertEqual(committedFinal, "ca")
    }

    func testToneReplacementInGrammarParser() {
        let hybrid = GrammarProfile.smartHybrid
        let parser = InputGrammarParser.shared

        // casf -> cà (tone acute replaced by grave)
        XCTAssertEqual(parser.parse(Array("casf"), profile: hybrid).rendered, "cà")

        // gafs -> gá (tone grave replaced by acute)
        XCTAssertEqual(parser.parse(Array("gafs"), profile: hybrid).rendered, "gá")

        // casz -> ca (z removes tone)
        XCTAssertEqual(parser.parse(Array("casz"), profile: hybrid).rendered, "ca")

        // trfwuongr -> trưởng (pre-vowel grave replaced by hook)
        XCTAssertEqual(parser.parse(Array("trfwuongr"), profile: hybrid).rendered, "trưởng")

        // truowngfr -> trưởng (trailing grave replaced by hook)
        XCTAssertEqual(parser.parse(Array("truowngfr"), profile: hybrid).rendered, "trưởng")

        // neeusf -> nều (acute replaced by grave)
        XCTAssertEqual(parser.parse(Array("neeusf"), profile: hybrid).rendered, "nều")
    }

    func testPostCommitBackspaceOnCompoundVowelDoesNotShiftToneOrJump() {
        let engine = EngineBridge()
        for ch in "dduowcj" {
            _ = engine.feed(ch)
        }
        XCTAssertEqual(engine.currentOutput(), "được")
        engine.commitWord(raw: "dduowcj", rendered: "được")
        XCTAssertFalse(engine.isComposing)

        // Stepping back into committed "được" must keep "đượ" (never shift tone to "đựơ")
        let firstBack = engine.editBackspaceAt(caretBack: 0)
        XCTAssertEqual(firstBack?.backspaces, 4)
        XCTAssertEqual(firstBack?.suffix, "đượ")
        XCTAssertEqual(engine.currentOutput(), "đượ")
        XCTAssertTrue(engine.isComposing)

        // Continuing backspace must delete 1 character at a time cleanly
        let secondBack = engine.backspace()
        XCTAssertEqual(secondBack?.backspaces, 1)
        XCTAssertEqual(secondBack?.suffix, "")
        XCTAssertEqual(engine.currentOutput(), "đư")

        let thirdBack = engine.backspace()
        XCTAssertEqual(thirdBack?.backspaces, 1)
        XCTAssertEqual(thirdBack?.suffix, "")
        XCTAssertEqual(engine.currentOutput(), "đ")

        let fourthBack = engine.backspace()
        XCTAssertEqual(fourthBack?.backspaces, 1)
        XCTAssertEqual(fourthBack?.suffix, "")
        XCTAssertEqual(engine.currentOutput(), "")
        XCTAssertFalse(engine.isComposing)

        // Also verify re-typing 'c' after stepping back once into "được" restores "được"
        for ch in "dduowcj" {
            _ = engine.feed(ch)
        }
        engine.commitWord(raw: "dduowcj", rendered: "được")
        _ = engine.editBackspaceAt(caretBack: 0)
        XCTAssertEqual(engine.currentOutput(), "đượ")
        let retyped = engine.feed("c")
        XCTAssertEqual(retyped?.backspaces, 0)
        XCTAssertEqual(retyped?.suffix, "c")
        XCTAssertEqual(engine.currentOutput(), "được")
    }

    func testPostCommitBackspaceAfterEnglishOverrideDoesNotResurrectPreviousWord() {
        let session = InputSessionManager()
        session.smartBilingualEnabled = true

        for ch in "blood" {
            _ = session.handleCharacter(ch)
        }
        _ = session.commitWord(smartBilingualEnabled: true)

        for ch in "restrict" {
            _ = session.handleCharacter(ch)
        }
        guard case let .commit(_, committedSecond, _) = session.commitWord(smartBilingualEnabled: true) else {
            return XCTFail("Expected commit for 'restrict'")
        }
        XCTAssertEqual(committedSecond, "restrict")

        // Backspace #1: delete trailing space
        guard case .passThrough = session.handleBackspace() else {
            return XCTFail("Expected .passThrough on space deletion")
        }

        // Backspace #2: step into "restrict" -> "restric" (never resurrect "blood" -> "bloo")
        guard case let .replace(bs2, text2) = session.handleBackspace() else {
            return XCTFail("Expected .replace on stepping into committed word")
        }
        XCTAssertEqual(bs2, 8)
        XCTAssertEqual(text2, "restric")
        XCTAssertEqual(session.composingWord, "restric")

        // Backspace #3: "restric" -> "restri"
        guard case let .replace(bs3, text3) = session.handleBackspace() else {
            return XCTFail("Expected .replace on subsequent backspace")
        }
        XCTAssertEqual(bs3, 1)
        XCTAssertEqual(text3, "")
        XCTAssertEqual(session.composingWord, "restri")
    }

    func testPostCommitBackspacePreservesEscapedRawKeysAndInlineInflections() {
        for profile in [GrammarProfile.classic, .senFlex, .smartHybrid] {
            let engine = EngineBridge()
            engine.setInputMethod(.telex)
            engine.setGrammarProfile(profile)

            for ch in "hairrs" {
                _ = engine.feed(ch)
            }
            XCTAssertEqual(engine.currentOutput(), "hairs")
            engine.commitWord(raw: "hairrs", rendered: "hairs")

            // Backspace into committed "hairs" -> "hair" must preserve escaped "hairr" raw keys
            let stepBack = engine.editBackspaceAt(caretBack: 0)
            XCTAssertEqual(stepBack?.backspaces, 5)
            XCTAssertEqual(stepBack?.suffix, "hair")
            XCTAssertEqual(engine.rawString(), "hairr")

            // Typing 'y' next must produce "hairy" (not "haỉy")
            _ = engine.feed("y")
            XCTAssertEqual(engine.currentOutput(), "hairy", "Profile \(profile) failed on hairs -> backspace -> y")
        }

        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "restricte", rendered: "retỉcte"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "restricted", rendered: "retictẻd"))
    }

    func testPostCommitEnglishSuffixEditAndInlineInflections() {
        let prevProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = prevProvider }

        let cases: [(stem: String, suffix: String, expected: String)] = [
            ("restrict", "ed", "restricted"),
            ("request", "ed", "requested"),
            ("let", "ter", "letter")
        ]

        for tc in cases {
            let session = InputSessionManager()
            session.smartBilingualEnabled = true
            session.inlineBilingualEnabled = true

            for ch in tc.stem {
                _ = session.handleCharacter(ch)
            }
            _ = session.commitWord(smartBilingualEnabled: true)
            _ = session.handleBackspace() // delete space -> editCaretBack = 0

            for ch in tc.suffix {
                _ = session.handleCharacter(ch)
            }
            XCTAssertEqual(session.currentOutput(), tc.expected, "Failed post-commit suffix edit for \(tc.stem) + \(tc.suffix)")
        }

        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "cores", rendered: "cỏe"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "cored", rendered: "cỏed"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "studies", rendered: "stúdié"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "texted", rendered: "tễtd"))
        XCTAssertTrue(SmartBilingualDetector.isInlineEnglishWord(raw: "released", rendered: "reléaed"))

        // Backspacing through a post-commit inline English word ("restrict" -> Space -> Backspace -> "s" -> "restricts")
        // must delete 1 character at a time ("restrict", "restric", "restri", ...) instead of mutating into "rétic".
        let session = InputSessionManager()
        session.smartBilingualEnabled = true
        session.inlineBilingualEnabled = true
        for ch in "restrict" { _ = session.handleCharacter(ch) }
        _ = session.commitWord(smartBilingualEnabled: true)
        _ = session.handleBackspace()
        _ = session.handleCharacter("s")
        XCTAssertEqual(session.currentOutput(), "restricts")

        let expectedPrefixes = ["restrict", "restric", "restri", "restr", "rest", "res", "re", "r"]
        for expected in expectedPrefixes {
            _ = session.handleBackspace()
            XCTAssertEqual(session.currentOutput(), expected)
            XCTAssertEqual(session.rawWord, expected)
        }
        _ = session.handleBackspace()
        XCTAssertEqual(session.currentOutput(), "")
    }

    func testPostCommitAndPostCodaCircumflexWithTones() {
        for profile in [GrammarProfile.classic, .senFlex, .smartHybrid] {
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(profile)
            session.smartBilingualEnabled = true

            // 1. "nhan" + Space + Backspace + "a" -> "nhân", then + s/f/r/x/j -> nhấn/nhần/nhẩn/nhẫn/nhận
            let nhanToneCases: [(toneKey: Character, expected: String)] = [
                ("s", "nhấn"),
                ("f", "nhần"),
                ("r", "nhẩn"),
                ("x", "nhẫn"),
                ("j", "nhận")
            ]
            for tc in nhanToneCases {
                session.reset()
                for ch in "nhan" { _ = session.handleCharacter(ch) }
                _ = session.commitWord(smartBilingualEnabled: true)
                _ = session.handleBackspace() // delete space

                _ = session.handleCharacter("a")
                XCTAssertEqual(session.currentOutput(), "nhân", "profile=\(profile): nhan + space + bs + a should be nhân")

                _ = session.handleCharacter(tc.toneKey)
                XCTAssertEqual(session.currentOutput(), tc.expected, "profile=\(profile): nhan + space + bs + a + \(tc.toneKey) should be \(tc.expected)")

                // Reverse order after backspace: tone first, then 'a' (e.g. nhan + space + bs + s + a -> nhấn)
                session.reset()
                for ch in "nhan" { _ = session.handleCharacter(ch) }
                _ = session.commitWord(smartBilingualEnabled: true)
                _ = session.handleBackspace()

                _ = session.handleCharacter(tc.toneKey)
                _ = session.handleCharacter("a")
                XCTAssertEqual(session.currentOutput(), tc.expected, "profile=\(profile): nhan + space + bs + \(tc.toneKey) + a should be \(tc.expected)")
            }

            // 2. "them" -> "thềm" and "trong" -> "trồng" (both post-commit and inline free-mark)
            let postCommitWordCases: [(stem: String, suffix: String, expected: String)] = [
                ("them", "ef", "thềm"),
                ("them", "fe", "thềm"),
                ("themf", "e", "thềm"),
                ("trong", "of", "trồng"),
                ("trong", "fo", "trồng"),
                ("trongf", "o", "trồng"),
                ("thef", "e", "thề")
            ]
            for tc in postCommitWordCases {
                session.reset()
                for ch in tc.stem { _ = session.handleCharacter(ch) }
                _ = session.commitWord(smartBilingualEnabled: true)
                _ = session.handleBackspace()
                for ch in tc.suffix { _ = session.handleCharacter(ch) }
                XCTAssertEqual(session.currentOutput(), tc.expected, "profile=\(profile): \(tc.stem) + space + bs + \(tc.suffix) should be \(tc.expected)")
            }

            // 3. Inline post-coda circumflex + cancellation (nhana -> nhân, nhanaa -> nhâna, nhanaaa -> nhânaa, themef -> thềm, themfe -> thềm, trongo -> trông, trongoo -> trôngo, trongooo -> trôngoo)
            // Known English post-coda vowel words (theme, meme, gene, scene, data, photo, moto, goto, mono, momo) remain English inline; adjacent Telex (theem -> thêm, meem -> mêm, geen -> gên) composes Vietnamese.
            let inlineCases: [(input: String, expected: String)] = [
                ("nhana", "nhân"),
                ("nhanas", "nhấn"),
                ("nhansa", "nhấn"),
                ("theem", "thêm"),
                ("theme", "theme"),
                ("meme", "meme"),
                ("gene", "gene"),
                ("data", "data"),
                ("photo", "photo"),
                ("themef", "thềm"),
                ("themfe", "thềm"),
                ("trongo", "trông"),
                ("trongof", "trồng"),
                ("trongfo", "trồng"),
                ("nhanaa", "nhâna"),
                ("nhanaaa", "nhânaa"),
                ("ddeme", "đêm"),
                ("ddemee", "đême"),
                ("ddemeee", "đêmee"),
                ("trongoo", "trôngo"),
                ("trongooo", "trôngoo")
            ]
            for tc in inlineCases {
                session.reset()
                for ch in tc.input { _ = session.handleCharacter(ch) }
                XCTAssertEqual(session.currentOutput(), tc.expected, "profile=\(profile): inline \(tc.input) should be \(tc.expected)")
                guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                    return XCTFail("Expected commit for \(tc.input)")
                }
                XCTAssertEqual(committed, tc.expected, "profile=\(profile): committed \(tc.input) should be \(tc.expected)")
            }
        }
    }

    func testStickyKeyAndMissedSpacePhraseManagement() {
        let session = InputSessionManager()
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            session.setGrammarProfile(profile)
            let phraseCases: [(String, String)] = [
                ("hieernt hij", "hiểnt hị"),
                ("hieernthij", "hiểnthij"),
                ("vieecj lamf", "việc làm"),
                ("vieecjlamf", "việclamf"),
                ("dduowcj rooif", "được rồi"),
                ("dduowcjrooif", "đượcrooif")
            ]
            for (input, expected) in phraseCases {
                session.reset()
                session.context = ""
                var rendered = ""
                for ch in input {
                    if session.isWordBoundary(ch) {
                        if case let .commit(backspaces, text, isOverride) = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch) {
                            if isOverride {
                                rendered.removeLast(min(backspaces, rendered.count))
                                rendered += text
                            }
                        }
                        rendered.append(ch)
                    } else {
                        switch session.handleCharacter(ch) {
                        case let .replace(backspaces, text):
                            if backspaces > 0 { rendered.removeLast(min(backspaces, rendered.count)) }
                            rendered += text
                        case .passThrough:
                            rendered.append(ch)
                        default:
                            break
                        }
                    }
                }
                if session.isComposing {
                    if case let .commit(backspaces, text, isOverride) = session.commitWord(smartBilingualEnabled: true) {
                        if isOverride {
                            rendered.removeLast(min(backspaces, rendered.count))
                            rendered += text
                        }
                    }
                }
                XCTAssertEqual(rendered, expected, "profile=\(profile): phrase '\(input)' must render deterministically as '\(expected)'")
            }
        }
    }

    func testPreVowelModifierPostCommitAndEscapeVariants() {
        let session = InputSessionManager()
        session.inlineBilingualEnabled = true

        for profile in [GrammarProfile.senFlex, .smartHybrid] {
            session.setGrammarProfile(profile)

            // 1. User types "gxo", presses Space (even after English/ASCII context), then Backspace (deletes space) + 'x' -> "gox" (never "gxox")
            session.reset()
            session.clearContext()
            session.appendContext("test")
            session.appendContext("hello")
            for ch in "gxo" {
                _ = session.handleCharacter(ch)
            }
            XCTAssertEqual(session.currentOutput(), "gõ", "profile=\(profile): gxo must compose to gõ")
            guard case let .commit(_, committedGxo, isOverrideGxo) = session.commitWord(smartBilingualEnabled: true) else {
                return XCTFail("Expected commit for gxo")
            }
            XCTAssertFalse(isOverrideGxo, "profile=\(profile): gxo must not be overridden to raw in English context")
            XCTAssertEqual(committedGxo, "gõ")

            // Backspace deletes space and arms editCaretBack = 0
            _ = session.handleBackspace()
            XCTAssertEqual(session.editCaretBack, 0)

            // Pressing 'x' cancels tilde tone on "gõ" -> "gox" (never "gxox")
            let editAction = session.handleCharacter("x")
            guard case let .replace(backspaces, replacement) = editAction else {
                return XCTFail("Expected .replace action when pressing 'x' after gõ + Space + Backspace")
            }
            XCTAssertEqual(backspaces, 2)
            XCTAssertEqual(replacement, "gox", "profile=\(profile): gxo + Space + Backspace + x must produce gox, never gxox")
            guard case let .commit(_, committedGox, _) = session.commitWord(smartBilingualEnabled: true) else {
                return XCTFail("Expected commit for gox")
            }
            XCTAssertEqual(committedGox, "gox")

            // 2. Inline pre-vowel escapes, codas, and open syllables must never jump modifier back before vowel
            let inlineCases: [(input: String, expected: String)] = [
                ("gxox", "gox"),
                ("gxoxx", "goxx"),
                ("gxoz", "go"),
                ("gxoc", "gõc"),
                ("gxon", "gõn"),
                ("gxoi", "gõi"),
                ("cfungf", "cungf"),
                ("ssinhs", "sinhs"),
                ("rrinhr", "rinhr"),
                ("xxinhx", "xinhx"),
                ("ddsons", "đons"),
                ("qfuaf", "quaf"),
                ("gwow", "gơw"),
                ("gwoww", "gơww"),
                ("gwuongw", "gươngw"),
                ("gwuongww", "gươngww"),
                ("cxo", "cõ"),
                ("ssi", "sí"),
                ("gso", "gó"),
                ("goxz", "go"),
                ("ronfz", "ron")
            ]

            for tc in inlineCases {
                session.reset()
                session.clearContext()
                for ch in tc.input {
                    _ = session.handleCharacter(ch)
                }
                XCTAssertEqual(session.currentOutput(), tc.expected, "profile=\(profile): inline \(tc.input) should be \(tc.expected)")
                guard case let .commit(_, committed, _) = session.commitWord(smartBilingualEnabled: true) else {
                    return XCTFail("Expected commit for \(tc.input)")
                }
                XCTAssertEqual(committed, tc.expected, "profile=\(profile): committed \(tc.input) should be \(tc.expected)")
            }
        }
    }

    func testNFDDecomposedPrefixPreservesExactUTF16BackspaceCount() {
        let engine = VietnameseEngine()
        // "tân" in NFD decomposed form: 't' + 'a' + U+0302 (combining circumflex) = 3 UTF-16 code units
        // (whereas NFC "tâ" is only 2 UTF-16 code units).
        let nfdPrefix = "ta\u{0302}"
        XCTAssertEqual(nfdPrefix.utf16.count, 3)

        engine.setCompositionPrefix(nfdPrefix)
        XCTAssertTrue(engine.currentOutput().unicodeScalars.elementsEqual(nfdPrefix.unicodeScalars))

        // Typing 's' to turn "tâ" (NFD, 3 UTF-16) into "tấ" (NFC, 2 UTF-16):
        // Common prefix is 't' (1 UTF-16), so deleted slice on screen is "a\u{0302}" = 2 UTF-16 backspaces!
        let diff = engine.feed("s")
        XCTAssertEqual(diff?.backspaces, 2)
        XCTAssertEqual(diff?.suffix, "ấ")
        XCTAssertEqual(engine.currentOutput(), "tấ")
    }

    func testMachineTypingDetectorDistinguishesHumanFromSyntheticBursts() {
        var detector = MachineTypingDetector()
        var eventSec: TimeInterval = 100.0
        var arrivalNs: UInt64 = 100_000_000_000

        // 1. Fast human typing (40ms per key = 25 keys/sec) never triggers burst mode
        for _ in 0..<20 {
            eventSec += 0.040
            arrivalNs += 40_000_000
            XCTAssertFalse(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false))
        }

        // 2. Short 3-key rollover (<12ms) does not trigger burst mode (requires 6 consecutive intervals)
        for _ in 0..<3 {
            eventSec += 0.004
            arrivalNs += 4_000_000
            XCTAssertFalse(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false))
        }

        // Pause resets streak
        eventSec += 0.050
        arrivalNs += 50_000_000
        XCTAssertFalse(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false))

        // 3. Hardware key repeat (holding down a key) at 5ms never triggers burst mode
        for _ in 0..<10 {
            eventSec += 0.005
            arrivalNs += 5_000_000
            XCTAssertFalse(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: true))
        }

        // 4. Synthetic AI agent / barcode burst: 6+ consecutive non-repeat intervals at 2ms on BOTH clocks
        for step in 1...5 {
            eventSec += 0.002
            arrivalNs += 2_000_000
            XCTAssertFalse(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false), "Step \(step) should not yet enter burst")
        }
        eventSec += 0.002
        arrivalNs += 2_000_000
        XCTAssertTrue(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false), "6th fast interval must enter burst")

        // Subsequent fast keys stay in burst
        eventSec += 0.002
        arrivalNs += 2_000_000
        XCTAssertTrue(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false))

        // First human-paced key (>= 12ms) immediately exits burst mode
        eventSec += 0.025
        arrivalNs += 25_000_000
        XCTAssertFalse(detector.observe(eventTimestampSeconds: eventSec, arrivalNanoseconds: arrivalNs, isRepeat: false))
    }

    // MARK: - P0.5: VNI Post-Commit Editing & Duplicate Injection Audit

    private func driveVNIScenarioOnHostBuffer(
        baseRaw: String,
        extraKeys: String,
        scenario: Int
    ) -> (screenText: String, session: InputSessionManager) {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
        let session = InputSessionManager()
        session.setInputMethod(.vni)
        session.setModernOrthography(true)
        session.smartBilingualEnabled = true
        session.inlineBilingualEnabled = true

        var buffer = ""
        func pressChar(_ ch: Character) {
            if session.isWordBoundary(ch) {
                if session.isComposing {
                    let action = session.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    if case let .commit(bs, text, isOverride) = action, isOverride || bs > 0 {
                        if bs > 0 && buffer.count >= bs {
                            buffer.removeLast(bs)
                        }
                        buffer.append(text)
                    }
                } else {
                    session.editCaretBack = InputSessionManager.caretDisarmed
                }
                buffer.append(ch)
                return
            }
            let action = session.handleCharacter(ch)
            switch action {
            case .replace(let bs, let text):
                if bs > 0 && buffer.count >= bs {
                    buffer.removeLast(bs)
                }
                buffer.append(text)
            case .passThrough:
                buffer.append(ch)
            case .commit(let bs, let text, _):
                if bs > 0 && buffer.count >= bs {
                    buffer.removeLast(bs)
                }
                buffer.append(text)
            case .consumed, .reset:
                break
            }
        }

        func pressBackspace() {
            let action = session.handleBackspace()
            switch action {
            case .replace(let bs, let text):
                if bs > 0 && buffer.count >= bs {
                    buffer.removeLast(bs)
                }
                buffer.append(text)
            case .passThrough:
                if !buffer.isEmpty {
                    buffer.removeLast()
                }
            case .reset:
                if !buffer.isEmpty {
                    buffer.removeLast()
                }
            case .commit, .consumed:
                break
            }
        }

        for ch in baseRaw {
            pressChar(ch)
        }
        switch scenario {
        case 1:
            for ch in extraKeys { pressChar(ch) }
        case 2:
            for ch in extraKeys { pressChar(ch) }
            pressChar(" ")
        case 3:
            pressChar(" ")
            pressBackspace()
            for ch in extraKeys { pressChar(ch) }
        case 4:
            pressChar(" ")
            pressBackspace()
            for ch in extraKeys { pressChar(ch) }
            pressChar(" ")
        default:
            break
        }
        return (buffer, session)
    }

    func testVNIPostCommitObservedBugsAndFourScenarioMatrix() {
        let cases: [(baseVariants: [String], extra: String, expectedBase: String, expectedEscaped: String, expectedDecision: PostCommitEditDecisionKind)] = [
            // 1. trường + 7, 2 -> truòng72 (both infix truo72ng and suffix truong72, plus truo7ng2 and tru7o7ng2)
            (["truo72ng", "truong72", "truo7ng2", "tru7o7ng2", "tru7ong2"], "72", "trường", "truòng72", .vowelShapeCancellation),
            // 2. không + 6 -> khong6 (both infix kho6ng and suffix khong6)
            (["kho6ng", "khong6"], "6", "không", "khong6", .vowelShapeCancellation),
            // 3. quyết + 6, 1 -> quyét61 (both infix quye61t and suffix quyet61, plus quye6t1)
            (["quye61t", "quyet61", "quye6t1", "quyet16"], "61", "quyết", "quyét61", .vowelShapeCancellation)
        ]

        for testCase in cases {
            for rawVariant in testCase.baseVariants {
                // Verify base word composition first
                let baseCheck = driveVNIScenarioOnHostBuffer(baseRaw: rawVariant, extraKeys: "", scenario: 0)
                XCTAssertEqual(baseCheck.screenText, testCase.expectedBase, "Base VNI composition failed for '\(rawVariant)'")

                // Scenario 1: Immediate append (no Space)
                let (s1Text, _) = driveVNIScenarioOnHostBuffer(baseRaw: rawVariant, extraKeys: testCase.extra, scenario: 1)
                XCTAssertEqual(s1Text, testCase.expectedEscaped, "Scenario 1 failed for '\(rawVariant) + \(testCase.extra)'")
                XCTAssertFalse(s1Text.contains("truo72ng"), "Integrity Gate: mid-word raw VNI ledger leaked in '\(s1Text)'")
                XCTAssertFalse(s1Text.contains("kho6ng"), "Integrity Gate: mid-word raw VNI ledger leaked in '\(s1Text)'")
                XCTAssertFalse(s1Text.contains("quye61t"), "Integrity Gate: mid-word raw VNI ledger leaked in '\(s1Text)'")

                // Scenario 2: Immediate append + Space
                let (s2Text, _) = driveVNIScenarioOnHostBuffer(baseRaw: rawVariant, extraKeys: testCase.extra, scenario: 2)
                XCTAssertEqual(s2Text, testCase.expectedEscaped + " ", "Scenario 2 failed for '\(rawVariant) + \(testCase.extra) + Space'")
                XCTAssertFalse(s2Text.contains("7272") || s2Text.contains("66") || s2Text.contains("6161"), "Integrity Gate: duplicate digits in '\(s2Text)'")

                // Scenario 3: Space + Backspace + append
                let (s3Text, s3Session) = driveVNIScenarioOnHostBuffer(baseRaw: rawVariant, extraKeys: testCase.extra, scenario: 3)
                XCTAssertEqual(s3Text, testCase.expectedEscaped, "Scenario 3 failed for '\(rawVariant) + Space + Backspace + \(testCase.extra)'")
                XCTAssertEqual(s3Session.lastPostCommitEditTransaction?.decisionKind, testCase.expectedDecision)
                XCTAssertEqual(s3Session.lastPostCommitEditTransaction?.priorRenderedWord, testCase.expectedBase)
                XCTAssertEqual(s3Session.lastPostCommitEditTransaction?.isLiteralLockedAfterEdit, true)

                // Scenario 4: Space + Backspace + append + Space
                let (s4Text, _) = driveVNIScenarioOnHostBuffer(baseRaw: rawVariant, extraKeys: testCase.extra, scenario: 4)
                XCTAssertEqual(s4Text, testCase.expectedEscaped + " ", "Scenario 4 failed for '\(rawVariant) + Space + Backspace + \(testCase.extra) + Space'")
                XCTAssertFalse(s4Text.contains("7272") || s4Text.contains("66") || s4Text.contains("6161"), "Integrity Gate: duplicate digits in '\(s4Text)'")
            }
        }
    }

    func testVNIIntegrityGateAndBackspaceRecoveryAcrossModifiersAndTones() {
        // 1. Backspace recovery after VNI cancellation:
        // trường + 7 -> truòng7 + 2 -> truòng72 + ⌫ -> truòng7 + ⌫ -> trường
        for variant in ["truo72ng", "truong72"] {
            let session = InputSessionManager()
            session.setInputMethod(.vni)
            for ch in variant { _ = session.handleCharacter(ch) }
            XCTAssertEqual(session.currentOutput(), "trường")
            _ = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
            _ = session.handleBackspace() // delete space
            _ = session.handleCharacter("7")
            XCTAssertEqual(session.currentOutput(), "truòng7")
            _ = session.handleCharacter("2")
            XCTAssertEqual(session.currentOutput(), "truòng72")

            // Step back with Backspace
            _ = session.handleBackspace()
            XCTAssertEqual(session.currentOutput(), "truòng7")
            _ = session.handleBackspace()
            XCTAssertEqual(session.currentOutput(), "trường")
        }

        // 2. Repeated VNI modifiers across all vowels (â/ê/ô/ơ/ư/ă/ươ), stroke (đ), and tones (1..5, 0):
        let repeatedModifierCases: [(baseRaw: String, extra: String, expectedBase: String, expectedAfterExtra: String)] = [
            ("ca6n", "6", "cân", "can6"),
            ("ke6nh", "6", "kênh", "kenh6"),
            ("kho6ng", "6", "không", "khong6"),
            ("mo7", "7", "mơ", "mo7"),
            ("tu7", "7", "tư", "tu7"),
            ("tha8ng1", "8", "thắng", "tháng8"),
            ("d9uong72", "9", "đường", "dường9"),
            ("toa1", "1", "toá", "toa1"),
            ("toa2", "2", "toà", "toa2"),
            ("toa3", "3", "toả", "toa3"),
            ("toa4", "4", "toã", "toa4"),
            ("toa5", "5", "toạ", "toa5"),
            ("toan1", "0", "toán", "toan")
        ]

        for item in repeatedModifierCases {
            let (s1, _) = driveVNIScenarioOnHostBuffer(baseRaw: item.baseRaw, extraKeys: item.extra, scenario: 1)
            XCTAssertEqual(s1, item.expectedAfterExtra, "Scenario 1 failed for \(item.baseRaw) + \(item.extra)")
            let (s3, _) = driveVNIScenarioOnHostBuffer(baseRaw: item.baseRaw, extraKeys: item.extra, scenario: 3)
            XCTAssertEqual(s3, item.expectedAfterExtra, "Scenario 3 failed for \(item.baseRaw) + \(item.extra)")
            let (s4, _) = driveVNIScenarioOnHostBuffer(baseRaw: item.baseRaw, extraKeys: item.extra, scenario: 4)
            XCTAssertEqual(s4, item.expectedAfterExtra + " ", "Scenario 4 failed for \(item.baseRaw) + \(item.extra)")
        }

        // 3. Integrity Gate: Non-applicable VNI modifier after Space + Backspace must NOT corrupt existing diacritics:
        // 'trường' has no 'a'/'ă', so pressing '8' after Space + Backspace must leave 'trường' intact and append '8' -> 'trường8'
        let (nonApplicableS3, _) = driveVNIScenarioOnHostBuffer(baseRaw: "truo72ng", extraKeys: "8", scenario: 3)
        XCTAssertEqual(nonApplicableS3, "trường8")
        let (nonApplicableS4, _) = driveVNIScenarioOnHostBuffer(baseRaw: "truo72ng", extraKeys: "8", scenario: 4)
        XCTAssertEqual(nonApplicableS4, "trường8 ")
    }

    func testTelexComparisonSimulatorVNIMatrixAndReportMetadata() {
        let matrix = TelexComparisonSimulator.buildFourScenarioMatrix(
            baseRawWord: "truong72",
            extraKey: "72",
            inputMethod: .vni
        )
        XCTAssertEqual(matrix.count, 4)
        XCTAssertEqual(matrix[0].vieLotusOutput, "truòng72")
        XCTAssertEqual(matrix[1].vieLotusOutput, "truòng72 ")
        XCTAssertEqual(matrix[2].vieLotusOutput, "truòng72")
        XCTAssertEqual(matrix[3].vieLotusOutput, "truòng72 ")

        // Verify EmpiricalComparisonRow.generateMarkdownReport auto-corrects stale 'trưởng + w' metadata when VNI rows are present
        var rows = EmpiricalComparisonRow.defaultRows()
        rows[0].appleTrace.snapshots = ["t", "tr", "tru", "truo", "trươ", "trườ", "trườn", "trường", "truòng7", "truòng72"]
        rows[0].appleTrace.currentText = "truòng72"
        rows[0].vieLotusTrace.snapshots = rows[0].appleTrace.snapshots
        rows[0].vieLotusTrace.currentText = "truòng72"

        let report = EmpiricalComparisonRow.generateMarkdownReport(
            platformName: "macOS",
            wordNote: "trưởng + w (truowngr + w)",
            autocorrectEnabled: false,
            rows: rows
        )
        XCTAssertTrue(report.contains("Apple VNI vs. Sen Việt"), "Report header must identify Apple VNI")
        XCTAssertTrue(report.contains("- **Kiểu gõ**: `VNI`"), "Report must record VNI input method")
        XCTAssertTrue(report.contains("trường + 7, 2 (VNI)"), "Report must infer actual VNI word under test instead of stale 'trưởng + w'")
        XCTAssertFalse(report.contains("trưởng + w"), "Report must not leak stale 'trưởng + w' metadata on VNI test")
    }

    func testFcitx5LotusParityQuapAndUCLN() {
        let session = InputSessionManager()
        session.setInputMethod(.telex)
        for ch in "quapj" { _ = session.handleCharacter(ch) }
        XCTAssertEqual(session.currentOutput(), "quạp")
        if case .commit(_, let text, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(text, "quạp")
        } else {
            XCTFail("Expected commit on quapj + Space")
        }

        session.reset()
        for ch in "UWCLN" { _ = session.handleCharacter(ch) }
        XCTAssertEqual(session.currentOutput(), "ƯCLN")
        if case .commit(_, let text, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(text, "ƯCLN")
        } else {
            XCTFail("Expected commit on UWCLN + Space")
        }

        let (vniQuapBuf, _) = driveVNIScenarioOnHostBuffer(baseRaw: "quap5", extraKeys: "", scenario: 2)
        XCTAssertEqual(vniQuapBuf, "quạp ")
    }

    func testVikeyParityChafoLowxAndRefRef() {
        let session = InputSessionManager()
        session.setInputMethod(.telex)

        for ch in "Chafo" { _ = session.handleCharacter(ch) }
        XCTAssertEqual(session.currentOutput(), "Chào")
        if case .commit(_, let text, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(text, "Chào")
        } else {
            XCTFail("Expected commit on Chafo + Space")
        }

        for ch in "lowx" { _ = session.handleCharacter(ch) }
        XCTAssertEqual(session.currentOutput(), "lỡ")
        if case .commit(_, let text, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(text, "lỡ")
        } else {
            XCTFail("Expected commit on lowx + Space")
        }

        session.reset()
        session.context = ""
        for ch in "ref" { _ = session.handleCharacter(ch) }
        if case .commit(_, let text1, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(text1, "rè")
        } else {
            XCTFail("Expected commit on first ref + Space")
        }
        for ch in "ref" { _ = session.handleCharacter(ch) }
        if case .commit(_, let text2, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") {
            XCTAssertEqual(text2, "rè")
        } else {
            XCTFail("Expected commit on second ref + Space")
        }
    }
}
