// EventBus.swift — Central event dispatch for LensCore.
//
// EventBus is a Swift actor, so `emit(_:)` is safe to call from any
// concurrency context (main actor, background tasks, other actors).
//
// Subscription model: callers call `makeStream()` to get an
// AsyncStream<LensEvent>. Each call returns a fresh, independent stream
// that buffers events without bound (policy: .unbounded) until the
// consuming Task reads them. The caller owns the Task driving iteration
// and must cancel it (or let it go out of scope) when the observer is
// done — this automatically terminates the stream and removes it from
// the bus.
//
// Why AsyncStream: it integrates cleanly with structured concurrency
// (for-await loops, task cancellation) and requires no additional
// dependencies. The unbounded buffer ensures that brief bursts of events
// (e.g. bulk item inserts) are not dropped.
import Foundation

public actor EventBus {

    // MARK: - Shared instance

    /// App-wide shared bus. Inject a fresh `EventBus()` in unit tests
    /// to keep test runs isolated from each other.
    public static let shared = EventBus()

    // MARK: - Private state

    /// Keyed by a per-subscriber UUID so each stream can be individually removed
    /// without the caller needing to hold a reference to the continuation itself.
    private var continuations: [UUID: AsyncStream<LensEvent>.Continuation] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Subscribe

    /// Returns an `AsyncStream` that delivers every event emitted to this bus
    /// until the consuming Task is cancelled or the continuation is terminated.
    ///
    /// Typical usage in a view model or app-layer coordinator:
    /// ```swift
    /// let task = Task {
    ///     for await event in await EventBus.shared.makeStream() {
    ///         handle(event)
    ///     }
    /// }
    /// // Later, when the observer is done:
    /// task.cancel()
    /// ```
    public func makeStream() -> AsyncStream<LensEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LensEvent>.makeStream()
        continuations[id] = continuation
        // onTermination fires when the consuming Task is cancelled or the
        // continuation is explicitly finished. Dispatch removal back onto the
        // actor to keep `continuations` mutation actor-isolated.
        continuation.onTermination = { [id] _ in
            Task { [weak self] in
                await self?.removeContinuation(id: id)
            }
        }
        return stream
    }

    // MARK: - Publish

    /// Broadcast `event` to every active subscriber.
    ///
    /// Safe to call from any concurrency context; actor isolation serialises
    /// the yield calls so subscribers always see events in emission order.
    public func emit(_ event: LensEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    // MARK: - Private

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
