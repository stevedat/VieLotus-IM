import XCTest
@testable import VieLotusCore

final class ClientAdapterTests: XCTestCase {
    func testLabHostBundleIDsSelectExpectedAdapterRoutes() {
        let profiles: [(String, AppCategory)] = [
            ("org.vielotus.inputmethod.vielotuslab.appkit", .standardAppKit),
            ("org.vielotus.inputmethod.vielotuslab.chromium", .chromium),
            ("org.vielotus.inputmethod.vielotuslab.com.microsoft.word", .msOffice),
            ("org.vielotus.inputmethod.vielotuslab.terminal", .terminal),
            ("org.vielotus.inputmethod.vielotuslab.raycast", .overlay)
        ]

        for (bundleID, expectedCategory) in profiles {
            XCTAssertEqual(ClientAdapter.classify(bundleIdentifier: bundleID), expectedCategory, bundleID)
        }
    }

    func testLabHostProfilesUseExpectedPresentationModes() {
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.google.antigravity"),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.openai.codex"),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.stablyai.orca"),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "org.vielotus.inputmethod.vielotuslab.chromium"),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .msOffice, bundleIdentifier: "org.vielotus.inputmethod.vielotuslab.com.microsoft.word"),
            .directReplacement
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .terminal, bundleIdentifier: "org.vielotus.inputmethod.vielotuslab.terminal", terminalDirectEnabled: false),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .terminal, bundleIdentifier: "org.vielotus.inputmethod.vielotuslab.terminal", terminalDirectEnabled: true),
            .terminalDirect
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.microsoft.edgemac"),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.google.chrome"),
            .markedText
        )
    }

    func testPresentationPreferencesAndPerAppOverrides() {
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.google.chrome", preference: .directReplacement),
            .directReplacement
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.google.chrome", preference: .markedText),
            .markedText
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(
                for: .chromium,
                bundleIdentifier: "com.openai.codex",
                appOverrides: ["com.openai.codex": .directReplacement]
            ),
            .directReplacement
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(
                for: .chromium,
                bundleIdentifier: "com.google.chrome",
                preference: .directReplacement,
                appOverrides: ["com.google.chrome": .markedText]
            ),
            .markedText
        )
        XCTAssertTrue(ClientAdapter.allowsDynamicMarkedTextFallback(bundleIdentifier: "com.google.chrome", preference: .automatic, appOverrides: [:]))
        XCTAssertFalse(ClientAdapter.allowsDynamicMarkedTextFallback(bundleIdentifier: "com.google.chrome", preference: .directReplacement, appOverrides: [:]))
        XCTAssertFalse(ClientAdapter.allowsDynamicMarkedTextFallback(bundleIdentifier: "com.google.chrome", preference: .automatic, appOverrides: ["com.google.chrome": .directReplacement]))
    }

    func testExpandedAppClassification() {
        let testCases: [(String, AppCategory)] = [
            // Terminals
            ("com.apple.terminal", .terminal),
            ("com.googlecode.iterm2", .terminal),
            ("io.alacritty", .terminal),
            ("net.kovidgoyal.kitty", .terminal),
            ("com.mitchellh.ghostty", .terminal),
            ("com.github.wez.wezterm", .terminal),
            ("dev.warp.warp-terminal", .terminal),
            ("com.raphaelamorim.rio", .terminal),
            ("co.zeit.hyper", .terminal),
            ("org.tabby", .terminal),

            // Overlays
            ("com.apple.spotlight", .overlay),
            ("com.raycast.macos", .overlay),
            ("com.runningwithcrayons.alfred", .overlay),
            ("at.obdev.launchbar", .overlay),
            ("com.sol-app", .overlay),

            // Office
            ("com.microsoft.word", .msOffice),
            ("com.microsoft.excel", .msOffice),
            ("com.microsoft.powerpoint", .msOffice),
            ("com.microsoft.onenote.mac", .msOffice),
            ("com.microsoft.outlook", .msOffice),

            // Chromium / Electron / CEF
            ("com.google.chrome", .chromium),
            ("com.brave.browser", .chromium),
            ("com.microsoft.edgemac", .chromium),
            ("com.microsoft.edgemac.dev", .chromium),
            ("company.thebrowser.browser", .chromium),
            ("com.operasoftware.opera", .chromium),
            ("com.vivaldi.vivaldi", .chromium),
            ("com.microsoft.vscode", .chromium),
            ("com.todesktop.230313mzl4w4u92.cursor", .chromium),
            ("com.codeium.windsurf", .chromium),
            ("com.google.antigravity", .chromium),
            ("com.openai.codex", .chromium),
            ("com.tinyspeck.slackmacgap", .chromium),
            ("com.hnc.discord", .chromium),
            ("notion.id", .chromium),
            ("md.obsidian", .chromium),
            ("com.logseq.logseq", .chromium),
            ("com.linear", .chromium),
            ("com.figma.desktop", .chromium),
            ("com.vng.zalo", .chromium),
            ("ru.keepcoder.telegram", .chromium),
            ("com.microsoft.teams2", .chromium),
            ("net.whatsapp.whatsapp", .chromium),
            ("org.whispersystems.signal-desktop", .chromium),
            ("com.stablyai.orca", .chromium),
            ("com.anthropic.claudefordesktop", .chromium),
            ("com.openai.chat", .chromium),
            ("com.byteplus.trae", .chromium),
            ("com.genoffice.app", .chromium),
            ("com.postmanlabs.mac", .chromium),

            // Standard AppKit & Native
            ("com.apple.safari", .standardAppKit),
            ("com.apple.notes", .standardAppKit),
            ("com.apple.mail", .standardAppKit),
            ("com.apple.iwork.pages", .standardAppKit),
            ("com.apple.dt.xcode", .standardAppKit),
            ("com.apple.textedit", .standardAppKit),
            ("com.apple.finder", .standardAppKit),
            ("com.jetbrains.intellij", .standardAppKit),
            ("com.google.android.studio", .standardAppKit),
            ("com.sublimetext.4", .standardAppKit),
            ("org.mozilla.firefox", .standardAppKit),
            // Remote Desktop & VM
            ("com.microsoft.rdc.macos", .remoteOrVirtualMachine),
            ("com.p5sys.jump.mac.viewer", .remoteOrVirtualMachine),
            ("com.apple.remotedesktop", .remoteOrVirtualMachine),
            ("com.carriez.rustdesk", .remoteOrVirtualMachine),
            ("com.teamviewer.teamviewer", .remoteOrVirtualMachine),
            ("com.philandro.anydesk", .remoteOrVirtualMachine),
            ("com.parsecgaming.parsec", .remoteOrVirtualMachine),
            ("com.moonlight-stream.moonlight", .remoteOrVirtualMachine),
            ("com.zuler.deskin", .remoteOrVirtualMachine),
            ("com.youqu.todesk", .remoteOrVirtualMachine),
            ("com.oray.sunloginc", .remoteOrVirtualMachine),
            ("com.splashtop.personal", .remoteOrVirtualMachine),
            ("com.nomachine.nxplayer", .remoteOrVirtualMachine),
            ("com.realvnc.vncviewer", .remoteOrVirtualMachine),
            ("com.edovia.screens5", .remoteOrVirtualMachine),
            ("com.citrix.receiver.nomas", .remoteOrVirtualMachine),
            ("com.vmware.fusion", .remoteOrVirtualMachine),
            ("com.parallels.desktop.console", .remoteOrVirtualMachine),
            ("com.utmapp.UTM", .remoteOrVirtualMachine),
        ]

        for (bundleID, expectedCategory) in testCases {
            XCTAssertEqual(ClientAdapter.classify(bundleIdentifier: bundleID), expectedCategory, "Mismatch for \(bundleID)")
        }
    }

    func testPassthroughPresentationModeForRemoteApps() {
        // When passthroughRemoteApps is true, Remote Desktop apps resolve to .passthrough
        XCTAssertEqual(
            ClientAdapter.presentationMode(
                for: .remoteOrVirtualMachine,
                bundleIdentifier: "com.microsoft.rdc.macos",
                passthroughRemoteApps: true
            ),
            .passthrough
        )

        // When passthroughRemoteApps is false, Remote Desktop apps default to .markedText
        XCTAssertEqual(
            ClientAdapter.presentationMode(
                for: .remoteOrVirtualMachine,
                bundleIdentifier: "com.microsoft.rdc.macos",
                passthroughRemoteApps: false
            ),
            .markedText
        )

        // When per-app override specifies .passthrough, it is honored regardless of category
        XCTAssertEqual(
            ClientAdapter.presentationMode(
                for: .chromium,
                bundleIdentifier: "com.google.chrome",
                appOverrides: ["com.google.chrome": .passthrough]
            ),
            .passthrough
        )

        // When global preference is .passthrough, it applies globally
        XCTAssertEqual(
            ClientAdapter.presentationMode(
                for: .standardAppKit,
                bundleIdentifier: "com.apple.safari",
                preference: .passthrough
            ),
            .passthrough
        )
    }

    func testBrowserAppDetection() {
        let browsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
            "company.thebrowser.dia",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
            "org.mozilla.firefox",
            "app.zen-browser.zen",
            "com.kagi.kagimacOS",
            "com.coccoc.Coccoc",
            "com.duckduckgo.macos.browser"
        ]
        for bundleID in browsers {
            XCTAssertTrue(ClientAdapter.isBrowserApp(bundleIdentifier: bundleID), "Expected browser for \(bundleID)")
        }

        let nonBrowsers = [
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
            "com.vng.zalo",
            "com.stablyai.orca",
            "com.apple.Notes",
            "com.apple.Terminal",
            nil
        ]
        for bundleID in nonBrowsers {
            XCTAssertFalse(ClientAdapter.isBrowserApp(bundleIdentifier: bundleID), "Expected non-browser for \(bundleID ?? "nil")")
        }
    }

    func testHighlightedURLOrDomainDetection() {
        let validURLs = [
            "https://www.google.com/search?q=vielotus",
            "http://localhost:3000/dashboard",
            "localhost:5173",
            "google.com",
            "shopee.vn/cart",
            "tuoitre.vn",
            "docs.google.com/document/d/123",
            "chrome://settings",
            "about:blank",
            "www.vnexpress.net"
        ]
        for url in validURLs {
            XCTAssertTrue(ClientAdapter.isHighlightedURLOrDomain(url), "Expected valid URL/domain for '\(url)'")
        }

        let nonURLs = [
            "",
            "   ",
            "Xin chào Việt Nam",
            "thời tiết hôm nay",
            "hello world",
            "justaword",
            "sentence.",
            ".leadingdot",
            "trailingdot."
        ]
        for text in nonURLs {
            XCTAssertFalse(ClientAdapter.isHighlightedURLOrDomain(text), "Expected non-URL for '\(text)'")
        }
    }

    func testInlineURLAutocompleteTailDetection() {
        // Real browser inline autocomplete tails (e.g. g[oogle.com], sho[pee.vn], tuoi[tre.vn], docs[.google.com])
        XCTAssertTrue(ClientAdapter.isInlineURLAutocompleteTail("oogle.com", matchingNextChar: "o"))
        XCTAssertTrue(ClientAdapter.isInlineURLAutocompleteTail("ogle.com", matchingNextChar: "o"))
        XCTAssertTrue(ClientAdapter.isInlineURLAutocompleteTail("pee.vn", matchingNextChar: "p"))
        XCTAssertTrue(ClientAdapter.isInlineURLAutocompleteTail("tre.vn/thoi-su", matchingNextChar: "t"))
        XCTAssertTrue(ClientAdapter.isInlineURLAutocompleteTail(".google.com"))
        XCTAssertTrue(ClientAdapter.isInlineURLAutocompleteTail("host:3000", matchingNextChar: "h"))
        XCTAssertFalse(ClientAdapter.isInlineURLAutocompleteTail("oogle.com", matchingNextChar: "x"))

        // Reject ordinary prose selections (e.g. Cmd+A or mouse selection in an editor)
        XCTAssertFalse(ClientAdapter.isInlineURLAutocompleteTail("Xin chào các bạn"))
        XCTAssertFalse(ClientAdapter.isInlineURLAutocompleteTail("hello world.com"))
        XCTAssertFalse(ClientAdapter.isInlineURLAutocompleteTail("plainword"))
        XCTAssertFalse(ClientAdapter.isInlineURLAutocompleteTail("sentence."))
    }

    func testDirectReplacementGuardRangeOwnership() {
        // 1. Valid owned range in standard ASCII/Vietnamese BMP composition ("tiế", 3 UTF-16 units)
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: 10, length: 3),
                composingWord: "tiế",
                compositionStartLocation: 10,
                virtualCursorLocation: 13,
                hostSubstring: "tiế"
            ),
            .owned
        )

        // 2. Valid owned range after surrogate pair / emoji prefix ("😀 " = 3 UTF-16 units, startLoc = 3)
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: 3, length: 4),
                composingWord: "việt",
                compositionStartLocation: 3,
                virtualCursorLocation: 7,
                hostSubstring: "việt"
            ),
            .owned
        )

        // 3. Reject NSNotFound or zero-length range
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: NSNotFound, length: 0),
                composingWord: "việt"
            ),
            .invalidRange
        )

        // 4. Never replace more UTF-16 units than the current composition session owns
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: 8, length: 5),
                composingWord: "tiế",
                compositionStartLocation: 10,
                virtualCursorLocation: 13
            ),
            .exceedsOwnedSessionLength
        )

        // 5. Reject range outside [compositionStartLocation, virtualCursorLocation]
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: 9, length: 2),
                composingWord: "tiế",
                compositionStartLocation: 10,
                virtualCursorLocation: 13
            ),
            .outsideCompositionBounds
        )

        // 6. Detect host text divergence (host buffer mutated externally to unrelated text)
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: 10, length: 3),
                composingWord: "tiế",
                compositionStartLocation: 10,
                virtualCursorLocation: 13,
                hostSubstring: "abc"
            ),
            .hostTextDiverged
        )

        // 7. Allow NFD vs NFC equivalent host substring without false divergence
        let nfdSubstring = "tiế".decomposedStringWithCanonicalMapping
        XCTAssertEqual(
            DirectReplacementGuard.verifyRangeOwnership(
                replacementRange: NSRange(location: 10, length: (nfdSubstring as NSString).length),
                composingWord: nfdSubstring,
                compositionStartLocation: 10,
                virtualCursorLocation: 10 + (nfdSubstring as NSString).length,
                hostSubstring: "tiế".precomposedStringWithCanonicalMapping
            ),
            .owned
        )
    }

    func testDirectReplacementGuardCursorEvaluationAndDynamicFallback() {
        ClientAdapter.resetDynamicMarkedText()
        defer { ClientAdapter.resetDynamicMarkedText() }

        // 1. In-sync cursor
        XCTAssertEqual(
            DirectReplacementGuard.evaluateCursorState(
                selection: NSRange(location: 5, length: 0),
                virtualCursorLocation: 5,
                compositionStartLocation: 2,
                composingWordUTF16Length: 3,
                lastReplacementLength: 1
            ),
            .inSync
        )

        // 2. Invalid selection (NSNotFound) triggers fallback to Marked Text
        XCTAssertEqual(
            DirectReplacementGuard.evaluateCursorState(
                selection: NSRange(location: NSNotFound, length: 0),
                virtualCursorLocation: 5,
                compositionStartLocation: 2,
                composingWordUTF16Length: 3
            ),
            .invalidSelectionFallbackToMarkedText
        )

        // 3. Host silently ignored replacementRange (e.g. replaced "a" len=1 with "á" at start=0,
        //    expected virtualCursorLocation=1, but host appended "á" to produce "aá" at cursor=2)
        let evalIgnored = DirectReplacementGuard.evaluateCursorState(
            selection: NSRange(location: 2, length: 0),
            virtualCursorLocation: 1,
            compositionStartLocation: 0,
            composingWordUTF16Length: 1,
            lastReplacementLength: 1,
            hostWindowSubstring: "aá",
            expectedIgnoredWindowText: "aá"
        )
        XCTAssertEqual(evalIgnored, .ignoredReplacementFallbackToMarkedText)

        // Verify ClientAdapter transitions the broken host to .markedText while keeping healthy AppKit on .directReplacement
        let brokenBundleID = "com.thirdparty.broken-direct-replace"
        let initialRes = ClientAdapter.resolvePresentationModeWithSource(for: .standardAppKit, bundleIdentifier: brokenBundleID)
        XCTAssertEqual(initialRes.mode, .directReplacement)
        XCTAssertEqual(initialRes.source, .categoryHeuristic(.standardAppKit))
        XCTAssertFalse(ClientAdapter.isForcedMarkedText(for: brokenBundleID))

        ClientAdapter.forceMarkedText(for: brokenBundleID)
        XCTAssertTrue(ClientAdapter.isForcedMarkedText(for: brokenBundleID))
        let fallbackRes = ClientAdapter.resolvePresentationModeWithSource(for: .standardAppKit, bundleIdentifier: brokenBundleID)
        XCTAssertEqual(fallbackRes.mode, .markedText)
        XCTAssertEqual(fallbackRes.source, .dynamicFallback)
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .standardAppKit, bundleIdentifier: "com.apple.notes"),
            .directReplacement
        )

        ClientAdapter.clearForcedMarkedText(for: brokenBundleID)
        XCTAssertFalse(ClientAdapter.isForcedMarkedText(for: brokenBundleID))
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .standardAppKit, bundleIdentifier: brokenBundleID),
            .directReplacement
        )

        // 4. External single-character Backspace retains prefix
        XCTAssertEqual(
            DirectReplacementGuard.evaluateCursorState(
                selection: NSRange(location: 4, length: 0),
                virtualCursorLocation: 5,
                compositionStartLocation: 2,
                composingWordUTF16Length: 3
            ),
            .prefixRetained(charsDeleted: 1)
        )

        // 5. External full-word Backspace clears composition
        XCTAssertEqual(
            DirectReplacementGuard.evaluateCursorState(
                selection: NSRange(location: 2, length: 0),
                virtualCursorLocation: 5,
                compositionStartLocation: 2,
                composingWordUTF16Length: 3
            ),
            .compositionCleared
        )

        // 6. External cursor jump (mouse click or arrow jump outside word) resets session cleanly
        XCTAssertEqual(
            DirectReplacementGuard.evaluateCursorState(
                selection: NSRange(location: 20, length: 0),
                virtualCursorLocation: 5,
                compositionStartLocation: 2,
                composingWordUTF16Length: 3,
                lastReplacementLength: 1
            ),
            .externalCursorJumpResetSession
        )
    }

    func testExcelAppDetection() {
        XCTAssertTrue(ClientAdapter.isExcelApp(bundleIdentifier: "com.microsoft.Excel"))
        XCTAssertTrue(ClientAdapter.isExcelApp(bundleIdentifier: "com.microsoft.excel"))
        XCTAssertTrue(ClientAdapter.isExcelApp(bundleIdentifier: "org.vielotus.inputmethod.vielotuslab.com.microsoft.excel"))
        XCTAssertFalse(ClientAdapter.isExcelApp(bundleIdentifier: "com.microsoft.Word"))
        XCTAssertFalse(ClientAdapter.isExcelApp(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(ClientAdapter.isExcelApp(bundleIdentifier: nil))
    }

    func testExtractAdoptableOnsetPrefixAndPartialWordReplacementFlows() {
        // 1. Positive onset extraction cases (partial-word selection & post-deletion caret)
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "c", nextChar: "u", hasActiveSelection: true),
            "c"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "ch", nextChar: "o", hasActiveSelection: true),
            "ch"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "ch", nextChar: "i", hasActiveSelection: true),
            "ch"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "q", nextChar: "u", hasActiveSelection: true),
            "q"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "qu", nextChar: "o", hasActiveSelection: true),
            "qu"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "d", nextChar: "d", hasActiveSelection: true),
            "d"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "ngh", nextChar: "i", hasActiveSelection: true),
            "ngh"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "gi", nextChar: "s", hasActiveSelection: true),
            "gi"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "xin c", nextChar: "u", hasActiveSelection: true),
            "c"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "(c", nextChar: "u", hasActiveSelection: true),
            "c"
        )
        XCTAssertEqual(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "C", nextChar: "u", hasActiveSelection: false, charAfterCaret: " "),
            "C"
        )

        // 2. Negative onset extraction cases (paths, identifiers, digits, invalid clusters, mid-word caret)
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "/c", nextChar: "u", hasActiveSelection: true))
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "user.c", nextChar: "o", hasActiveSelection: true))
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "a_c", nextChar: "u", hasActiveSelection: true))
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "3c", nextChar: "u", hasActiveSelection: true))
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "abcd", nextChar: "u", hasActiveSelection: true))
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "s", nextChar: "b", hasActiveSelection: true))
        XCTAssertNil(DirectReplacementGuard.extractAdoptableOnsetPrefix(beforeCaret: "q", nextChar: "a", hasActiveSelection: true))
        XCTAssertNil(
            DirectReplacementGuard.extractAdoptableOnsetPrefix(
                beforeCaret: "c",
                nextChar: "u",
                hasActiveSelection: false,
                charAfterCaret: "ù"
            )
        )

        // 3. End-to-end partial-word replacement via setCompositionPrefix(onset) + rhyme typing + commitWord
        let partialWordCases: [(initialWord: String, keptOnset: String, typedRhyme: String, expected: String)] = [
            ("cùng", "c", "uoois", "cuối"),
            ("chúng", "ch", "ojn", "chọn"),
            ("chúng", "ch", "onj", "chọn"),
            ("chúng", "ch", "is", "chí"),
            ("chúng", "ch", "or", "chỏ"),
            ("quáng", "q", "uawng", "quăng"),
            ("quáng", "qu", "oocs", "quốc"),
            ("dùng", "d", "di", "đi")
        ]

        for (initialWord, keptOnset, typedRhyme, expected) in partialWordCases {
            guard let firstChar = typedRhyme.first else {
                XCTFail("Empty typedRhyme")
                continue
            }
            let adopted = DirectReplacementGuard.extractAdoptableOnsetPrefix(
                beforeCaret: keptOnset,
                nextChar: firstChar,
                hasActiveSelection: true
            )
            XCTAssertEqual(adopted, keptOnset, "Expected onset '\(keptOnset)' from '\(initialWord)' to be adopted")

            let session = InputSessionManager()
            session.setCompositionPrefix(keptOnset)
            var screen = keptOnset
            for ch in typedRhyme {
                let act = session.handleCharacter(ch)
                if case let .replace(bs, txt) = act {
                    if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                    screen += txt
                } else if case .passThrough = act {
                    screen.append(ch)
                }
            }
            if session.isComposing {
                let act = session.commitWord(smartBilingualEnabled: true, boundaryChar: " ")
                if case let .commit(bs, txt, isOverride) = act, isOverride {
                    if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                    screen += txt
                }
            }
            XCTAssertEqual(
                screen,
                expected,
                "Partial replacement '\(initialWord)' -> keep '\(keptOnset)' + '\(typedRhyme)' expected '\(expected)', got '\(screen)'"
            )
        }
    }
}
