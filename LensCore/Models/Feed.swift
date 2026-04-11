// Feed.swift — SwiftData entity representing a subscribed RSS/Atom/JSON feed.
//
// categoryId uses a plain UUID foreign key (not a SwiftData relationship) per
// the product spec's data model. This keeps cross-entity queries simple and
// avoids cascade-delete complexity in Phase 2A.
import SwiftData
import Foundation

@Model
public final class Feed {
    // @Attribute(.unique) prevents inserting the same feed URL twice.
    // SwiftData throws if a duplicate is attempted — the caller must handle this.
    @Attribute(.unique) public var url: URL
    public var id: UUID
    public var displayName: String
    public var categoryId: UUID?
    public var iconRef: String?
    public var createdAt: Date
    public var lastFetchedAt: Date?
    public var lastFetchError: String?
    public var consecutiveFailureCount: Int
    // afforded: active in v2 — per-feed refresh override
    public var refreshInterval: TimeInterval?

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        categoryId: UUID? = nil,
        iconRef: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.categoryId = categoryId
        self.iconRef = iconRef
        self.createdAt = createdAt
        self.lastFetchedAt = nil
        self.lastFetchError = nil
        self.consecutiveFailureCount = 0
        self.refreshInterval = nil // afforded: active in v2
    }
}
