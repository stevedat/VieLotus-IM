import Foundation
import Dispatch
#if os(macOS)
import Cocoa
#endif

/// State snapshot of macOS system-wide Secure Event Input.
public struct SecureInputState: Equatable, Sendable {
    public let isActive: Bool
    public let holderPID: Int32?
    public let holderName: String?
    public let holderBundleID: String?

    public init(
        isActive: Bool,
        holderPID: Int32? = nil,
        holderName: String? = nil,
        holderBundleID: String? = nil
    ) {
        self.isActive = isActive
        self.holderPID = holderPID
        self.holderName = holderName
        self.holderBundleID = holderBundleID
    }

    public static let inactive = SecureInputState(isActive: false)
}

/// Provider protocol for querying system Secure Event Input.
public protocol SecureInputProvider: Sendable {
    func queryState() -> SecureInputState
}

/// Default system provider for macOS.
public final class SystemSecureInputProvider: SecureInputProvider, @unchecked Sendable {
    public init() {}

    public func queryState() -> SecureInputState {
        #if os(macOS)
        // 1. Check HIToolbox IsSecureEventInputEnabled dynamically to maintain Core platform agnosticism
        typealias IsSecureEventInputEnabledFunc = @convention(c) () -> DarwinBoolean
        var isEnabled = false

        if let handle = dlopen(nil, RTLD_NOW) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "IsSecureEventInputEnabled") {
                let fn = unsafeBitCast(sym, to: IsSecureEventInputEnabledFunc.self)
                isEnabled = fn().boolValue
            }
        }

        guard isEnabled else {
            return .inactive
        }

        // 2. Discover holder PID via CGSessionCopyCurrentDictionary
        var holderPID: pid_t? = nil
        var holderName: String? = nil
        var holderBundleID: String? = nil

        if let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any],
           let pidNum = sessionDict["kCGSSessionSecureInputPID"] as? NSNumber {
            let pid = pidNum.int32Value
            if pid > 0 {
                holderPID = pid
                if let app = NSRunningApplication(processIdentifier: pid) {
                    holderName = app.localizedName
                    holderBundleID = app.bundleIdentifier
                }
            }
        }

        return SecureInputState(
            isActive: true,
            holderPID: holderPID,
            holderName: holderName,
            holderBundleID: holderBundleID
        )
        #else
        return .inactive
        #endif
    }
}

/// `SecureInputMonitor` monitors system-wide password fields and secure sessions (e.g. Keychain, 1Password, sudo).
///
/// When Secure Event Input is active:
/// 1. Keyboard events are blocked from IME synthesis.
/// 2. `VieLotusIMController` immediately enters raw pass-through to avoid corrupted buffers or delays.
/// 3. When Secure Input is released, the monitor detects the transition and resumes composition cleanly.
public final class SecureInputMonitor: @unchecked Sendable {
    public static let shared = SecureInputMonitor()

    public var provider: SecureInputProvider

    private var lastState: SecureInputState = .inactive
    private var lastQueryNanos: UInt64 = 0
    private let queryThrottleNanos: UInt64 = 30_000_000 // 30ms throttle for rapid keystroke loops

    public init(provider: SecureInputProvider = SystemSecureInputProvider()) {
        self.provider = provider
    }

    /// Fast-checked property indicating whether Secure Input is active.
    public var isSecureInputActive: Bool {
        currentState.isActive
    }

    /// Queries the current snapshot with a microsecond-level throttle.
    public var currentState: SecureInputState {
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastQueryNanos < queryThrottleNanos {
            return lastState
        }
        lastQueryNanos = now
        lastState = provider.queryState()
        return lastState
    }

    /// Forces an immediate unthrottled refresh.
    @discardableResult
    public func refresh() -> SecureInputState {
        lastQueryNanos = DispatchTime.now().uptimeNanoseconds
        lastState = provider.queryState()
        return lastState
    }
}
