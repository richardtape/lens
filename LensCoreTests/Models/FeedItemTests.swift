// FeedItemTests.swift — unit tests for FeedItem and SavedState.
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("FeedItem model")
struct FeedItemTests {

    @Test("default values are correct")
    func defaultValues() {
        let item = FeedItem(feedId: UUID(), stableId: "abc123", title: "Test Article")

        #expect(item.isRead == false)
        #expect(item.isStarred == false)
        #expect(item.savedOfflineState == .notSaved)
        #expect(item.contentHTML == nil)
        #expect(item.summaryHTML == nil)
        // Verify afforded fields are nil — do not activate them
        #expect(item.thumbnailURL == nil)
        #expect(item.estimatedReadMinutes == nil)
        #expect(item.enclosureURL == nil)
        #expect(item.enclosureMIMEType == nil)
    }

    @Test("inserts and fetches via in-memory container")
    func persistAndFetch() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        let feedId = UUID()
        let item = FeedItem(feedId: feedId, stableId: "s1", title: "Hello SwiftData")
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FeedItem>())
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Hello SwiftData")
        #expect(fetched[0].feedId == feedId)
    }

    @Test("SavedState round-trips through Codable")
    func savedStateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in [SavedState.notSaved, .saving, .saved, .error] {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(SavedState.self, from: data)
            #expect(decoded == state)
        }
    }
}
