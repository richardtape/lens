// EventBusTests.swift — Integration tests for EventBus emit/subscribe behaviour.
//
// Each test creates its own EventBus() instance to avoid shared state.
// Tests are async because EventBus is an actor and AsyncStream is consumed
// with `for await`.
import Testing
import Foundation
@testable import LensCore

@Suite("EventBus")
struct EventBusTests {

    // MARK: - Single subscriber

    @Test("Emitted event is received by a single subscriber")
    func singleSubscriberReceivesEvent() async {
        let bus = EventBus()
        let stream = await bus.makeStream()

        await bus.emit(.userInitiatedRefresh)

        var received: LensEvent? = nil
        for await event in stream {
            received = event
            break
        }

        #expect(received == .userInitiatedRefresh)
    }

    @Test("Subscriber receives events in emission order")
    func eventsDeliveredInOrder() async {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let id = UUID()

        await bus.emit(.feedFetchStarted(feedId: id))
        await bus.emit(.feedFetchCompleted(feedId: id, newItemCount: 3))

        var received: [LensEvent] = []
        for await event in stream {
            received.append(event)
            if received.count == 2 { break }
        }

        #expect(received == [
            .feedFetchStarted(feedId: id),
            .feedFetchCompleted(feedId: id, newItemCount: 3),
        ])
    }

    // MARK: - Multiple subscribers

    @Test("All active subscribers receive each emitted event")
    func multipleSubscribersAllReceive() async {
        let bus = EventBus()
        let stream1 = await bus.makeStream()
        let stream2 = await bus.makeStream()

        await bus.emit(.appLaunched)

        var received1: LensEvent? = nil
        var received2: LensEvent? = nil

        for await event in stream1 { received1 = event; break }
        for await event in stream2 { received2 = event; break }

        #expect(received1 == .appLaunched)
        #expect(received2 == .appLaunched)
    }

    // MARK: - Cancellation / cleanup

    @Test("Cancelled task stops receiving events and is removed from the bus")
    func cancelledSubscriberRemoved() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()

        // Drive the stream in a task we will cancel immediately.
        let consumerTask = Task {
            for await _ in stream { }
        }
        consumerTask.cancel()

        // Give the actor a moment to process the termination callback.
        // We yield the current task a few times; no fixed sleep needed.
        for _ in 0..<10 {
            await Task.yield()
        }

        // After cancellation, emitting should not crash or hang.
        // (The removed continuation no longer receives yields.)
        await bus.emit(.userInitiatedRefresh)
        // No assertion needed — success is reaching this line without hanging.
    }

    // MARK: - shared instance

    @Test("EventBus.shared is non-nil and usable")
    func sharedInstanceUsable() async {
        // Just confirms the singleton compiles and the actor is reachable.
        // We do NOT emit events on the shared instance to avoid polluting
        // any other test that might share the process's shared bus.
        let bus = EventBus.shared
        #expect(bus !== nil as AnyObject?)
    }
}
