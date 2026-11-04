import Foundation
import os

/// DEBUG-only metadata logger for `VieLotusIM`.
/// Never accepts or emits typed characters, keycodes, raw buffers, or composed text —
/// logs only compile-time event codes, lengths, presentation state, and range offsets.
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()
    
    #if DEBUG
    private let logger = Logger(subsystem: "org.vielotus.inputmethod", category: "Engine")
    #endif

    private init() {}

    /// One-time startup cleanup of legacy log files from older test versions (never called on the keystroke path).
    func cleanupLegacyLogFile() {
        if let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let legacyLog = libraryDir.appendingPathComponent("Logs/VieLotusIM.log")
            if FileManager.default.fileExists(atPath: legacyLog.path) {
                try? FileManager.default.removeItem(at: legacyLog)
            }
        }
    }

    @inline(__always)
    func logEvent(_ event: StaticString, app: @autoclosure () -> String? = nil, detail: @autoclosure () -> String = "") {
        #if DEBUG
        let appTag = app() ?? "?"
        let meta = detail()
        if meta.isEmpty {
            logger.debug("\(event, privacy: .public) | app: \(appTag, privacy: .private)")
        } else {
            logger.debug("\(event, privacy: .public) | app: \(appTag, privacy: .private) | \(meta, privacy: .private)")
        }
        #endif
    }
}
