import XCTest
@testable import VieLotusCore


final class KeyboardPreferencesTests: XCTestCase {
    func testKeyboardPreferencesDefaultsAndOverrides() {
        let suiteName = "test.vietlotus.keyboard.prefs"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        testDefaults.set(true, forKey: "macroEnabled")
        let prefs = KeyboardPreferences(defaults: testDefaults)

        // Default input method is telex, so showNumberRow and showCommaKey default to false (100% Apple native Row 4)
        XCTAssertEqual(prefs.inputMethod, .telex)
        XCTAssertEqual(prefs.grammarProfile, .senFlex)
        XCTAssertFalse(prefs.showNumberRow)
        XCTAssertFalse(prefs.showCommaKey)
        XCTAssertFalse(prefs.macroEnabled)
        prefs.macroEnabled = true
        XCTAssertTrue(KeyboardPreferences(defaults: testDefaults).macroEnabled)
        prefs.macroEnabled = false
        XCTAssertFalse(KeyboardPreferences(defaults: testDefaults).macroEnabled)
        XCTAssertTrue(prefs.smartBilingual)
        XCTAssertFalse(prefs.wordSuggestionsEnabled)
        prefs.wordSuggestionsEnabled = true
        XCTAssertTrue(KeyboardPreferences(defaults: testDefaults).wordSuggestionsEnabled)
        prefs.wordSuggestionsEnabled = false
        XCTAssertFalse(KeyboardPreferences(defaults: testDefaults).wordSuggestionsEnabled)
        XCTAssertTrue(prefs.modernOrthography)
        XCTAssertTrue(prefs.hapticFeedbackEnabled)
        XCTAssertTrue(prefs.soundFeedbackEnabled)
        XCTAssertTrue(prefs.autoCapitalizationEnabled)
        XCTAssertTrue(prefs.periodShortcutEnabled)
        XCTAssertFalse(prefs.glideTypingEnabled)
        XCTAssertFalse(prefs.mascotEnabled)

        // Mutate and verify persistence
        prefs.mascotEnabled = true
        XCTAssertTrue(prefs.mascotEnabled)
        prefs.mascotEnabled = false
        XCTAssertFalse(prefs.mascotEnabled)

        XCTAssertFalse(prefs.mascotAdvancedModeEnabled)
        prefs.mascotAdvancedModeEnabled = true
        XCTAssertTrue(prefs.mascotAdvancedModeEnabled)
        prefs.mascotAdvancedModeEnabled = false
        XCTAssertFalse(prefs.mascotAdvancedModeEnabled)

        XCTAssertTrue(prefs.mascotChibiFrameEnabled)
        prefs.mascotChibiFrameEnabled = false
        XCTAssertFalse(prefs.mascotChibiFrameEnabled)
        prefs.mascotChibiFrameEnabled = true
        XCTAssertTrue(prefs.mascotChibiFrameEnabled)

        // Free tier by default: mascotFlexUnlocked is false and mascotRoamArea is .barOnly (Full-Bar Roaming)
        XCTAssertFalse(prefs.mascotFlexUnlocked)
        XCTAssertEqual(prefs.mascotFlexPlan, .free)
        XCTAssertEqual(prefs.mascotRoamArea, .barOnly)

        // Unlocking Gói Flex (.lifetime / .yearly) unlocks .fullKeyboard roaming
        prefs.mascotFlexPlan = .lifetime
        XCTAssertTrue(prefs.mascotFlexUnlocked)
        XCTAssertEqual(prefs.mascotFlexPlan, .lifetime)
        XCTAssertEqual(prefs.mascotRoamArea, .fullKeyboard)
        prefs.mascotRoamArea = .barOnly
        XCTAssertEqual(prefs.mascotRoamArea, .barOnly)
        prefs.mascotRoamArea = .fullKeyboard
        XCTAssertEqual(prefs.mascotRoamArea, .fullKeyboard)

        prefs.mascotFlexPlan = .yearly
        XCTAssertTrue(prefs.mascotFlexUnlocked)
        XCTAssertEqual(prefs.mascotFlexPlan, .yearly)
        prefs.mascotFlexPlan = .free
        XCTAssertFalse(prefs.mascotFlexUnlocked)
        XCTAssertEqual(prefs.mascotRoamArea, .barOnly)

        XCTAssertFalse(prefs.mascotCoupleEnabled)
        XCTAssertTrue(prefs.mascotReminderEnabled)
        XCTAssertEqual(prefs.mascot1Outfit, .denimBlue)
        XCTAssertEqual(prefs.mascot1Accessory, .none)
        XCTAssertEqual(prefs.mascot2Outfit, .lotusPink)
        XCTAssertEqual(prefs.mascot2Accessory, .bowRibbon)
        XCTAssertEqual(prefs.mascotFishingPreset, .iLoveYou)
        XCTAssertEqual(prefs.quickReminderButtonTitle, "📌 I love you ❤️ ↻")

        // Cycle quick reminder on Free tier: iLoveYou -> missYou -> milkTea -> happyDay -> Tắt -> drinkWater
        prefs.cycleQuickReminder()
        XCTAssertTrue(prefs.mascotReminderEnabled)
        XCTAssertEqual(prefs.mascotFishingPreset, .missYou)
        prefs.cycleQuickReminder()
        XCTAssertEqual(prefs.mascotFishingPreset, .milkTea)
        prefs.cycleQuickReminder()
        XCTAssertEqual(prefs.mascotFishingPreset, .happyDay)
        prefs.cycleQuickReminder()
        XCTAssertFalse(prefs.mascotReminderEnabled)
        XCTAssertEqual(prefs.quickReminderButtonTitle, "🔕 Nhắc nhau: Tắt ↻")
        prefs.cycleQuickReminder()
        XCTAssertTrue(prefs.mascotReminderEnabled)
        XCTAssertEqual(prefs.mascotFishingPreset, .drinkWater)
        XCTAssertEqual(prefs.quickReminderButtonTitle, "📌 Uống nước 💧 ↻")

        prefs.mascotCoupleEnabled = true
        prefs.mascot1Outfit = .royalGold
        prefs.mascot1Accessory = .crown
        prefs.mascot2Outfit = .emeraldMint
        prefs.mascot2Accessory = .nonLa
        prefs.mascotFishingPreset = .customText
        prefs.customMascotFishingText = "Thương em nhiều ❤️"

        XCTAssertTrue(prefs.mascotCoupleEnabled)
        XCTAssertEqual(prefs.mascot1Outfit, .royalGold)
        XCTAssertEqual(prefs.mascot1Accessory, .crown)
        XCTAssertEqual(prefs.mascot2Outfit, .emeraldMint)
        XCTAssertEqual(prefs.mascot2Accessory, .nonLa)
        XCTAssertEqual(prefs.mascotFishingPreset, .customText)
        XCTAssertEqual(prefs.customMascotFishingText, "Thương em nhiều ❤️")
        XCTAssertEqual(prefs.mascotFishingPreset.steps(customText: prefs.customMascotFishingText).final, "Thương em nhiều ❤️")
        prefs.grammarProfile = .classic
        XCTAssertEqual(prefs.grammarProfile, .classic)

        prefs.inputMethod = .vni
        XCTAssertEqual(prefs.inputMethod, .vni)
        // showNumberRow defaults to false unless explicitly enabled
        XCTAssertFalse(prefs.showNumberRow)

        // Explicit override persists regardless of input method
        prefs.showNumberRow = true
        XCTAssertTrue(prefs.showNumberRow)
        prefs.showNumberRow = false
        XCTAssertFalse(prefs.showNumberRow)

        prefs.showCommaKey = true
        XCTAssertTrue(prefs.showCommaKey)
        prefs.showCommaKey = false
        XCTAssertFalse(prefs.showCommaKey)

        prefs.smartBilingual = false
        XCTAssertFalse(prefs.smartBilingual)

        prefs.modernOrthography = false
        XCTAssertFalse(prefs.modernOrthography)

        prefs.hapticFeedbackEnabled = false
        XCTAssertFalse(prefs.hapticFeedbackEnabled)

        prefs.soundFeedbackEnabled = false
        XCTAssertFalse(prefs.soundFeedbackEnabled)

        prefs.autoCapitalizationEnabled = false
        XCTAssertFalse(prefs.autoCapitalizationEnabled)

        prefs.periodShortcutEnabled = false
        XCTAssertFalse(prefs.periodShortcutEnabled)

        prefs.glideTypingEnabled = true
        XCTAssertTrue(prefs.glideTypingEnabled)

        // Verify one-time migration restores autoCapitalizationEnabled = true and periodShortcutEnabled = true by default
        let migSuite = "test.vietlotus.keyboard.prefs.mig"
        let migDefaults = UserDefaults(suiteName: migSuite)!
        migDefaults.removePersistentDomain(forName: migSuite)
        migDefaults.set(false, forKey: "autoCapitalizationEnabled")
        migDefaults.set(false, forKey: "periodShortcutEnabled")
        let migratedPrefs = KeyboardPreferences(defaults: migDefaults)
        XCTAssertTrue(migratedPrefs.autoCapitalizationEnabled)
        XCTAssertTrue(migratedPrefs.periodShortcutEnabled)
        migDefaults.removePersistentDomain(forName: migSuite)

        // Clean up
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    func testUIKitAdapterWithVniMethod() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.vni)
        let proxy = MockTextDocumentProxy()

