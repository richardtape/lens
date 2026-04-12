// LensUITests/TimelineFilterTests.swift
// Pending human completing Task 2 (creating the LensUITests Xcode target before tests run).
import Testing
import Foundation
import SwiftData
@testable import LensUI
@testable import LensCore

struct TimelineFilterTests {

    // A minimal in-memory ModelContainer for exercising fetch descriptors.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: FeedItem.self, Feed.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func allUnfiltered_producesNoPredicate() throws {
        let descriptor = TimelineFilter.fetchDescriptor(filter: .all, unreadOnly: false)
        // A nil predicate means "fetch all" — no filtering applied.
        #expect(descriptor.predicate == nil)
    }

    @Test func allUnreadOnly_producesPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let readItem = FeedItem(feedId: UUID(), stableId: "r", title: "Read")
        readItem.isRead = true
        let unreadItem = FeedItem(feedId: UUID(), stableId: "u", title: "Unread")
        context.insert(readItem)
        context.insert(unreadItem)
        try context.save()

        let descriptor = TimelineFilter.fetchDescriptor(filter: .all, unreadOnly: true)
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].stableId == "u")
    }

    @Test func feedFilter_returnsOnlyMatchingFeed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let targetId = UUID()
        let other = UUID()
        let a = FeedItem(feedId: targetId, stableId: "a", title: "A")
        let b = FeedItem(feedId: other, stableId: "b", title: "B")
        context.insert(a); context.insert(b)
        try context.save()

        let descriptor = TimelineFilter.fetchDescriptor(filter: .feed(targetId), unreadOnly: false)
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].feedId == targetId)
    }

    @Test func feedFilterUnread_appliesBothConditions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let feedId = UUID()
        let read = FeedItem(feedId: feedId, stableId: "r", title: "R"); read.isRead = true
        let unread = FeedItem(feedId: feedId, stableId: "u", title: "U")
        context.insert(read); context.insert(unread)
        try context.save()

        let descriptor = TimelineFilter.fetchDescriptor(filter: .feed(feedId), unreadOnly: true)
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].isRead == false)
    }

    @Test func categoryFilter_noPredicate_fetchesAll() throws {
        // Category filter is resolved in-memory (FeedItem has no categoryId).
        // The fetch descriptor for .category returns all items (optionally unread-filtered),
        // and the caller does the feed-ID membership check in Swift.
        let descriptor = TimelineFilter.fetchDescriptor(filter: .category(UUID()), unreadOnly: false)
        #expect(descriptor.predicate == nil)
    }
}
