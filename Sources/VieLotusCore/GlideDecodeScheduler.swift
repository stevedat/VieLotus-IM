#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation

public struct GlideDecodeOutput: Sendable {
    public let geometric: [GlideCandidate]
    public let ranked: [GlideCandidate]
    public init(geometric: [GlideCandidate], ranked: [GlideCandidate]) {
        self.geometric = geometric
        self.ranked = ranked
    }
}

/// Owns one background decoder and publishes only the latest request on the main actor.
/// Document/caret validation remains the platform adapter's responsibility.
@MainActor
public final class GlideDecodeScheduler<Result: Sendable> {
    private var generation: UInt64 = 0
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.vielotus.glide"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    public init() {}

    public func invalidate() {
        generation &+= 1
        queue.cancelAllOperations()
    }

    public func prepare(_ work: @escaping @Sendable () -> Void) {
        queue.addOperation(work)
    }

    public func submit(work: @escaping @Sendable () -> Result,
                       completion: @escaping @MainActor (Result) -> Void) {
        invalidate()
        let ticket = generation
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let result = work()
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !operation.isCancelled, self.generation == ticket else { return }
                completion(result)
            }
        }
        queue.addOperation(operation)
    }
}
#endif
