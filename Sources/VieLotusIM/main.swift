import Cocoa
import InputMethodKit
import VieLotusCore
import VieLotusTrace

final class VieLotusIMAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

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

        // Pre-warm NaturalLanguage recognizer & bilingual lookup tables off the main thread
        SmartBilingualDetector.warmUpModelsAsync()

        // Proactively release bilingual/NLP caches when macOS signals memory pressure
        let pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        pressureSource.setEventHandler {
            SmartBilingualDetector.purgeMemoryForLowMemoryWarning()
        }
        pressureSource.resume()
        memoryPressureSource = pressureSource
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("VieLotusIM (Sen Việt): InputMethodKit server terminating")
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
}

private func runVieLotusIMMain() -> Never {
    if CommandLine.arguments.contains("--status") || CommandLine.arguments.contains("--doctor") {
        let bundleID = Bundle.main.bundleIdentifier ?? InputSourceStatus.defaultBundleID
        let status = InputSourceDoctor.inspect(bundleID: bundleID)
        if CommandLine.arguments.contains("--json") {
            print(status.jsonReport())
        } else {
            print(status.humanReadableReport())
        }
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = VieLotusIMAppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
    exit(0)
}

runVieLotusIMMain()
