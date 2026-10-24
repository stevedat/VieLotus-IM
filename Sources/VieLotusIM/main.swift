import Cocoa
import InputMethodKit
import CryptoKit
import VieLotusCore

final class VieLotusIMAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?
    private var bridgeDaemon: LocalLoopbackBridge?
    private let bridgeCoordinator = VieLotusBridgeCoordinator(
        getMode: {
            let prefs = Preferences.shared
            if !prefs.vietnameseEnabled {
                return "en"
            }
            return prefs.inputMethod == .vni ? "vni" : "telex"
        },
        applyMode: { normalized in
            let prefs = Preferences.shared
            switch normalized {
            case "en":
                prefs.vietnameseEnabled = false
            case "telex":
                prefs.vietnameseEnabled = true
                prefs.inputMethod = .telex
            case "vni":
                prefs.vietnameseEnabled = true
                prefs.inputMethod = .vni
            default:
                break
            }
        }
    )

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

        // 3. Local Loopback Daemon is strictly OPT-IN (disabled by default to guarantee zero background listeners)
        #if canImport(Network)
        let bridgeOptIn = UserDefaults.standard.bool(forKey: "enableLocalLoopbackBridge")
            || ProcessInfo.processInfo.environment["VIELOTUS_ENABLE_LOOPBACK_BRIDGE"] == "1"
        if bridgeOptIn {
            bridgeDaemon = LocalLoopbackBridge(delegate: bridgeCoordinator)
            bridgeDaemon?.start()
        }
        #endif

        // Pre-warm NaturalLanguage recognizer & system spell daemon when main runloop is idle
        DispatchQueue.main.async {
            _ = SmartBilingualDetector.isEnglishWord(raw: "test", context: "vietlotus cold start prewarm")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("VieLotusIM (Sen Việt): InputMethodKit server terminating")
        bridgeDaemon?.stop()
    }
}

let app = NSApplication.shared
let delegate = VieLotusIMAppDelegate()
app.delegate = delegate
app.run()
