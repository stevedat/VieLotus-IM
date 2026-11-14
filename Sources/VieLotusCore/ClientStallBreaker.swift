import Foundation
import Dispatch
#if canImport(os.lock)
import os.lock
#endif

/// `ClientStallBreaker` detects when an external host application (e.g. Chrome, VS Code, Excel)
/// stalls or deadlocks during synchronous InputMethodKit IPC calls.
///
/// If a client application takes longer than `stallThresholdMs` (default 150ms) to respond,
/// or if an operation times out, the breaker marks that application's `bundleIdentifier`
/// as *degraded* for `degradationDurationSec` (default 5.0s).
///
/// While degraded, `VieLotusIMController` immediately passes through raw keystrokes
/// without blocking on synchronous IPC, preventing the entire macOS IME subsystem from hanging.
public final class ClientStallBreaker: @unchecked Sendable {
    public static let shared = ClientStallBreaker()

    #if canImport(os.lock)
    private var lock = os_unfair_lock()
    #else
    private let lock = NSLock()
    #endif
    private var degradedClients: [String: UInt64] = [:]
    private var inFlightOperations: [String: (token: UInt64, startNanos: UInt64)] = [:]
    private var nextOperationToken: UInt64 = 0

    /// Fast-path boolean to skip dictionary lookups when no apps are degraded or in-flight.
    public private(set) var anyDegraded: Bool = false
    private var anyInFlight: Bool = false

    /// Latency threshold in milliseconds before a client is flagged as stalled.
    public var stallThresholdMs: Double = 150.0

    /// Duration in seconds to keep a stalled client in degraded (pass-through) mode.
    public var degradationDurationSec: Double = 5.0

    public init() {}

    @inline(__always)
    private func withLock<T>(_ block: () -> T) -> T {
        #if canImport(os.lock)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return block()
        #else
        lock.lock()
        defer { lock.unlock() }
        return block()
        #endif
    }

    /// Checks if a client bundle is currently in a degraded pass-through state,
    /// or if an in-flight synchronous IPC call for that bundle has exceeded `stallThresholdMs`.
    public func isDegraded(bundleIdentifier: String?) -> Bool {
        guard (anyDegraded || anyInFlight), let bundleID = bundleIdentifier, !bundleID.isEmpty else {
            return false
        }

        return withLock {
            let now = DispatchTime.now().uptimeNanoseconds

            if let inFlight = inFlightOperations[bundleID], now >= inFlight.startNanos {
                let elapsedMs = Double(now - inFlight.startNanos) / 1_000_000.0
                if elapsedMs > stallThresholdMs {
                    let expireNanos = now + UInt64(degradationDurationSec * 1_000_000_000)
                    degradedClients[bundleID] = expireNanos
                    anyDegraded = true
                    return true
                }
            }

            guard let expireTime = degradedClients[bundleID] else {
                return false
            }

            if now < expireTime {
                return true
            }

            // Expired — restore client
            degradedClients.removeValue(forKey: bundleID)
            anyDegraded = !degradedClients.isEmpty
            return false
        }
    }

    /// Explicitly marks a client application as degraded.
    public func markDegraded(bundleIdentifier: String, durationSec: Double? = nil) {
        guard !bundleIdentifier.isEmpty else { return }

        let duration = durationSec ?? degradationDurationSec
        let expireNanos = DispatchTime.now().uptimeNanoseconds + UInt64(duration * 1_000_000_000)

        withLock {
            degradedClients[bundleIdentifier] = expireNanos
            anyDegraded = true
        }
    }

    /// Clears degradation for a specific bundle, or all bundles if nil.
    public func clear(bundleIdentifier: String? = nil) {
        withLock {
            if let bundleID = bundleIdentifier {
                degradedClients.removeValue(forKey: bundleID)
                inFlightOperations.removeValue(forKey: bundleID)
            } else {
                degradedClients.removeAll(keepingCapacity: true)
                inFlightOperations.removeAll(keepingCapacity: true)
            }
            anyDegraded = !degradedClients.isEmpty
            anyInFlight = !inFlightOperations.isEmpty
        }
    }

    /// Records the latency of a completed client IPC call and triggers degradation if it exceeded the threshold.
    public func recordLatency(bundleIdentifier: String?, operation: String, durationMs: Double) {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty else { return }
        if durationMs > stallThresholdMs {
            markDegraded(bundleIdentifier: bundleID)
        }
    }

    /// Measures an execution block with an in-flight tracker and watchdog latency check,
    /// flagging degradation if the synchronous IPC call stalls.
    public func executeWithWatchdog<T>(bundleIdentifier: String?, operation: String, block: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        var token: UInt64 = 0
        if let bundleID = bundleIdentifier, !bundleID.isEmpty {
            withLock {
                nextOperationToken &+= 1
                token = nextOperationToken
                inFlightOperations[bundleID] = (token: token, startNanos: start)
                anyInFlight = true
            }
        }
        defer {
            let end = DispatchTime.now().uptimeNanoseconds
            let elapsedMs = end >= start ? Double(end - start) / 1_000_000.0 : 0.0
            if let bundleID = bundleIdentifier, !bundleID.isEmpty {
                withLock {
                    if inFlightOperations[bundleID]?.token == token {
                        inFlightOperations.removeValue(forKey: bundleID)
                        anyInFlight = !inFlightOperations.isEmpty
                    }
                    if elapsedMs > stallThresholdMs {
                        let expireNanos = end + UInt64(degradationDurationSec * 1_000_000_000)
                        degradedClients[bundleID] = expireNanos
                        anyDegraded = true
                    }
                }
            }
        }
        return try block()
    }
}
