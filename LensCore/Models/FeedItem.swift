// FeedItem.swift — SwiftData entity for a single article/entry from a feed.
//
// Fields marked "afforded: active in vN" must be stored from day one but
// must not be read, written, or surfaced in UI until the stated version.
import SwiftData
import Foundation

/// The download / save-for-offline status of a feed item.
public enum SavedState: String, Codable, Sendable {
    case notSaved
    case saving
    case saved
    case error
}

@Model
public final class FeedItem {
    public var id: UUID
    /// UUID of the parent Feed. Plain FK — not a SwiftData relationship.
    public var feedId: UUID
    /// GUID from the feed, or a content hash if absent.
    /// Used for deduplication (Phase 4.7) and stable references.
    public var stableId: String
    public var title: String
    public var link: URL?
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var summaryHTML: String?
    public var contentHTML: String?
    public var isRead: Bool
    public var isStarred: Bool
    public var savedOfflineState: SavedState
    /// Escape hatch for feed-format-specific metadata not modelled above.
    public var rawMetadata: Data?
    // afforded: card view not active in v1
    public var thumbnailURL: URL?
    // afforded: not displayed in v1
    public var estimatedReadMinutes: Int?
    // afforded: not active in v1
    public var enclosureURL: URL?
    // afforded: not active in v1
    public var enclosureMIMEType: String?

    public init(
        id: UUID = UUID(),
        feedId: UUID,
        stableId: String,
        title: String,
        link: URL? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        summaryHTML: String? = nil,
        contentHTML: String? = nil
    ) {
        self.id = id
        self.feedId = feedId
        self.stableId = stableId
        self.title = title
        self.link = link
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.summaryHTML = summaryHTML
        self.contentHTML = contentHTML
        self.isRead = false
        self.isStarred = false
        self.savedOfflineState = .notSaved
        self.rawMetadata = nil
        self.thumbnailURL = nil       // afforded: card view not active in v1
        self.estimatedReadMinutes = nil // afforded: not displayed in v1
        self.enclosureURL = nil        // afforded: not active in v1
        self.enclosureMIMEType = nil   // afforded: not active in v1
    }
}
