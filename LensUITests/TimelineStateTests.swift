// LensUITests/TimelineStateTests.swift
import Testing
import Foundation
@testable import LensUI
import LensCore

// TimelineState uses @MainActor. Swift Testing supports async tests via
// async @Test functions; use MainActor.run to drive state changes.
//
// Timing note: TimelineState.init enqueues a Task to call EventBus.makeStream().
// That Task must run and cross the actor boundary before we emit — otherwise the
// stream isn't registered yet and the event is dropped. A short sleep before
// emitting ensures the subscription is established first.
struct TimelineStateTests {

    @Test func bannerSet_whenBackgroundRefreshCompletesWithNewItems() async {
        let bus = EventBus()
        let state = await TimelineState(eventBus: bus)

        // Let the subscription Task start and register its stream before emitting.
        try? await Task.sleep(for: .milliseconds(50))

        await bus.emit(.backgroundRefreshCompleted(newItemCount: 5))

        // Give the subscriber task a moment to process the event.
        try? await Task.sleep(for: .milliseconds(50))

        let banner = await MainActor.run { state.newItemsBanner }
        #expect(banner?.count == 5)
    }

    @Test func bannerNotSet_whenNewItemCountIsZero() async {
        let bus = EventBus()
        let state = await TimelineState(eventBus: bus)

        try? await Task.sleep(for: .milliseconds(50))

        await bus.emit(.backgroundRefreshCompleted(newItemCount: 0))
        try? await Task.sleep(for: .milliseconds(50))

        let banner = await MainActor.run { state.newItemsBanner }
        #expect(banner == nil)
    }

    @Test func bannerNotSet_whenFilterModeIsNotAll() async {
        let bus = EventBus()
        let state = await TimelineState(eventBus: bus)

        try? await Task.sleep(for: .milliseconds(50))

        await MainActor.run { state.filterMode = .feed(UUID()) }

        await bus.emit(.backgroundRefreshCompleted(newItemCount: 3))
        try? await Task.sleep(for: .milliseconds(50))

        let banner = await MainActor.run { state.newItemsBanner }
        #expect(banner == nil)
    }
}
