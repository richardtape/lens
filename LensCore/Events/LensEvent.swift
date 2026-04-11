// LensEvent.swift — Typed domain events for the Lens event bus.
//
// Every case in this enum is part of the public addon API (spec §3.7).
// Case names and associated-value labels are stable — renaming is a
// breaking change that requires a versioning notice in the event catalog.
//
// Threading: LensEvent is Sendable so events can cross actor boundaries
// safely. All associated values (UUID, String, Int, Date) are themselves
// Sendable.
import Foundation

// MARK: - FeedHealthStatus

/// The fetch-health state of a single Feed.
///
/// Emitted inside `LensEvent.feedHealthChanged` whenever health transitions.
/// Used by the sidebar to show badges and error rows (spec §4.14).
public enum FeedHealthStatus: Equatable, Sendable {
    /// Feed fetched successfully on its most recent attempt.
    case healthy
    /// Feed has failed `consecutiveFailures` times but hasn't crossed the
    /// unhealthy threshold yet (threshold = 5 per spec §4.14).
    case degraded(consecutiveFailures: Int)
    /// Feed has exceeded the failure threshold.
    /// `error` is the human-readable message shown in the sidebar.
    /// `lastFetchedAt` is nil if the feed has never succeeded.
    case unhealthy(error: String, lastFetchedAt: Date?)
}

// MARK: - LensEvent

/// All substantive domain events in Lens.
///
/// Emit events via `EventBus.shared.emit(_:)`.
/// Subscribe by calling `EventBus.shared.makeStream()` and iterating with
/// `for await event in stream { … }`.
///
/// See spec §3.7 for the full event catalog and ordering guarantees.
public enum LensEvent: Equatable, Sendable {

    // MARK: App lifecycle

    /// The app has finished launching and the data stack is ready.
    case appLaunched

    // MARK: Background refresh

    /// A background refresh cycle has started.
    case backgroundRefreshStarted
    /// A background refresh cycle has completed.
    /// `newItemCount` is the total number of new items inserted across all feeds.
    case backgroundRefreshCompleted(newItemCount: Int)

    // MARK: Feed fetch

    /// A fetch for a specific feed has begun.
    case feedFetchStarted(feedId: UUID)
    /// A fetch for a specific feed completed successfully.
    /// `newItemCount` is the count of items inserted (0 if nothing new).
    case feedFetchCompleted(feedId: UUID, newItemCount: Int)
    /// A fetch for a specific feed failed.
    /// `error` is a human-readable description; shown in sidebar (spec §4.14).
    case feedFetchFailed(feedId: UUID, error: String)
    /// The health state of a feed changed (spec §4.14).
    /// Emitted after every fetch — both success (→ healthy) and failure (→ degraded/unhealthy).
    case feedHealthChanged(feedId: UUID, status: FeedHealthStatus)

    // MARK: User-initiated refresh

    /// The user triggered a refresh of all feeds
    /// (pull-to-refresh on iOS; `r` key on macOS when no specific feed is focused).
    case userInitiatedRefresh
    /// The user triggered a refresh for one specific feed
    /// (Retry button or right-click/long-press menu on the feed row).
    /// Distinct from `userInitiatedRefresh` so addons can react to per-feed retries
    /// separately from global refreshes (spec §4.14).
    case userInitiatedFeedRefresh(feedId: UUID)

    // MARK: Item lifecycle

    /// A `FeedItem` was parsed and inserted into the store.
    case itemParsed(itemId: UUID, feedId: UUID)
    /// A `FeedItem` was opened in the reader view.
    case itemDisplayed(itemId: UUID)
    /// A `FeedItem` was marked as read.
    case itemMarkedRead(itemId: UUID)
    /// A `FeedItem` was marked as unread.
    case itemMarkedUnread(itemId: UUID)
    /// A `FeedItem` was starred (favourited).
    case itemStarred(itemId: UUID)
    /// A `FeedItem` had its star removed.
    case itemUnstarred(itemId: UUID)
    /// A `FeedItem` was saved for offline reading.
    case itemSavedOffline(itemId: UUID)
    /// An offline-saved `FeedItem` had its saved copy removed.
    case itemOfflineSaveRemoved(itemId: UUID)

    // MARK: Reader / theme

    /// The active reading theme was changed.
    /// `themeName` is the identifier from the theme's manifest (or `"default"` for the built-in theme).
    case themeApplied(themeName: String)

    // MARK: Addon lifecycle

    /// An addon was successfully downloaded, verified, extracted, and registered.
    /// `addonId` is the `identifier` field from the addon's manifest.json.
    case addonInstalled(addonId: String)
    /// An addon installation attempt failed at any stage.
    /// `addonId` is nil if the failure occurred before the manifest was parsed
    /// (e.g. download or ZIP extraction failure).
    case addonInstallFailed(addonId: String?, error: String)
}
