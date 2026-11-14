import XCTest
@testable import VieLotusCore

final class MockTextDocumentProxy: TextDocumentProxyProtocol {
    var buffer: String = ""
    var deleteBackwardCount: Int = 0

    var documentContextBeforeInput: String? {
        return buffer
    }

    var documentContextAfterInput: String? {
        return nil
    }

    func insertText(_ text: String) {
        buffer.append(text)
    }

    func deleteBackward() {
        deleteBackwardCount += 1
        if !buffer.isEmpty {
            buffer.removeLast()
        }
    }
}

final class UIKitInputSessionAdapterTests: XCTestCase {
#if DEBUG
    func testToneReplacementRequiresHostEditButABCAppendsOnly() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.macroEnabled = false
        for ch in "cos" { adapter.handleCharacter(ch, proxy: proxy) }
        XCTAssertEqual(proxy.buffer, "có")
        XCTAssertEqual(adapter.debugProxyDeleteCount, 1)
        XCTAssertEqual(adapter.debugProxyInsertCount, 1)

        let abcProxy = MockTextDocumentProxy()
        let abc = UIKitInputSessionAdapter()
        abc.literalOverrideEnabled = true
        for ch in "cos" { abc.handleCharacter(ch, proxy: abcProxy) }
        XCTAssertEqual(abcProxy.buffer, "cos")
        XCTAssertEqual(abc.debugProxyDeleteCount, 0)
        XCTAssertEqual(abc.debugProxyInsertCount, 1)
    }
