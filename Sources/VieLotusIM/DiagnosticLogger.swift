import Foundation
import os

final class DiagnosticLogger {
    static let shared = DiagnosticLogger()
    
    #if DEBUG
    private let logger = Logger(subsystem: "org.vielotus.inputmethod", category: "Engine")
    #endif

    private init() {
        // Zero-logging posture: Automatically remove legacy log file from older test versions
        if let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let legacyLog = libraryDir.appendingPathComponent("Logs/VieLotusIM.log")
            if FileManager.default.fileExists(atPath: legacyLog.path) {
                try? FileManager.default.removeItem(at: legacyLog)
            }
        }
    }
    
    func log(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }
}
