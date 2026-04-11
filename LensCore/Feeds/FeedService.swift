// FeedService.swift — Orchestrates fetch → parse → persist → emit for a single feed.
//
// Called by: app targets (LensIOS/LensMac) when the user triggers a refresh
// (pull-to-refresh, `r` key) or when a background task fires (Phase 5).
//
// Concurrency notes:
//   • FeedService is an actor; `fetchFeed(feedId:)` is safe to call concurrently
//     for multiple feeds.
//   • Each call creates a fresh ModelContext from the shared ModelContainer.
//     ModelContext is NOT Sendable — we never pass it across the actor boundary.
//   • URLSession.shared is used for simplicity; Phase 5 may introduce a
//     custom session with background download support.
import Foundation
import SwiftData

public actor FeedService {

    // MARK: - Dependencies

    private let container: ModelContainer
    private let eventBus: EventBus
    private let feedFactory: FeedFactory

    // MARK: - Init

    public init(
        container: ModelContainer,
        eventBus: EventBus = .shared,
        feedFactory: FeedFactory = .shared
    ) {
        self.container = container
        self.eventBus = eventBus
        self.feedFactory = feedFactory
    }

    // MARK: - Public API

    /// Fetch and refresh a single feed identified by its UUID.
    ///
    /// Emits:
    ///   1. `feedFetchStarted(feedId:)`
    ///   2. `feedFetchCompleted(feedId:newItemCount:)` on success, or
    ///      `feedFetchFailed(feedId:error:)` on failure.
    ///   3. `feedHealthChanged(feedId:status:)` reflecting the updated health.
    ///
    /// Never throws — errors are surfaced via emitted events so callers do not
    /// need to handle them at the call site.
    public func fetchFeed(feedId: UUID) async {
        await eventBus.emit(.feedFetchStarted(feedId: feedId))

        do {
            let newItemCount = try await performFetch(feedId: feedId)
            await eventBus.emit(.feedFetchCompleted(feedId: feedId, newItemCount: newItemCount))
            await eventBus.emit(.feedHealthChanged(feedId: feedId, status: .healthy))
        } catch {
            let message = error.localizedDescription
            await eventBus.emit(.feedFetchFailed(feedId: feedId, error: message))
            // Record the failure and read back the resulting health status.
            let status = await recordFailure(feedId: feedId, error: message)
            await eventBus.emit(.feedHealthChanged(feedId: feedId, status: status))
        }
    }

    // MARK: - Private

    /// Core fetch/parse/persist logic. Returns the count of newly inserted items.
    private func performFetch(feedId: UUID) async throws -> Int {
        let context = ModelContext(container)

        // Load the Feed record.
        var descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedId })
        descriptor.fetchLimit = 1
        guard let feed = try context.fetch(descriptor).first else {
            throw FeedServiceError.feedNotFound(feedId)
        }

        // HTTP fetch. URLSession validates TLS by default (platform certificate pinning).
        let (data, response) = try await URLSession.shared.data(from: feed.url)
        // Extract MIME type from Content-Type header (e.g. "application/rss+xml; charset=utf-8").
        let rawContentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        let mimeType = rawContentType.map { $0.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) } ?? nil

        // Select a parser.
        guard let parser = await feedFactory.parser(for: data, mimeType: mimeType) else {
            throw FeedServiceError.unsupportedFormat
        }

        // Parse.
        let parsedFeed = try parser.parse(data: data, feedURL: feed.url)

        // Seed displayName from feed metadata if the user hasn't set it yet.
        if feed.displayName.isEmpty {
            feed.displayName = parsedFeed.title
        }

        // Insert new items; skip items whose stableId already exists for this feed.
        var newItemCount = 0
        for parsed in parsedFeed.items {
            let sid = parsed.stableId
            var itemDescriptor = FetchDescriptor<FeedItem>(
                predicate: #Predicate { $0.stableId == sid && $0.feedId == feedId }
            )
            itemDescriptor.fetchLimit = 1
            let existing = try context.fetch(itemDescriptor)
            guard existing.isEmpty else { continue }

            // FeedItem.init only exposes non-afforded fields; set afforded fields after init.
            let item = FeedItem(
                feedId: feedId,
                stableId: parsed.stableId,
                title: parsed.title,
                link: parsed.link,
                publishedAt: parsed.publishedAt,
                updatedAt: parsed.updatedAt,
                summaryHTML: parsed.summaryHTML,
                contentHTML: parsed.contentHTML
            )
            item.thumbnailURL = parsed.thumbnailURL          // afforded: card view not active in v1
            item.estimatedReadMinutes = parsed.estimatedReadMinutes  // afforded: not displayed in v1
            item.enclosureURL = parsed.enclosureURL          // afforded: not active in v1
            item.enclosureMIMEType = parsed.enclosureMIMEType  // afforded: not active in v1
            context.insert(item)
            newItemCount += 1

            // Capture id before crossing async boundary.
            let itemId = item.id
            await eventBus.emit(.itemParsed(itemId: itemId, feedId: feedId))
        }

        // Update feed success metadata.
        feed.lastFetchedAt = Date()
        feed.consecutiveFailureCount = 0
        feed.lastFetchError = nil
        try context.save()

        return newItemCount
    }

    /// Increments `consecutiveFailureCount` on the Feed record and returns the new health status.
    private func recordFailure(feedId: UUID, error: String) async -> FeedHealthStatus {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedId })
        descriptor.fetchLimit = 1
        guard let feed = (try? context.fetch(descriptor))?.first else {
            return .unhealthy(error: error, lastFetchedAt: nil)
        }
        feed.consecutiveFailureCount += 1
        feed.lastFetchError = error
        try? context.save()
        return healthStatus(for: feed, error: error)
    }

    /// Maps `consecutiveFailureCount` to the appropriate `FeedHealthStatus`.
    /// Threshold of 5 consecutive failures → unhealthy (spec §4.14).
    private func healthStatus(for feed: Feed, error: String) -> FeedHealthStatus {
        switch feed.consecutiveFailureCount {
        case 0:       return .healthy
        case 1..<5:   return .degraded(consecutiveFailures: feed.consecutiveFailureCount)
        default:      return .unhealthy(error: error, lastFetchedAt: feed.lastFetchedAt)
        }
    }
}

// MARK: - Errors

public enum FeedServiceError: Error, Sendable {
    case feedNotFound(UUID)
    case unsupportedFormat
}
