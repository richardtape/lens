// FeedTests.swift — unit tests for the Feed SwiftData model.
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("Feed model")
struct FeedTests {

    @Test("default values are correct")
    func defaultValues() {
        let feed = Feed(url: URL(string: "https://example.com/feed.xml")!,
                        displayName: "Example")

        #expect(feed.consecutiveFailureCount == 0)
        #expect(feed.lastFetchedAt == nil)
        #expect(feed.lastFetchError == nil)
        #expect(feed.categoryId == nil)
        #expect(feed.iconRef == nil)
        #expect(feed.refreshInterval == nil) // afforded field: nil by default
    }

    @Test("inserts and fetches via in-memory SwiftData container")
    func persistAndFetch() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        // Use ModelContext(container) rather than container.mainContext:
        // mainContext is @MainActor-bound; ModelContext(container) is actor-agnostic
        // and safe to use from unspecified Swift Testing isolation contexts.
        let context = ModelContext(container)

        let url = URL(string: "https://example.com/feed.xml")!
        context.insert(Feed(url: url, displayName: "Example Feed"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Feed>())
        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Example Feed")
        #expect(fetched[0].url == url)
    }

    @Test("inserting duplicate URL upserts — single record remains")
    func duplicateURLUpserts() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        let url = URL(string: "https://example.com/feed.xml")!

        context.insert(Feed(url: url, displayName: "First"))
        try context.save()

        // SwiftData @Attribute(.unique) triggers an upsert, not an error.
        // The second insert merges with the existing record.
        context.insert(Feed(url: url, displayName: "Duplicate"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Feed>())
        #expect(fetched.count == 1)
    }
}
