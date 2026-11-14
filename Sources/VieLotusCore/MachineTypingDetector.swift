import Foundation

/// Detects synthetic high-speed keystroke bursts from AI computer-use agents
/// (`orca computer`, Claude Computer Use, Peekaboo), barcode scanners, and
/// external text-expansion tools, allowing the IME to bypass composition during
/// machine-driven input bursts so raw ASCII/code is not mutated into Vietnamese.
///
/// Human typing (even 220+ WPM rollover) rarely produces more than 1–2 consecutive
/// keystrokes under 12 ms. Requiring `requiredStreak` (default 6) consecutive
/// non-repeat keystrokes with BOTH hardware event timestamp delta AND process arrival
/// delta under `thresholdNs` (12 ms) reliably separates synthetic bursts from fast
/// human typing and OS main-thread wakeups.
public struct MachineTypingDetector: Sendable {
    public let thresholdNs: UInt64
    public let requiredStreak: Int

    private var lastEventNs: UInt64?
    private var lastArrivalNs: UInt64?
    private var fastCount: Int = 0
    public private(set) var inBurst: Bool = false

    public init(thresholdNs: UInt64 = 12_000_000, requiredStreak: Int = 6) {
        self.thresholdNs = thresholdNs
        self.requiredStreak = requiredStreak
    }

    /// Evaluates a key-down event's timestamps and returns `true` if the event
    /// is part of a synthetic machine-typing burst.
    public mutating func observe(
        eventTimestampSeconds: TimeInterval,
        arrivalNanoseconds: UInt64,
        isRepeat: Bool
    ) -> Bool {
        let eventNs = eventTimestampSeconds > 0
            ? UInt64(eventTimestampSeconds * 1_000_000_000)
            : 0

        // Holding down a physical key generates OS key-repeat events at a fixed cadence;
        // refresh clock baselines so timestamps do not go stale, and never treat repeat as a burst.
        if isRepeat {
            lastEventNs = eventNs > 0 ? eventNs : lastEventNs
            lastArrivalNs = arrivalNanoseconds > 0 ? arrivalNanoseconds : lastArrivalNs
            fastCount = 0
            inBurst = false
            return false
        }

        let eventDelta: UInt64 = {
            if let lastEventNs, eventNs >= lastEventNs {
                return eventNs - lastEventNs
            }
            return UInt64.max
        }()
        let arrivalDelta: UInt64 = {
            if let lastArrivalNs, arrivalNanoseconds >= lastArrivalNs {
                return arrivalNanoseconds - lastArrivalNs
            }
            return UInt64.max
        }()

        lastEventNs = eventNs > 0 ? eventNs : nil
        lastArrivalNs = arrivalNanoseconds > 0 ? arrivalNanoseconds : nil

        let hasValidClocks = eventNs > 0 && arrivalNanoseconds > 0
        if hasValidClocks && eventDelta < thresholdNs && arrivalDelta < thresholdNs {
            fastCount += 1
            if fastCount >= requiredStreak {
                inBurst = true
            }
        } else {
            fastCount = 0
            inBurst = false
        }

        return inBurst
    }

    public mutating func reset() {
        lastEventNs = nil
        lastArrivalNs = nil
        fastCount = 0
        inBurst = false
    }
}
