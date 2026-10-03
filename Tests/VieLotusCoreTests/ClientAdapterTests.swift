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
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "org.vielotus.inputmethod.vielotuslab.chromium"),
            .directReplacement
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
            .directReplacement
        )
        XCTAssertEqual(
            ClientAdapter.presentationMode(for: .chromium, bundleIdentifier: "com.google.chrome"),
            .directReplacement
        )
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
            ("dev.zed.Zed", .standardAppKit),
        ]

        for (bundleID, expectedCategory) in testCases {
            XCTAssertEqual(ClientAdapter.classify(bundleIdentifier: bundleID), expectedCategory, "Mismatch for \(bundleID)")
        }
    }
}