#endif

    func testVietnameseTypingWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "tiếng" -> t i e e n g s
        let chars: [Character] = ["t", "i", "e", "e", "n", "g", "s"]
        for c in chars {
            adapter.handleCharacter(c, proxy: proxy)
        }

        XCTAssertEqual(proxy.buffer, "tiếng")

        // Type space -> commits word and adds space
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "tiếng ")
    }

    func testBackspaceDuringCompositionWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "toán" -> t o a n s
        for c in ["t", "o", "a", "n", "s"] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "toán")

        // Backspace once -> strips acute tone 's', leaving "toan"
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "toan")

        // Backspace again -> deletes 'n', leaving "toa"
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "toa")

        // Backspace again -> deletes 'a', leaving "to"
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "to")
    }

    func testMacroExpansionWithMockProxy() {
        MacroEngine.shared.resetToDefaults()
        defer { MacroEngine.shared.resetToDefaults() }

        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.macroEnabled = true
        let proxy = MockTextDocumentProxy()

        // 1. By default, "vn" must remain "vn" without unsolicited expansion
        adapter.handleCharacter("v", proxy: proxy)
        adapter.handleCharacter("n", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "vn")
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "vn ")

        // 2. When user explicitly configures "vn" -> "Việt Nam":
        proxy.buffer = ""
        MacroEngine.shared.setMacro(key: "vn", value: "Việt Nam")

        // Type "vn" + space
        adapter.handleCharacter("v", proxy: proxy)
        adapter.handleCharacter("n", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "vn")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam ")

        // Type "ddc" (đc) + space -> "được "
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("c", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam đc")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được ")

        // Type "sddt" (sđt) + space -> "số điện thoại "
        adapter.handleCharacter("s", proxy: proxy)
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("d", proxy: proxy)
        adapter.handleCharacter("t", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được sđt")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được số điện thoại ")

        // Type "cty" + space -> "công ty "
        adapter.handleCharacter("c", proxy: proxy)
        adapter.handleCharacter("t", proxy: proxy)
        adapter.handleCharacter("y", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được số điện thoại cty")

        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt Nam được số điện thoại công ty ")
    }

    func testSmartBilingualRestoreWithMockProxy() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.smartBilingual = true
        let proxy = MockTextDocumentProxy()

        // Type "more" (m o r e) -> during typing: m -> mo -> mỏ -> mỏe
        for c in ["m", "o", "r", "e"] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }

        // On word boundary (space), Smart Bilingual restores raw English word "more"
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "more ")
    }

    func testEmojiInsertionAfterComposingWord() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "việt" -> v i e e t j (still composing)
        for c in ["v", "i", "e", "e", "t", "j"] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertTrue(adapter.session.isComposing)
        XCTAssertEqual(proxy.buffer, "việt")

        // User taps emoji "🇻🇳" -> commits active word first, then inserts emoji
        adapter.commitWord(proxy: proxy)
        proxy.insertText("🇻🇳")

        XCTAssertFalse(adapter.session.isComposing)
        XCTAssertEqual(proxy.buffer, "việt🇻🇳")
    }

    func testEmojiInsertionAndBackspace() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        let proxy = MockTextDocumentProxy()

        // Type "chào " -> c h a o f + space
        for c in ["c", "h", "a", "o", "f", " "] as [Character] {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "chào ")

        // Insert emoji "😊"
        proxy.insertText("😊")
        XCTAssertEqual(proxy.buffer, "chào 😊")

        // Backspace removes the emoji
        proxy.deleteBackward()
        XCTAssertEqual(proxy.buffer, "chào ")
    }

    func testMultiScalarEmojiInsertion() {
        let proxy = MockTextDocumentProxy()

        let emojis = ["🇻🇳", "❤️", "🎉", "😮‍💨", "☕️"]
        for emoji in emojis {
            proxy.insertText(emoji)
        }

        XCTAssertEqual(proxy.buffer, "🇻🇳❤️🎉😮‍💨☕️")
    }

    func testPostCommitToneModificationAndEscapeMinimalDiff() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.smartHybrid)
        let proxy = MockTextDocumentProxy()

        // "cá" + Space + Backspace + "f" -> "cà" (only 1 deleteBackward for "á", not 2 for "cá")
        for c in "cas " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "cá ")
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "cá")

        let deletesBeforeToneSwap = proxy.deleteBackwardCount
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "cà")
        XCTAssertEqual(proxy.deleteBackwardCount - deletesBeforeToneSwap, 1, "Should only delete 'á' (1 char) instead of full word 'cá'")

        // Commit and test "gà" + Space + Backspace + "f" + "f" -> "gaf" -> "gaff"
        adapter.handleCharacter(" ", proxy: proxy)
        for c in "gaf " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "cà gà ")
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "cà gà")

        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "cà gaf")
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "cà gaff")
    }

    func testPostCommitEnglishSuffixEditMinimalDiff() {
        let prevProvider = SmartBilingualDetector.spellCheckerProvider
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        defer { SmartBilingualDetector.spellCheckerProvider = prevProvider }

        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.smartHybrid)
        adapter.smartBilingual = true
        let proxy = MockTextDocumentProxy()

        for c in "restrict " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "restrict ")

        // Backspace space, then type "ed" -> "restricted" with 0 backspaces during "ed"
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "restrict")

        let deletesBeforeSuffix = proxy.deleteBackwardCount
        adapter.handleCharacter("e", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "restricte")
        adapter.handleCharacter("d", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "restricted")
        XCTAssertEqual(proxy.deleteBackwardCount - deletesBeforeSuffix, 0, "Common prefix diff should append 'e' and 'd' with 0 deleteBackward calls")
    }

    func testContextWordResurrectionAfterCursorMoveAndCandidateCommit() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.smartHybrid)
        let proxy = MockTextDocumentProxy()

        // 1. Simulate cursor placed at the end of an existing word in documentContextBeforeInput
        proxy.buffer = "Hôm nay trời tả"
        adapter.handleExternalTextChange(proxy: proxy)

        // Typing 'f' modifies 'tả' -> 'tà' in-place
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hôm nay trời tà")
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hôm nay trời tà ")

        // 2. Simulate candidate selection ("Xin chào ") followed by Backspace + tone change ('s' -> "Xin cháo")
        adapter.commitCandidate("Xin chào", proxy: proxy, trailingSpace: true)
        XCTAssertEqual(proxy.buffer, "Hôm nay trời tà Xin chào ")

        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hôm nay trời tà Xin chào")

        adapter.handleCharacter("s", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hôm nay trời tà Xin cháo")

        // 3. Simulate host app clearing text box mid-composition (e.g. pressing Send in chat app)
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        XCTAssertFalse(adapter.session.isComposing)

        for c in "toots" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "tốt")
    }

    func testPostCommitCircumflexAndToneModification() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.smartHybrid)
        let proxy = MockTextDocumentProxy()

        // 1. "nhan " + Backspace + "a" -> "nhân" + "s" -> "nhấn"
        for c in "nhan " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "nhan ")
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhan")

        adapter.handleCharacter("a", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhân")
        adapter.handleCharacter("s", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhấn")
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhần")
        adapter.handleCharacter("r", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhẩn")
        adapter.handleCharacter("x", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhẫn")
        adapter.handleCharacter("j", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhận")
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhận ")

        // 2. "them " + Backspace + "e" ("theme") + "f" -> "thềm"
        for c in "them " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        adapter.handleBackspace(proxy: proxy)
        adapter.handleCharacter("e", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhận theme")
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhận thềm")
        adapter.handleCharacter(" ", proxy: proxy)

        // 3. "trong " + Backspace + "f" + "o" -> "trồng"
        for c in "trong " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        adapter.handleBackspace(proxy: proxy)
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhận thềm tròng")
        adapter.handleCharacter("o", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "nhận thềm trồng")

        // 4. Reverse order: "nhan " + Backspace + tone ("r", "s", "f", "x", "j") + "a" -> "nhẩn", "nhấn", "nhần", "nhẫn", "nhận"
        let reverseToneCases: [(toneKey: Character, afterTone: String, afterCircumflex: String)] = [
            ("r", "nhản", "nhẩn"),
            ("s", "nhán", "nhấn"),
            ("f", "nhàn", "nhần"),
            ("x", "nhãn", "nhẫn"),
            ("j", "nhạn", "nhận")
        ]
        for tc in reverseToneCases {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for c in "nhan " {
                adapter.handleCharacter(c, proxy: proxy)
            }
            adapter.handleBackspace(proxy: proxy)
            adapter.handleCharacter(tc.toneKey, proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.afterTone)
            adapter.handleCharacter("a", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.afterCircumflex)
        }
    }

    func testAppleTelexPostCommitBackspaceAppendParity() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.smartHybrid)
        let proxy = MockTextDocumentProxy()

        // 1. Immediate while composing ("Thêm ngay sau gõ" & "Thêm ngay sau gõ + Space")
        // Non-locking literal append: redundant post-coda modifiers append literally to the composed stem without locking keys
        let immediateCases: [(raw: String, expectedInline: String)] = [
            ("Truowngrw", "Trưởngw"),
            ("truowngrw", "trưởngw"),
            ("keenhe", "kênhe"),
            ("hoongfo", "hồngo"),
            ("kinhsi", "kínhi"),
            ("muwngfu", "mừngu"),
            ("dduowngfu", "đườngu"),
            ("dduowngfo", "đuồng"),
            ("dduowngfoo", "đuồngo")
        ]
        for tc in immediateCases {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for c in tc.raw {
                adapter.handleCharacter(c, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, tc.expectedInline, "Immediate inline output for '\(tc.raw)'")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.expectedInline + " ", "Immediate + Space output for '\(tc.raw)'")
        }

        // 2. Post-commit after Space + Backspace ("gõ xong + space + xoá lùi rồi thêm" & "+ space")
        let postCommitCases: [(wordRaw: String, committedWord: String, extraKey: Character, expectedAfterKey: String)] = [
            ("truowngr", "trưởng", "w", "trưởngw"),
            ("keenh", "kênh", "e", "kênhe"),
            ("hoongf", "hồng", "o", "hồngo"),
            ("kinhs", "kính", "i", "kínhi"),
            ("muwngf", "mừng", "u", "mừngu"),
            ("dduowngf", "đường", "u", "đườngu"),
            ("dduowngf", "đường", "o", "đuồng")
        ]
        for tc in postCommitCases {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for c in tc.wordRaw {
                adapter.handleCharacter(c, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, tc.committedWord)
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.committedWord + " ")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.committedWord)
            adapter.handleCharacter(tc.extraKey, proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.expectedAfterKey, "Post-commit Space+Backspace+'\(tc.extraKey)' on '\(tc.committedWord)'")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.expectedAfterKey + " ", "Post-commit Space+Backspace+'\(tc.extraKey)'+Space on '\(tc.committedWord)'")
        }
    }

    func testTelexComparisonSimulatorFourScenarioMatrix() {
        let truongRows = TelexComparisonSimulator.buildFourScenarioMatrix(
            baseRawWord: "Truowngr",
            extraKey: "w",
            simulateAppleAutocorrect: true
        )
        XCTAssertEqual(truongRows.count, 4)
        XCTAssertEqual(truongRows[0].appleTelexOutput, "Trưởngw")
        XCTAssertEqual(truongRows[0].vieLotusOutput, "Trưởngw")
        XCTAssertEqual(truongRows[1].appleTelexOutput, "Trưởng ")
        XCTAssertEqual(truongRows[1].vieLotusOutput, "Trưởngw ")
        XCTAssertEqual(truongRows[2].appleTelexOutput, "Trưởngư")
        XCTAssertEqual(truongRows[2].vieLotusOutput, "Trưởngw")
        XCTAssertEqual(truongRows[3].appleTelexOutput, "Trưởngư ")
        XCTAssertEqual(truongRows[3].vieLotusOutput, "Trưởngw ")

        let kenhRows = TelexComparisonSimulator.buildFourScenarioMatrix(
            baseRawWord: "keenh",
            extraKey: "e",
            simulateAppleAutocorrect: true
        )
        XCTAssertEqual(kenhRows.count, 4)
        XCTAssertEqual(kenhRows[0].appleTelexOutput, "kênhe")
        XCTAssertEqual(kenhRows[0].vieLotusOutput, "kênhe")
        XCTAssertEqual(kenhRows[1].appleTelexOutput, "kênh ")
        XCTAssertEqual(kenhRows[1].vieLotusOutput, "kênhe ")
        XCTAssertEqual(kenhRows[2].appleTelexOutput, "kênhe")
        XCTAssertEqual(kenhRows[2].vieLotusOutput, "kênhe")
        XCTAssertEqual(kenhRows[3].appleTelexOutput, "kênh ")
        XCTAssertEqual(kenhRows[3].vieLotusOutput, "kênhe ")
    }

    func testLongPressDiacriticSelectionNeverCollapsesToRawTelex() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.smartHybrid)
        let proxy = MockTextDocumentProxy()

        // 1. Consecutive long-press vowel selections: "ế" then "ể" -> "ếể" (must NEVER collapse to "eeseer")
        adapter.handleCharacter("ế", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "ế")
        adapter.handleCharacter("ể", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "ếể")
        adapter.handleCharacter("ệ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "ếểệ")
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "ếểệ ")

        // 2. Consecutive "đ" then "đ" -> "đđ" (must NEVER collapse to "dd")
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        adapter.handleCharacter("đ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "đ")
        adapter.handleCharacter("đ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "đđ")

        // 3. Phonotactically invalid prefix + long-press vowel: "k" then "ă" -> "kă" (must NEVER collapse to "kaw")
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        adapter.handleCharacter("k", proxy: proxy)
        adapter.handleCharacter("ă", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "kă")

        // 4. Long-press vowel followed by normal ASCII vowel/modifier: "ế" + "e" -> "ếe" (must NEVER collapse to "eese")
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        adapter.handleCharacter("ế", proxy: proxy)
        adapter.handleCharacter("e", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "ếe")

        // 5. Valid syllable continuation with long-press characters: "đ" + "i" + "n" + "h" + "s" -> "đính"
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for c in "đinhs" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "đính")

        // 6. Valid syllable continuation with pre-toned vowel: "v" + "i" + "ệ" + "t" -> "việt"
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for c in "việt" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "việt")

        // 7. All accented vowel families in consecutive pairs (a/ă/â, e/ê, i, o/ô/ơ, u/ư, y, d/đ)
        let consecutivePairs: [(Character, Character, String)] = [
            ("ắ", "ặ", "ắặ"),
            ("ấ", "ẩ", "ấẩ"),
            ("ố", "ổ", "ốổ"),
            ("ớ", "ở", "ớở"),
            ("ứ", "ử", "ứử"),
            ("í", "ỉ", "íỉ"),
            ("ý", "ỷ", "ýỷ"),
            ("Đ", "đ", "Đđ")
        ]
        for (first, second, expected) in consecutivePairs {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            adapter.handleCharacter(first, proxy: proxy)
            adapter.handleCharacter(second, proxy: proxy)
            XCTAssertEqual(proxy.buffer, expected, "Consecutive long-press '\(first)' + '\(second)' must stay '\(expected)'")
        }
    }

    func testDoubleSpacePeriodShortcutAndDotSpaceSentenceStartCapitalization() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()

        // 1. Double-space after word -> ". " + capitalized next sentence ("Chào. Hoa")
        for c in "Chaof" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        adapter.commitWord(proxy: proxy, suffix: " ")
        XCTAssertEqual(proxy.buffer, "Chào ")
        adapter.applyDoubleSpacePeriodShortcut(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Chào. ")
        XCTAssertEqual(adapter.effectiveContextBeforeInput(proxy: proxy), "Chào. ")

        for c in "Hoa" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        adapter.commitWord(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Chào. Hoa")

        // 2. Explicit "." + " " -> ". " + capitalized next sentence ("Chào. Đi")
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for c in "Chaof" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        adapter.handleCharacter(".", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Chào.")
        adapter.commitWord(proxy: proxy, suffix: " ")
        XCTAssertEqual(proxy.buffer, "Chào. ")
        XCTAssertEqual(adapter.effectiveContextBeforeInput(proxy: proxy), "Chào. ")

        for c in "Ddi" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        adapter.commitWord(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Chào. Đi")
    }

    func testVNIPostCommitRepeatedModifierEscapeNeverDuplicatesOrInjectsInfixDigits() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.vni)

        let cases: [(rawBase: String, committedWord: String, extra: String, expected: String)] = [
            ("truo72ng", "trường", "72", "truòng72"),
            ("truong72", "trường", "72", "truòng72"),
            ("kho6ng", "không", "6", "khong6"),
            ("khong6", "không", "6", "khong6"),
            ("quye61t", "quyết", "61", "quyét61"),
            ("quyet61", "quyết", "61", "quyét61")
        ]

        for tc in cases {
            // Scenario 1 & 2: Immediate append + Space
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for c in tc.rawBase { adapter.handleCharacter(c, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, tc.committedWord)
            for c in tc.extra { adapter.handleCharacter(c, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, tc.expected, "iOS VNI Scenario 1 for \(tc.rawBase) + \(tc.extra)")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.expected + " ", "iOS VNI Scenario 2 for \(tc.rawBase) + \(tc.extra) + Space")

            // Scenario 3 & 4: Space + Backspace + append + Space
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for c in tc.rawBase { adapter.handleCharacter(c, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, tc.committedWord)
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.committedWord + " ")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.committedWord)
            for c in tc.extra { adapter.handleCharacter(c, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, tc.expected, "iOS VNI Scenario 3 for \(tc.rawBase) + Space + Backspace + \(tc.extra)")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, tc.expected + " ", "iOS VNI Scenario 4 for \(tc.rawBase) + Space + Backspace + \(tc.extra) + Space")
        }
    }

    func testStrokeDConsonantAbbreviationsOnIOSAdapterWithSpace() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        let prevMacro = MacroEngine.shared.isEnabled
        MacroEngine.shared.isEnabled = false
        defer { MacroEngine.shared.isEnabled = prevMacro }

        let cases: [(raw: String, expected: String)] = [
            ("DDH", "ĐH"),
            ("DDT", "ĐT"),
            ("DDW", "ĐW"),
            ("DDQ", "ĐQ"),
            ("ddh", "đh"),
            ("ddt", "đt"),
            ("ddw", "đw"),
            ("ddq", "đq"),
            ("DDC", "ĐC"),
            ("SDDT", "SĐT"),
            ("BDDS", "BĐS"),
            ("HDDND", "HĐND"),
            ("DDHQG", "ĐHQG")
        ]

        for (raw, expected) in cases {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in raw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, expected, "iOS inline composition for \(raw)")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, expected + " ", "iOS Space commit for \(raw) must remain \(expected)")
        }
    }

    private final class SelectionMockTextDocumentProxy: TextDocumentProxyProtocol {
        var before: String = ""
        var selected: String = ""
        var after: String = ""

        var fullText: String { before + selected + after }

        var documentContextBeforeInput: String? { before }
        var documentContextAfterInput: String? { after.isEmpty ? nil : after }
        var selectedText: String? { selected.isEmpty ? nil : selected }

        func selectSuffix(_ suffix: String) -> Bool {
            guard before.hasSuffix(suffix) else { return false }
            before.removeLast(suffix.count)
            selected = suffix
            return true
        }

        func insertText(_ text: String) {
            selected = ""
            before.append(text)
        }

        func deleteBackward() {
            if !selected.isEmpty {
                selected = ""
            } else if !before.isEmpty {
                before.removeLast()
            }
        }
    }

    func testPartialWordSelectionReplacementAndStandaloneRhymesOnIOS() {
        func runSelectionScenario(
            method: InputMethodType = .telex,
            initialRaw: String,
            selectSuffix: String,
            deleteFirst: Bool = false,
            replacementRaw: String,
            expected: String,
            label: String
        ) {
            let proxy = SelectionMockTextDocumentProxy()
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(method)
            adapter.smartBilingual = true

            for ch in initialRaw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertTrue(proxy.selectSuffix(selectSuffix), "Failed to select '\(selectSuffix)' in '\(proxy.fullText)' (\(label))")
            if deleteFirst {
                adapter.handleBackspace(proxy: proxy)
            }
            for ch in replacementRaw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.fullText, expected, label)
        }

        // 1. Telex partial-word selection replacements
        runSelectionScenario(initialRaw: "cufng", selectSuffix: "ùng", replacementRaw: "uoois ", expected: "cuối ", label: "cùng -> select ùng -> uoois")
        runSelectionScenario(initialRaw: "chusng", selectSuffix: "úng", replacementRaw: "ojn ", expected: "chọn ", label: "chúng -> select úng -> ojn")
        runSelectionScenario(initialRaw: "chusng", selectSuffix: "úng", replacementRaw: "is ", expected: "chí ", label: "chúng -> select úng -> is")
        runSelectionScenario(initialRaw: "quasng", selectSuffix: "uáng", replacementRaw: "uawng ", expected: "quăng ", label: "quáng -> select uáng -> uawng")
        runSelectionScenario(initialRaw: "dufng", selectSuffix: "ùng", replacementRaw: "di ", expected: "đi ", label: "dùng -> select ùng -> di")
        runSelectionScenario(initialRaw: "cufng", selectSuffix: "ùng", deleteFirst: true, replacementRaw: "uoois ", expected: "cuối ", label: "cùng -> select ùng -> Backspace -> uoois")
        runSelectionScenario(initialRaw: "cufng", selectSuffix: "ùng", replacementRaw: " ", expected: "c ", label: "cùng -> select ùng -> Space")
        runSelectionScenario(initialRaw: "tafnh", selectSuffix: "nh", replacementRaw: "s ", expected: "tàs ", label: "tành -> select nh -> s (preserve accented prefix)")
        runSelectionScenario(initialRaw: "cufng", selectSuffix: "cùng", replacementRaw: "uoois ", expected: "uối ", label: "cùng -> select whole word -> uoois")

        // 2. VNI partial-word selection replacements (including d + 9 -> đ and post-Backspace onset adoption)
        runSelectionScenario(method: .vni, initialRaw: "cu2ng", selectSuffix: "ùng", replacementRaw: "uo61i ", expected: "cuối ", label: "VNI cùng -> select ùng -> uo61i")
        runSelectionScenario(method: .vni, initialRaw: "du2ng", selectSuffix: "ùng", replacementRaw: "9i ", expected: "đi ", label: "VNI dùng -> select ùng -> 9i")
        runSelectionScenario(method: .vni, initialRaw: "cu2ng", selectSuffix: "ùng", deleteFirst: true, replacementRaw: "uo61i ", expected: "cuối ", label: "VNI cùng -> select ùng -> Backspace -> uo61i")
    }

    private final class CountingTextDocumentProxy: TextDocumentProxyProtocol {
        var buffer: String = ""
        var afterBuffer: String = ""
        var beforeReads: Int = 0
        var afterReads: Int = 0
        var selectedTextReads: Int = 0

        var documentContextBeforeInput: String? {
            beforeReads += 1
            return buffer
        }

        var documentContextAfterInput: String? {
            afterReads += 1
            return afterBuffer.isEmpty ? nil : afterBuffer
        }

        var selectedText: String? {
            selectedTextReads += 1
            return nil
        }

        func insertText(_ text: String) {
            buffer.append(text)
        }

        func deleteBackward() {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
        }
    }

    func testSingleReadPerKeystrokeXPCBudgetAndZeroAfterInputReadsOnWordEnd() {
        let proxy = CountingTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)

        // First keystroke performs 1 reconcile read + 1 one-time sync-mode probe (<= 2 reads) and 1 initial selectedText check
        adapter.handleCharacter("t", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "t")
        XCTAssertLessThanOrEqual(proxy.beforeReads, 2)
        XCTAssertEqual(proxy.afterReads, 0)
        XCTAssertEqual(proxy.selectedTextReads, 1)

        // Every subsequent keystroke across circumflex, horn, tone, space, and next words
        // must read documentContextBeforeInput at most 1 time, documentContextAfterInput 0 times,
        // and selectedText at most 1 time (0 times inside multi-character performReplace loops)!
        for ch in "ieengs vieetj hieenj ddaij " {
            let prevBeforeReads = proxy.beforeReads
            let prevAfterReads = proxy.afterReads
            let prevSelectedReads = proxy.selectedTextReads
            adapter.handleCharacter(ch, proxy: proxy)
            let deltaBefore = proxy.beforeReads - prevBeforeReads
            let deltaAfter = proxy.afterReads - prevAfterReads
            let deltaSelected = proxy.selectedTextReads - prevSelectedReads
            XCTAssertLessThanOrEqual(deltaBefore, 1, "Keystroke '\(ch)' exceeded 1 documentContextBeforeInput read (got \(deltaBefore))")
            XCTAssertEqual(deltaAfter, 0, "Keystroke '\(ch)' unexpectedly read documentContextAfterInput (got \(deltaAfter))")
            XCTAssertLessThanOrEqual(deltaSelected, 1, "Keystroke '\(ch)' exceeded 1 selectedText read during replacement (got \(deltaSelected))")
        }
        XCTAssertEqual(proxy.buffer, "tiếng việt hiện đại ")

        // Post-commit Backspace + tone change ('j' -> 'f') also stays within 1 before-read and 1 selectedText-read per event
        let prevBeforeBs = proxy.beforeReads
        let prevSelectedBs = proxy.selectedTextReads
        adapter.handleBackspace(proxy: proxy)
        XCTAssertLessThanOrEqual(proxy.beforeReads - prevBeforeBs, 1)
        XCTAssertLessThanOrEqual(proxy.selectedTextReads - prevSelectedBs, 1)
        let prevBeforeTone = proxy.beforeReads
        let prevSelectedTone = proxy.selectedTextReads
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertLessThanOrEqual(proxy.beforeReads - prevBeforeTone, 1)
        XCTAssertLessThanOrEqual(proxy.selectedTextReads - prevSelectedTone, 1)
        XCTAssertEqual(proxy.buffer, "tiếng việt hiện đài")
    }

    func testSupplementaryLexiconFilteringAndUserMacroPrecedence() {
        let engine = MacroEngine(initialMacros: ["cty": "công ty"], autoLoadFromDisk: false, autoSaveToDisk: false)
        engine.updateSupplementaryShortcuts([
            (userInput: "omw", documentText: "On my way!"),
            (userInput: "addr", documentText: "123 Lê Lợi, Q.1"),
            (userInput: "hello", documentText: "Hello"),          // Rejected: case-insensitive identity
            (userInput: "a", documentText: "alpha"),              // Rejected: single-char shortcut
            (userInput: "sđt2", documentText: "0909000111"),      // Rejected: non-ASCII / digit in key
            (userInput: "cty", documentText: "Override Attempt")  // Lower priority than explicit/default macro
        ])

        XCTAssertEqual(engine.lookup(word: "omw"), "On my way!")
        XCTAssertEqual(engine.lookup(word: "OMW"), "ON MY WAY!")
        XCTAssertEqual(engine.lookup(word: "addr"), "123 Lê Lợi, Q.1")
        XCTAssertNil(engine.lookup(word: "hello"))
        XCTAssertNil(engine.lookup(word: "a"))
        XCTAssertNil(engine.lookup(word: "sđt2"))
        XCTAssertEqual(engine.lookup(word: "cty"), "công ty", "Explicit/default macro must take precedence over supplementary lexicon")

        // User-defined macro added later also overrides supplementary shortcut
        engine.setMacro(key: "omw", value: "Đang trên đường")
        XCTAssertEqual(engine.lookup(word: "omw"), "Đang trên đường")
        XCTAssertNil(engine.getAllMacros()["addr"], "Supplementary shortcuts must never leak into persisted user macros")
    }

    func testConditionalCursorRoundTripGuardInvalidatesOnHostTextChange() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)

        // 1. Type "tả" and perform cursor round-trip (← then →) while host text still matches "tả"
        for ch in "tar" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "tả")
        adapter.session.stepCaretBack()
        XCTAssertEqual(adapter.session.editCaretBack, 1)
        adapter.session.stepCaretForward()
        XCTAssertEqual(adapter.session.editCaretBack, 0)

        // Host text is still "tả" -> post-commit tone edit 'f' succeeds -> "tà"
        adapter.handleCharacter("f", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "tà")

        // 2. Perform cursor round-trip (← then →), but host autocorrects/replaces "tà" with "khác" during navigation
        adapter.session.stepCaretBack()
        adapter.session.stepCaretForward()
        XCTAssertEqual(adapter.session.editCaretBack, 0)

        proxy.buffer = "khác"
        adapter.reconcileIfNeeded(proxy: proxy)
        XCTAssertEqual(
            adapter.session.editCaretBack,
            InputSessionManager.caretDisarmed,
            "Armed post-commit state must be invalidated when host document text no longer ends with the committed word"
        )
    }

    func testCosAndJustBilingualBehavior() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        adapter.smartBilingual = true

        // 1. "just" has impossible Vietnamese onset 'j' -> restores to English "just "
        proxy.buffer = ""
        adapter.session.reset()
        for ch in "just " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "just ")

        // 2. "cos" with NO context must preserve Vietnamese "có " because 'c-o-s' is the ONLY keystroke path to "có"
        proxy.buffer = ""
        adapter.session.reset()
        for ch in "cos " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "có ")

        // 3. Double-tap 's' escape ("coss") cancels tone and produces literal English "cos "
        proxy.buffer = ""
        adapter.session.reset()
        for ch in "coss " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "cos ")

        // 4. "cos" with English context ("sin and ") correctly produces "sin and cos "
        proxy.buffer = "sin and "
        adapter.session.reset()
        adapter.session.appendContext("sin")
        adapter.session.appendContext("and")
        for ch in "cos " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "sin and cos ")

        // 5. "cos" with Vietnamese context ("tôi ") correctly produces "tôi có "
        proxy.buffer = "tôi "
        adapter.session.reset()
        adapter.session.appendContext("tôi")
        for ch in "cos " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "tôi có ")
    }

    func testABCLiteralModeTypingAndCandidateCommitWithLatencyBenchmark() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)

        // 1. Enable ABC mode
        adapter.literalOverrideEnabled = true
        XCTAssertTrue(adapter.literalOverrideEnabled)

        // Type "hel"
        for ch in "hel" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "hel")
        XCTAssertEqual(adapter.session.composingWord, "hel")

        // Slot 1 replacement: "help" with trailing space
        let suggestion = SuggestionCandidate(
            displayText: "help",
            insertionText: "help",
            replacementMode: .replaceComposing,
            source: .englishCompletion,
            score: 2.0
        )
        adapter.commitSuggestion(suggestion, proxy: proxy, trailingSpace: true)
        XCTAssertEqual(proxy.buffer, "help ")
        XCTAssertFalse(adapter.session.isComposing)

        // 2. Switch back to Vietnamese (VI) mode
        adapter.literalOverrideEnabled = false
        XCTAssertFalse(adapter.literalOverrideEnabled)

        // Type "vieetj" -> "việt"
        for ch in "vieetj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "help việt")

        // Space commits "việt "
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "help việt ")

        // 3. Keystroke latency benchmark across 2,000 keystrokes
        var latenciesNs: [UInt64] = []
        latenciesNs.reserveCapacity(2000)

        let testSentence = "hoc sinh hoc gioi giang day tieng viet rat tot "
        let benchProxy = MockTextDocumentProxy()
        let benchAdapter = UIKitInputSessionAdapter()
        benchAdapter.session.setInputMethod(.telex)
        benchAdapter.session.setGrammarProfile(.senFlex)

        // Warm-up
        for ch in testSentence {
            benchAdapter.handleCharacter(ch, proxy: benchProxy)
        }
        benchProxy.buffer = ""
        benchAdapter.session.reset()

        let startTotal = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<40 {
            for ch in testSentence {
                let t0 = DispatchTime.now().uptimeNanoseconds
                benchAdapter.handleCharacter(ch, proxy: benchProxy)
                let t1 = DispatchTime.now().uptimeNanoseconds
                latenciesNs.append(t1 - t0)
            }
        }
        let totalTimeMs = Double(DispatchTime.now().uptimeNanoseconds - startTotal) / 1_000_000.0

        latenciesNs.sort()
        let p50Us = Double(latenciesNs[latenciesNs.count / 2]) / 1000.0
        let p95Us = Double(latenciesNs[(latenciesNs.count * 95) / 100]) / 1000.0
        let p99Us = Double(latenciesNs[(latenciesNs.count * 99) / 100]) / 1000.0

        print("=== IOS ADAPTER KEYSTROKE & DISPATCH LATENCY BENCHMARK ===")
        print("Total keystrokes: \(latenciesNs.count) in \(String(format: "%.2f", totalTimeMs)) ms")
        print("p50 latency: \(String(format: "%.2f", p50Us)) µs")
        print("p95 latency: \(String(format: "%.2f", p95Us)) µs")
        print("p99 latency: \(String(format: "%.2f", p99Us)) µs")

        // In-memory keystroke dispatch must be <= 100 µs (0.1 ms) at p95
        XCTAssertLessThan(p95Us, 100.0, "p95 keystroke dispatch latency (\(p95Us) µs) must be well under 100 µs")
    }

    func testMixedVietnameseEnglishAlternatingLatencyAndZeroRedundantXPCReads() {
        let mixedSentence = "chuowng trinhf programming interface thieets kees system architecture kieemr thuwr performance "
        let expected = "chương trình programming interface thiết kế system architecture kiểm thử performance "
        let proxy = CountingTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        adapter.smartBilingual = true

        // 1. Verify accuracy + XPC read budget on alternating Vietnamese-English code-switching
        var firstKey = true
        for ch in mixedSentence {
            let prevBefore = proxy.beforeReads
            let prevAfter = proxy.afterReads
            let prevSelected = proxy.selectedTextReads
            adapter.handleCharacter(ch, proxy: proxy)
            if firstKey {
                firstKey = false
            } else {
                XCTAssertLessThanOrEqual(proxy.beforeReads - prevBefore, 1)
                XCTAssertEqual(proxy.afterReads - prevAfter, 0)
                XCTAssertLessThanOrEqual(proxy.selectedTextReads - prevSelected, 1)
            }
        }
        XCTAssertEqual(proxy.buffer, expected)

        // 2. Benchmark 20 alternating code-switching rounds (~1,900 keystrokes)
        // Warm-up 1 round so lazy singleton dictionaries are loaded before timing
        proxy.buffer = ""
        adapter.session.reset()
        adapter.session.clearContext()
        for ch in mixedSentence {
            adapter.handleCharacter(ch, proxy: proxy)
        }

        var latenciesNs: [UInt64] = []
        latenciesNs.reserveCapacity(mixedSentence.count * 20)
        for _ in 0..<20 {
            proxy.buffer = ""
            adapter.session.reset()
            adapter.session.clearContext()
            for ch in mixedSentence {
                let t0 = DispatchTime.now().uptimeNanoseconds
                adapter.handleCharacter(ch, proxy: proxy)
                let t1 = DispatchTime.now().uptimeNanoseconds
                latenciesNs.append(t1 - t0)
            }
            XCTAssertEqual(proxy.buffer, expected)
        }
        latenciesNs.sort()
        let p50Us = Double(latenciesNs[latenciesNs.count / 2]) / 1000.0
        let p95Us = Double(latenciesNs[(latenciesNs.count * 95) / 100]) / 1000.0
        let p99Us = Double(latenciesNs[(latenciesNs.count * 99) / 100]) / 1000.0
        print("=== IOS MIXED VN/EN ALTERNATING LATENCY BENCHMARK ===")
        print("Samples: \(latenciesNs.count) | p50: \(String(format: "%.2f", p50Us)) µs | p95: \(String(format: "%.2f", p95Us)) µs | p99: \(String(format: "%.2f", p99Us)) µs")
        XCTAssertLessThan(p95Us, 150.0, "Mixed VN/EN code-switching p95 latency (\(p95Us) µs) must remain under 150 µs")
    }

    func testDoubleSpacePeriodShortcutAndPreTransformTelexFastPath() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)

        // 1. Standard word + Space #1 + delayed selectionWillChange echo (> 120ms, e.g. at 260ms) + Space #2 -> ". "
        for ch in "vieetj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "việt")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 100.00), .committedComposingWord("việt"))
        XCTAssertEqual(proxy.buffer, "việt ")
        XCTAssertEqual(adapter.cachedBeforeInput, "việt ")
        // Simulate UIKit firing selectionWillChange both inside (<120ms) and outside (>120ms, at 260ms) while proxy context is intact
        XCTAssertTrue(adapter.handleSelectionWillChange(isInternalEcho: true, proxy: proxy, now: 100.05))
        XCTAssertTrue(adapter.handleSelectionWillChange(isInternalEcho: false, proxy: proxy, now: 100.26))
        XCTAssertEqual(adapter.lastSpaceTapTime, 100.00, "Delayed selectionWillChange echo with intact proxy context must not wipe lastSpaceTapTime")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 100.38), .insertedPeriodShortcut)
        XCTAssertEqual(proxy.buffer, "việt. ")
        XCTAssertEqual(adapter.cachedBeforeInput, "việt. ")

        // 2. Subsequent word after ". " + Backspace into committed word + Space #1 + Space #2 -> ". "
        for ch in "nghieengs" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "việt. nghiếng")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 101.00), .committedComposingWord("nghiếng"))
        XCTAssertEqual(proxy.buffer, "việt. nghiếng ")
        // Backspace twice (delete space + 'g' into committed word), then re-type 'g', Space #1, Space #2
        adapter.handleBackspace(proxy: proxy)
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "việt. nghiến")
        adapter.handleCharacter("g", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "việt. nghiếng")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 102.00), .committedComposingWord("nghiếng"))
        XCTAssertEqual(proxy.buffer, "việt. nghiếng ")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 102.20), .insertedPeriodShortcut)
        XCTAssertEqual(proxy.buffer, "việt. nghiếng. ")

        // 3. Candidate selection (which appends trailing space) + internal selectionWillChange echo + Space #1 + Space #2 -> ". "
        for ch in "nam" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        adapter.commitCandidate("Nam", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "việt. nghiếng. Nam ")
        XCTAssertTrue(adapter.justInsertedCandidateWithTrailingSpace)
        adapter.handleSelectionWillChange(isInternalEcho: true)
        XCTAssertTrue(adapter.justInsertedCandidateWithTrailingSpace, "Internal selectionWillChange echo must not clear candidate trailing-space flag")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 103.00), .absorbedAfterCandidateTrailingSpace)
        XCTAssertEqual(proxy.buffer, "việt. nghiếng. Nam ")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 103.22), .insertedPeriodShortcut)
        XCTAssertEqual(proxy.buffer, "việt. nghiếng. Nam. ")
        // Calling a third time after ". " must insert a normal space without deleting ". "
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 103.35), .insertedSpace)
        XCTAssertEqual(proxy.buffer, "việt. nghiếng. Nam.  ")

        // 4. Genuine external selectionWillChange (cursor moved to different context) cancels pending first Space tap
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "test" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 110.00), .committedComposingWord("test"))
        XCTAssertEqual(proxy.buffer, "test ")
        proxy.buffer = "te"
        XCTAssertFalse(adapter.handleSelectionWillChange(isInternalEcho: false, proxy: proxy, now: 110.18))
        XCTAssertEqual(adapter.lastSpaceTapTime, 0, "External selectionWillChange with diverged context must reset lastSpaceTapTime")
        proxy.buffer = "test "
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 110.20), .insertedSpace)
        XCTAssertEqual(proxy.buffer, "test  ")

        // 4b. Long paragraph (>240 UTF-8 bytes where shadowBeforeInput truncates to 80 chars) + Space #1 + Space #2 -> ". "
        let longPrefix = String(repeating: "Trường đại học Bách Khoa thành phố Hồ Chí Minh ", count: 6)
        proxy.buffer = longPrefix
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "vieetj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        let nowLong = Date().timeIntervalSince1970
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: nowLong), .committedComposingWord("việt"))
        XCTAssertTrue(proxy.buffer.hasSuffix("việt "))
        XCTAssertTrue(adapter.handleSelectionWillChange(isInternalEcho: false, proxy: proxy, now: nowLong + 0.30))
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: nowLong + 0.35), .insertedPeriodShortcut)
        XCTAssertTrue(proxy.buffer.hasSuffix("việt. "))

        // 5. Stale cache guard: host externally mutates "hello " -> "helloX" while cachedBeforeInput still holds "hello "
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "hello" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 120.00), .committedComposingWord("hello"))
        XCTAssertEqual(proxy.buffer, "hello ")
        XCTAssertEqual(adapter.cachedBeforeInput, "hello ")
        // Simulate external host mutation to "helloX" without notifying adapter first
        proxy.buffer = "helloX"
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: 120.15), .insertedSpace)
        XCTAssertEqual(proxy.buffer, "helloX ", "Must never delete non-space character 'X' when host mutated buffer")
        XCTAssertEqual(adapter.cachedBeforeInput, "helloX ")
        proxy.buffer = "helloX"
        XCTAssertFalse(adapter.deleteTrailingSpaceBeforePunctuation(proxy: proxy))
        XCTAssertEqual(proxy.buffer, "helloX")

        // 6. Incremental O(1) rawFastMask & renderedOutputIsASCII state on VietnameseEngine
        adapter.session.reset()
        XCTAssertTrue(adapter.session.engine.renderedOutputIsASCII)
        XCTAssertEqual(adapter.session.engine.rawFastMask & 0x0100, 0)
        for ch in "coding" {
            adapter.handleCharacter(ch, proxy: proxy)
            XCTAssertTrue(adapter.session.engine.renderedOutputIsASCII)
            XCTAssertEqual(adapter.session.engine.rawFastMask & 0x0100, 0)
        }
        XCTAssertEqual(adapter.session.rawWord, "coding")
    }

    func testPostCodaModifierUntonedStopCodaSyllablesNeverRevertToRaw() {
        SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()

        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)

        let cases: [(raw: String, expected: String)] = [
            ("truocw", "trươc"),
            ("luocw", "lươc"),
            ("cuocw", "cươc"),
            ("luotw", "lươt"),
            ("muocw", "mươc"),
            ("nuocw", "nươc"),
            ("buocw", "bươc"),
            ("dduocw", "đươc"),
            ("mucw", "mưc"),
            ("lucw", "lưc"),
            ("macw", "măc"),
            ("capw", "căp"),
            ("catw", "căt"),
            ("nhata", "nhât"),
            ("tiepe", "tiêp"),
            ("viece", "viêc"),
            ("cuoco", "cuôc"),
            ("thuoco", "thuôc"),
            ("docd", "đoc"),
            ("datd", "đat"),
            ("Truocw", "Trươc"),
            ("Luocw", "Lươc"),
            ("Cuocw", "Cươc"),
            ("Luotw", "Lươt"),
            ("Muocw", "Mươc")
        ]

        var timestamp = 200.0
        for (raw, expected) in cases {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in raw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, expected, "Inline composition for '\(raw)' must be '\(expected)', not raw")
            XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp), .committedComposingWord(expected))
            XCTAssertEqual(proxy.buffer, expected + " ", "Committed output after Space for '\(raw)' must remain '\(expected) ', never reverted to '\(raw) '")
            timestamp += 1.0
        }

        // Also verify continuing with tone keys before Space (`truocws -> trước`, `luotwj -> lượt`)
        // and post-commit Backspace + tone key (`truocw` + Space + Backspace + `s` -> `trước`).
        let tonedCases: [(raw: String, expected: String)] = [
            ("truocws", "trước"),
            ("truocwj", "trược"),
            ("luocws", "lước"),
            ("luocwj", "lược"),
            ("cuocws", "cước"),
            ("cuocwj", "cược"),
            ("luotws", "lướt"),
            ("luotwj", "lượt"),
            ("muocws", "mước"),
            ("muocwj", "mược")
        ]
        for (raw, expected) in tonedCases {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in raw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, expected, "Toned composition for '\(raw)' must be '\(expected)'")
            XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp), .committedComposingWord(expected))
            XCTAssertEqual(proxy.buffer, expected + " ")
            timestamp += 1.0
        }

        // Post-commit Backspace into `trươc ` + `s` -> `trước`
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "truocw" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp), .committedComposingWord("trươc"))
        XCTAssertEqual(proxy.buffer, "trươc ")
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "trươc")
        adapter.handleCharacter("s", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "trước")

        // Ensure English compounds with overwritten interior 'w' like `howto` still restore to raw `howto`
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "howto" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 10.0), .committedComposingWord("howto"))
        XCTAssertEqual(proxy.buffer, "howto ")
    }

    // MARK: — Bug B: Double Consonant Letter-Drop Fix

    /// Verifies that double consonants (ss, rr, ff, etc.) in English words are preserved
    /// and not swallowed by the engine's tone cancel mechanism.
    ///
    /// The fix ensures tone keys produce literals when the resulting toned syllable
    /// is NOT plausible Vietnamese (e.g. `monté` from `montes` is invalid).
    /// For valid Vietnamese syllables (e.g. `mé` from `mes`), tone is still applied
    /// normally and the cancel mechanism works as expected (matching Apple Telex).
    func testDoubleConsonantLetterDropPreservation() {
        SmartBilingualDetector.spellCheckerProvider = IOSSpellChecker()

        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let timestamp: TimeInterval = 1000.0

        // Case 1: montessori — engine must NOT apply tone to "monté" (non-plausible VN)
        // so "montes" + s → literal "montess", then "montesso" + r + i → "montessori"
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "montessori" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "montessori", "montessori inline must preserve double s")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp), .committedComposingWord("montessori"))
        XCTAssertEqual(proxy.buffer, "montessori ")

        // Case 2: session — double s after non-plausible "sesió" (non-standard onset)
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "session" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "session", "session inline must preserve double s")
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 1.0), .committedComposingWord("session"))

        // Case 3: message — double s with plausible intermediate "mé"
        // Engine correctly applies tone to "me" + s → "mé", then cancel → "mes"
        // SmartBilingual must restore to "message"
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "message" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 2.0), .committedComposingWord("message"))

        // Case 4: access — double c then double s
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "access" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 3.0), .committedComposingWord("access"))

        // Case 5: process — double s
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "process" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 4.0), .committedComposingWord("process"))

        // Case 6: office — double f (non-plausible "ó" from "of" + f... wait, "ó" IS plausible)
        // SmartBilingual must rescue
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "office" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 5.0), .committedComposingWord("office"))

        // Case 7: current — double r
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "current" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 6.0), .committedComposingWord("current"))

        // Case 8: directory — double r after "di" (which IS plausible VN onset)
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "directory" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 7.0), .committedComposingWord("directory"))

        // Case 9: Valid Vietnamese tone must still work — "mẹ" from m+e+j
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "mej" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "mẹ", "Valid VN tone must still be applied")

        // Case 10: Valid Vietnamese cancel — "tes" from t+e+s+s (matching Apple)
        // "te" + s → "té" (plausible VN) → "te" + ss → cancel → "tes"
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "tess" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "tes", "tess must produce tes (matching Apple Telex: cancel on plausible VN)")

        // Case 11: boss — SmartBilingual rescue for known English word
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "boss" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 8.0), .committedComposingWord("boss"))

        // Case 12: kuss — "kú" is NOT plausible VN, so s must be literal
        // "ku" + s → literal "kus" → "kus" + s → literal "kuss"
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "kuss" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "kuss", "kuss must preserve both s's (kú is non-plausible VN)")

        // Case 13: staff — double f
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "staff" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 9.0), .committedComposingWord("staff"))

        // Case 14: class — double s at end
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "class" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 10.0), .committedComposingWord("class"))

        // Case 15: press — double s
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "press" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 11.0), .committedComposingWord("press"))

        // Case 16: ruff — double f after non-plausible VN
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "ruff" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(adapter.handleSpaceTap(proxy: proxy, now: timestamp + 12.0), .committedComposingWord("ruff"))
    }

    // MARK: - Controller-Level Anti-Dropped-Char & Proxy Read Budget Suite (Vikey rtsim-inspired)

    /// Simulates a full two-sided (`before` + `after`) document proxy with `documentIdentifier`,
    /// cursor movement, and read/write counters to verify controller-level invariants.
    private final class ControllerSimDocumentProxy: TextDocumentProxyProtocol {
        var documentID: UUID = UUID()
        var beforeText: String = ""
        var afterText: String = ""
        var currentSelectedText: String? = nil

        var beforeReads: Int = 0
        var afterReads: Int = 0
        var selectedTextReads: Int = 0
        var insertCalls: Int = 0
        var deleteCalls: Int = 0

        var documentContextBeforeInput: String? {
            beforeReads += 1
            return beforeText
        }

        var documentContextAfterInput: String? {
            afterReads += 1
            return afterText.isEmpty ? nil : afterText
        }

        var selectedText: String? {
            selectedTextReads += 1
            return currentSelectedText
        }

        func insertText(_ text: String) {
            insertCalls += 1
            if currentSelectedText != nil {
                currentSelectedText = nil
            }
            beforeText.append(text)
        }

        func deleteBackward() {
            deleteCalls += 1
            if currentSelectedText != nil {
                currentSelectedText = nil
                return
            }
            if !beforeText.isEmpty {
                beforeText.removeLast()
            }
        }

        var fullText: String {
            beforeText + (currentSelectedText ?? "") + afterText
        }

        /// Moves the cursor to a character offset from the start of `fullText`.
        func moveCursor(toOffset offset: Int) {
            let combined = beforeText + afterText
            let clamped = max(0, min(combined.count, offset))
            let idx = combined.index(combined.startIndex, offsetBy: clamped)
            beforeText = String(combined[..<idx])
            afterText = String(combined[idx...])
            currentSelectedText = nil
        }
    }

    /// Mirrors `KeyboardViewController`'s synchronous keystroke + suggestion context + document-ID guard pipeline.
    private final class ControllerHarness {
        let adapter = UIKitInputSessionAdapter()
        var cachedCommittedContext: String = ""
        var lastInternalEditTime: TimeInterval = 0
        var lastInternalEditDocumentID: UUID?
        var wordSuggestionsEnabled: Bool = true

        var displayedVietnameseContext: SuggestionInputContext?
        var displayedVietnameseAnchor: SuggestionDocumentAnchor?
        var displayedVietnameseDocumentID: UUID?
        var currentSuggestionItems: [SuggestionCandidate] = []

        init() {
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
        }

        func buildSuggestionContext() -> SuggestionInputContext {
            SuggestionInputContext(
                beforeContext: cachedCommittedContext,
                afterContext: "",
                composingWord: adapter.session.composingWord,
                rawWord: adapter.session.rawWord,
                isComposing: adapter.session.isComposing,
                macroEnabled: adapter.session.macroEnabled,
                typingMode: adapter.literalOverrideEnabled ? .literalABC : .vietnamese
            )
        }

        func syncCachedContextFromProxy(_ proxy: ControllerSimDocumentProxy) {
            let before = adapter.effectiveContextBeforeInput(proxy: proxy) ?? ""
            if adapter.session.isComposing {
                let comp = adapter.session.composingWord
                if !comp.isEmpty && before.hasSuffix(comp) {
                    cachedCommittedContext = String(before.dropLast(comp.count))
                    return
                }
            }
            cachedCommittedContext = String(before.suffix(80))
        }

        func appendToCachedContext(_ text: String) {
            guard !text.isEmpty else { return }
            cachedCommittedContext.append(text)
            if cachedCommittedContext.count > 80 {
                cachedCommittedContext = String(cachedCommittedContext.suffix(80))
            }
        }

        /// Synchronous per-keystroke turn matching `KeyboardViewController.onKeyTapped`.
        @discardableResult
        func tapKey(_ ch: Character, proxy: ControllerSimDocumentProxy, now: TimeInterval) -> SuggestionInputContext {
            lastInternalEditTime = now
            lastInternalEditDocumentID = proxy.documentID
            let wasComposing = adapter.session.isComposing
            let priorComposing = adapter.session.composingWord
            if adapter.literalOverrideEnabled {
                adapter.handleLiteralCharacter(ch, proxy: proxy)
            } else {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            if !adapter.session.isComposing {
                let lastCommitted = adapter.session.engine.lastCommittedWord ?? ""
                let committedWord = wasComposing ? (lastCommitted.isEmpty ? priorComposing : lastCommitted) : ""
                appendToCachedContext(committedWord + String(ch))
            }
            // Synchronous portion of updateSuggestions() builds context in-memory with 0 proxy reads
            return buildSuggestionContext()
        }

        func tapSpace(proxy: ControllerSimDocumentProxy, now: TimeInterval) {
            lastInternalEditTime = now
            lastInternalEditDocumentID = proxy.documentID
            let outcome = adapter.handleSpaceTap(proxy: proxy, periodShortcutEnabled: true, now: now)
            switch outcome {
            case .insertedPeriodShortcut:
                if cachedCommittedContext.hasSuffix(" ") {
                    cachedCommittedContext.removeLast()
                }
                appendToCachedContext(". ")
            case .absorbedAfterCandidateTrailingSpace:
                break
            case .committedComposingWord(let word):
                appendToCachedContext(word + " ")
            case .insertedSpace:
                appendToCachedContext(" ")
            }
        }

        func tapBackspace(proxy: ControllerSimDocumentProxy, now: TimeInterval) {
            lastInternalEditTime = now
            lastInternalEditDocumentID = proxy.documentID
            adapter.handleBackspace(proxy: proxy)
            syncCachedContextFromProxy(proxy)
        }

        /// Simulates the debounced suggestion worker completing for a snapshot captured at `scheduleSuggestionCheck`.
        func completeDebouncedSuggestionTurn(
            capturedContext: SuggestionInputContext,
            capturedGeneration: UInt64,
            capturedDocumentID: UUID,
            capturedAnchor: SuggestionDocumentAnchor?,
            liveProxy: ControllerSimDocumentProxy
        ) -> Bool {
            guard wordSuggestionsEnabled,
                  !adapter.literalOverrideEnabled,
                  adapter.session.isCurrentGeneration(capturedGeneration),
                  liveProxy.documentID == capturedDocumentID,
                  buildSuggestionContext() == capturedContext,
                  let anchor = capturedAnchor,
                  anchor.matches(
                      before: adapter.cachedBeforeInput ?? liveProxy.documentContextBeforeInput,
                      after: liveProxy.documentContextAfterInput,
                      hasSelection: liveProxy.selectedText?.isEmpty == false
                  ) else {
                return false
            }
            let items = WordSuggestionEngine.shared.suggest(context: capturedContext, limit: 3)
            displayedVietnameseContext = capturedContext
            displayedVietnameseAnchor = anchor
            displayedVietnameseDocumentID = capturedDocumentID
            currentSuggestionItems = items
            return true
        }

        /// Simulates tapping a suggestion pill on `CandidateBarView` with all controller guards active.
        func selectSuggestion(_ suggestion: SuggestionCandidate, proxy: ControllerSimDocumentProxy) -> Bool {
            let currentCtx = buildSuggestionContext()
            if displayedVietnameseDocumentID != proxy.documentID ||
                displayedVietnameseContext != currentCtx ||
                !currentSuggestionItems.contains(suggestion) ||
                displayedVietnameseAnchor?.matches(
                    before: proxy.documentContextBeforeInput,
                    after: proxy.documentContextAfterInput,
                    hasSelection: proxy.selectedText?.isEmpty == false
                ) != true {
                adapter.handleExternalTextChange(proxy: proxy)
                syncCachedContextFromProxy(proxy)
                currentSuggestionItems = []
                return false
            }
            adapter.commitSuggestion(suggestion, proxy: proxy, trailingSpace: true)
            appendToCachedContext(suggestion.insertionText + " ")
            return true
        }

        /// Mirrors `KeyboardViewController.selectionWillChange` + `textDidChange` when cursor moves or field changes.
        func handleHostSelectionAndTextDidChange(proxy: ControllerSimDocumentProxy, now: TimeInterval) {
            let sameDocument = (lastInternalEditDocumentID == proxy.documentID)
            let isInternalEcho = adapter.handleSelectionWillChange(
                isInternalEcho: sameDocument && (now - lastInternalEditTime < 0.12),
                proxy: proxy,
                now: now
            )
            if !isInternalEcho {
                displayedVietnameseContext = nil
                displayedVietnameseAnchor = nil
                displayedVietnameseDocumentID = nil
                currentSuggestionItems = []
            }
            let suppressionWindow: TimeInterval = adapter.session.isComposing ? 0.65 : 0.35
            if sameDocument && (now - lastInternalEditTime < suppressionWindow) {
                return
            }
            if sameDocument && adapter.isPendingDoubleSpaceContextIntact(proxy: proxy, now: now) {
                return
            }
            adapter.handleExternalTextChange(proxy: proxy)
            syncCachedContextFromProxy(proxy)
        }
    }

    func testControllerLevelRtsimMultiFingerRolloverBilingualCursorAndFieldSwitchInvariants() {
        let proxy = ControllerSimDocumentProxy()
        let controller = ControllerHarness()
        var clock: TimeInterval = 1_000.0

        // 1. Two-finger overlapping chord / rollover typing (key 1 down -> key 2 down flushes key 1 -> key 2 up commits key 2)
        // Verify exact character order and zero dropped/duplicated characters on rapid Vietnamese & English chords.
        var timingTracker = KeyboardInputTimingTracker<Int>()
        let chordPairs: [(Character, Character)] = [
            ("v", "i"), ("e", "e"), ("t", "j"), (" ", "s"), ("e", "n"), (" ", "t"), ("e", "s"), ("t", " ")
        ]
        var touchID = 0
        for (k1, k2) in chordPairs {
            touchID += 1
            let id1 = touchID
            touchID += 1
            let id2 = touchID
            clock += 0.018
            timingTracker.touchDown(owner: id1, timestamp: clock)
            clock += 0.012
            timingTracker.touchDown(owner: id2, timestamp: clock)
            // Rollover flushes k1 on k2 touchDown
            let flushSample = timingTracker.commit(owner: id1, triggerTimestamp: clock, handlerEnteredAt: clock + 0.001, source: .rollover)
            XCTAssertNotNil(flushSample.keyDownTimestamp)
            if k1 == " " {
                controller.tapSpace(proxy: proxy, now: clock)
            } else {
                _ = controller.tapKey(k1, proxy: proxy, now: clock)
            }
            // Release k2 commits k2
            clock += 0.015
            let releaseSample = timingTracker.commit(owner: id2, triggerTimestamp: clock, handlerEnteredAt: clock + 0.001, source: .touchUpInside)
            XCTAssertNotNil(releaseSample.keyDownTimestamp)
            if k2 == " " {
                controller.tapSpace(proxy: proxy, now: clock)
            } else {
                _ = controller.tapKey(k2, proxy: proxy, now: clock)
            }
        }
        XCTAssertEqual(proxy.fullText, "việt sen test ")

        // 2. Continuous VI–EN code-switching + ABC literal override toggle in the same field
        // Count proxy reads per keystroke while wordSuggestionsEnabled == true!
        proxy.beforeText = ""
        proxy.afterText = ""
        controller.handleHostSelectionAndTextDidChange(proxy: proxy, now: clock + 1.0)
        clock += 1.0

        let mixedStream = "Hoom nay team deploy banr release mowis vaf fix bug montessori "
        for ch in mixedStream {
            clock += 0.025
            let prevBefore = proxy.beforeReads
            let prevAfter = proxy.afterReads
            let prevSelected = proxy.selectedTextReads

            if ch == " " {
                controller.tapSpace(proxy: proxy, now: clock)
            } else {
                let ctx = controller.tapKey(ch, proxy: proxy, now: clock)
                XCTAssertEqual(ctx.rawWord, controller.adapter.session.rawWord)
            }

            // Synchronous keystroke + suggestion context build must NEVER add extra proxy reads beyond the adapter's 1-read budget!
            XCTAssertLessThanOrEqual(proxy.beforeReads - prevBefore, 1, "Keystroke '\(ch)' exceeded 1 beforeContext read with suggestions enabled")
            XCTAssertEqual(proxy.afterReads - prevAfter, 0, "Synchronous keystroke '\(ch)' must perform 0 afterContext reads")
            XCTAssertLessThanOrEqual(proxy.selectedTextReads - prevSelected, 1, "Keystroke '\(ch)' exceeded 1 selectedText read")
        }
        XCTAssertEqual(proxy.fullText, "Hôm nay team deploy bản release mới và fix bug montessori ")

        // Toggle ABC literal override mid-sentence, type raw Telex keys, then toggle back to Vietnamese
        controller.adapter.literalOverrideEnabled = true
        for ch in "telex_raw " {
            clock += 0.02
            if ch == " " {
                controller.tapSpace(proxy: proxy, now: clock)
            } else {
                _ = controller.tapKey(ch, proxy: proxy, now: clock)
            }
        }
        controller.adapter.literalOverrideEnabled = false
        for ch in "chuaanr " {
            clock += 0.02
            if ch == " " {
                controller.tapSpace(proxy: proxy, now: clock)
            } else {
                _ = controller.tapKey(ch, proxy: proxy, now: clock)
            }
        }
        XCTAssertEqual(proxy.fullText, "Hôm nay team deploy bản release mới và fix bug montessori telex_raw chuẩn ")

        // 3. Space followed by Backspace (reopen committed word at editCaretBack == 0) and edit tone
        // Type "thays" -> "tháy", Space -> "tháy ", Backspace -> "tháy" (armed at editCaretBack == 0), "f" -> "thày", Space -> "thày "
        for ch in "thays" {
            clock += 0.02
            _ = controller.tapKey(ch, proxy: proxy, now: clock)
        }
        clock += 0.02
        controller.tapSpace(proxy: proxy, now: clock)
        XCTAssertTrue(proxy.fullText.hasSuffix("tháy "))
        clock += 0.02
        controller.tapBackspace(proxy: proxy, now: clock)
        XCTAssertTrue(proxy.fullText.hasSuffix("tháy"))
        clock += 0.02
        _ = controller.tapKey("f", proxy: proxy, now: clock)
        clock += 0.02
        controller.tapSpace(proxy: proxy, now: clock)
        XCTAssertTrue(proxy.fullText.hasSuffix("thày "), "Space + Backspace + 'f' must edit armed 'tháy' into 'thày ' (got '\(proxy.fullText)')")

        // 4. Cursor moves away into the middle of the text and returns:
        // Verify zero corruption of text outside the composing region (both beforePrefix and afterText remain intact)
        let snapshotBeforeCursorMove = proxy.fullText
        // Move cursor right after "Hôm nay " (offset 8)
        proxy.moveCursor(toOffset: 8)
        clock += 0.20
        controller.handleHostSelectionAndTextDidChange(proxy: proxy, now: clock)
        let expectedSuffixAfterCursor = String(snapshotBeforeCursorMove.dropFirst(8))
        XCTAssertEqual(proxy.afterText, expectedSuffixAfterCursor)

        // Type "rất " at the middle cursor position
        for ch in "raats" {
            clock += 0.02
            _ = controller.tapKey(ch, proxy: proxy, now: clock)
        }
        clock += 0.02
        controller.tapSpace(proxy: proxy, now: clock)
        XCTAssertEqual(proxy.beforeText, "Hôm nay rất ")
        XCTAssertEqual(proxy.afterText, expectedSuffixAfterCursor, "Suffix after cursor must NEVER be modified while composing mid-sentence")

        // Move cursor back to the end of the document and type "tốt"
        proxy.moveCursor(toOffset: proxy.fullText.count)
        clock += 0.20
        controller.handleHostSelectionAndTextDidChange(proxy: proxy, now: clock)
        for ch in "toots" {
            clock += 0.02
            _ = controller.tapKey(ch, proxy: proxy, now: clock)
        }
        XCTAssertEqual(proxy.fullText, "Hôm nay rất " + expectedSuffixAfterCursor + "tốt")

        // 5. Switch text fields (`documentID` changes within 50ms of typing, inside the 0.65s suppression window)
        // while a suggestion from the old field is pending/displayed!
        let oldDocID = proxy.documentID
        let oldCapturedCtx = controller.buildSuggestionContext()
        let oldCapturedGen = controller.adapter.session.sessionGeneration
        let prevBeforeReadsForAnchor = proxy.beforeReads
        let prevAfterReadsForAnchor = proxy.afterReads
        let oldAnchor = SuggestionDocumentAnchor(
            before: controller.adapter.cachedBeforeInput ?? proxy.documentContextBeforeInput,
            after: proxy.documentContextAfterInput
        )
        // Anchor creation uses adapter.cachedBeforeInput (0 beforeReads) and 1 afterRead
        XCTAssertEqual(proxy.beforeReads - prevBeforeReadsForAnchor, 0, "Debounced suggestion anchor must reuse adapter.cachedBeforeInput (0 extra beforeReads)")
        XCTAssertEqual(proxy.afterReads - prevAfterReadsForAnchor, 1)

        // Complete suggestion worker on Field A first so `currentSuggestionItems` is populated
        XCTAssertTrue(
            controller.completeDebouncedSuggestionTurn(
                capturedContext: oldCapturedCtx,
                capturedGeneration: oldCapturedGen,
                capturedDocumentID: oldDocID,
                capturedAnchor: oldAnchor,
                liveProxy: proxy
            )
        )
        let staleSuggestionFromFieldA = controller.currentSuggestionItems.first!

        // Immediately (only 30ms later — inside the 0.65s suppression window!) user taps into Field B (`newDocID`)
        clock += 0.030
        proxy.documentID = UUID()
        proxy.beforeText = "Field B: "
        proxy.afterText = ""
        controller.handleHostSelectionAndTextDidChange(proxy: proxy, now: clock)

        // Verify Field A's composing state was reset immediately despite being within 0.65s of the last keystroke in Field A
        XCTAssertFalse(controller.adapter.session.isComposing, "Switching documentID within 30ms must not be suppressed as an internal echo")
        XCTAssertTrue(controller.currentSuggestionItems.isEmpty, "Pending suggestions from Field A must be cleared on documentID change")

        // Even if an in-flight worker from Field A finishes late, it must be rejected because documentID changed
        XCTAssertFalse(
            controller.completeDebouncedSuggestionTurn(
                capturedContext: oldCapturedCtx,
                capturedGeneration: oldCapturedGen,
                capturedDocumentID: oldDocID,
                capturedAnchor: oldAnchor,
                liveProxy: proxy
            )
        )
        // And attempting to select a stale suggestion from Field A must be rejected without mutating Field B
        XCTAssertFalse(controller.selectSuggestion(staleSuggestionFromFieldA, proxy: proxy))
        XCTAssertEqual(proxy.fullText, "Field B: ", "Field B text must remain completely untouched by Field A's stale suggestion")

        // Typing in Field B works cleanly without deleting characters from Field B's prefix;
        // standalone "His" prefers "His" while offering "Hí" in suggestions
        for ch in "His" {
            clock += 0.02
            _ = controller.tapKey(ch, proxy: proxy, now: clock)
        }
        XCTAssertEqual(proxy.fullText, "Field B: His")
        let fieldBCtx = controller.buildSuggestionContext()
        XCTAssertEqual(fieldBCtx.composingWord, "His")
        XCTAssertEqual(fieldBCtx.rawWord, "His")
        let fieldBSuggestions = WordSuggestionEngine.shared.suggest(context: fieldBCtx, limit: 3).map(\.displayText)
        XCTAssertTrue(fieldBSuggestions.contains("His"), "Field B composing 'His' must offer 'His' in suggestions")
        XCTAssertTrue(fieldBSuggestions.contains("Hí"), "Field B composing 'His' must also offer Vietnamese twin 'Hí' in suggestions (got \(fieldBSuggestions))")

        // Continuing to type " car is " after "His" keeps English context so "car" -> "car" and "is" -> "is"
        for ch in " car is " {
            clock += 0.02
            if ch == " " {
                controller.tapSpace(proxy: proxy, now: clock)
            } else {
                _ = controller.tapKey(ch, proxy: proxy, now: clock)
            }
        }
        XCTAssertEqual(proxy.fullText, "Field B: His car is ")

        // Typing "This is " after a Vietnamese sentence (even if host fires textDidChange after "This " before "is" is typed)
        // restores "Thí" -> "This" inline as soon as 's' of "is" is tapped!
        proxy.beforeText = "Xin chào. "
        clock += 1.0
        controller.handleHostSelectionAndTextDidChange(proxy: proxy, now: clock)
        for ch in "This" {
            clock += 0.02
            _ = controller.tapKey(ch, proxy: proxy, now: clock)
        }
        XCTAssertEqual(proxy.fullText, "Xin chào. Thí")
        clock += 0.02
        controller.tapSpace(proxy: proxy, now: clock)
        XCTAssertEqual(proxy.fullText, "Xin chào. Thí ")

        // Simulate a late/paused host textDidChange notification (> 0.7s after "This ")
        clock += 0.75
        controller.handleHostSelectionAndTextDidChange(proxy: proxy, now: clock)

        clock += 0.02
        _ = controller.tapKey("i", proxy: proxy, now: clock)
        XCTAssertEqual(proxy.fullText, "Xin chào. Thí i")
        clock += 0.02
        _ = controller.tapKey("s", proxy: proxy, now: clock)
        XCTAssertEqual(proxy.fullText, "Xin chào. This is", "Tapping 's' of 'is' after 'This ' must immediately restore 'Thí' -> 'This' inline")
        clock += 0.02
        controller.tapSpace(proxy: proxy, now: clock)
        XCTAssertEqual(proxy.fullText, "Xin chào. This is ")
    }

    func testSuggestionDocumentAnchorMatchesEmptyNilBeforeContext() {
        // Real iOS UITextDocumentProxy returns nil for documentContextBeforeInput in an empty text field;
        // KeyboardViewController falls back to cachedCommittedContext ("") so the empty-field anchor is non-nil
        let cachedCommittedContext = ""
        let proxyBefore: String? = nil
        let anchorFromEmptyFallback = SuggestionDocumentAnchor(before: proxyBefore ?? cachedCommittedContext, after: nil)
        XCTAssertNotNil(anchorFromEmptyFallback, "Empty text field fallback must produce a valid SuggestionDocumentAnchor")
        XCTAssertTrue(anchorFromEmptyFallback?.matches(before: proxyBefore ?? cachedCommittedContext, after: nil, hasSelection: false) == true)
        XCTAssertTrue(anchorFromEmptyFallback?.matches(before: "", after: nil, hasSelection: false) == true)

        // Genuinely unavailable context (both nil) remains nil
        XCTAssertNil(SuggestionDocumentAnchor(before: nil, after: nil))
    }

    func testContextualURLWebSearchAndEmailSuggestionsCommitWithoutSpaces() {
        let proxy = MockTextDocumentProxy()
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)

        // 1. Empty URL field offers ["https://", "www.", ".com"]
        let initialURL = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .url,
            beforeContext: "",
            composingWord: "",
            rawWord: "",
            isComposing: false
        )
        XCTAssertEqual(initialURL?.map(\.displayText), ["https://", "www.", ".com"])
        adapter.commitSuggestion(initialURL![0], proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "https://")

        // 2. After "https://", offers ["www.", ".com", ".vn"]
        let afterScheme = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .url,
            beforeContext: proxy.buffer,
            composingWord: "",
            rawWord: "",
            isComposing: false
        )
        XCTAssertEqual(afterScheme?.map(\.displayText), ["www.", ".com", ".vn"])
        adapter.commitSuggestion(afterScheme![0], proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "https://www.")

        // 3. Typing "vnexpress" (even if Telex composed "vnexpré") and tapping ".net" restores raw ASCII + ".net" without space
        for ch in "vnexpress" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        let afterDomainStem = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .url,
            beforeContext: "https://www.",
            composingWord: adapter.session.composingWord,
            rawWord: adapter.session.rawWord,
            isComposing: adapter.session.isComposing
        )
        XCTAssertEqual(afterDomainStem?.map(\.displayText), [".com", ".vn", ".net"])
        adapter.commitSuggestion(afterDomainStem![2], proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "https://www.vnexpress.net")

        // 4. WebSearch field: empty offers URL starters, but Vietnamese words or spaces fall back to nil (Vietnamese engine)
        let emptySearch = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .webSearch,
            beforeContext: "",
            composingWord: "",
            rawWord: "",
            isComposing: false
        )
        XCTAssertEqual(emptySearch?.map(\.displayText), ["https://", "www.", ".com"])
        let vnQuerySearch = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .webSearch,
            beforeContext: "thời",
            composingWord: "thời",
            rawWord: "thoiwf",
            isComposing: true
        )
        XCTAssertNil(vnQuerySearch, "Valid Vietnamese syllable in .webSearch must fall through to Vietnamese suggestions")

        // 5. Email field: typing username and tapping "@gmail.com" commits without spaces
        proxy.buffer = ""
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "nguyenvana" {
            adapter.handleLiteralCharacter(ch, proxy: proxy)
        }
        let emailLocalSuggestions = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .emailAddress,
            beforeContext: "",
            composingWord: adapter.session.composingWord,
            rawWord: adapter.session.rawWord,
            isComposing: adapter.session.isComposing
        )
        XCTAssertEqual(emailLocalSuggestions?.map(\.displayText), ["@gmail.com", "@icloud.com", "@outlook.com"])
        adapter.commitSuggestion(emailLocalSuggestions![0], proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "nguyenvana@gmail.com")

        // 6. Universal '@' quick email domain suggestions in any field (.standard):
        // Typing "user@" or "@" offers all 5 domains: gmail.com, icloud.com, outlook.com, yahoo.com, live.com
        let universalAtSuggestions = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .standard,
            beforeContext: "Liên hệ: nguyenvana@",
            composingWord: "",
            rawWord: "",
            isComposing: false
        )
        XCTAssertEqual(
            universalAtSuggestions?.map(\.displayText),
            ["gmail.com", "icloud.com", "outlook.com", "yahoo.com", "live.com"]
        )
        proxy.buffer = "Liên hệ: nguyenvana@"
        adapter.handleExternalTextChange(proxy: proxy)
        adapter.commitSuggestion(universalAtSuggestions![3], proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "Liên hệ: nguyenvana@yahoo.com")

        // Prefix filtering after '@' (e.g., "user@li" -> "live.com")
        proxy.buffer = "user@"
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "li" {
            adapter.handleLiteralCharacter(ch, proxy: proxy)
        }
        let filteredLiveDomain = WordSuggestionEngine.contextualFieldSuggestions(
            fieldKind: .standard,
            beforeContext: "user@",
            composingWord: adapter.session.composingWord,
            rawWord: adapter.session.rawWord,
            isComposing: adapter.session.isComposing
        )
        XCTAssertEqual(filteredLiveDomain?.map(\.displayText), ["live.com"])
        adapter.commitSuggestion(filteredLiveDomain![0], proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "user@live.com")

        // 7. Opening bracket '(', '[', '{', '<' offers closing bracket ')', ']', '}', '>' immediately & while composing inside
        for (opener, closer) in [("(", ")"), ("[", "]"), ("{", "}"), ("<", ">")] {
            let immediateCloser = WordSuggestionEngine.contextualFieldSuggestions(
                fieldKind: .standard,
                beforeContext: "Ghi chú \(opener)",
                composingWord: "",
                rawWord: "",
                isComposing: false
            )
            XCTAssertEqual(immediateCloser?.map(\.displayText), [closer], "Opening '\(opener)' must immediately suggest closing '\(closer)'")
        }

        // Typing "(vieetj" inside unclosed '(' pins ')' in WordSuggestionEngine.suggest and commits "(việt)" without losing "việt"
        proxy.buffer = "("
        adapter.handleExternalTextChange(proxy: proxy)
        for ch in "vieetj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "(việt")
        let insideBracketSuggestions = WordSuggestionEngine.shared.suggest(
            context: SuggestionInputContext(
                beforeContext: "(",
                afterContext: "",
                composingWord: adapter.session.composingWord,
                rawWord: adapter.session.rawWord,
                isComposing: adapter.session.isComposing,
                macroEnabled: false
            ),
            limit: 3
        )
        XCTAssertEqual(insideBracketSuggestions.last?.displayText, ")", "Unclosed '(' on current line must pin ')' in candidate bar")
        adapter.commitSuggestion(insideBracketSuggestions.last!, proxy: proxy, trailingSpace: false)
        XCTAssertEqual(proxy.buffer, "(việt)")
    }
}
