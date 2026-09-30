import Cocoa
import InputMethodKit
import VieLotusCore

final class VieLotusIMAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    override init() {
        super.init()

        // 1. Inject macOS Spell Checker Provider immediately
        SmartBilingualDetector.spellCheckerProvider = MacSpellChecker()

        // 2. Register IMKServer synchronously before runloop starts to prevent cold-start IPC drop
        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? "org.vielotus.inputmethod.VieLotusIM_Connection"
        let bundleID = Bundle.main.bundleIdentifier ?? "org.vielotus.inputmethod.VieLotusIM"
        server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
        NSLog("VieLotusIM (Sen Việt): InputMethodKit server started synchronously with connection: \(connectionName), bundleID: \(bundleID)")

    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("VieLotusIM (Sen Việt): Application finished launching and ready for input")
        // Pre-warm NaturalLanguage recognizer & system spell daemon when main runloop is idle
        DispatchQueue.main.async {
            _ = SmartBilingualDetector.isEnglishWord(raw: "test", context: "vietlotus cold start prewarm")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("VieLotusIM (Sen Việt): InputMethodKit server terminating")
    }
}

let app = NSApplication.shared
let delegate = VieLotusIMAppDelegate()
app.delegate = delegate
app.run()