        // Type "Việt" in VNI: V i e 6 5 t
        let chars: [Character] = ["V", "i", "e", "6", "5", "t"]
        for c in chars {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "Việt")

        // Space commits
        adapter.handleCharacter(" ", proxy: proxy)
        XCTAssertEqual(proxy.buffer, "Việt ")
    }

    func testUIKitAdapterWithSenFlexProfile() {
        let adapter = UIKitInputSessionAdapter()
        adapter.session.setInputMethod(.telex)
        adapter.session.setGrammarProfile(.senFlex)
        let proxy = MockTextDocumentProxy()

        // Pre-vowel tone in SEN Flex: T s e e t -> Tết
        for c in "Tseet" {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.buffer, "Tết")
    }

    func testUIKitAdapterHandlesAsyncXPCProxyLagWithoutManglingWords() {
        /// Simulates real iOS `UITextDocumentProxy` where `insertText` and `deleteBackward`
        /// execute over asynchronous IPC and do NOT mutate `documentContextBeforeInput` synchronously.
        final class LaggingXPCProxy: TextDocumentProxyProtocol {
            var trueBuffer: String = ""
            var exposedSnapshot: String? = ""
            var documentContextBeforeInput: String? { exposedSnapshot }
            var documentContextAfterInput: String? { nil }

            func insertText(_ text: String) {
                trueBuffer.append(text)
                // Intentionally do NOT update `exposedSnapshot` synchronously
            }

            func deleteBackward() {
                if !trueBuffer.isEmpty {
                    trueBuffer.removeLast()
                }
                // Intentionally do NOT update `exposedSnapshot` synchronously
            }

            func flushXPC() {
                exposedSnapshot = trueBuffer
            }
        }

        let adapter = UIKitInputSessionAdapter()
        let proxy = LaggingXPCProxy()

        // 1. Type "chào " (c h a f o <space>) while XPC lags behind
        for c in "chafo " {
            adapter.handleCharacter(c, proxy: proxy)
        }
        XCTAssertEqual(proxy.trueBuffer, "chào ")

        // Host app XPC catches up to "chào "
        proxy.flushXPC()

        // 2. User rapidly presses Backspace to delete space, then immediately taps 's' to change "chào" -> "cháo"
        // BEFORE XPC updates `exposedSnapshot` (which is still "chào " with trailing space!).
        adapter.handleBackspace(proxy: proxy)
        XCTAssertEqual(proxy.trueBuffer, "chào")

        adapter.handleCharacter("s", proxy: proxy)
        XCTAssertEqual(proxy.trueBuffer, "cháo")

        // 3. Transient nil `documentContextBeforeInput` during `handleExternalTextChange` must not reset active composition
        proxy.exposedSnapshot = nil
        adapter.handleExternalTextChange(proxy: proxy)
        XCTAssertTrue(adapter.session.isComposing)
    }

    func testBuiltInKeyboardThemeSystemAndPersistence() {
        let suiteName = "test.vietlotus.keyboard.themes"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        let prefs = KeyboardPreferences(defaults: testDefaults)
        XCTAssertEqual(prefs.theme, .systemAuto)

        // Verify all 8 built-in themes persist and expose valid palettes
        for theme in KeyboardThemeID.allCases {
            prefs.theme = theme
            XCTAssertEqual(prefs.theme, theme)
            XCTAssertFalse(theme.displayName.isEmpty)
            XCTAssertFalse(theme.subtitle.isEmpty)

            let lightPalette = theme.resolvedPalette(isDarkSystem: false)
            let darkPalette = theme.resolvedPalette(isDarkSystem: true)
            for palette in [lightPalette, darkPalette] {
                for color in [
                    palette.backdropColor,
                    palette.glassBorderColor,
                    palette.letterKeyBackground,
                    palette.letterKeyText,
                    palette.specialKeyBackground,
                    palette.specialKeyText,
                    palette.returnKeyBackground,
                    palette.returnKeyText
                ] {
                    XCTAssertTrue((0.0...1.0).contains(color.r))
                    XCTAssertTrue((0.0...1.0).contains(color.g))
                    XCTAssertTrue((0.0...1.0).contains(color.b))
                    XCTAssertTrue((0.0...1.0).contains(color.a))
                }
            }
        }

        // Verify specific requested themes
        XCTAssertEqual(KeyboardThemeID.classicLight.displayName, "Classic Light")
        XCTAssertEqual(KeyboardThemeID.classicLight.subtitle, "Giao diện sáng, tối giản")
        XCTAssertFalse(KeyboardThemeID.classicLight.resolvedPalette(isDarkSystem: true).isDark)

        XCTAssertEqual(KeyboardThemeID.midnightDark.displayName, "Midnight Dark")
        XCTAssertEqual(KeyboardThemeID.midnightDark.subtitle, "Nền tối, tương phản rõ")
        XCTAssertTrue(KeyboardThemeID.midnightDark.resolvedPalette(isDarkSystem: false).isDark)

        XCTAssertEqual(KeyboardThemeID.mintGreen.displayName, "Mint Green")
        XCTAssertEqual(KeyboardThemeID.mintGreen.subtitle, "Xanh dịu, hiện đại")
        XCTAssertFalse(KeyboardThemeID.mintGreen.resolvedPalette(isDarkSystem: true).isDark)

        XCTAssertEqual(KeyboardThemeID.pastelRose.displayName, "Pastel Rose")
        XCTAssertEqual(KeyboardThemeID.pastelRose.subtitle, "Hồng nhẹ nhàng")
        XCTAssertFalse(KeyboardThemeID.pastelRose.resolvedPalette(isDarkSystem: true).isDark)

        // Verify cycle order wraps back to .systemAuto
        var current: KeyboardThemeID = .systemAuto
        for _ in 0..<KeyboardThemeID.allCases.count {
            current = current.nextTheme
        }
        XCTAssertEqual(current, .systemAuto)

        testDefaults.removePersistentDomain(forName: suiteName)
    }

    func testMascotCoupleNonOverlappingGeometryAndCustomEffectStyles() {
        let suiteName = "test.vietlotus.keyboard.couple_effects"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        let prefs = KeyboardPreferences(defaults: testDefaults)
        // Side-by-side non-overlapping geometry invariant: center-to-center gap (31.5pt) must exceed
        // the largest medallion diameter (31.0pt full-bleed / 26.0pt chibi frame) so faces never cover each other.
        XCTAssertEqual(MascotSharedSpec.Motion.coupleSnuggleGapPt, 31.5)
        XCTAssertGreaterThan(
            CGFloat(MascotSharedSpec.Motion.coupleSnuggleGapPt),
            MascotSharedSpec.FaceFraming.fullBleedFaceSize
        )
        XCTAssertGreaterThan(
            CGFloat(MascotSharedSpec.Motion.coupleSnuggleGapPt),
            MascotSharedSpec.FaceFraming.chibiFaceSize
        )

        // Default effect style is .floatingHearts
        XCTAssertEqual(prefs.mascotEffectStyle, .floatingHearts)

        for style in MascotEffectStyle.allCases {
            prefs.mascotEffectStyle = style
            XCTAssertEqual(prefs.mascotEffectStyle, style)
            XCTAssertFalse(style.displayName.isEmpty)
            XCTAssertFalse(style.shortIcon.isEmpty)
        }

        // Default Chibi outer border style is .classic3D
        XCTAssertEqual(prefs.mascotChibiBorderStyle, .classic3D)
        for border in MascotChibiBorderStyle.allCases {
            prefs.mascotChibiBorderStyle = border
            XCTAssertEqual(prefs.mascotChibiBorderStyle, border)
            XCTAssertFalse(border.displayName.isEmpty)
            XCTAssertFalse(border.shortIcon.isEmpty)
        }

        // Default Reminder font style is .rounded
        XCTAssertEqual(prefs.mascotReminderFontStyle, .rounded)
        for fontStyle in MascotReminderFontStyle.allCases {
            prefs.mascotReminderFontStyle = fontStyle
            XCTAssertEqual(prefs.mascotReminderFontStyle, fontStyle)
            XCTAssertFalse(fontStyle.displayName.isEmpty)
            XCTAssertFalse(fontStyle.shortIcon.isEmpty)
        }

        // Default Motion style is .playfulStroll
        XCTAssertEqual(prefs.mascotMotionStyle, .playfulStroll)
        for motion in MascotMotionStyle.allCases {
            prefs.mascotMotionStyle = motion
            XCTAssertEqual(prefs.mascotMotionStyle, motion)
            XCTAssertFalse(motion.displayName.isEmpty)
            XCTAssertFalse(motion.shortIcon.isEmpty)
        }

        testDefaults.removePersistentDomain(forName: suiteName)
    }

    func testInputMethodPersistenceAcrossRestartAndDualStoreFallback() {
        let primarySuite = "test.vietlotus.keyboard.primary"
        let localSuite = "test.vietlotus.keyboard.local"
        let primaryDefaults = UserDefaults(suiteName: primarySuite)!
        let localDefaults = UserDefaults(suiteName: localSuite)!
        primaryDefaults.removePersistentDomain(forName: primarySuite)
        localDefaults.removePersistentDomain(forName: localSuite)

        // 1. User switches from Telex to VNI
        do {
            let prefs = KeyboardPreferences(defaults: primaryDefaults, localDefaults: localDefaults)
            XCTAssertEqual(prefs.inputMethod, .telex)
            prefs.inputMethod = .vni
            XCTAssertEqual(prefs.inputMethod, .vni)
        }

        // 2. Normal restart: new KeyboardPreferences instance restores .vni
        do {
            let restartedPrefs = KeyboardPreferences(defaults: primaryDefaults, localDefaults: localDefaults)
            XCTAssertEqual(restartedPrefs.inputMethod, .vni)
        }

        // 3. Simulate iOS Keyboard Extension without Full Access where App Group container (primaryDefaults)
        // is inaccessible/empty after reboot, leaving only the extension's localDefaults container.
        primaryDefaults.removePersistentDomain(forName: primarySuite)
        do {
            let rebootedExtensionPrefs = KeyboardPreferences(defaults: primaryDefaults, localDefaults: localDefaults)
            XCTAssertEqual(
                rebootedExtensionPrefs.inputMethod,
                .vni,
                "VNI selection must survive reboot via localDefaults even when App Group UserDefaults is unavailable"
            )
        }

        // 4. Simulate stale "telex" in one store with older timestamp and newer "vni" in the other store:
        // reconciliation must always pick the newer timestamp so VNI never reverts to Telex.
        primaryDefaults.set("telex", forKey: "inputMethodV2")
        primaryDefaults.set(1_000.0, forKey: "preferencesUpdatedAtV1")
        localDefaults.set("vni", forKey: "inputMethodV2")
        localDefaults.set(2_000.0, forKey: "preferencesUpdatedAtV1")
        do {
            let reconciledFromLocal = KeyboardPreferences(defaults: primaryDefaults, localDefaults: localDefaults)
            XCTAssertEqual(reconciledFromLocal.inputMethod, .vni)
            XCTAssertEqual(primaryDefaults.string(forKey: "inputMethodV2"), "vni")
        }

        // And the symmetric direction: Host App updated primaryDefaults to "vni" with a newer timestamp
        // while extension's localDefaults still had "telex" with an older timestamp.
        primaryDefaults.set("vni", forKey: "inputMethodV2")
        primaryDefaults.set(3_000.0, forKey: "preferencesUpdatedAtV1")
        localDefaults.set("telex", forKey: "inputMethodV2")
        localDefaults.set(2_000.0, forKey: "preferencesUpdatedAtV1")
        do {
            let reconciledFromPrimary = KeyboardPreferences(defaults: primaryDefaults, localDefaults: localDefaults)
            XCTAssertEqual(reconciledFromPrimary.inputMethod, .vni)
            XCTAssertEqual(localDefaults.string(forKey: "inputMethodV2"), "vni")
        }

        // 5. Verify session switching between Telex and VNI cleanly resets state and applies new rules immediately
        let session = InputSessionManager()
        XCTAssertEqual(session.engine.inputMethod, .telex)
        session.setInputMethod(.vni)
        XCTAssertEqual(session.engine.inputMethod, .vni)
        for ch in "truong72" {
            _ = session.handleCharacter(ch)
        }
        XCTAssertEqual(session.composingWord, "trường")
        session.setInputMethod(.telex)
        XCTAssertEqual(session.engine.inputMethod, .telex)
        XCTAssertFalse(session.isComposing)
        for ch in "truowngf" {
            _ = session.handleCharacter(ch)
        }
        XCTAssertEqual(session.composingWord, "trường")

        primaryDefaults.removePersistentDomain(forName: primarySuite)
        localDefaults.removePersistentDomain(forName: localSuite)
    }

    func testFeedbackURLIncludesPlatformVersionAndStructuredWordParameters() {
        let url = AppInfo.feedbackURL(
            platform: "ios",
            inputMethod: "Telex",
            smartBilingual: true,
            typedKeys: "just",
            actualOutput: "jút",
            expectedOutput: "just"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "stevedat.github.io")
        XCTAssertEqual(components?.path, "/VieLotus-IM/feedback.html")

        let queryDict = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(queryDict["platform"], "ios")
        XCTAssertEqual(queryDict["v"], AppInfo.appVersion)
        XCTAssertEqual(queryDict["build"], AppInfo.buildNumber)
        XCTAssertEqual(queryDict["im"], "telex")
        XCTAssertEqual(queryDict["bilingual"], "1")
        XCTAssertEqual(queryDict["keys"], "just")
        XCTAssertEqual(queryDict["actual"], "jút")
        XCTAssertEqual(queryDict["expected"], "just")
    }
}
