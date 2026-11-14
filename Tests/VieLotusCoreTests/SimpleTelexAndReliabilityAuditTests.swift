import XCTest
@testable import VieLotusCore

private final class AsyncSimulatingTextDocumentProxy: TextDocumentProxyProtocol {
    var realBuffer: String = ""
    /// Simulates a delayed/stale XPC snapshot reported by `documentContextBeforeInput`
    var reportedSnapshot: String?
    var simulateAsyncXPC: Bool = true

    var documentContextBeforeInput: String? {
        if simulateAsyncXPC {
            return reportedSnapshot
        }
        return realBuffer
    }

    var documentContextAfterInput: String? {
        return nil
    }

    func insertText(_ text: String) {
        realBuffer.append(text)
        if !simulateAsyncXPC {
            reportedSnapshot = realBuffer
        }
    }

    func deleteBackward() {
        if !realBuffer.isEmpty {
            realBuffer.removeLast()
        }
        if !simulateAsyncXPC {
            reportedSnapshot = realBuffer
        }
    }
}

final class SimpleTelexAndReliabilityAuditTests: XCTestCase {
    private var previousSpellCheckerProvider: SpellCheckerProvider?

    override func setUp() {
        super.setUp()
        previousSpellCheckerProvider = SmartBilingualDetector.spellCheckerProvider
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif
    }

    override func tearDown() {
        SmartBilingualDetector.spellCheckerProvider = previousSpellCheckerProvider
        super.tearDown()
    }

    // MARK: - Issue A: Simple Telex Standalone 'w' & Valid Combinations

