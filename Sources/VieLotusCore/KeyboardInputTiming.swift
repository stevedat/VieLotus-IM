import Foundation

/// Diagnostic clocks only; contains no key or text payload. All timestamps use
/// the system-uptime timebase. Missing/future samples are reported as unavailable.
public struct KeyboardInputTiming {
    public enum Source: Int32 {
        case touchUpInside = 1, touchUpOutside, rollover, specialFlush, backspaceFlush, returnFlush
    }
    public let sequence: Int
    public let triggerTimestamp: TimeInterval?
    public let keyDownTimestamp: TimeInterval?
    public let handlerEnteredAt: TimeInterval?
    public let source: Source

    public static func milliseconds(since timestamp: TimeInterval?, now: TimeInterval) -> Double {
        guard let timestamp, timestamp.isFinite, now.isFinite, now >= timestamp else { return -1 }
        return (now - timestamp) * 1_000
    }
}

/// Owns original down samples independently for overlapping thumbs. A commit
/// consumes only that owner's sample and always takes its trigger event afresh.
public struct KeyboardInputTimingTracker<Owner: Hashable> {
    private var downSamples: [Owner: TimeInterval] = [:]
    private var sequence = 0
    public init() {}

    public mutating func touchDown(owner: Owner, timestamp: TimeInterval?) {
        downSamples[owner] = timestamp
    }

    public mutating func cancel(owner: Owner) { downSamples.removeValue(forKey: owner) }

    public mutating func commit(owner: Owner, triggerTimestamp: TimeInterval?,
                                handlerEnteredAt: TimeInterval?, source: KeyboardInputTiming.Source) -> KeyboardInputTiming {
        sequence += 1
        return KeyboardInputTiming(sequence: sequence, triggerTimestamp: triggerTimestamp,
                                   keyDownTimestamp: downSamples.removeValue(forKey: owner),
                                   handlerEnteredAt: handlerEnteredAt, source: source)
    }
}
