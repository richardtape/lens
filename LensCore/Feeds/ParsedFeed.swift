// ParsedFeed.swift — Intermediate value types produced by feed parsers.
//
// These types are pure Swift — no SwiftData, no SwiftUI. They live between
// the wire format (XML / JSON bytes) and the SwiftData store, allowing parsers
// to be unit-tested without any infrastructure.
import Foundation

// MARK: - ParsedFeed

/// The top-level result of parsing a feed document.
public struct ParsedFeed: Sendable {
    /// Feed title from the document (may be empty if the feed omits it).
    public var title: String
    /// All items found in the document, in document order (not sorted by date).
    public var items: [ParsedFeedItem]

    public init(title: String, items: [ParsedFeedItem] = []) {
        self.title = title
        self.items = items
    }
}

// MARK: - ParsedFeedItem

/// One item/entry from a parsed feed.
///
/// All fields map directly to `FeedItem` SwiftData properties (spec §7.1).
/// Afforded fields (`thumbnailURL`, `estimatedReadMinutes`, `enclosureURL`,
/// `enclosureMIMEType`) are populated at parse time per the spec's note
/// "populated at parse time" — they are stored but not displayed in v1 UI.
public struct ParsedFeedItem: Sendable {
    public var stableId: String        // guid / entry id / JSON Feed id
    public var title: String
    public var link: URL?
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var summaryHTML: String?
    public var contentHTML: String?
    public var thumbnailURL: URL?      // afforded: card view not active in v1
    public var estimatedReadMinutes: Int?  // afforded: not displayed in v1
    public var enclosureURL: URL?      // afforded: not active in v1
    public var enclosureMIMEType: String?  // afforded: not active in v1

    public init(stableId: String, title: String) {
        self.stableId = stableId
        self.title = title
    }
}

// MARK: - Shared helpers

extension ParsedFeedItem {
    /// Estimates reading time from HTML, or nil if the content is too short to bother.
    /// Strips HTML tags with a regex and counts whitespace-separated words at ~200 wpm.
    static func estimateReadMinutes(fromHTML html: String?) -> Int? {
        guard let html, !html.isEmpty else { return nil }
        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= 50 else { return nil }
        return max(1, wordCount / 200)
    }
}