    func testStandaloneWRemainsWByDefaultAcrossAllProfiles() {
        for profile in GrammarProfile.allCases {
            let engine = VietnameseEngine()
            engine.grammarProfile = profile
            XCTAssertTrue(engine.simpleTelex, "Simple Telex must be enabled by default")

            XCTAssertEqual(engine.transform(Array("w")), "w", "profile=\(profile): standalone 'w' -> 'w'")
            XCTAssertEqual(engine.transform(Array("W")), "W", "profile=\(profile): standalone 'W' -> 'W'")

            let session = InputSessionManager()
            session.setGrammarProfile(profile)
            _ = session.handleCharacter("w")
            XCTAssertEqual(session.composingWord, "w", "session composing 'w' must be 'w' in \(profile)")
            guard case let .commit(_, committedW, _) = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ") else {
                return XCTFail("Expected commit for standalone 'w'")
            }
            XCTAssertEqual(committedW, "w")

            let adapter = UIKitInputSessionAdapter()
            adapter.session.setGrammarProfile(profile)
            let proxy = MockTextDocumentProxy()
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "w")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "w ")
            adapter.handleCharacter("W", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "w W")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "w W ")

            // Repeated 'w' keystrokes and post-commit space + backspace + 'w' must be 1-to-1 ("w" -> "ww" -> "www")
            let adapter2 = UIKitInputSessionAdapter()
            adapter2.session.setGrammarProfile(profile)
            let proxy2 = MockTextDocumentProxy()
            adapter2.handleCharacter("w", proxy: proxy2)
            XCTAssertEqual(proxy2.buffer, "w")
            adapter2.handleCharacter("w", proxy: proxy2)
            XCTAssertEqual(proxy2.buffer, "ww", "profile=\(profile): typing 'w' twice in Simple Telex must display 'ww'")
            adapter2.handleCharacter(" ", proxy: proxy2)
            XCTAssertEqual(proxy2.buffer, "ww ")
            adapter2.handleBackspace(proxy: proxy2)
            XCTAssertEqual(proxy2.buffer, "ww")
            adapter2.handleCharacter("w", proxy: proxy2)
            XCTAssertEqual(proxy2.buffer, "www", "profile=\(profile): 'ww' + space + backspace + 'w' must become 'www'")

            // Single 'w' + space + backspace + 'w' must become 'ww' (never jump to 'www')
            let adapter3 = UIKitInputSessionAdapter()
            adapter3.session.setGrammarProfile(profile)
            let proxy3 = MockTextDocumentProxy()
            adapter3.handleCharacter("w", proxy: proxy3)
            XCTAssertEqual(proxy3.buffer, "w")
            adapter3.handleCharacter(" ", proxy: proxy3)
            XCTAssertEqual(proxy3.buffer, "w ")
            adapter3.handleBackspace(proxy: proxy3)
            XCTAssertEqual(proxy3.buffer, "w")
            adapter3.handleCharacter("w", proxy: proxy3)
            XCTAssertEqual(proxy3.buffer, "ww", "profile=\(profile): 'w' + space + backspace + 'w' must become 'ww'")
        }
    }

    func testValidWCombinationsPreservedUnderSimpleTelex() {
        let cases: [(raw: String, expected: String)] = [
            ("aw", "ă"),
            ("AW", "Ă"),
            ("ow", "ơ"),
            ("OW", "Ơ"),
            ("uw", "ư"),
            ("UW", "Ư"),
            ("uow", "ươ"),
            ("uaw", "ưa"),
            ("uwa", "ưa"),
            ("uuw", "ưu"),
            ("uwu", "ưu"),
            ("uwaa", "ưaa"),
            ("muwaa", "mưaa"),
            ("wa", "wa"),
            ("wu", "wu"),
            ("cswap", "cswap"),
            ("bswap", "bswap"),
            ("ws", "ứ"),
            ("wr", "ử"),
            ("was", "ứa"),
            ("wus", "ứu"),
            ("ww", "ww"),
            ("www", "www"),
            ("wwww", "wwww"),
            ("aww", "aw"),
            ("oww", "ow"),
            ("uww", "uw"),
            ("toans", "toán"),
            ("truowngf", "trường"),
            ("nguowif", "người"),
            ("muowif", "mười"),
            ("buowms", "bướm")
        ]

        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let engine = VietnameseEngine()
            engine.grammarProfile = profile
            for (raw, expected) in cases {
                XCTAssertEqual(
                    engine.transform(Array(raw)),
                    expected,
                    "profile=\(profile): '\(raw)' must transform to '\(expected)'"
                )
            }
        }
    }

    func testOPRSCFlexibleKeyOrderingAndAmbiguityProtection() {
        for profile in [GrammarProfile.smartHybrid, .senFlex] {
            let engine = VietnameseEngine()
            engine.grammarProfile = profile

            // 1. OPRSC unambiguous valid Vietnamese permutations
            let validOPRSC: [(raw: String, expected: String)] = [
                ("truowfng", "trường"),
                ("truwowngf", "trường"),
                ("truowngf", "trường"),
                ("truwfowng", "trường"),
                ("trwfuong", "trường"),
                ("trwuongf", "trường"),
                ("nwuongs", "nướng"),
                ("thwuongr", "thưởng"),
                ("buwsowm", "bướm"),
                ("muwfowi", "mười"),
                ("nguwfowi", "người"),
                ("gwuong", "gương"),
                ("lwuong", "lương"),
                ("twuong", "tương"),
                ("cwam", "căm"),
                ("gwapj", "gặp"),
                ("cfung", "cùng"),
                ("ddson", "đón"),
                ("nhana", "nhân"),
                ("nhanas", "nhấn"),
                ("nhansa", "nhấn"),
                ("theem", "thêm"),
                ("themef", "thềm"),
                ("themfe", "thềm"),
                ("trongo", "trông"),
                ("tuongw", "tương"),
                ("nuocws", "nước")
            ]

            for (raw, expected) in validOPRSC {
                XCTAssertEqual(
                    engine.transform(Array(raw)),
                    expected,
                    "profile=\(profile): OPRSC sequence '\(raw)' expected '\(expected)'"
                )
            }

            // 2. Ambiguous / English sequences must NEVER be forced into corrupted Vietnamese
            let nonForcedInputs: [String] = [
                "w", "W",
                "theme", "themes", "meme", "memes", "gene", "genes", "data", "photo", "photos", "moto", "goto", "mono", "momo",
                "twin", "swim", "twig", "twit",
                "two", "swap", "swan", "swam", "sword", "dwarf",
                "new", "web", "wifi", "window", "world", "water", "write", "wrong"
            ]
            for raw in nonForcedInputs {
                XCTAssertEqual(
                    engine.transform(Array(raw)),
                    raw,
                    "profile=\(profile): ambiguous/English sequence '\(raw)' must remain literal '\(raw)'"
                )
            }
        }
    }

    // MARK: - Issue B: Rapid Delete / Retype Reliability & Ghost Resurrection Prevention

    func testRapidDeletionOfLongInvalidStringsDoesNotMutateIntoDiacritics() {
        let rawInvalidStrings = [
            "asdfghjklqwertyuiop",
            "toansdfghjkl",
            "restricts",
            "wertyuiop"
        ]

        for raw in rawInvalidStrings {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            adapter.smartBilingual = true
            let proxy = MockTextDocumentProxy()

            for ch in raw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, raw, "Long invalid/English string '\(raw)' should display as literal raw before backspace")

            // Rapidly backspace every character one by one
            var expectedRemaining = raw
            while !expectedRemaining.isEmpty {
                expectedRemaining.removeLast()
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(
                    proxy.buffer,
                    expectedRemaining,
                    "Rapid backspace on '\(raw)' must deterministically remove 1 character without spontaneous diacritic mutation"
                )
            }
            XCTAssertFalse(adapter.session.isComposing)
        }

        // Also test a long string starting with a valid Vietnamese syllable followed by garbage ("truowngfxyzabc" -> "trưỡngyzabc"):
        // Backspacing pops the literal suffix ("yzabc") 1 char at a time down to "trưỡng", then applies semantic backspace
        // ("trưỡng" -> "trương" -> "truong" -> "truon" -> "truo" -> "tru" -> "tr" -> "t" -> "").
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()
        for ch in "truowngfxyzabc" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "trưỡngyzabc")
        let expectedSteps = [
            "trưỡngyzab", "trưỡngyza", "trưỡngyz", "trưỡngy", "trưỡng",
            "trương", "truong", "truon", "truo", "tru", "tr", "t", ""
        ]
        for expected in expectedSteps {
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, expected)
        }
        XCTAssertFalse(adapter.session.isComposing)
    }

    func testFullDeletionFollowedByImmediateRetypingNeverResurrectsDeletedWord() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()

        // Scenario 1: Commit "chào ", hold backspace to delete everything + extra backspaces on empty field,
        // then immediately type "s", "f", "a", "d", "w", or a new sentence.
        let triggerNextStarts: [(retype: String, expected: String)] = [
            ("s", "s"),
            ("f", "f"),
            ("r", "r"),
            ("x", "x"),
            ("j", "j"),
            ("d", "d"),
            ("a", "a"),
            ("w", "w"),
            ("saos", "sáo"),
            ("dduowngf", "đường"),
            ("xin chaof", "xin chào")
        ]

        for (retype, expected) in triggerNextStarts {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)

            // Type and commit "trường "
            for ch in "truowngf " {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường ")

            // Hold Backspace (delete "trường " = 7 chars + 5 extra repeat ticks on empty buffer)
            for _ in 0..<12 {
                adapter.handleBackspace(proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "")
            XCTAssertFalse(adapter.session.isComposing)
            XCTAssertNil(adapter.session.engine.lastCommittedWord, "Committed history must be purged after full word deletion")

            // Immediately type new characters
            for ch in retype {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(
                proxy.buffer,
                expected,
                "Retyping '\(retype)' immediately after full backspace must produce '\(expected)' with zero ghost resurrection"
            )
        }
    }

    func testAsyncXPCOutOfOrderSnapshotDuringRapidBackspaceNeverCorruptsRetype() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = AsyncSimulatingTextDocumentProxy()

        // Type "việt nam "
        for ch in "vieetj nam " {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.realBuffer, "việt nam ")

        // Simulate rapid Backspace where XPC snapshots arrive out of order / lagging behind realBuffer
        let staleSnapshots = [
            "việt nam ",
            "việt nam",
            "việt na",
            "việt na", // lagging duplicate
            "việt n",
            "việt ",
            "việt",
            "việ",
            "việ",     // lagging duplicate
            "vi",
            "v",
            "vi"       // out-of-order stale XPC notification arriving while realBuffer is already empty!
        ]
        for snap in staleSnapshots {
            proxy.reportedSnapshot = snap
            adapter.handleBackspace(proxy: proxy)
        }
        XCTAssertEqual(proxy.realBuffer, "")

        // Immediately type "toans" -> "toán" while reportedSnapshot is still stale
        for ch in "toans" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.realBuffer, "toán")
    }

    func testHostTextDivergenceSafeReconciliationAndSolverFailureSafety() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()

        // 1. User types "trường" (composing)
        for ch in "truowngf" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "trường")
        XCTAssertTrue(adapter.session.isComposing)

        // 2. Third-party app externally replaces buffer (e.g. autocomplete or cursor jump) WITHOUT calling textDidChange
        proxy.buffer = "Hello "

        // 3. Next keystroke must safely reconcile and not delete into "Hello "
        for ch in "vieetj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "Hello việt")

        // 4. Commit "việt " -> Backspace space -> type invalid consonant 'k' or 'z' that fails phonotactics:
        //    must NEVER expose raw Telex "vieetjk" or corrupt "việt"
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hello việt ")
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hello việt")
        adapter.handleCharacter("k", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Hello việtk", "Invalid post-commit consonant must simply append 'k' without exposing raw Telex 'vieetjk'")
    }

    func testSessionGenerationIDIncrementsOnEverySessionBoundary() {
        let session = InputSessionManager()
        let gen0 = session.sessionGeneration
        XCTAssertTrue(session.isCurrentGeneration(gen0))

        _ = session.handleCharacter("t")
        let gen1 = session.sessionGeneration
        XCTAssertNotEqual(gen0, gen1)
        XCTAssertFalse(session.isCurrentGeneration(gen0))
        XCTAssertTrue(session.isCurrentGeneration(gen1))

        _ = session.handleCharacter("a")
        XCTAssertEqual(session.sessionGeneration, gen1, "In-word keystrokes belong to the same session generation")

        _ = session.handleBackspace()
        _ = session.handleBackspace() // deletes to empty -> .reset
        let gen2 = session.sessionGeneration
        XCTAssertNotEqual(gen1, gen2, "Deleting composition to empty must advance sessionGeneration")
    }

    func testUnicodeNFCAndNFDAndEmojiSynchronizationDuringRapidEdits() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()

        // Seed NFD decomposed Vietnamese text + multi-scalar emoji
        let nfdPrefix = "👨‍👩‍👧‍👦 Cộng hoà ".decomposedStringWithCanonicalMapping
        proxy.buffer = nfdPrefix
        adapter.handleExternalTextChange(proxy: proxy)

        for ch in "xax hooij" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, nfdPrefix + "xã hội")

        // Rapidly delete "xã hội" ("hội" = 5 semantic steps + " " = 1 + "xã" = 2 chars = 8 backspaces) and retype "chur nghiax" -> "chủ nghĩa"
        for _ in 0..<8 {
            adapter.handleBackspace(proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, nfdPrefix)

        for ch in "chur nghiax" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, nfdPrefix + "chủ nghĩa")
    }

    func testPropertyBasedRandomDeleteAndRetypeInvariants() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()

        let corpus: [(raw: String, expected: String)] = [
            ("w", "w"),
            ("aw", "ă"),
            ("ow", "ơ"),
            ("uw", "ư"),
            ("truowngf", "trường"),
            ("trwfuong", "trường"),
            ("nguwfowi", "người"),
            ("vietej", "việt"),
            ("toans", "toán"),
            ("asdfghjkl", "asdfghjkl"),
            ("twin", "twin"),
            ("window", "window"),
            ("ddoois", "đối"),
            ("nhanas", "nhấn")
        ]

        var rngState: UInt64 = 0x5EED_CAFE_2026_1022
        func nextRandom(bound: Int) -> Int {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Int((rngState >> 33) % UInt64(bound))
        }

        for iteration in 0..<150 {
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)

            // Type 1 to 3 words with random noise / partial deletes, then delete everything and type a target word
            let wordCount = 1 + nextRandom(bound: 3)
            for _ in 0..<wordCount {
                let sample = corpus[nextRandom(bound: corpus.count)]
                for ch in sample.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                if nextRandom(bound: 2) == 0 {
                    adapter.handleCharacter(" ", proxy: proxy)
                }
            }

            // Hold Backspace until buffer is completely empty + extra repeat ticks
            let deleteTicks = proxy.buffer.count + 4 + nextRandom(bound: 8)
            for _ in 0..<deleteTicks {
                adapter.handleBackspace(proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "", "Iteration \(iteration): buffer must be empty after full backspace burst")
            XCTAssertFalse(adapter.session.isComposing, "Iteration \(iteration): session must not be composing on empty buffer")

            // Immediately retype a fresh word from corpus
            let target = corpus[nextRandom(bound: corpus.count)]
            for ch in target.raw {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(
                proxy.buffer,
                target.expected,
                "Iteration \(iteration): retyping '\(target.raw)' after rapid delete must yield '\(target.expected)'"
            )
        }
    }

    // MARK: - Unified Telex Correctness & State Integrity V1 Regression Matrix (C1 - C6 & D)

    func testC1AppleStyleBackspaceAndZCancellation() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(profile)
            let proxy = MockTextDocumentProxy()

            // 1. đúng -> đung -> đun
            for ch in "ddungs" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "đúng", "profile=\(profile)")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đung", "profile=\(profile): đúng -> đung")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đun", "profile=\(profile): đung -> đun")

            // 2. được -> đươc -> đuoc -> đuo -> đu -> đ -> d -> ""
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "dduowcj" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "được", "profile=\(profile)")
            let expectedDuocBackspaceChain = ["đươc", "đuoc", "đuo", "đu", "đ", "d", ""]
            for expected in expectedDuocBackspaceChain {
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, expected, "profile=\(profile): expected '\(expected)' in được backspace chain")
            }

            // 3. đúng + z -> đung, đung + z -> đungz
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "ddungs" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "đúng", "profile=\(profile)")
            adapter.handleCharacter("z", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đung", "profile=\(profile): đúng + z -> đung")
            adapter.handleCharacter("z", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đungz", "profile=\(profile): đung + z -> đungz")

            // Direct untoned đung + z -> đungz
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "ddungz" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "đungz", "profile=\(profile): untoned đung + z -> đungz")
        }
    }

    func testC2VowelModificationAndLiteralFallback() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(profile)
            let proxy = MockTextDocumentProxy()

            // 1. trường + o -> truồng
            for ch in "truongwf" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile)")
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng", "profile=\(profile): trường + o -> truồng")

            // 2. Policy 3B+: trường + w -> trườngw (+ w -> trườngww), Backspace -> trườngw -> Backspace -> trường -> + s -> trướng -> + o -> truống -> + o -> truốngo -> + o -> truốngoo
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "truongwf" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile)")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngw", "profile=\(profile): trường + w -> trườngw (semantic saturation preserves horn and tone)")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngww", "profile=\(profile): trườngw + w -> trườngww (second w appends literally)")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngw", "profile=\(profile): Backspace removes second literal w back to trườngw")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile): Backspace removes first literal w back to trường")
            adapter.handleCharacter("s", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trướng", "profile=\(profile): trường + s -> trướng")
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truống", "profile=\(profile): trướng + o -> truống")
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truốngo", "profile=\(profile): truống + o -> truốngo (semantic saturation preserves circumflex and tone)")
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truốngoo", "profile=\(profile): truốngo + o -> truốngoo (never locks keys)")

            // 3. Anti-raw-dump & post-coda modifier saturation cases: truonwgfswo -> trướngwo, truowngfxwf -> trưỡngwf, congror -> cổngr
            let antiRawCases: [(raw: String, expected: String)] = [
                ("truonwgfswo", "trướngwo"),
                ("truowngfxwf", "trưỡngwf"),
                ("congror", "cổngr")
            ]
            for tc in antiRawCases {
                proxy.buffer = ""
                adapter.handleExternalTextChange(proxy: proxy)
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, tc.expected, "profile=\(profile): '\(tc.raw)' must produce '\(tc.expected)'")
            }
        }
    }

    func testC3ReopenPreviousCompositionAndHostVerification() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(profile)
            let proxy = MockTextDocumentProxy()

            // 1. truồng -> Space -> Backspace -> w -> trường
            for ch in "truoongf" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "truồng", "profile=\(profile)")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng ", "profile=\(profile)")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng", "profile=\(profile)")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile): truồng -> Space -> Backspace -> w -> trường")

            // 2. Longer sequence involving trường -> (+o) truồng -> Space -> Backspace -> Backspace -> truồn -> (+w) trườn -> Backspace -> trươn
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "truongwf" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile)")
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng", "profile=\(profile)")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng ", "profile=\(profile)")
            adapter.handleBackspace(proxy: proxy) // deletes space
            XCTAssertEqual(proxy.buffer, "truồng", "profile=\(profile)")
            adapter.handleBackspace(proxy: proxy) // deletes 'g' from committed truồng -> truồn
            XCTAssertEqual(proxy.buffer, "truồn", "profile=\(profile)")
            adapter.handleCharacter("w", proxy: proxy) // reshapes truồn -> trườn
            XCTAssertEqual(proxy.buffer, "trườn", "profile=\(profile)")
            adapter.handleBackspace(proxy: proxy) // semantic backspace on active trườn -> trươn
            XCTAssertEqual(proxy.buffer, "trươn", "profile=\(profile)")

            // 3. Safe host verification: if host text changes after Space deletion so it no longer ends with committed word,
            // never overwrite unverified host text.
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "truoongf " {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            adapter.handleBackspace(proxy: proxy) // armed editCaretBack = 0 on "truồng"
            proxy.buffer = "khác" // external cursor move / host edit without notification
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "khácw", "profile=\(profile): must disarm reopen when host text does not match committed word")
        }
    }

    func testC4FlexibleTelexOrderingAndC5DefectElimination() {
        let flexibleOrders = [
            "truongwf",
            "truongfw",
            "truowngf",
            "truwongf",
            "truwowngf",
            "trwuongf",
            "truowfng"
        ]

        for order in flexibleOrders {
            // 1. Base production -> trường
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            for ch in order {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường", "order '\(order)' must produce 'trường'")

            // 2. Policy 3B+: Append 'w' -> trườngw, + 'w' -> trườngww, Backspace x2 -> trường, then 's' -> trướng, 'f' -> trường
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngw", "order '\(order)' + w must saturate and append literal 'w' as 'trườngw'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngww", "order '\(order)' + ww must append second literal 'w' as 'trườngww'")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngw", "order '\(order)' + ww + Backspace must restore 'trườngw'")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường", "order '\(order)' + w + Backspace must restore 'trường'")
            adapter.handleCharacter("s", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trướng", "order '\(order)' + s must produce 'trướng'")
            adapter.handleCharacter("f", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường", "order '\(order)' + sf must restore 'trường'")

            // 3. Append 'o' -> truồng, then + w -> trường; append 'z' -> trương, then + z -> trươngz
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng", "order '\(order)' -> trường + o must produce 'truồng'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường", "order '\(order)' -> truồng + w must produce 'trường'")
            adapter.handleCharacter("z", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trương", "order '\(order)' -> trường + z must produce 'trương'")
            adapter.handleCharacter("z", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trươngz", "order '\(order)' -> trương + z must produce 'trươngz'")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trương", "order '\(order)' -> trươngz + Backspace must restore 'trương'")

            // 4. Repeated Backspace from 'trường' follows identical canonical semantic steps regardless of input order
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in order {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường")
            let expectedBackspaceSteps = ["trương", "truong", "truon", "truo", "tru", "tr", "t", ""]
            for expected in expectedBackspaceSteps {
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, expected, "order '\(order)' semantic backspace step expected '\(expected)'")
            }

            // 5. Insert Space, delete Space, then continue typing ('o' -> truồng, 's' -> trướng)
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in order {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường ")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trường")
            adapter.handleCharacter("o", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "truồng", "order '\(order)' + Space + Backspace + o -> truồng")
        }

        // Policy 3B+: Verify 'được' and 'đươc' across all flexible orders + 'w' saturates ('đượcw'/'đươcw') and second 'w' appends literal 'w' ('đượcww'/'đươcww')
        let duocOrders = ["dduowcj", "dduocwj", "dduocjw", "dduwocj", "dduwowcj"]
        for order in duocOrders {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            for ch in order {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "được", "order '\(order)' must produce 'được'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đượcw", "order '\(order)' + w must saturate to 'đượcw'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đượcww", "order '\(order)' + ww must append second literal 'w' as 'đượcww'")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đượcw", "order '\(order)' + ww + Backspace must restore 'đượcw'")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "được", "order '\(order)' + w + Backspace must restore 'được'")
            adapter.handleBackspace(proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đươc", "order '\(order)' + Backspace must strip tone to 'đươc'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đươcw", "order '\(order)' -> đươc + w must saturate to 'đươcw'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "đươcww", "order '\(order)' -> đươc + ww must produce 'đươcww'")
        }

        // Verify relaxedCoda 'truowgf' -> 'trường' + 'w' -> 'trườngw' + 'w' -> 'trườngww'
        do {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            adapter.session.setRelaxedCoda(true)
            let proxy = MockTextDocumentProxy()
            for ch in "truowgf" {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trường")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngw", "relaxedCoda truowgf + w must saturate to 'trườngw'")
            adapter.handleCharacter("w", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "trườngww", "relaxedCoda truowgf + ww must append second literal 'w' as 'trườngww'")
        }
    }

    func testC6RapidDeleteAndRetypeLongInvalidString() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()

        let invalidBurst = "sdjkadsalasdlkasdh"
        for ch in invalidBurst {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, invalidBurst)

        // Rapidly delete everything + extra held-backspace ticks
        for _ in 0..<(invalidBurst.count + 6) {
            adapter.handleBackspace(proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "")
        XCTAssertFalse(adapter.session.isComposing)

        // Immediately type a new Vietnamese word
        for ch in "dduowcj" {
            adapter.handleCharacter(ch, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "được")
    }

    // MARK: - C7. Strict Vietnamese Guard (4 Core Invariants & Literal Override)

    func testC7StrictVietnameseGuardFourInvariantsAndLiteralOverride() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // Case 1: Policy 3B+: trường -> +o -> truồng -> +o -> truồngo -> +o -> truồngoo -> +o -> truồngooo -> Space -> "truồngooo " (Zero Key Lock & Zero Raw Collapse)
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in "truongwf" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile)")

                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồng", "profile=\(profile): first +o reshapes trường -> truồng")
                XCTAssertEqual(adapter.session.rawWord, "truoongf", "profile=\(profile): rawWord must be canonicalized")

                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngo", "profile=\(profile): second +o saturates and appends literally truồng -> truồngo")

                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngoo", "profile=\(profile): third +o appends literally without locking keys")

                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngooo", "profile=\(profile): fourth +o appends literally without locking keys")

                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngooo ", "profile=\(profile): Space commits 'truồngooo ' without raw Telex collapse")
            }

            // Case 2: trường -> +o -> truồng -> +o -> truồngo -> +o -> truồngoo -> +o -> truồngooo -> Backspace x4 -> "trường" (Reversible Backspace)
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in "truongwf" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồng")
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngo")
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngoo")
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngooo")

                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngoo")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngo")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồng")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "trường", "profile=\(profile): Backspace reverses each step back to 'trường'")
            }

            // Case 3: trường -> +o -> truồng -> +o -> truồngo -> +o -> truồngoo -> +o -> truồngooo -> +u -> "truồngooou"
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in "truongwf" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                adapter.handleCharacter("o", proxy: proxy)
                adapter.handleCharacter("o", proxy: proxy)
                adapter.handleCharacter("o", proxy: proxy)
                adapter.handleCharacter("o", proxy: proxy)
                adapter.handleCharacter("u", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truồngooou", "profile=\(profile): +ooou after 'truồng' produces 'truồngooou' without key locking")
            }

            // Case 4: Explicit Literal Intent — Long-press literal key (`handleLiteralCharacter`) or `ABC` toggle (`literalOverrideEnabled`)
            // allows typing special strings like "truôngoou" or "truồngoou" without Space + Backspace.
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                // Type "truông" via Telex ("truoong"), then hold 'o', 'o', 'u' via Literal Override:
                for ch in "truoong" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "truông")
                adapter.handleLiteralCharacter("o", proxy: proxy)
                adapter.handleLiteralCharacter("o", proxy: proxy)
                adapter.handleLiteralCharacter("u", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truôngoou", "profile=\(profile): Literal Override via long-press allows typing 'truôngoou' directly")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truôngoo")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truôngo")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "truông")

                // Also test `ABC` toolbar toggle (`literalOverrideEnabled = true`) in-place after typing "truồng":
                proxy.buffer = ""
                adapter.handleExternalTextChange(proxy: proxy)
                for ch in "truongwfo" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "truồng")
                adapter.literalOverrideEnabled = true
                for ch in "oou" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "truồngoou", "profile=\(profile): ABC Literal Override toggle appends 'oou' verbatim without Space+Backspace")
            }
        }
    }

    // MARK: - C8. Tone-Only Z Cancellation (P0)

    func testC8ToneOnlyZCancellation() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // 1. roonj -> rộn -> (+z) rôn -> (+z) rônz -> (+z) rônzz -> Backspace -> rônz -> Backspace -> rôn -> Backspace -> rộn
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in "roonj" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "rộn", "profile=\(profile): roonj -> rộn")

                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "rôn", "profile=\(profile): roonjz -> rôn")

                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "rônz", "profile=\(profile): roonjzz -> rônz (must never generate roonz)")

                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "rônzz", "profile=\(profile): roonjzzz -> rônzz")

                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "rônz", "profile=\(profile): rônzz -> Backspace -> rônz")

                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "rôn", "profile=\(profile): rônz -> Backspace -> rôn")

                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "rộn", "profile=\(profile): rôn -> Backspace -> rộn")
            }

            // 2. được + z -> đươc, cấn + z -> cân, chữ + z -> chư, ô + z -> ôz (no active tone)
            let directCases: [(input: String, expectedAfterZ: String, expectedAfterSecondZ: String, expectedOriginalToned: String?)] = [
                ("dduowcj", "đươc", "đươcz", "được"),
                ("caans", "cân", "cânz", "cấn"),
                ("chuwx", "chư", "chưz", "chữ"),
                ("oo", "ôz", "ôzz", nil),
                ("aa", "âz", "âzz", nil),
                ("ee", "êz", "êzz", nil),
                ("aw", "ăz", "ăzz", nil),
                ("ow", "ơz", "ơzz", nil),
                ("uw", "ưz", "ưzz", nil),
                ("dd", "đz", "đzz", nil)
            ]

            for tc in directCases {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in tc.input {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                if let expectedToned = tc.expectedOriginalToned {
                    XCTAssertEqual(proxy.buffer, expectedToned, "profile=\(profile) input=\(tc.input)")
                }
                let beforeZ = proxy.buffer

                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expectedAfterZ, "profile=\(profile): '\(tc.input)' + z -> '\(tc.expectedAfterZ)'")

                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expectedAfterSecondZ, "profile=\(profile): '\(tc.input)' + zz -> '\(tc.expectedAfterSecondZ)'")

                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expectedAfterZ, "profile=\(profile): '\(tc.expectedAfterSecondZ)' -> Backspace -> '\(tc.expectedAfterZ)'")

                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, beforeZ, "profile=\(profile): '\(tc.expectedAfterZ)' -> Backspace -> '\(beforeZ)'")
            }

            // 3. Free-order Telex sequences + z + z + Backspace (for senFlex & smartHybrid)
            if profile != .classic {
                let freeOrderCases: [(input: String, toned: String, untoned: String, withLiteralZ: String)] = [
                    ("roojn", "rộn", "rôn", "rônz"),
                    ("rjoon", "rộn", "rôn", "rônz"),
                    ("rjon", "rọn", "ron", "ronz"),
                    ("dduowjc", "được", "đươc", "đươcz"),
                    ("ddwuocj", "được", "đươc", "đươcz"),
                    ("caasn", "cấn", "cân", "cânz"),
                    ("chxuw", "chữ", "chư", "chưz"),
                    ("truowfng", "trường", "trương", "trươngz"),
                    ("truwongf", "trường", "trương", "trươngz"),
                    ("trwuongf", "trường", "trương", "trươngz")
                ]

                for fc in freeOrderCases {
                    let adapter = UIKitInputSessionAdapter()
                    adapter.session.setInputMethod(.telex)
                    adapter.session.setGrammarProfile(profile)
                    let proxy = MockTextDocumentProxy()

                    for ch in fc.input {
                        adapter.handleCharacter(ch, proxy: proxy)
                    }
                    XCTAssertEqual(proxy.buffer, fc.toned, "profile=\(profile) freeOrder='\(fc.input)'")

                    adapter.handleCharacter("z", proxy: proxy)
                    XCTAssertEqual(proxy.buffer, fc.untoned, "profile=\(profile) freeOrder='\(fc.input)' + z -> '\(fc.untoned)'")

                    adapter.handleCharacter("z", proxy: proxy)
                    XCTAssertEqual(proxy.buffer, fc.withLiteralZ, "profile=\(profile) freeOrder='\(fc.input)' + zz -> '\(fc.withLiteralZ)'")

                    adapter.handleBackspace(proxy: proxy)
                    XCTAssertEqual(proxy.buffer, fc.untoned, "profile=\(profile) freeOrder='\(fc.input)' Backspace 1 -> '\(fc.untoned)'")

                    adapter.handleBackspace(proxy: proxy)
                    XCTAssertEqual(proxy.buffer, fc.toned, "profile=\(profile) freeOrder='\(fc.input)' Backspace 2 -> '\(fc.toned)'")
                }
            }
        }
    }

    func testLateVowelModifiersAndCodaContinuations() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let cases: [(raw: String, expectedAfterTone: String, expectedAfterMod: String, coda: Character?, expectedFinal: String)] = [
                ("casa", "cá", "cấ", "n", "cấn"),
                ("Casa", "Cá", "Cấ", "n", "Cấn"),
                ("casa", "cá", "cấ", "t", "cất"),
                ("casa", "cá", "cấ", "u", "cấu"),
                ("casa", "cá", "cấ", "y", "cấy"),
                ("masa", "má", "mấ", "n", "mấn"),
                ("Masa", "Má", "Mấ", "n", "Mấn"),
                ("maja", "mạ", "mậ", "n", "mận"),
                ("coso", "có", "cố", "n", "cốn"),
                ("toso", "tó", "tố", "t", "tốt"),
                ("tese", "té", "tế", "n", "tến"),
                ("bese", "bé", "bế", "n", "bến"),
                ("casw", "cá", "cắ", "n", "cắn"),
                ("masw", "má", "mắ", "n", "mắn")
            ]

            for tc in cases {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                let prefix3 = String(tc.raw.prefix(3))
                let modChar = tc.raw.last!
                for ch in prefix3 {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, tc.expectedAfterTone, "profile=\(profile) prefix=\(prefix3)")

                adapter.handleCharacter(modChar, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expectedAfterMod, "profile=\(profile) raw=\(tc.raw)")

                // Backspace reverses the late vowel modifier back to the toned base vowel
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expectedAfterTone, "profile=\(profile) backspace on \(tc.raw)")

                // Re-apply late vowel modifier and continue with coda
                adapter.handleCharacter(modChar, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.expectedAfterMod, "profile=\(profile) re-apply on \(tc.raw)")
                if let coda = tc.coda {
                    adapter.handleCharacter(coda, proxy: proxy)
                    XCTAssertEqual(proxy.buffer, tc.expectedFinal, "profile=\(profile) coda on \(tc.raw)\(coda)")
                }
            }
        }
    }

    func testVowelShapeModifierCancellationAndSymmetryWithZ() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let shapeUndoCases: [(raw: String, composed: String, modKey: Character, afterFirstMod: String, afterSecondMod: String, afterModThenZ: String)] = [
                // Policy 3B+: Horn / Breve ('w') semantic saturation + safe literal fallback
                ("nhuwngx", "những", "w", "nhữngw", "nhữngww", "nhữngwz"),
                ("nhungwx", "những", "w", "nhữngw", "nhữngww", "nhữngwz"),
                ("dduowcj", "được", "w", "đượcw", "đượcww", "đượcwz"),
                ("dduongwf", "đường", "w", "đườngw", "đườngww", "đườngwz"),
                ("truowngf", "trường", "w", "trườngw", "trườngww", "trườngwz"),
                ("truwowngf", "trường", "w", "trườngw", "trườngww", "trườngwz"),
                ("chuwngs", "chứng", "w", "chứngw", "chứngww", "chứngwz"),
                ("chungws", "chứng", "w", "chứngw", "chứngww", "chứngwz"),
                ("chuwng", "chưng", "w", "chưngw", "chưngww", "chưngwz"),
                ("bawngf", "bằng", "w", "bằngw", "bằngww", "bằngwz"),
                ("bangwf", "bằng", "w", "bằngw", "bằngww", "bằngwz"),
                // Policy 3B+: Circumflex ('a', 'e', 'o') semantic saturation + safe literal fallback
                ("caans", "cấn", "a", "cấna", "cấnaa", "cấnaz"),
                ("casan", "cấn", "a", "cấna", "cấnaa", "cấnaz"),
                ("caan", "cân", "a", "câna", "cânaa", "cânaz"),
                ("nhaanj", "nhận", "a", "nhậna", "nhậnaa", "nhậnaz"),
                ("meens", "mến", "e", "mếne", "mếnee", "mếnez"),
                ("leen", "lên", "e", "lêne", "lênee", "lênez"),
                ("tieengs", "tiếng", "e", "tiếnge", "tiếngee", "tiếngez"),
                ("nhoons", "nhốn", "o", "nhốno", "nhốnoo", "nhốnoz"),
                ("choon", "chôn", "o", "chôno", "chônoo", "chônoz"),
                ("muoons", "muốn", "o", "muốno", "muốnoo", "muốnoz"),
                // Open syllables & offglides ('để + e', 'đố + o', 'cố + o', 'kể + e', 'cấ + a', 'cử + w', 'sở + w', 'cắ + w', 'cửa + w', 'người + w')
                ("ddeer", "để", "e", "đểe", "đểee", "đểez"),
                ("ddere", "để", "e", "đểe", "đểee", "đểez"),
                ("ddoos", "đố", "o", "đốo", "đốoo", "đốoz"),
                ("ddoso", "đố", "o", "đốo", "đốoo", "đốoz"),
                ("toos", "tố", "o", "tốo", "tốoo", "tốoz"),
                ("coso", "cố", "o", "cốo", "cốoo", "cốoz"),
                ("coor", "cổ", "o", "cổo", "cổoo", "cổoz"),
                ("toof", "tồ", "o", "tồo", "tồoo", "tồoz"),
                ("booj", "bộ", "o", "bộo", "bộoo", "bộoz"),
                ("keer", "kể", "e", "kểe", "kểee", "kểez"),
                ("veef", "về", "e", "vềe", "vềee", "vềez"),
                ("leej", "lệ", "e", "lệe", "lệee", "lệez"),
                ("quees", "quế", "e", "quếe", "quếee", "quếez"),
                ("caas", "cấ", "a", "cấa", "cấaa", "cấaz"),
                ("casa", "cấ", "a", "cấa", "cấaa", "cấaz"),
                ("cuwr", "cử", "w", "cửw", "cửww", "cửwz"),
                ("curw", "cử", "w", "cửw", "cửww", "cửwz"),
                ("sowr", "sở", "w", "sởw", "sởww", "sởwz"),
                ("sorw", "sở", "w", "sởw", "sởww", "sởwz"),
                ("nhows", "nhớ", "w", "nhớw", "nhớww", "nhớwz"),
                ("nhosw", "nhớ", "w", "nhớw", "nhớww", "nhớwz"),
                ("caws", "cắ", "w", "cắw", "cắww", "cắwz"),
                ("casw", "cắ", "w", "cắw", "cắww", "cắwz"),
                ("cuwar", "cửa", "w", "cửaw", "cửaww", "cửawz"),
                ("cuarw", "cửa", "w", "cửaw", "cửaww", "cửawz"),
                ("nguowif", "người", "w", "ngườiw", "ngườiww", "ngườiwz"),
                ("tuooir", "tuổi", "o", "tuổio", "tuổioo", "tuổioz"),
                ("nhieeuf", "nhiều", "e", "nhiềue", "nhiềuee", "nhiềuez"),
                ("ddaauf", "đầu", "a", "đầua", "đầuaa", "đầuaz")
            ]

            for tc in shapeUndoCases {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, tc.composed, "profile=\(profile) raw=\(tc.raw)")

                // Policy 3B+: First press of modifier key saturates and appends literal modifier key
                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterFirstMod, "profile=\(profile) \(tc.raw) + \(tc.modKey)")

                // Verify Space after 1st press commits afterFirstMod + " " (never raw keystroke dump like ddeere / ddooso)
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterFirstMod + " ", "profile=\(profile) \(tc.raw) + \(tc.modKey) + Space")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterFirstMod)

                // Re-type in fresh session to verify 2nd press, Backspace 1 & 2, and + z
                proxy.buffer = ""
                adapter.handleExternalTextChange(proxy: proxy)
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterFirstMod)

                // Second press of modifier key appends second literal modifier key
                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterSecondMod, "profile=\(profile) \(tc.raw) + \(tc.modKey)\(tc.modKey)")

                // Verify Space after 2nd press commits afterSecondMod + " "
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterSecondMod + " ", "profile=\(profile) \(tc.raw) + \(tc.modKey)\(tc.modKey) + Space")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterSecondMod)

                // Re-type in fresh session to test active composition Backspace 1 & Backspace 2
                proxy.buffer = ""
                adapter.handleExternalTextChange(proxy: proxy)
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                adapter.handleCharacter(tc.modKey, proxy: proxy)
                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterSecondMod)

                // Backspace 1 removes the second literal modifier key -> back to afterFirstMod
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterFirstMod, "profile=\(profile) Backspace 1 on \(tc.afterSecondMod)")

                // Backspace 2 removes the first literal modifier key -> back to original composed syllable
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.composed, "profile=\(profile) Backspace 2 on \(tc.afterFirstMod)")

                // Re-apply modifier key then press 'z' -> appends literal 'z' after saturated literal modifier
                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterFirstMod)
                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterModThenZ, "profile=\(profile) \(tc.raw) + \(tc.modKey) + z")
            }

            // Also verify reverse order: 'z' first (strip tone) then 'w'/'a'/'e'/'o' (saturates and appends literal modifier)
            let zThenModCases: [(raw: String, composed: String, afterZ: String, modKey: Character, afterZThenMod: String, afterSecondMod: String)] = [
                ("chuwngs", "chứng", "chưng", "w", "chưngw", "chưngww"),
                ("nhuwngx", "những", "nhưng", "w", "nhưngw", "nhưngww"),
                ("dduowcj", "được", "đươc", "w", "đươcw", "đươcww"),
                ("truowngf", "trường", "trương", "w", "trươngw", "trươngww"),
                ("caans", "cấn", "cân", "a", "câna", "cânaa"),
                ("meens", "mến", "mên", "e", "mêne", "mênee"),
                ("nhoons", "nhốn", "nhôn", "o", "nhôno", "nhônoo")
            ]

            for tc in zThenModCases {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()

                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, tc.composed)

                adapter.handleCharacter("z", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterZ, "profile=\(profile) \(tc.raw) + z")

                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterZThenMod, "profile=\(profile) \(tc.raw) + z + \(tc.modKey)")

                adapter.handleCharacter(tc.modKey, proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.afterSecondMod, "profile=\(profile) \(tc.raw) + z + \(tc.modKey)\(tc.modKey)")
            }
        }
    }

    func testBackspaceStyleAndOfficialSuggestionPreservation() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // 1. BackspaceStyle: Apple-style semantic vs Gboard-style fast character deletion
            let appleAdapter = UIKitInputSessionAdapter()
            appleAdapter.session.setInputMethod(.telex)
            appleAdapter.session.setGrammarProfile(profile)
            XCTAssertEqual(appleAdapter.backspaceStyle, .appleSemantic)
            let appleProxy = MockTextDocumentProxy()
            for ch in "dduowcj" {
                appleAdapter.handleCharacter(ch, proxy: appleProxy)
            }
            XCTAssertEqual(appleProxy.buffer, "được")
            for step in ["đươc", "đuoc", "đuo", "đu", "đ", "d", ""] {
                appleAdapter.handleBackspace(proxy: appleProxy)
                XCTAssertEqual(appleProxy.buffer, step, "profile=\(profile) Apple-style Backspace expected '\(step)'")
            }

            let gboardAdapter = UIKitInputSessionAdapter()
            gboardAdapter.session.setInputMethod(.telex)
            gboardAdapter.session.setGrammarProfile(profile)
            gboardAdapter.backspaceStyle = .gboardCharacter
            let gboardProxy = MockTextDocumentProxy()
            for ch in "dduowcj" {
                gboardAdapter.handleCharacter(ch, proxy: gboardProxy)
            }
            XCTAssertEqual(gboardProxy.buffer, "được")
            for step in ["đượ", "đư", "đ", ""] {
                gboardAdapter.handleBackspace(proxy: gboardProxy)
                XCTAssertEqual(gboardProxy.buffer, step, "profile=\(profile) Gboard-style Backspace expected '\(step)'")
            }

            // 2. Official suggestion preservation: teh -> select "the" -> Backspace -> "th" (never "teh")
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(profile)
            for ch in "teh" {
                _ = session.handleCharacter(ch)
            }
            let commitAction = session.selectSuggestion("the", trailingSpace: false)
            guard case let .commit(_, committedText, isOverride) = commitAction else {
                return XCTFail("Expected commit from selectSuggestion")
            }
            XCTAssertEqual(committedText, "the")
            XCTAssertTrue(isOverride)
            let bsAction = session.handleBackspace()
            guard case let .replace(_, afterBs) = bsAction else {
                return XCTFail("Expected replace from Backspace after selectSuggestion")
            }
            XCTAssertEqual(afterBs, "th", "profile=\(profile): teh -> select 'the' -> Backspace must be 'th'")
        }
    }

    // MARK: - P0: Unexpected Autocorrection & Raw Replay Audit (khoog, hoog, khoogo, hoogo, khoong, hoong)

    func testP0KhoogHoogAutocorrectAndRawReplayAudit() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let telexCases: [(raw: String, stepByStep: [String], committedWithSpace: String)] = [
                ("khoog", ["k", "kh", "kho", "khô", "khôg"], "khôg "),
                ("hoog", ["h", "ho", "hô", "hôg"], "hôg "),
                ("khoogo", ["k", "kh", "kho", "khô", "khôg", "khôgo"], "khôgo "),
                ("hoogo", ["h", "ho", "hô", "hôg", "hôgo"], "hôgo "),
                ("khoong", ["k", "kh", "kho", "khô", "khôn", "không"], "không "),
                ("hoong", ["h", "ho", "hô", "hôn", "hông"], "hông ")
            ]

            for tc in telexCases {
                // 1. Core-only (VietnameseEngine default: relaxedCoda = false)
                let engine = VietnameseEngine()
                engine.inputMethod = .telex
                engine.grammarProfile = profile
                XCTAssertFalse(engine.relaxedCoda, "Default engine.relaxedCoda must be false (Telex-only)")

                var coreSteps: [String] = []
                for ch in tc.raw {
                    _ = engine.feed(ch)
                    coreSteps.append(engine.currentOutput())
                }
                XCTAssertEqual(coreSteps, tc.stepByStep, "Core-only profile=\(profile) raw=\(tc.raw)")

                // 2. iOS UIKitInputSessionAdapter (smartBilingual = true, inlineBilingualEnabled = true)
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                var iosSteps: [String] = []
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                    iosSteps.append(proxy.buffer)
                }
                XCTAssertEqual(iosSteps, tc.stepByStep, "iOS adapter profile=\(profile) raw=\(tc.raw)")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.committedWithSpace, "iOS commit profile=\(profile) raw=\(tc.raw)")

                // 3. macOS-equivalent InputSessionManager (smartBilingualEnabled = true, inlineBilingualEnabled = true)
                let macSession = InputSessionManager()
                macSession.setInputMethod(.telex)
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macSteps: [String] = []
                for ch in tc.raw {
                    _ = macSession.handleCharacter(ch)
                    macSteps.append(macSession.composingWord)
                }
                XCTAssertEqual(macSteps, tc.stepByStep, "macOS session profile=\(profile) raw=\(tc.raw)")
                let commitAct = macSession.commitWord(smartBilingualEnabled: true)
                if case let .commit(_, text, isOverride) = commitAct, isOverride {
                    XCTFail("profile=\(profile) raw=\(tc.raw) must NOT be overridden to '\(text)' on commit")
                }
            }

            // 4. Backspace chain on khôgo -> khôg -> khô -> kho -> kh -> k -> ""
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                for ch in "khoogo" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "khôgo")
                for expected in ["khôg", "khô", "kho", "kh", "k", ""] {
                    adapter.handleBackspace(proxy: proxy)
                    XCTAssertEqual(proxy.buffer, expected, "profile=\(profile) Backspace on khôgo expected '\(expected)'")
                }
            }

            // 5. Post-commit reopen: khoog + Space ("khôg ") + Backspace ("khôg") + o -> "khôgo" (never "khoogo")
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                for ch in "khoog " {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "khôg ")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "khôg")
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "khôgo", "profile=\(profile) post-commit khôg + o must be khôgo")
            }

            // 6. External Host Autocorrect mismatch guard (mid-composition & post-commit):
            // If host mutates "khôg" -> "không" on screen, typing "o" next must yield "khôngo" (never "khoogo")
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                for ch in "khoog" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "khôg")
                // Simulate external host autocorrect mutating "khôg" -> "không"
                proxy.buffer = "không"
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "khôngo", "profile=\(profile) host autocorrected không + o must be khôngo, never khoogo")
            }

            // 7. When relaxedCoda IS explicitly enabled: khoog -> không, khoogo -> khôngo (never khoogo)
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                adapter.session.engine.setRelaxedCoda(true)
                let proxy = MockTextDocumentProxy()
                for ch in "khoog" {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "không")
                adapter.handleCharacter("o", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "khôngo", "profile=\(profile) relaxedCoda=true: không + o must be khôngo, never khoogo")
            }
        }
    }

    // MARK: - C9. P0 Systemic Raw-Replay, Macro Contextual Protection & Generative Syllable Matrix

    func testP0SystemicRawReplayMacroAndGenerativeSyllableMatrix() {
        MacroEngine.shared.resetToDefaults()
        defer { MacroEngine.shared.resetToDefaults() }

        // 1. Macro & .vn / vn Contextual Protection Matrix
        do {
            let technicalInputs = [
                "vn ",
                ".vn ",
                "google.com.vn ",
                "vn.example.com ",
                "https://vn/path ",
                "user@vn.com ",
                "report_vn.pdf ",
                "vn_id ",
                "my-vn ",
                "vn-app ",
                "vn() ",
                "2vn ",
                "vn2 "
            ]

            // 1a. Default MacroEngine: "vn" is NOT in defaultMacros; all technical and standalone inputs remain unchanged
            for sample in technicalInputs {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.macroEnabled = true
                let proxy = MockTextDocumentProxy()
                for ch in sample {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, sample, "Default macro mode must preserve '\(sample)'")
            }

            // 1b. Explicit user-configured macro ("vn" -> "Việt Nam"):
            // Standalone prose "vn " expands, while ALL technical contexts (.vn, domains, URLs, emails, filenames, code) remain unexpanded!
            MacroEngine.shared.setMacro(key: "vn", value: "Việt Nam")
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.macroEnabled = true
                let proxy = MockTextDocumentProxy()
                for ch in "vn " {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "Việt Nam ", "Explicit user macro 'vn' must expand in standalone prose")
            }

            for sample in technicalInputs.dropFirst() {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.macroEnabled = true
                let proxy = MockTextDocumentProxy()
                for ch in sample {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, sample, "Explicit user macro 'vn' must STILL be suppressed in technical context '\(sample)'")
            }

            // 1c. Typing ".v" + Backspace + "vn " (where "." remains on screen) must still suppress macro expansion
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.macroEnabled = true
                let proxy = MockTextDocumentProxy()
                adapter.handleCharacter(".", proxy: proxy)
                adapter.handleCharacter("v", proxy: proxy)
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, ".")
                for ch in "vn " {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, ".vn ", "Deleting 'v' after '.' must keep '.' technical delimiter protection active")
            }
            MacroEngine.shared.resetToDefaults()
        }

        // 2. Confirmed Reproduction Targets: canhf -> cành + a / af / aa / w / repeated tones / Backspace / Space
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            let canhfCases: [(raw: String, steps: [String], committed: String)] = [
                ("canhf", ["c", "ca", "can", "canh", "cành"], "cành "),
                ("canhfa", ["c", "ca", "can", "canh", "cành", "cànha"], "cànha "),
                ("canhfaf", ["c", "ca", "can", "canh", "cành", "cànha", "cànhaf"], "cànhaf "),
                ("canhfaa", ["c", "ca", "can", "canh", "cành", "cànha", "cànhaa"], "cànhaa "),
                ("canhfw", ["c", "ca", "can", "canh", "cành", "cànhw"], "cànhw "),
                ("canhfww", ["c", "ca", "can", "canh", "cành", "cànhw", "cànhww"], "cànhww "),
                ("hongfw", ["h", "ho", "hon", "hong", "hòng", "hòngw"], "hòngw "),
                ("hoongfw", ["h", "ho", "hô", "hôn", "hông", "hồng", "hồngw"], "hồngw ")
            ]

            for tc in canhfCases {
                // Core
                let engine = VietnameseEngine()
                engine.inputMethod = .telex
                engine.grammarProfile = profile
                var coreSteps: [String] = []
                for ch in tc.raw {
                    _ = engine.feed(ch)
                    coreSteps.append(engine.currentOutput())
                }
                XCTAssertEqual(coreSteps, tc.steps, "Core profile=\(profile) raw=\(tc.raw)")

                // iOS adapter
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                var iosSteps: [String] = []
                for ch in tc.raw {
                    adapter.handleCharacter(ch, proxy: proxy)
                    iosSteps.append(proxy.buffer)
                }
                XCTAssertEqual(iosSteps, tc.steps, "iOS profile=\(profile) raw=\(tc.raw)")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, tc.committed, "iOS commit profile=\(profile) raw=\(tc.raw)")

                // macOS session
                let macSession = InputSessionManager()
                macSession.setInputMethod(.telex)
                macSession.setGrammarProfile(profile)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true
                var macSteps: [String] = []
                for ch in tc.raw {
                    _ = macSession.handleCharacter(ch)
                    macSteps.append(macSession.composingWord)
                }
                XCTAssertEqual(macSteps, tc.steps, "macOS profile=\(profile) raw=\(tc.raw)")
                let commitAct = macSession.commitWord(smartBilingualEnabled: true)
                if case let .commit(_, text, isOverride) = commitAct {
                    XCTAssertFalse(isOverride, "macOS commit must not override '\(tc.raw)' to '\(text)'")
                    XCTAssertEqual(text + " ", tc.committed)
                } else {
                    XCTFail("Expected .commit for \(tc.raw)")
                }
            }

            // Reversible Backspace & Post-Commit Reopen on canhfaf / canhfaa / canhfw
            for (overflowTail, midStates) in [
                ("af", ["cànhaf", "cànha", "cành"]),
                ("aa", ["cànhaa", "cànha", "cành"]),
                ("w", ["cànhw", "cành"])
            ] {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                for ch in ("canhf" + overflowTail) {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, midStates[0], "profile=\(profile) tail=\(overflowTail)")
                for expected in midStates.dropFirst() {
                    adapter.handleBackspace(proxy: proxy)
                    XCTAssertEqual(proxy.buffer, expected, "profile=\(profile) Backspace on \(midStates[0])")
                }
                // After returning to "cành", pressing Backspace strips tone to "canh", and retyping "f" restores "cành"
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "canh")
                adapter.handleCharacter("f", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "cành")
            }

            // Post-commit reopen: canhf + Space ("cành ") + Backspace ("cành") + af -> "cànhaf"
            do {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(profile)
                let proxy = MockTextDocumentProxy()
                for ch in "canhf " {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, "cành ")
                adapter.handleBackspace(proxy: proxy)
                XCTAssertEqual(proxy.buffer, "cành")
                adapter.handleCharacter("a", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "cànha")
                adapter.handleCharacter("f", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "cànhaf")
                adapter.handleCharacter(" ", proxy: proxy)
                XCTAssertEqual(proxy.buffer, "cànhaf ")
            }
        }

        // 3. Generative Property-Based Differential Matrix across all 12 Vietnamese vowels, codas, and tones
        let syllableSeeds: [(rawOrders: [String], expected: String, incompatibleTails: [String])] = [
            (["canhf", "cafnh"], "cành", ["a", "af", "aa", "e", "o", "w"]),
            (["basnh", "banhs"], "bánh", ["a", "as", "aa", "e", "o", "w"]),
            (["bats"], "bát", ["e", "es", "ee", "o"]),
            (["bawsn", "bawns"], "bắn", ["e", "o", "w", "ww"]),
            (["caans", "casan", "caasn"], "cấn", ["a", "as", "aa", "e", "o"]),
            (["ddeemj", "ddejme"], "đệm", ["e", "ej", "ee", "a", "o", "w"]),
            (["khieems", "khiesem"], "khiếm", ["e", "es", "ee", "a", "o", "w"]),
            (["minhf", "mifnh"], "mình", ["a", "af", "aa", "e", "o", "w"]),
            (["lichj", "lijch"], "lịch", ["a", "aj", "e", "o", "w"]),
            (["hongf", "hofng"], "hòng", ["a", "af", "e", "w", "ww"]),
            (["hoongf", "hofong"], "hồng", ["o", "of", "oo", "a", "e", "w"]),
            (["howns", "hoswn", "howsn"], "hớn", ["a", "e", "w", "ww"]),
            (["truowngr", "truongwr", "truwongr"], "trưởng", ["w", "wr", "ww", "a", "e"]),
            (["ddungs", "ddusng"], "đúng", ["a", "e", "o"]),
            (["huwngs", "huwsng"], "hứng", ["a", "e", "o", "w", "ww"]),
            (["quynhf", "quyfnh"], "quỳnh", ["a", "af", "e", "o", "w"])
        ]

        // Mutual-exclusion vowel reshape verification: bắn + a -> bấn, + a -> bấna
        do {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            for ch in "bawns" { adapter.handleCharacter(ch, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, "bắn")
            adapter.handleCharacter("a", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "bấn", "Mutual-exclusion vowel reshape: bắn + a -> bấn")
            adapter.handleCharacter("a", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "bấna", "Subsequent duplicate modifier overflows literally: bấn + a -> bấna")
        }

        for seed in syllableSeeds {
            for rawOrder in seed.rawOrders {
                for tail in seed.incompatibleTails {
                    let fullRaw = rawOrder + tail
                    let expectedFinal = seed.expected + tail

                    let adapter = UIKitInputSessionAdapter()
                    adapter.session.setInputMethod(.telex)
                    adapter.session.setGrammarProfile(.senFlex)
                    let proxy = MockTextDocumentProxy()

                    let macSession = InputSessionManager()
                    macSession.setInputMethod(.telex)
                    macSession.setGrammarProfile(.senFlex)
                    macSession.smartBilingualEnabled = true
                    macSession.inlineBilingualEnabled = true

                    for ch in fullRaw {
                        adapter.handleCharacter(ch, proxy: proxy)
                        _ = macSession.handleCharacter(ch)
                        XCTAssertEqual(
                            proxy.buffer,
                            macSession.composingWord,
                            "macOS/iOS differential mismatch on '\(fullRaw)' at char '\(ch)'"
                        )
                    }

                    XCTAssertEqual(
                        proxy.buffer,
                        expectedFinal,
                        "Syllable '\(rawOrder)' (\(seed.expected)) + '\(tail)' must preserve Unicode as '\(expectedFinal)', got '\(proxy.buffer)'"
                    )
                    XCTAssertFalse(
                        proxy.buffer.allSatisfy(\.isASCII),
                        "Syllable '\(fullRaw)' must NEVER collapse to raw ASCII '\(proxy.buffer)'"
                    )

                    // Verify Backspace undoes the literal overflow tail back to `seed.expected`
                    for _ in 0..<tail.count {
                        adapter.handleBackspace(proxy: proxy)
                        _ = macSession.handleBackspace()
                    }
                    XCTAssertEqual(
                        proxy.buffer,
                        seed.expected,
                        "Backspace after '\(fullRaw)' must restore '\(seed.expected)' on iOS"
                    )
                    XCTAssertEqual(
                        macSession.composingWord,
                        seed.expected,
                        "Backspace after '\(fullRaw)' must restore '\(seed.expected)' on macOS"
                    )

                    // Re-append tail and commit with Space
                    for ch in tail {
                        adapter.handleCharacter(ch, proxy: proxy)
                        _ = macSession.handleCharacter(ch)
                    }
                    adapter.handleCharacter(" ", proxy: proxy)
                    let macCommit = macSession.commitWord(smartBilingualEnabled: true)
                    XCTAssertEqual(
                        proxy.buffer,
                        expectedFinal + " ",
                        "Space commit on '\(fullRaw)' must preserve '\(expectedFinal) '"
                    )
                    if case let .commit(_, macCommittedText, isOverride) = macCommit {
                        XCTAssertFalse(isOverride, "macOS Space commit on '\(fullRaw)' must not override to raw")
                        XCTAssertEqual(macCommittedText, expectedFinal)
                    } else {
                        XCTFail("Expected .commit on macOS for '\(fullRaw)'")
                    }
                }
            }
        }
    }

    // MARK: - C10. P0.1 Runtime Validation & Regression Hardening (4 Review Points + 6-Item Checklist)

    func testP0_1RuntimeValidationAndRegressionHardeningChecklist() throws {
        // Point 1 & Checklist 5: Root cause of `khôg -> không` and `hôg -> hông`
        // Prove that `relaxedCoda` ("Tốc gõ phụ âm: Cuối (-g/-h/-k)") is the exact engine switch
        // that turns `khoog -> không` and `hoog -> hông`, and verify both `relaxedCoda = false` and `true`
        // preserve Unicode when `+ o` is typed (`khôgo` vs `khôngo`, `hôgo` vs `hôngo`).
        do {
            for (relaxed, expectedKhoog, expectedKhoogo, expectedHoog, expectedHoogo) in [
                (false, "khôg", "khôgo", "hôg", "hôgo"),
                (true, "không", "khôngo", "hông", "hôngo")
            ] {
                let macSession = InputSessionManager()
                macSession.setInputMethod(.telex)
                macSession.setGrammarProfile(.senFlex)
                macSession.setRelaxedCoda(relaxed)
                macSession.smartBilingualEnabled = true
                macSession.inlineBilingualEnabled = true

                for ch in "khoog" { _ = macSession.handleCharacter(ch) }
                XCTAssertEqual(macSession.composingWord, expectedKhoog, "relaxedCoda=\(relaxed) khoog")
                _ = macSession.handleCharacter("o")
                XCTAssertEqual(macSession.composingWord, expectedKhoogo, "relaxedCoda=\(relaxed) khoogo")
                macSession.reset()

                for ch in "hoog" { _ = macSession.handleCharacter(ch) }
                XCTAssertEqual(macSession.composingWord, expectedHoog, "relaxedCoda=\(relaxed) hoog")
                _ = macSession.handleCharacter("o")
                XCTAssertEqual(macSession.composingWord, expectedHoogo, "relaxedCoda=\(relaxed) hoogo")
            }
        }

        // Point 2: Macro Migration Provenance Safety
        // Verify untouched legacy factory-seeded `macros.json` drops `"vn": "Việt Nam"`,
        // while user-created `"vn": "Việt Nam"` (via setMacro or custom macros.json) is NEVER deleted.
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Case 2A: Untouched legacy factory-seeded macros.json -> migrates away `"vn": "Việt Nam"`
            let legacyFile = tempDir.appendingPathComponent("legacy_factory_macros.json")
            var legacyFactory = MacroEngine.defaultMacros
            legacyFactory["vn"] = "Việt Nam"
            let legacyData = try JSONSerialization.data(withJSONObject: legacyFactory, options: [.prettyPrinted])
            try legacyData.write(to: legacyFile)

            let migratedEngine = MacroEngine(storageURL: legacyFile, autoSaveToDisk: false)
            XCTAssertTrue(migratedEngine.loadFromDisk(url: legacyFile))
            XCTAssertNil(migratedEngine.lookup(word: "vn"), "Untouched legacy factory-seeded 'vn' macro must be migrated away")
            XCTAssertEqual(migratedEngine.lookup(word: "hn"), "Hà Nội", "Other factory defaults must remain intact")

            // Case 2B: User explicitly added `"vn": "Việt Nam"` via `setMacro` -> preserved across reload
            let userExplicitFile = tempDir.appendingPathComponent("user_explicit_macros.json")
            let userEngine = MacroEngine(storageURL: userExplicitFile, autoSaveToDisk: true)
            userEngine.setMacro(key: "vn", value: "Việt Nam")
            XCTAssertTrue(userEngine.userDefinedKeys.contains("vn"))
            XCTAssertTrue(userEngine.loadFromDisk(url: userExplicitFile))
            XCTAssertEqual(userEngine.lookup(word: "vn"), "Việt Nam", "Explicitly user-created 'vn -> Việt Nam' macro must NEVER be deleted by migration")

            // Case 2C: Custom macros.json containing custom user entries alongside `"vn": "Việt Nam"` -> preserved
            let customFile = tempDir.appendingPathComponent("custom_macros.json")
            var customDict = MacroEngine.defaultMacros
            customDict["vn"] = "Việt Nam"
            customDict["myco"] = "Công ty Cổ phần Sen Việt"
            let customData = try JSONSerialization.data(withJSONObject: customDict, options: [.prettyPrinted])
            try customData.write(to: customFile)

            let customEngine = MacroEngine(storageURL: customFile, autoSaveToDisk: false)
            XCTAssertTrue(customEngine.loadFromDisk(url: customFile))
            XCTAssertEqual(customEngine.lookup(word: "vn"), "Việt Nam", "User-customized macros.json must preserve 'vn -> Việt Nam'")
            XCTAssertEqual(customEngine.lookup(word: "myco"), "Công ty Cổ phần Sen Việt")
        }

        // Point 3 & Checklist 6: Locked Stem + Literal Tail under Mid-Word Caret Movement, Selection, and Cmd+Z Undo
        do {
            // 3A. Mid-word caret movement on iOS (`cànhaf` -> move caret to `cành|af` -> press `s` -> `cánh|af`)
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            for ch in "canhfaf" { adapter.handleCharacter(ch, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, "cànhaf")

            // Simulate user moving cursor left by 2 chars into `cành|af`:
            // `documentContextBeforeInput` is now `"cành"`.
            proxy.buffer = "cành"
            adapter.handleExternalTextChange(proxy: proxy)
            XCTAssertFalse(adapter.session.isComposing, "Moving caret into middle of word must close active composition")
            XCTAssertEqual(adapter.session.editCaretBack, 0, "Prefix 'cành' before caret must be armed for editing")
            adapter.handleCharacter("s", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "cánh", "Typing 's' at 'cành|af' must update stem tone to 'cánh' without stale lock")

            // 3B. Mid-word caret movement on macOS `InputSessionManager` (`stepCaretBack`)
            let macSession = InputSessionManager()
            macSession.setInputMethod(.telex)
            macSession.setGrammarProfile(.senFlex)
            for ch in "canhfaf" { _ = macSession.handleCharacter(ch) }
            XCTAssertEqual(macSession.composingWord, "cànhaf")
            XCTAssertTrue(macSession.isComposing)
            macSession.stepCaretBack()
            XCTAssertFalse(macSession.isComposing, "stepCaretBack while composing must commit/close active composition")
            XCTAssertEqual(macSession.editCaretBack, 1)
            macSession.stepCaretBack()
            XCTAssertEqual(macSession.editCaretBack, 2)
            // Typing at mid-word (`editCaretBack == 2`) starts fresh at the cursor without mutating the old locked stem
            let midAction = macSession.handleCharacter("x")
            XCTAssertEqual(midAction, .replace(backspaces: 0, text: "x"))
            XCTAssertEqual(macSession.composingWord, "x")

            // 3C. Selection overwrite & Cmd+Z Undo:
            // User types `canhfaf` (`cànhaf`), then presses Cmd+Z (host clears buffer to `""`), then types `vieetj` -> `việt`
            proxy.buffer = ""
            adapter.handleExternalTextChange(proxy: proxy)
            for ch in "vieetj" { adapter.handleCharacter(ch, proxy: proxy) }
            XCTAssertEqual(proxy.buffer, "việt", "Typing after Cmd+Z undo must start clean and never replay 'canhfaf'")
        }

        // Point 4 & Checklist 1–4: Host Presentation Profiles (TextEdit/Notes, Chrome/Electron, VS Code/Terminal, iOS)
        do {
            let hostBundles: [(name: String, bundleID: String, expectedMode: PresentationMode)] = [
                ("TextEdit", "com.apple.TextEdit", .directReplacement),
                ("Notes", "com.apple.Notes", .directReplacement),
                ("Chrome", "com.google.Chrome", .markedText),
                ("VS Code", "com.microsoft.VSCode", .markedText),
                ("Terminal", "com.apple.Terminal", .terminalDirect),
                ("Ghostty", "com.mitchellh.ghostty", .terminalDirect)
            ]
            for host in hostBundles {
                let category = ClientAdapter.classify(bundleIdentifier: host.bundleID)
                let mode = ClientAdapter.presentationMode(
                    for: category,
                    bundleIdentifier: host.bundleID,
                    terminalDirectEnabled: true,
                    passthroughRemoteApps: true,
                    preference: .automatic,
                    appOverrides: [:]
                )
                XCTAssertEqual(mode, host.expectedMode, "Host \(host.name) (\(host.bundleID)) presentation mode")
            }
        }
    }

    // MARK: - P0.2 Semantic Tone Escape & Canonical Return (`CancelToneAndEmitLiteral`)

    func testP0_2SemanticToneEscapeAndCanonicalReturn() {
        for profile in [GrammarProfile.classic, .smartHybrid, .senFlex] {
            // 1. Exact reproduction targets:
            // canhf + faa -> canhfaa (NOT canhffaa)
            // cafnh + faa -> canhfaa (NOT cafnhfaa)
            // canhr + raa -> canhraa (NOT canhrraa)
            // canhf + r -> cảnh
            // canhfr + r -> canhr
            let stepByStepSequences: [(raw: String, expectedSteps: [String])] = [
                ("canhffaa", ["c", "ca", "can", "canh", "cành", "canhf", "canhfa", "canhfaa"]),
                ("cafnhfaa", ["c", "ca", "cà", "càn", "cành", "canhf", "canhfa", "canhfaa"]),
                ("canhrraa", ["c", "ca", "can", "canh", "cảnh", "canhr", "canhra", "canhraa"]),
                ("canhfr",   ["c", "ca", "can", "canh", "cành", "cảnh"]),
                ("canhfrr",  ["c", "ca", "can", "canh", "cành", "cảnh", "canhr"]),
                ("canhfrraa", ["c", "ca", "can", "canh", "cành", "cảnh", "canhr", "canhra", "canhraa"]),
                ("hoongff",  ["h", "ho", "hô", "hôn", "hông", "hồng", "hôngf"]),
                ("hoonfgf",  ["h", "ho", "hô", "hôn", "hồn", "hồng", "hôngf"]),
                ("hoongffaa", ["h", "ho", "hô", "hôn", "hông", "hồng", "hôngf", "hôngfa", "hôngfaa"]),
                ("truowrngr", ["t", "tr", "tru", "truo", "trươ", "trưở", "trưởn", "trưởng", "trươngr"]),
                ("truowngrr", ["t", "tr", "tru", "truo", "trươ", "trươn", "trương", "trưởng", "trươngr"]),
                ("dduwsngs", ["d", "đ", "đu", "đư", "đứ", "đứn", "đứng", "đưngs"])
            ]

            for item in stepByStepSequences {
                let session = InputSessionManager()
                session.setInputMethod(.telex)
                session.setGrammarProfile(profile)
                var actualSteps: [String] = []
                for ch in item.raw {
                    _ = session.handleCharacter(ch)
                    actualSteps.append(session.composingWord)
                }
                XCTAssertEqual(actualSteps, item.expectedSteps, "profile=\(profile) raw=\(item.raw) step-by-step")
                let committed = session.commitWord(smartBilingualEnabled: true)
                if case .commit(_, let text, _) = committed {
                    XCTAssertEqual(text, item.expectedSteps.last, "profile=\(profile) raw=\(item.raw) commit must preserve escaped output")
                }
            }

            // 2. Multi-order Telex equivalence: `canhf + faa` and `cafnh + faa` must have identical canonical state and Backspace trajectory
            do {
                let s1 = InputSessionManager()
                s1.setInputMethod(.telex)
                s1.setGrammarProfile(profile)
                for ch in "canhffaa" { _ = s1.handleCharacter(ch) }

                let s2 = InputSessionManager()
                s2.setInputMethod(.telex)
                s2.setGrammarProfile(profile)
                for ch in "cafnhfaa" { _ = s2.handleCharacter(ch) }

                XCTAssertEqual(s1.composingWord, "canhfaa")
                XCTAssertEqual(s2.composingWord, "canhfaa")

                // Backspace trajectory: canhfaa -> canhfa -> canhf -> canh
                for expectedAfterBS in ["canhfa", "canhf", "canh"] {
                    _ = s1.handleBackspace()
                    _ = s2.handleBackspace()
                    XCTAssertEqual(s1.composingWord, expectedAfterBS, "profile=\(profile) s1 Backspace")
                    XCTAssertEqual(s2.composingWord, expectedAfterBS, "profile=\(profile) s2 Backspace")
                }
                XCTAssertEqual(s1.rawWord, "canh", "After backspacing escaped tail, s1 rawWord must be canonical untoned syllable")
                XCTAssertEqual(s2.rawWord, "canh", "After backspacing escaped tail, s2 rawWord must be canonical untoned syllable")
                // After returning to `canh`, typing `f` re-applies Huyền (`cành`) cleanly!
                _ = s1.handleCharacter("f")
                _ = s2.handleCharacter("f")
                XCTAssertEqual(s1.composingWord, "cành")
                XCTAssertEqual(s2.composingWord, "cành")
            }

            // 3. Modified vowel Backspace trajectory (`hôngfaa -> hôngfa -> hôngf -> hông`) across both Backspace styles
            for bsStyle in [BackspaceStyle.appleSemantic, .gboardCharacter] {
                let session = InputSessionManager()
                session.setInputMethod(.telex)
                session.setGrammarProfile(profile)
                session.setBackspaceStyle(bsStyle)
                for ch in "hoongffaa" { _ = session.handleCharacter(ch) }
                XCTAssertEqual(session.composingWord, "hôngfaa")
                _ = session.handleBackspace()
                XCTAssertEqual(session.composingWord, "hôngfa", "profile=\(profile) style=\(bsStyle)")
                _ = session.handleBackspace()
                XCTAssertEqual(session.composingWord, "hôngf", "profile=\(profile) style=\(bsStyle)")
                _ = session.handleBackspace()
                XCTAssertEqual(session.composingWord, "hông", "profile=\(profile) style=\(bsStyle)")
            }
        }
    }

    // MARK: - P0.3 Frequency-Aware Bilingual Intent Arbitration

    func testP0_3FrequencyAwareBilingualIntentArbitration() {
        // 1. Required Golden Phrase Matrix (P0.3 Section F)
        let goldenPhrases: [(input: String, expected: String)] = [
            ("tôi sex đi ", "tôi sẽ đi "),
            ("ngày mai sex có ", "ngày mai sẽ có "),
            ("safe sex ", "safe sex "),
            ("about sex education ", "about sex education "),
            ("she is here ", "she is here "),
            // Loanword `sex` in Vietnamese nominal contexts:
            ("phim sex ", "phim sex "),
            ("clip sex ", "clip sex "),
            ("video sex ", "video sex "),
            ("cảnh sex ", "cảnh sex "),
            // Explicit tone escape (`sexx -> sex`, `iss -> is`):
            ("sexx ", "sex "),
            ("iss ", "is "),
            ("sexx education ", "sex education ")
        ]

        for item in goldenPhrases {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            for ch in item.input {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, item.expected, "P0.3 Golden phrase failed for input: '\(item.input)'")
        }

        // Candidate selection & Experimental Frequency-Weighted policy for sentence-initial `sex education` and `this is good`:
        do {
            // In Experimental Frequency-Weighted policy (`bilingualNoContextPolicy = .experimentalFrequencyWeighted`),
            // `this` at sentence start resolves to `"this"` (EN 9.7 > VN 4.8), so `"this is good "` resolves end-to-end:
            let expAdapter = UIKitInputSessionAdapter()
            expAdapter.session.setInputMethod(.telex)
            expAdapter.session.setGrammarProfile(.senFlex)
            expAdapter.session.bilingualNoContextPolicy = .experimentalFrequencyWeighted
            let expProxy = MockTextDocumentProxy()
            for ch in "this is good " {
                expAdapter.handleCharacter(ch, proxy: expProxy)
            }
            XCTAssertEqual(expProxy.buffer, "this is good ")

            // For `sex education` at sentence start (no prior context):
            // 1) Under P0.3 Section B & C, `sex` composes as `sẽ` with raw candidate `"sex"` in the suggestion bar,
            //    and never retroactively mutates an already-committed word when the user types the next word.
            // 2) Selecting the `"sex"` candidate in the suggestion bar commits `"sex "` and then `"education "` -> `"sex education "`.
            let selAdapter = UIKitInputSessionAdapter()
            selAdapter.session.setInputMethod(.telex)
            selAdapter.session.setGrammarProfile(.senFlex)
            let selProxy = MockTextDocumentProxy()
            for ch in "sex" {
                selAdapter.handleCharacter(ch, proxy: selProxy)
            }
            XCTAssertEqual(selProxy.buffer, "sẽ")
            let sexArbAtStart = selAdapter.session.evaluateBilingualCandidates()
            XCTAssertEqual(sexArbAtStart.primaryCandidate.text, "sẽ")
            XCTAssertEqual(sexArbAtStart.secondaryCandidate?.text, "sex")
            selAdapter.commitCandidate("sex", proxy: selProxy, trailingSpace: true)
            for ch in "education " {
                selAdapter.handleCharacter(ch, proxy: selProxy)
            }
            XCTAssertEqual(selProxy.buffer, "sex education ")
        }

        // 2. Standalone no-context policy comparison (`.standardVietnameseFirst` vs `.experimentalFrequencyWeighted`)
        do {
            // Standard Vietnamese-first (default): `sex -> sẽ`, `is -> í`, `as -> á`, `if -> ì`
            let stdSession = InputSessionManager()
            stdSession.bilingualNoContextPolicy = .standardVietnameseFirst
            for ch in "is" { _ = stdSession.handleCharacter(ch) }
            XCTAssertEqual(stdSession.composingWord, "í")
            let stdCommit = stdSession.commitWord(smartBilingualEnabled: true)
            XCTAssertEqual(stdCommit, .commit(backspaces: 1, text: "í", isOverride: false))

            // Experimental Frequency-Weighted A/B policy:
            // `sex` -> `sẽ` (VN 9.5 > EN 6.5) with secondary candidate `"sex"`
            // `is`  -> `is` (EN 9.8 > VN 2.5) with secondary candidate `"í"`
            let expSession = InputSessionManager()
            expSession.bilingualNoContextPolicy = .experimentalFrequencyWeighted
            for ch in "sex" { _ = expSession.handleCharacter(ch) }
            XCTAssertEqual(expSession.composingWord, "sẽ")
            let sexArb = expSession.evaluateBilingualCandidates()
            XCTAssertEqual(sexArb.primaryCandidate.text, "sẽ")
            XCTAssertEqual(sexArb.secondaryCandidate?.text, "sex")

            expSession.reset()
            expSession.clearContext()
            for ch in "is" { _ = expSession.handleCharacter(ch) }
            XCTAssertEqual(expSession.composingWord, "is")
            let isArb = expSession.evaluateBilingualCandidates()
            XCTAssertEqual(isArb.primaryCandidate.text, "is")
            XCTAssertEqual(isArb.secondaryCandidate?.text, "í")
        }

        // 3. Suggestion Bar Bilingual Twin Reachability (neither language is ever locked out)
        do {
            let suggestionEngine = WordSuggestionEngine.shared
            let sCtx = SuggestionInputContext(beforeContext: "tôi ", composingWord: "sẽ", isComposing: true)
            let sCands = suggestionEngine.suggest(context: sCtx, limit: 5).map(\.displayText)
            XCTAssertEqual(sCands.first, "sẽ", "Primary slot must keep 'sẽ'")
            XCTAssertTrue(sCands.contains("sex"), "Suggestion bar must offer raw English twin 'sex' for 1-tap selection: \(sCands)")

            let iCtx = SuggestionInputContext(beforeContext: "", composingWord: "í", isComposing: true)
            let iCands = suggestionEngine.suggest(context: iCtx, limit: 5).map(\.displayText)
            XCTAssertEqual(iCands.first, "í")
            XCTAssertTrue(iCands.contains("is"), "Suggestion bar must offer raw English twin 'is' for 1-tap selection: \(iCands)")
        }
    }

    // MARK: - P0.4 Systematic English/Vietnamese Collision Resolution

    func testP0_4SystematicEnglishVietnameseCollisionResolution() {
        #if os(macOS)
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()
        #endif

        // 1. Keystroke-by-keystroke mandatory tests across both genZMode = false and genZMode = true
        for genZ in [false, true] {
            for profile in [GrammarProfile.classic, .senFlex] {
                func traceSteps(_ input: String, context: String = "") -> (steps: [String], committed: String) {
                    let session = InputSessionManager()
                    session.setInputMethod(.telex)
                    session.setGrammarProfile(profile)
                    session.setGenZMode(genZ)
                    session.smartBilingualEnabled = true
                    session.inlineBilingualEnabled = true
                    session.context = context
                    var steps: [String] = []
                    for ch in input {
                        _ = session.handleCharacter(ch)
                        steps.append(session.composingWord)
                    }
                    let commitAction = session.commitWord(smartBilingualEnabled: true)
                    let committed: String
                    if case let .commit(_, text, _) = commitAction {
                        committed = text
                    } else {
                        committed = session.composingWord
                    }
                    return (steps, committed)
                }

                // 1a. `f → fe → fee → fees`: keep English word right while typing
                let feesTrace = traceSteps("fees")
                XCTAssertEqual(
                    feesTrace.steps,
                    ["f", "fe", "fee", "fees"],
                    "genZ=\(genZ) profile=\(profile): f -> fe -> fee -> fees must stay English at every keystroke"
                )
                XCTAssertEqual(feesTrace.committed, "fees")

                // 1b. `f → fe → fee → feee`: when `fee` is already selected as literal, keep all three 'e's (no fake escape)
                let feeeTrace = traceSteps("feee")
                XCTAssertEqual(
                    feeeTrace.steps,
                    ["f", "fe", "fee", "feee"],
                    "genZ=\(genZ) profile=\(profile): f -> fe -> fee -> feee must keep all 3 'e's without fake escape"
                )
                XCTAssertEqual(feeeTrace.committed, "feee")

                // 1c. Group 1 Invalid Vietnamese candidates: `free`, `green`, `book`, `good` stay English inline while typing
                XCTAssertEqual(traceSteps("free").steps, ["f", "fr", "fre", "free"])
                XCTAssertEqual(traceSteps("green").steps, ["g", "gr", "gre", "gree", "green"])
                XCTAssertEqual(traceSteps("book").steps.last, "book")
                XCTAssertEqual(traceSteps("good").steps.last, "good")

                // 1d. `t → tr → tre → tree`: select `trê` (no/VN context) or `tree` (English context)
                let treeNoCtx = traceSteps("tree", context: "")
                XCTAssertEqual(treeNoCtx.steps, ["t", "tr", "tre", "trê"])
                XCTAssertEqual(treeNoCtx.committed, "trê")

                let treeVnCtx = traceSteps("tree", context: "cá")
                XCTAssertEqual(treeVnCtx.steps, ["t", "tr", "tre", "trê"])
                XCTAssertEqual(treeVnCtx.committed, "trê")

                let treeEnCtx = traceSteps("tree", context: "the")
                XCTAssertEqual(
                    treeEnCtx.steps,
                    ["t", "tr", "tre", "tree"],
                    "genZ=\(genZ) profile=\(profile): 'the tree' must resolve to 'tree' inline on the 4th keystroke"
                )
                XCTAssertEqual(treeEnCtx.committed, "tree")

                // 1e. `tree → trees`: switch candidate inline (`trê -> trees`) when suffix `-s` clarifies English plural
                let treesTrace = traceSteps("trees", context: "")
                XCTAssertEqual(
                    treesTrace.steps,
                    ["t", "tr", "tre", "trê", "trees"],
                    "genZ=\(genZ) profile=\(profile): tree -> trees must switch from 'trê' to 'trees' inline on 's'"
                )
                XCTAssertEqual(treesTrace.committed, "trees")

                // 1f. `tôi queen` vs `the queen`
                let queenVnCtx = traceSteps("queen", context: "tôi")
                XCTAssertEqual(queenVnCtx.steps, ["q", "qu", "que", "quê", "quên"])
                XCTAssertEqual(queenVnCtx.committed, "quên")

                let queenEnCtx = traceSteps("queen", context: "the")
                XCTAssertEqual(queenEnCtx.steps.last, "queen")
                XCTAssertEqual(queenEnCtx.committed, "queen")
            }
        }

        // 2. End-to-end phrase typing via UIKitInputSessionAdapter (`cá tree`, `the tree`, `tôi queen`, `the queen`)
        for genZ in [false, true] {
            let phrases: [(input: String, expected: String)] = [
                ("cas tree ", "cá trê "),
                ("the tree ", "the tree "),
                ("tooi queen ", "tôi quên "),
                ("the queen ", "the queen "),
                ("the fees ", "the fees "),
                ("free book ", "free book "),
                ("good green trees ", "good green trees ")
            ]
            for item in phrases {
                let adapter = UIKitInputSessionAdapter()
                adapter.session.setInputMethod(.telex)
                adapter.session.setGrammarProfile(.senFlex)
                adapter.session.setGenZMode(genZ)
                let proxy = MockTextDocumentProxy()
                for ch in item.input {
                    adapter.handleCharacter(ch, proxy: proxy)
                }
                XCTAssertEqual(proxy.buffer, item.expected, "genZ=\(genZ) failed phrase: '\(item.input)'")
            }
        }

        // 3. Verify auto-generated classified collision corpus across all 3 mandatory groups
        let corpus = BilingualIntentArbiter.generateClassifiedCollisionCorpus()
        XCTAssertGreaterThanOrEqual(corpus.count, 33)
        let byRaw = Dictionary(uniqueKeysWithValues: corpus.map { ($0.rawEnglish, $0) })

        // Group 1: Invalid Vietnamese candidate
        for g1 in ["fee", "fees", "free", "green", "book", "good"] {
            guard let entry = byRaw[g1] else {
                XCTFail("Missing Group 1 entry: \(g1)")
                continue
            }
            XCTAssertEqual(entry.category, .invalidVietnameseCandidate, "\(g1) must be classified as .invalidVietnameseCandidate")
            XCTAssertFalse(entry.isPhonotacticallyValidVN, "\(g1) (\(entry.naiveTelex)) must fail strict VN phonotactics")
            XCTAssertEqual(entry.defaultNoContextWinner, g1, "\(g1) must win as raw English even without context")
            XCTAssertEqual(entry.enContextWinner, g1)
        }

        // Phonotactic-gap plurals (`trees/trế`, `teens/tến`)
        for gap in ["trees", "teens"] {
            guard let entry = byRaw[gap] else {
                XCTFail("Missing phonotactic-gap entry: \(gap)")
                continue
            }
            XCTAssertEqual(entry.category, .phonotacticGapVietnamese)
            XCTAssertTrue(entry.isPhonotacticallyValidVN)
            XCTAssertFalse(entry.isAttestedVNSyllable)
            XCTAssertEqual(entry.defaultNoContextWinner, gap)
        }

        // Group 2: Valid bilingual double-vowel collision
        for g2 in ["tree", "queen", "teen", "been", "seen", "bee", "bees", "beer", "moon", "noon", "room", "too", "boots"] {
            guard let entry = byRaw[g2] else {
                XCTFail("Missing Group 2 entry: \(g2)")
                continue
            }
            XCTAssertEqual(entry.category, .validBilingualVowelCollision, "\(g2) must be .validBilingualVowelCollision")
            XCTAssertTrue(entry.isPhonotacticallyValidVN)
            XCTAssertTrue(entry.isAttestedVNSyllable)
            XCTAssertEqual(entry.vnContextWinner, entry.naiveTelex, "\(g2) in VN context must resolve to '\(entry.naiveTelex)'")
            XCTAssertEqual(entry.enContextWinner, g2, "\(g2) in EN context must resolve to '\(g2)'")
            // Verify bidirectional twin in candidate bar
            XCTAssertEqual(BilingualIntentArbiter.bilingualTwinCandidate(composingWord: entry.naiveTelex, rawWord: g2)?.displayText, g2)
            XCTAssertEqual(BilingualIntentArbiter.bilingualTwinCandidate(composingWord: g2, rawWord: g2)?.displayText, entry.naiveTelex)
        }

        // Group 3: Valid bilingual tone & horn collision
        for g3 in ["sex", "is", "six", "cats", "hats", "last", "best", "rest", "car", "bar", "now", "cow"] {
            guard let entry = byRaw[g3] else {
                XCTFail("Missing Group 3 entry: \(g3)")
                continue
            }
            XCTAssertEqual(entry.category, .validBilingualToneOrHornCollision, "\(g3) must be .validBilingualToneOrHornCollision")
            XCTAssertTrue(entry.isPhonotacticallyValidVN)
            XCTAssertTrue(entry.isAttestedVNSyllable)
            XCTAssertEqual(entry.vnContextWinner, entry.naiveTelex, "\(g3) in VN context must resolve to '\(entry.naiveTelex)'")
            XCTAssertEqual(entry.enContextWinner, g3, "\(g3) in EN context must resolve to '\(g3)'")
            XCTAssertEqual(BilingualIntentArbiter.bilingualTwinCandidate(composingWord: entry.naiveTelex, rawWord: g3)?.displayText, g3)
            XCTAssertEqual(BilingualIntentArbiter.bilingualTwinCandidate(composingWord: g3, rawWord: g3)?.displayText, entry.naiveTelex)
        }
    }

    // MARK: - P0.4.1: Bilingual Arbitration Hardening Verification

    func testP0_4_1BilingualArbitrationHardening() {
        // 1. Sửa chính sách no-context (Probabilistic Bilingual No-Context Policy)
        let targetPairs: [(raw: String, vn: String, expectedNoCtxKind: BilingualCandidateKind)] = [
            ("is", "í", .rawLiteral),
            ("sex", "sẽ", .vietnameseTelex),
            ("tree", "trê", .vietnameseTelex),
            ("queen", "quên", .vietnameseTelex),
            ("been", "bên", .vietnameseTelex),
            ("too", "tô", .vietnameseTelex),
            ("moon", "môn", .vietnameseTelex)
        ]

        for item in targetPairs {
            let arb = BilingualIntentArbiter.arbitrate(
                raw: item.raw,
                rendered: item.vn,
                context: "",
                noContextPolicy: .probabilisticBilingual
            )
            XCTAssertEqual(
                arb.primaryCandidate.kind,
                item.expectedNoCtxKind,
                "No-context probabilistic arbitration for '\(item.raw)/\(item.vn)' expected \(item.expectedNoCtxKind)"
            )
            let vnEval = arb.candidates.first(where: { $0.kind == .vietnameseTelex })
            let enEval = arb.candidates.first(where: { $0.kind == .rawLiteral })
            XCTAssertGreaterThan(vnEval?.vnLexicalFrequency ?? 0.0, 0.0)
            XCTAssertGreaterThan(enEval?.enLexicalFrequency ?? 0.0, 0.0)
            XCTAssertEqual(arb.vietnameseProbability + arb.englishProbability, 1.0, accuracy: 1e-6)
        }

        // Verify standalone `is` prefers English `"is"` in default bilingual mode, while preserving ability to type `"í"`
        do {
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            adapter.handleCharacter("i", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "i")
            adapter.handleCharacter("s", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "is", "Standalone 'is' must prefer English in default bilingual config")
            XCTAssertEqual(adapter.session.candidateProvenance.selectedKind, .rawLiteral)
            XCTAssertEqual(adapter.session.candidateProvenance.selectionReason, .noContextFrequencyPrior)
            // Candidate bar still offers 1-tap Vietnamese twin `"í"`
            let twin = BilingualIntentArbiter.bilingualTwinCandidate(
                composingWord: adapter.session.composingWord,
                rawWord: adapter.session.rawWord
            )
            XCTAssertEqual(twin?.displayText, "í", "1-tap Vietnamese twin 'í' must remain available when 'is' is selected")
            adapter.handleCharacter(" ", proxy: proxy)
            XCTAssertEqual(proxy.buffer, "is ")

            // Typing `is` in Vietnamese context (`cái í`, `anh í`, `con í`, `này í`) produces `"í"`
            for vnPrefix in ["cais ", "anh ", "con ", "nayf "] {
                let vnAdapter = UIKitInputSessionAdapter()
                vnAdapter.session.setInputMethod(.telex)
                vnAdapter.session.setGrammarProfile(.senFlex)
                let vnProxy = MockTextDocumentProxy()
                for ch in vnPrefix {
                    vnAdapter.handleCharacter(ch, proxy: vnProxy)
                }
                vnAdapter.handleCharacter("i", proxy: vnProxy)
                vnAdapter.handleCharacter("s", proxy: vnProxy)
                XCTAssertTrue(
                    vnProxy.buffer.hasSuffix(" í"),
                    "Prefix '\(vnPrefix)' + 'is' must produce Vietnamese 'í', got '\(vnProxy.buffer)'"
                )
            }
        }

        // 2. Grammar-aware phonotactics (Standard Telex vs Gen-Z Mode vs Relaxed Coda)
        do {
            let feeStd = BilingualIntentArbiter.evaluatePhonotactics(
                raw: "fee",
                rendered: "fê",
                genZMode: false,
                relaxedCoda: false
            )
            XCTAssertFalse(feeStd.isStandardPhonotacticValid)
            XCTAssertFalse(feeStd.isGenZPhonotacticValid)
            XCTAssertEqual(feeStd.layer, .invalid)

            let feeGenZ = BilingualIntentArbiter.evaluatePhonotactics(
                raw: "fee",
                rendered: "fê",
                genZMode: true,
                relaxedCoda: false
            )
            XCTAssertFalse(feeGenZ.isStandardPhonotacticValid)
            XCTAssertTrue(feeGenZ.isGenZPhonotacticValid, "fê must NOT be treated as impossible when Gen-Z Mode allows f -> ph")
            XCTAssertEqual(feeGenZ.layer, .genZExtension)
            XCTAssertTrue(feeGenZ.blockedGenZExpansionOnEnglishWord, "Gen-Z expansion must not corrupt English 'fee'")

            // Verify non-English Gen-Z toned word (`foongf -> fòng`) is allowed when Gen-Z Mode is ON
            let foongfGenZ = BilingualIntentArbiter.evaluatePhonotactics(
                raw: "foongf",
                rendered: "fòng",
                genZMode: true,
                relaxedCoda: false
            )
            XCTAssertTrue(foongfGenZ.isGenZPhonotacticValid)
            XCTAssertFalse(foongfGenZ.blockedGenZExpansionOnEnglishWord)
            XCTAssertEqual(foongfGenZ.layer, .genZExtension)

            // Verify Relaxed Coda (`khoog -> khôg`)
            let khoogStd = BilingualIntentArbiter.evaluatePhonotactics(
                raw: "khoog",
                rendered: "khôg",
                genZMode: false,
                relaxedCoda: false
            )
            XCTAssertFalse(khoogStd.isStandardPhonotacticValid)
            XCTAssertFalse(khoogStd.isRelaxedCodaPhonotacticValid)
            XCTAssertEqual(khoogStd.layer, .invalid)

            let khoogRelaxed = BilingualIntentArbiter.evaluatePhonotactics(
                raw: "khoog",
                rendered: "khôg",
                genZMode: false,
                relaxedCoda: true
            )
            XCTAssertFalse(khoogRelaxed.isStandardPhonotacticValid)
            XCTAssertTrue(khoogRelaxed.isRelaxedCodaPhonotacticValid)
            XCTAssertEqual(khoogRelaxed.layer, .relaxedCodaExtension)
        }

        // 3. Candidate state provenance
        do {
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(.senFlex)
            session.inlineBilingualEnabled = true

            // Type `trưởngw` (`t-r-u-o-w-n-g-r-w`)
            for ch in "truowngrw" {
                _ = session.handleCharacter(ch)
            }
            let prov = session.candidateProvenance
            XCTAssertEqual(prov.rawCandidate, "truowngrw")
            XCTAssertEqual(prov.vietnameseCandidate, "trưởngw")
            XCTAssertEqual(prov.selectedCandidate, "trưởngw")
            XCTAssertEqual(prov.selectedKind, .vietnameseTelex)
            XCTAssertEqual(prov.literalSuffix, "w")
            XCTAssertTrue(prov.semanticTransformations.contains("uw->ư"))
            XCTAssertTrue(prov.semanticTransformations.contains("ow->ơ"))
            XCTAssertTrue(prov.semanticTransformations.contains("r->hook"))
        }

        // 4. Candidate stability & Hysteresis (`trê -> trees`, `quê -> queen`, `bô -> book`, post-commit immutability)
        do {
            // 4a. `trê -> trees`: stays `trê` at step 4, flips once at step 5 (`trees`) when phonotactic/lexical gap triggers
            let s1 = InputSessionManager()
            s1.setInputMethod(.telex)
            s1.setGrammarProfile(.senFlex)
            s1.inlineBilingualEnabled = true
            var steps1: [(word: String, kind: BilingualCandidateKind, flips: Int)] = []
            for ch in "trees" {
                _ = s1.handleCharacter(ch)
                steps1.append((s1.composingWord, s1.candidateProvenance.selectedKind, s1.candidateProvenance.flipCount))
            }
            XCTAssertEqual(steps1.map(\.word), ["t", "tr", "tre", "trê", "trees"])
            XCTAssertEqual(steps1[3].kind, .vietnameseTelex)
            XCTAssertEqual(steps1[4].kind, .rawLiteral)
            XCTAssertEqual(steps1[4].flips, 1)

            // 4b. `quê -> queen`: in no-context stays stable on Vietnamese (`quê -> quên`) with 0 flips
            let s2 = InputSessionManager()
            s2.setInputMethod(.telex)
            s2.setGrammarProfile(.senFlex)
            s2.inlineBilingualEnabled = true
            var steps2: [String] = []
            for ch in "queen" {
                _ = s2.handleCharacter(ch)
                steps2.append(s2.composingWord)
            }
            XCTAssertEqual(steps2, ["q", "qu", "que", "quê", "quên"])
            XCTAssertEqual(s2.candidateProvenance.flipCount, 0)

            // 4c. `bô -> book`: `b -> bo -> bô -> book` flips once on `'k'` because `bôk` violates Vietnamese stop-coda tone rules
            let s3 = InputSessionManager()
            s3.setInputMethod(.telex)
            s3.setGrammarProfile(.senFlex)
            s3.inlineBilingualEnabled = true
            var steps3: [String] = []
            for ch in "book" {
                _ = s3.handleCharacter(ch)
                steps3.append(s3.composingWord)
            }
            XCTAssertEqual(steps3, ["b", "bo", "bô", "book"])
            XCTAssertEqual(s3.candidateProvenance.selectedKind, .rawLiteral)
            XCTAssertEqual(s3.candidateProvenance.selectionReason, .phonotacticInvalidVN)

            // 4d. Post-commit immutability: already committed words never mutate when subsequent words are typed
            let adapter = UIKitInputSessionAdapter()
            adapter.session.setInputMethod(.telex)
            adapter.session.setGrammarProfile(.senFlex)
            let proxy = MockTextDocumentProxy()
            for ch in "tree " {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertEqual(proxy.buffer, "trê ")
            for ch in "is green " {
                adapter.handleCharacter(ch, proxy: proxy)
            }
            XCTAssertTrue(proxy.buffer.hasPrefix("trê "), "Committed 'trê ' must never be retroactively mutated")
        }

        // 5. Escape versus Literal (`trê + e -> tree`, `the tree + e -> the treee`, `fee + e -> feee`, `sê + e -> see` + Backspace/retype)
        do {
            // 5a. `trê + e -> tree` (Vietnamese composition + 3rd 'e' -> Classic Escape `tree`)
            let sTre = InputSessionManager()
            sTre.setInputMethod(.telex)
            sTre.setGrammarProfile(.senFlex)
            sTre.inlineBilingualEnabled = true
            for ch in "tree" { _ = sTre.handleCharacter(ch) }
            XCTAssertEqual(sTre.composingWord, "trê")
            XCTAssertEqual(sTre.candidateProvenance.selectedKind, .vietnameseTelex)
            _ = sTre.handleCharacter("e")
            XCTAssertEqual(sTre.composingWord, "tree")
            XCTAssertEqual(sTre.candidateProvenance.explicitEscapeState, .classicVowelEscape)
            // Backspace on escaped ASCII `tree` -> `tre`, retype `e` -> `trê`, retype `e` -> `tree`
            _ = sTre.handleBackspace()
            XCTAssertEqual(sTre.composingWord, "tre")
            _ = sTre.handleCharacter("e")
            XCTAssertEqual(sTre.composingWord, "trê")
            _ = sTre.handleCharacter("e")
            XCTAssertEqual(sTre.composingWord, "tree")

            // 5b. `the tree + e -> the treee` (English Literal selected + 'e' -> appends literal 'e' -> `treee`)
            let sTheTree = InputSessionManager()
            sTheTree.setInputMethod(.telex)
            sTheTree.setGrammarProfile(.senFlex)
            sTheTree.inlineBilingualEnabled = true
            sTheTree.context = "the"
            for ch in "tree" { _ = sTheTree.handleCharacter(ch) }
            XCTAssertEqual(sTheTree.composingWord, "tree")
            XCTAssertEqual(sTheTree.candidateProvenance.selectedKind, .rawLiteral)
            _ = sTheTree.handleCharacter("e")
            XCTAssertEqual(sTheTree.composingWord, "treee")
            XCTAssertEqual(sTheTree.candidateProvenance.selectedKind, .rawLiteral)
            // Backspace -> restores `tree`, retype `e` -> `treee`
            _ = sTheTree.handleBackspace()
            XCTAssertEqual(sTheTree.composingWord, "tree")
            XCTAssertEqual(sTheTree.candidateProvenance.selectedKind, .rawLiteral)
            _ = sTheTree.handleCharacter("e")
            XCTAssertEqual(sTheTree.composingWord, "treee")

            // 5c. `fee + e -> feee` (English Literal selected + 'e' -> `feee`)
            let sFee = InputSessionManager()
            sFee.setInputMethod(.telex)
            sFee.setGrammarProfile(.senFlex)
            sFee.inlineBilingualEnabled = true
            for ch in "fee" { _ = sFee.handleCharacter(ch) }
            XCTAssertEqual(sFee.composingWord, "fee")
            _ = sFee.handleCharacter("e")
            XCTAssertEqual(sFee.composingWord, "feee")
            // Backspace -> `fee`, retype `e` -> `feee`
            _ = sFee.handleBackspace()
            XCTAssertEqual(sFee.composingWord, "fee")
            _ = sFee.handleCharacter("e")
            XCTAssertEqual(sFee.composingWord, "feee")

            // 5d. `sê + e -> see` (Vietnamese composition + 3rd 'e' -> Classic Escape `see`)
            let sSee = InputSessionManager()
            sSee.setInputMethod(.telex)
            sSee.setGrammarProfile(.senFlex)
            sSee.inlineBilingualEnabled = true
            for ch in "see" { _ = sSee.handleCharacter(ch) }
            XCTAssertEqual(sSee.composingWord, "sê")
            _ = sSee.handleCharacter("e")
            XCTAssertEqual(sSee.composingWord, "see")
            XCTAssertEqual(sSee.candidateProvenance.explicitEscapeState, .classicVowelEscape)
            // Backspace on escaped ASCII `see` -> `se`, retype `e` -> `sê`, retype `e` -> `see`
            _ = sSee.handleBackspace()
            XCTAssertEqual(sSee.composingWord, "se")
            _ = sSee.handleCharacter("e")
            XCTAssertEqual(sSee.composingWord, "sê")
            _ = sSee.handleCharacter("e")
            XCTAssertEqual(sSee.composingWord, "see")
        }

        // 6. Full collision corpus & 6 quantitative metrics (Calibration vs Independent Holdout)
        do {
            let report = BilingualIntentArbiter.evaluateFullCollisionCorpus()
            XCTAssertGreaterThan(report.sweptEnglishWordCount, 250)
            XCTAssertGreaterThan(report.standardTelexCollisionCount, 50)
            XCTAssertGreaterThan(report.genZCollisionCount, 50)
            XCTAssertGreaterThan(report.vuisCollisionCount, 50)

            // Verify Calibration Set metrics
            XCTAssertEqual(report.calibrationMetrics.englishCorruptionRate, 0.0, accuracy: 1e-6)
            XCTAssertEqual(report.calibrationMetrics.vietnamesePreservationRate, 1.0, accuracy: 1e-6)
            XCTAssertEqual(report.calibrationMetrics.incorrectRawReplayRate, 0.0, accuracy: 1e-6)
            XCTAssertLessThan(report.calibrationMetrics.candidateFlipRate, 0.35)
            XCTAssertEqual(report.calibrationMetrics.extraKeystrokesToCorrect, 0.0, accuracy: 1e-6)
            XCTAssertEqual(report.calibrationMetrics.macOSiOSCoreConsistency, 1.0, accuracy: 1e-6)

            // Verify Independent Holdout Set metrics
            XCTAssertEqual(report.holdoutMetrics.englishCorruptionRate, 0.0, accuracy: 1e-6)
            XCTAssertEqual(report.holdoutMetrics.vietnamesePreservationRate, 1.0, accuracy: 1e-6)
            XCTAssertEqual(report.holdoutMetrics.incorrectRawReplayRate, 0.0, accuracy: 1e-6)
            XCTAssertLessThan(report.holdoutMetrics.candidateFlipRate, 0.35)
            XCTAssertEqual(report.holdoutMetrics.extraKeystrokesToCorrect, 0.0, accuracy: 1e-6)
            XCTAssertEqual(report.holdoutMetrics.macOSiOSCoreConsistency, 1.0, accuracy: 1e-6)
        }

        // 7. Runtime acceptance across macOS & iOS keystroke-by-keystroke + candidate bar
        do {
            let runtimeSequences: [(input: String, context: String, expectedSteps: [String])] = [
                ("fee", "", ["f", "fe", "fee"]),
                ("fees", "", ["f", "fe", "fee", "fees"]),
                ("tree", "", ["t", "tr", "tre", "trê"]),
                ("tree", "the", ["t", "tr", "tre", "tree"]),
                ("trees", "", ["t", "tr", "tre", "trê", "trees"]),
                ("is", "", ["i", "is"]),
                ("is", "cái", ["i", "í"]),
                ("sex", "", ["s", "se", "sẽ"]),
                ("sex", "the", ["s", "se", "sex"]),
                ("queen", "tôi", ["q", "qu", "que", "quê", "quên"]),
                ("queen", "the", ["q", "qu", "que", "quê", "queen"]),
                ("book", "", ["b", "bo", "bô", "book"])
            ]

            for seq in runtimeSequences {
                let macSession = InputSessionManager()
                macSession.setInputMethod(.telex)
                macSession.setGrammarProfile(.senFlex)
                macSession.inlineBilingualEnabled = true
                macSession.context = seq.context

                let iosAdapter = UIKitInputSessionAdapter()
                iosAdapter.session.setInputMethod(.telex)
                iosAdapter.session.setGrammarProfile(.senFlex)
                iosAdapter.session.context = seq.context
                let iosProxy = MockTextDocumentProxy()
                if !seq.context.isEmpty {
                    iosProxy.buffer = seq.context + " "
                }

                var macSteps: [String] = []
                var iosSteps: [String] = []
                for ch in seq.input {
                    _ = macSession.handleCharacter(ch)
                    macSteps.append(macSession.composingWord)

                    iosAdapter.handleCharacter(ch, proxy: iosProxy)
                    iosSteps.append(iosAdapter.session.composingWord)
                }

                XCTAssertEqual(macSteps, seq.expectedSteps, "macOS step mismatch for '\(seq.input)' (ctx='\(seq.context)')")
                XCTAssertEqual(iosSteps, seq.expectedSteps, "iOS step mismatch for '\(seq.input)' (ctx='\(seq.context)')")
            }
        }
    }

    // MARK: - P0.4.2 Sentence-Level Bilingual Consistency

    func testP0_4_2SentenceLevelBilingualConsistency() {
        func driveSentence(
            rawSentence: String,
            initialContext: String = "",
            policy: BilingualNoContextPolicy = .probabilisticBilingual,
            inlineBilingual: Bool = true
        ) -> (
            coreText: String,
            iosText: String,
            tokenProvenances: [CompositionCandidateProvenance],
            contextTrace: [String]
        ) {
            let coreSession = InputSessionManager()
            coreSession.setInputMethod(.telex)
            coreSession.setGrammarProfile(.senFlex)
            coreSession.bilingualNoContextPolicy = policy
            coreSession.inlineBilingualEnabled = inlineBilingual
            if !initialContext.isEmpty {
                for tok in initialContext.split(whereSeparator: \.isWhitespace) {
                    coreSession.appendContext(String(tok))
                }
            }

            let iosAdapter = UIKitInputSessionAdapter()
            iosAdapter.session.setInputMethod(.telex)
            iosAdapter.session.setGrammarProfile(.senFlex)
            iosAdapter.session.bilingualNoContextPolicy = policy
            iosAdapter.session.inlineBilingualEnabled = inlineBilingual
            let iosProxy = MockTextDocumentProxy()
            if !initialContext.isEmpty {
                for tok in initialContext.split(whereSeparator: \.isWhitespace) {
                    iosAdapter.session.appendContext(String(tok))
                }
                iosProxy.buffer = initialContext + " "
            }

            var coreBuffer = initialContext.isEmpty ? "" : (initialContext + " ")
            var provenances: [CompositionCandidateProvenance] = []
            var contextTrace: [String] = []

            for ch in rawSentence {
                if coreSession.isWordBoundary(ch) {
                    let wasComposing = coreSession.isComposing
                    let action = coreSession.commitWord(smartBilingualEnabled: true, boundaryChar: ch)
                    switch action {
                    case .commit(let backspaces, let text, _):
                        if backspaces > 0 && coreBuffer.count >= backspaces {
                            coreBuffer.removeLast(backspaces)
                        }
                        coreBuffer.append(text)
                        coreBuffer.append(ch)
                    case .passThrough:
                        coreBuffer.append(ch)
                    default:
                        coreBuffer.append(ch)
                    }
                    if wasComposing {
                        provenances.append(coreSession.lastCommittedProvenance)
                        contextTrace.append(coreSession.context)
                    }
                } else {
                    let action = coreSession.handleCharacter(ch)
                    switch action {
                    case .replace(let backspaces, let text):
                        if backspaces > 0 && coreBuffer.count >= backspaces {
                            coreBuffer.removeLast(backspaces)
                        }
                        coreBuffer.append(text)
                    case .passThrough:
                        coreBuffer.append(ch)
                    default:
                        break
                    }
                }
                iosAdapter.handleCharacter(ch, proxy: iosProxy)
            }

            if coreSession.isComposing {
                let action = coreSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
                if case .commit(let backspaces, let text, _) = action {
                    if backspaces > 0 && coreBuffer.count >= backspaces {
                        coreBuffer.removeLast(backspaces)
                    }
                    coreBuffer.append(text)
                }
                provenances.append(coreSession.lastCommittedProvenance)
                contextTrace.append(coreSession.context)
            }
            if iosAdapter.session.isComposing {
                iosAdapter.commitWord(proxy: iosProxy, suffix: "")
            }

            return (coreBuffer, iosProxy.buffer, provenances, contextTrace)
        }

        // 1. Reproduction Priority & Full-Sentence Input Test:
        // Verify `there is a tree` -> `there is a tree` (never `there í a tree`!)
        do {
            for inlineMode in [true, false] {
                let res = driveSentence(rawSentence: "there is a tree", inlineBilingual: inlineMode)
                XCTAssertEqual(res.coreText, "there is a tree", "Failed for inlineBilingual=\(inlineMode)")
                XCTAssertEqual(res.iosText, "there is a tree", "iOS failed for inlineBilingual=\(inlineMode)")
                XCTAssertEqual(res.contextTrace, [
                    "there",
                    "there is",
                    "there is a",
                    "there is a tree"
                ])
                XCTAssertEqual(res.tokenProvenances.map(\.selectedCandidate), ["there", "is", "a", "tree"])
                // Verify `is` provenance after `there`:
                let isProv = res.tokenProvenances[1]
                XCTAssertEqual(isProv.rawCandidate, "is")
                XCTAssertEqual(isProv.vietnameseCandidate, "í")
                XCTAssertEqual(isProv.selectedCandidate, "is")
                XCTAssertEqual(isProv.selectedKind, .rawLiteral)
                XCTAssertEqual(isProv.context, "there")
                XCTAssertEqual(isProv.sentenceLanguageState.momentum, .english)
            }

            // Target sentences with unambiguous first-token or Vietnamese/English context:
            let exactSentences: [(raw: String, expected: String)] = [
                ("there is a tree", "there is a tree"),
                ("it is too good", "it is too good"),
                ("the queen is here", "the queen is here"),
                ("tooi sex ddi", "tôi sẽ đi"),
                ("tooi queen maats", "tôi quên mất"),
                ("con cas tree", "con cá trê")
            ]
            for item in exactSentences {
                let resInline = driveSentence(rawSentence: item.raw, inlineBilingual: true)
                XCTAssertEqual(resInline.coreText, item.expected, "Core inline mismatch for '\(item.raw)'")
                XCTAssertEqual(resInline.iosText, item.expected, "iOS inline mismatch for '\(item.raw)'")

                let resCommit = driveSentence(rawSentence: item.raw, inlineBilingual: false)
                XCTAssertEqual(resCommit.coreText, item.expected, "Core commit mismatch for '\(item.raw)'")
                XCTAssertEqual(resCommit.iosText, item.expected, "iOS commit mismatch for '\(item.raw)'")
            }

            // Document & verify first-token single-word collision vs multi-word restoration:
            // - Standalone `here` (`h-e-r-e -> hể`, pinned by `ModifierPolicy3BPlusGoldenTests:530` in cold no-context) and
            //   standalone `this` (`t-h-i-s -> thí`, `whitelist_safe = never` pinned by `VNCollisionRatchetTests` in cold no-context)
            //   preserve Vietnamese when typed alone (`"here" -> "hể"`, `"this" -> "thí"`),
            //   while `"here is a tree"` and `"this is a book"` restore the 1-space prefix to English `"here is a tree"` and `"this is a book"`:
            let standaloneHere = driveSentence(rawSentence: "here", policy: .probabilisticBilingual)
            XCTAssertEqual(standaloneHere.coreText, "hể")
            XCTAssertEqual(standaloneHere.iosText, "hể")

            let standaloneThis = driveSentence(rawSentence: "this", policy: .probabilisticBilingual)
            XCTAssertEqual(standaloneThis.coreText, "thí")
            XCTAssertEqual(standaloneThis.iosText, "thí")

            let coldHere = driveSentence(rawSentence: "here is a tree", policy: .probabilisticBilingual)
            XCTAssertEqual(coldHere.coreText, "here is a tree")
            XCTAssertEqual(coldHere.iosText, "here is a tree")

            let coldThis = driveSentence(rawSentence: "this is a book", policy: .probabilisticBilingual)
            XCTAssertEqual(coldThis.coreText, "this is a book")
            XCTAssertEqual(coldThis.iosText, "this is a book")

            //   2) With preceding English context or under `.experimentalFrequencyWeighted`, both resolve to `"here is a tree"` and `"this is a book"`:
            let freqHere = driveSentence(rawSentence: "here is a tree", policy: .experimentalFrequencyWeighted)
            XCTAssertEqual(freqHere.coreText, "here is a tree")
            XCTAssertEqual(freqHere.iosText, "here is a tree")

            let freqThis = driveSentence(rawSentence: "this is a book", policy: .experimentalFrequencyWeighted)
            XCTAssertEqual(freqThis.coreText, "this is a book")
            XCTAssertEqual(freqThis.iosText, "this is a book")

            let ctxHere = driveSentence(rawSentence: "here is a tree", initialContext: "look", policy: .probabilisticBilingual)
            XCTAssertEqual(ctxHere.coreText, "look here is a tree")
            XCTAssertEqual(ctxHere.iosText, "look here is a tree")

            let ctxThis = driveSentence(rawSentence: "this is a book", initialContext: "think", policy: .probabilisticBilingual)
            XCTAssertEqual(ctxThis.coreText, "think this is a book")
            XCTAssertEqual(ctxThis.iosText, "think this is a book")
        }

        // 2. Language Context Propagation & Bidirectional Mid-Sentence Code-Switching (EN <-> VN in same sentence):
        do {
            // VN -> EN mid-sentence: `tôi nghĩ there is a tree`
            let vnToEn = driveSentence(rawSentence: "tooi nghix there is a tree")
            XCTAssertEqual(vnToEn.coreText, "tôi nghĩ there is a tree")
            XCTAssertEqual(vnToEn.iosText, "tôi nghĩ there is a tree")

            // EN -> VN mid-sentence: `there is a tree tôi sẽ đi`
            let enToVn = driveSentence(rawSentence: "there is a tree tooi sex ddi")
            XCTAssertEqual(enToVn.coreText, "there is a tree tôi sẽ đi")
            XCTAssertEqual(enToVn.iosText, "there is a tree tôi sẽ đi")

            // EN -> VN mid-sentence: `the queen đã quên mất`
            let enToVnQueen = driveSentence(rawSentence: "the queen ddax queen maats")
            XCTAssertEqual(enToVnQueen.coreText, "the queen đã quên mất")
            XCTAssertEqual(enToVnQueen.iosText, "the queen đã quên mất")

            // Punctuation boundaries within and across clauses:
            let punctSentence = driveSentence(rawSentence: "there is a tree, and it is too good.")
            XCTAssertEqual(punctSentence.coreText, "there is a tree, and it is too good.")
            XCTAssertEqual(punctSentence.iosText, "there is a tree, and it is too good.")

            // Focus change (`clearContext`) resets sentence state cleanly:
            let session = InputSessionManager()
            session.setInputMethod(.telex)
            session.setGrammarProfile(.senFlex)
            session.inlineBilingualEnabled = true
            for ch in "the" { _ = session.handleCharacter(ch) }
            _ = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
            XCTAssertEqual(session.sentenceLanguageState.momentum, .english)
            session.clearContext()
            XCTAssertEqual(session.context, "")
            XCTAssertEqual(session.sentenceLanguageState, .empty)
            for ch in "tree" { _ = session.handleCharacter(ch) }
            XCTAssertEqual(session.composingWord, "trê")

            // Backspace then retype inside `there is a tree`:
            let editSession = InputSessionManager()
            editSession.setInputMethod(.telex)
            editSession.setGrammarProfile(.senFlex)
            editSession.inlineBilingualEnabled = true
            for ch in "there" { _ = editSession.handleCharacter(ch) }
            _ = editSession.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
            for ch in "is" { _ = editSession.handleCharacter(ch) }
            XCTAssertEqual(editSession.composingWord, "is")
            _ = editSession.handleBackspace()
            XCTAssertEqual(editSession.composingWord, "i")
            _ = editSession.handleCharacter("s")
            XCTAssertEqual(editSession.composingWord, "is")
        }

        // 3. Preserve Telex Semantics (`í` reachable in Vietnamese context, `khoog -> khôg` never auto-expands to `không`):
        do {
            // `í` remains reachable in Vietnamese demonstrative contexts (`cái í`, `anh í`, `con í`):
            for vnHead in ["cais", "anh", "con"] {
                let res = driveSentence(rawSentence: "\(vnHead) is")
                let expectedHead = vnHead == "cais" ? "cái" : vnHead
                XCTAssertEqual(res.coreText, "\(expectedHead) í")
                XCTAssertEqual(res.iosText, "\(expectedHead) í")
            }

            // `khoog -> khôg` and `hoog -> hôg` NEVER auto-expand to `không` or `hông` in Core or Adapter:
            let khoogRes = driveSentence(rawSentence: "khoog hoog")
            XCTAssertEqual(khoogRes.coreText, "khôg hôg")
            XCTAssertEqual(khoogRes.iosText, "khôg hôg")

            // `khoogo -> khôgo` (no raw replay to `khoogo`):
            let khoogoRes = driveSentence(rawSentence: "khoogo")
            XCTAssertEqual(khoogoRes.coreText, "khôgo")
            XCTAssertEqual(khoogoRes.iosText, "khôgo")
        }
    }
}
