import Foundation
#if canImport(Darwin)
import Darwin
private func sys_open(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 { Darwin.open(path, oflag) }
private func sys_write(_ fd: Int32, _ buf: UnsafeRawPointer, _ nbyte: Int) -> Int { Darwin.write(fd, buf, nbyte) }
private func sys_read(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ nbyte: Int) -> Int { Darwin.read(fd, buf, nbyte) }
#elseif canImport(Glibc)
import Glibc
private func sys_open(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 { Glibc.open(path, oflag) }
private func sys_write(_ fd: Int32, _ buf: UnsafeRawPointer, _ nbyte: Int) -> Int { Glibc.write(fd, buf, nbyte) }
private func sys_read(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ nbyte: Int) -> Int { Glibc.read(fd, buf, nbyte) }
#endif

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

    /// Sensitive credential/password manager bundle identifiers that must never be observed or traced.
    public static let protectedBundleIDs: Set<String> = [
        "com.apple.passwords",
        "com.apple.keychainaccess",
        "com.apple.securityagent",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal",
        "com.dashlane.dashlane",
        "com.lastpass.lastpass",
        "me.proton.pass.catalyst",
        "ch.protonmail.pass",
        "in.sinew.enpass-desktop",
    ]

    public static let protectedBundleIDPrefixes: [String] = [
        "com.1password.",
        "com.agilebits.onepassword",
        "com.bitwarden.",
        "org.keepassxc.",
        "com.dashlane.",
        "com.lastpass.",
        "me.proton.pass",
    ]

    /// Returns `true` when the given bundle identifier belongs to a password manager or system credential prompt.
    public static func isProtectedBundleID(_ bundleID: String?) -> Bool {
        guard let normalized = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return false
        }
        if protectedBundleIDs.contains(normalized) {
            return true
        }
        return protectedBundleIDPrefixes.contains { normalized.hasPrefix($0) }
    }

    private static var directory: URL {
        #if canImport(Darwin)
        let basePath = "/private/tmp"
        return URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("org.vielotus.inputmethod.lab-traces-\(getuid())", isDirectory: true)
        #elseif canImport(Glibc)
        let basePath = "/tmp"
        return URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("org.vielotus.inputmethod.lab-traces-\(getuid())", isDirectory: true)
        #else
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("org.vielotus.inputmethod.lab-traces", isDirectory: true)
        #endif
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

    private static let activeSessionLock = NSLock()
    private static var cachedActiveSession: ActiveSession?
    private static var lastActiveSessionCheckNs: UInt64 = 0
    private static let activeSessionCacheTTLNs: UInt64 = 1_000_000_000 // 1 second

    public static func invalidateActiveSessionCache() {
        activeSessionLock.lock()
        cachedActiveSession = nil
        lastActiveSessionCheckNs = 0
        activeSessionLock.unlock()
    }

    public static func activate(traceID: String, targetBundleID: String) throws {
        cleanupStaleTraces()
        guard UUID(uuidString: traceID) != nil, !targetBundleID.isEmpty else {
            throw SpoolError.invalidTraceID
        }
        guard !isProtectedBundleID(targetBundleID) else {
            throw SpoolError.protectedTargetBundleID
        }
        let session = ActiveSession(traceID: traceID, targetBundleID: targetBundleID.lowercased(),
                                    startedAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: activeSessionURL, options: .atomic)
        #if canImport(Darwin) || canImport(Glibc)
        chmod(activeSessionURL.path, 0o600)
        #endif
        activeSessionLock.lock()
        cachedActiveSession = session
        lastActiveSessionCheckNs = DispatchTime.now().uptimeNanoseconds
        activeSessionLock.unlock()
    }

    public static func activeSession() -> ActiveSession? {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        activeSessionLock.lock()
        if lastActiveSessionCheckNs > 0 && nowNs >= lastActiveSessionCheckNs && (nowNs - lastActiveSessionCheckNs) < activeSessionCacheTTLNs {
            let cached = cachedActiveSession
            activeSessionLock.unlock()
            return cached
        }
        activeSessionLock.unlock()

        let loaded: ActiveSession?
        if let data = try? Data(contentsOf: activeSessionURL),
           let session = try? JSONDecoder().decode(ActiveSession.self, from: data),
           Date().timeIntervalSince(session.startedAt) < 1800 {
            loaded = session
        } else {
            loaded = nil
        }

        activeSessionLock.lock()
        cachedActiveSession = loaded
        lastActiveSessionCheckNs = nowNs
        activeSessionLock.unlock()
        return loaded
    }

    public static func deactivate(traceID: String) {
        invalidateActiveSessionCache()
        guard activeSession()?.traceID == traceID else { return }
        try? FileManager.default.removeItem(at: activeSessionURL)
        activeSessionLock.lock()
        cachedActiveSession = nil
        lastActiveSessionCheckNs = DispatchTime.now().uptimeNanoseconds
        activeSessionLock.unlock()
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
        #if canImport(Darwin) || canImport(Glibc)
        chmod(directory.path, 0o700)
        #endif
        let url = try fileURL(for: traceID)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(),
                                             attributes: [.posixPermissions: 0o600]) ||
                FileManager.default.fileExists(atPath: url.path) else {
            throw SpoolError.createFailed
        }
        #if canImport(Darwin) || canImport(Glibc)
        chmod(url.path, 0o600)
        #endif
    }

    public static func append(_ event: LabTraceEvent) throws {
        let url = try fileURL(for: event.traceID)
        let data = try JSONEncoder().encode(event) + Data([0x0A])
        #if canImport(Darwin) || canImport(Glibc)
        let descriptor = sys_open(url.path, O_WRONLY | O_APPEND | O_CLOEXEC)
        guard descriptor >= 0 else { throw SpoolError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SpoolError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }

        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = sys_write(descriptor, base.advanced(by: written), bytes.count - written)
                guard count > 0 else { throw SpoolError.writeFailed(errno) }
                written += count
            }
        }
        #else
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        #endif
    }

    public static func read(traceID: String, offset: inout UInt64) throws -> [LabTraceEvent] {
        let url = try fileURL(for: traceID)
        #if canImport(Darwin) || canImport(Glibc)
        let descriptor = sys_open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw SpoolError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_SH) == 0 else { throw SpoolError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }
        guard lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else { throw SpoolError.seekFailed(errno) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                sys_read(descriptor, bytes.baseAddress!, bytes.count)
            }
            guard count >= 0 else { throw SpoolError.readFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        offset += UInt64(data.count)
        return data.split(separator: 0x0A).compactMap { try? JSONDecoder().decode(LabTraceEvent.self, from: Data($0)) }
        #else
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(data.count)
        return data.split(separator: 0x0A).compactMap { try? JSONDecoder().decode(LabTraceEvent.self, from: Data($0)) }
        #endif
    }

    public static func remove(traceID: String) {
        guard let url = try? fileURL(for: traceID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private enum SpoolError: Error {
        case invalidTraceID
        case protectedTargetBundleID
        case createFailed
        case openFailed(Int32)
        case lockFailed(Int32)
        case writeFailed(Int32)
        case seekFailed(Int32)
        case readFailed(Int32)
    }
}
