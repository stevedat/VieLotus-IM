import Foundation
import Darwin

public struct LabTraceEvent: Codable, Sendable {
    public let traceID: String
    public let event: String
    public let key: String
    public let raw: String
    public let composing: String
    public let detail: String
    public let time: String
    public let monotonic: UInt64

    public init(traceID: String, event: String, key: String, raw: String, composing: String,
                detail: String, time: String, monotonic: UInt64) {
        self.traceID = traceID
        self.event = event
        self.key = key
        self.raw = raw
        self.composing = composing
        self.detail = detail
        self.time = time
        self.monotonic = monotonic
    }
}

public enum LabTraceSpool {
    public struct ActiveSession: Codable {
        public let traceID: String
        public let targetBundleID: String
        public let startedAt: Date
    }

    private static var directory: URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("org.vielotus.inputmethod.lab-traces-\(getuid())", isDirectory: true)
    }

    private static var activeSessionURL: URL {
        directory.appendingPathComponent("active-session.json")
    }

    public static func cleanupStaleTraces(maxAge: TimeInterval = 3600) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        if let data = try? Data(contentsOf: activeSessionURL),
           let session = try? JSONDecoder().decode(ActiveSession.self, from: data) {
            if Date().timeIntervalSince(session.startedAt) >= 1800 {
                try? FileManager.default.removeItem(at: activeSessionURL)
            }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let now = Date()
        for file in files where file.pathExtension == "jsonl" {
            if let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = attributes.contentModificationDate,
               now.timeIntervalSince(modDate) > maxAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    public static func activate(traceID: String, targetBundleID: String) throws {
        cleanupStaleTraces()
        guard UUID(uuidString: traceID) != nil, !targetBundleID.isEmpty else {
            throw SpoolError.invalidTraceID
        }
        let session = ActiveSession(traceID: traceID, targetBundleID: targetBundleID.lowercased(),
                                    startedAt: Date())
        try JSONEncoder().encode(session).write(to: activeSessionURL, options: .atomic)
        chmod(activeSessionURL.path, 0o600)
    }

    public static func activeSession() -> ActiveSession? {
        guard let data = try? Data(contentsOf: activeSessionURL),
              let session = try? JSONDecoder().decode(ActiveSession.self, from: data),
              Date().timeIntervalSince(session.startedAt) < 1800 else { return nil }
        return session
    }

    public static func deactivate(traceID: String) {
        guard activeSession()?.traceID == traceID else { return }
        try? FileManager.default.removeItem(at: activeSessionURL)
    }

    private static func fileURL(for traceID: String) throws -> URL {
        guard let uuid = UUID(uuidString: traceID) else { throw SpoolError.invalidTraceID }
        return directory.appendingPathComponent("\(uuid.uuidString).jsonl")
    }

    public static func prepare(traceID: String) throws {
        cleanupStaleTraces()
        _ = try fileURL(for: traceID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
        let url = try fileURL(for: traceID)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(),
                                             attributes: [.posixPermissions: 0o600]) ||
                FileManager.default.fileExists(atPath: url.path) else {
            throw SpoolError.createFailed
        }
        chmod(url.path, 0o600)
    }

    public static func append(_ event: LabTraceEvent) throws {
        let url = try fileURL(for: event.traceID)
        let data = try JSONEncoder().encode(event) + Data([0x0A])
        let descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CLOEXEC)
        guard descriptor >= 0 else { throw SpoolError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SpoolError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }

        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), bytes.count - written)
                guard count > 0 else { throw SpoolError.writeFailed(errno) }
                written += count
            }
        }
    }

    public static func read(traceID: String, offset: inout UInt64) throws -> [LabTraceEvent] {
        let url = try fileURL(for: traceID)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw SpoolError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_SH) == 0 else { throw SpoolError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }
        guard lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else { throw SpoolError.seekFailed(errno) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            guard count >= 0 else { throw SpoolError.readFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        offset += UInt64(data.count)
        return data.split(separator: 0x0A).compactMap { try? JSONDecoder().decode(LabTraceEvent.self, from: Data($0)) }
    }

    public static func remove(traceID: String) {
        guard let url = try? fileURL(for: traceID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private enum SpoolError: Error {
        case invalidTraceID
        case createFailed
        case openFailed(Int32)
        case lockFailed(Int32)
        case writeFailed(Int32)
        case seekFailed(Int32)
        case readFailed(Int32)
    }
}
