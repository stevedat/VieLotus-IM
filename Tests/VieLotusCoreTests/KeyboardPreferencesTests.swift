import XCTest
@testable import VieLotusCore


final class KeyboardPreferencesTests: XCTestCase {
    func testKeyboardPreferencesDefaultsAndOverrides() {
        let suiteName = "test.vietlotus.keyboard.prefs"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        let prefs = KeyboardPreferences(defaults: testDefaults)

        // Default input method is telex, so showNumberRow defaults to false
        XCTAssertEqual(prefs.inputMethod, .telex)
        XCTAssertFalse(prefs.showNumberRow)
        XCTAssertTrue(prefs.smartBilingual)
        XCTAssertTrue(prefs.modernOrthography)
        XCTAssertTrue(prefs.hapticFeedbackEnabled)
        XCTAssertTrue(prefs.soundFeedbackEnabled)
        XCTAssertTrue(prefs.autoCapitalizationEnabled)
        XCTAssertTrue(prefs.periodShortcutEnabled)

        // Mutate and verify persistence
        prefs.inputMethod = .vni
        XCTAssertEqual(prefs.inputMethod, .vni)
        // In VNI mode without explicit preference, showNumberRow automatically defaults to true
        XCTAssertTrue(prefs.showNumberRow)

        // Explicit override persists regardless of input method
        prefs.showNumberRow = false
        XCTAssertFalse(prefs.showNumberRow)

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
}
