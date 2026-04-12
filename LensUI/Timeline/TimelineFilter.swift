// TimelineFilter.swift — Filter state enum and SwiftData query builder.
//
// Note on category filtering: FeedItem stores feedId (not categoryId) per the
// data model, so category membership requires a join through Feed. SwiftData
// #Predicate cannot express cross-entity joins. The .category case therefore
// fetches all items (with optional unread filter) and defers the membership
// check to the caller's in-memory pass (see TimelineContentView.displayedItems).
import Foundation
import SwiftData
import LensCore

// MARK: - TimelineFilter

/// Describes which subset of FeedItems the timeline should show.
public enum TimelineFilter: Equatable {
    case all
    case category(UUID)
    case feed(UUID)
}

// MARK: - FetchDescriptor builder

extension TimelineFilter {

    /// Returns a `FetchDescriptor<FeedItem>` matching the given filter and read state.
    ///
    /// Sort: `publishedAt` descending. Items with nil `publishedAt` may appear
    /// at the top in SQLite's default NULL ordering (NULLS FIRST for DESC). A
    /// full NULLS LAST sort requires a post-fetch pass; deferred to Phase 4.
    ///
    /// The `.category` case cannot be expressed as a SwiftData predicate —
    /// callers must apply the feed-ID membership check in Swift after fetching.
    static func fetchDescriptor(
        filter: TimelineFilter,
        unreadOnly: Bool
    ) -> FetchDescriptor<FeedItem> {
        let sort: [SortDescriptor<FeedItem>] = [
            SortDescriptor(\.publishedAt, order: .reverse)
        ]
        switch (filter, unreadOnly) {
        case (.all, false), (.category, false):
            return FetchDescriptor<FeedItem>(sortBy: sort)

        case (.all, true), (.category, true):
            return FetchDescriptor<FeedItem>(
                predicate: #Predicate<FeedItem> { $0.isRead == false },
                sortBy: sort
            )

        case (.feed(let id), false):
            return FetchDescriptor<FeedItem>(
                predicate: #Predicate<FeedItem> { $0.feedId == id },
                sortBy: sort
            )

        case (.feed(let id), true):
            return FetchDescriptor<FeedItem>(
                predicate: #Predicate<FeedItem> { $0.feedId == id && $0.isRead == false },
                sortBy: sort
            )
        }
    }
}
