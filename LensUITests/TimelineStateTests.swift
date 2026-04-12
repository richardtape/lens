// LensUITests/TimelineStateTests.swift
// Pending human completing Task 2 (creating the LensUITests Xcode target before tests run).
import Testing
@testable import LensUI
import LensCore

// TimelineState uses @MainActor. Swift Testing supports async tests via
// async @Test functions; use MainActor.run to drive state changes.
struct TimelineStateTests {

    @Test func bannerSet_whenBackgroundRefreshCompletesWithNewItems() async {
        let bus = EventBus()
        let state = await TimelineState(eventBus: bus)

        // Emit the event that should trigger the banner.
        await bus.emit(.backgroundRefreshCompleted(newItemCount: 5))

        // Give the subscriber task a moment to process the event.
        try? await Task.sleep(for: .milliseconds(50))

        let banner = await MainActor.run { state.newItemsBanner }
        #expect(banner?.count == 5)
    }

    @Test func bannerNotSet_whenNewItemCountIsZero() async {
        let bus = EventBus()
        let state = await TimelineState(eventBus: bus)

        await bus.emit(.backgroundRefreshCompleted(newItemCount: 0))
        try? await Task.sleep(for: .milliseconds(50))

        let banner = await MainActor.run { state.newItemsBanner }
        #expect(banner == nil)
    }

    @Test func bannerNotSet_whenFilterModeIsNotAll() async {
        let bus = EventBus()
        let state = await TimelineState(eventBus: bus)
        await MainActor.run { state.filterMode = .feed(UUID()) }

        await bus.emit(.backgroundRefreshCompleted(newItemCount: 3))
        try? await Task.sleep(for: .milliseconds(50))

        let banner = await MainActor.run { state.newItemsBanner }
        #expect(banner == nil)
    }
}
