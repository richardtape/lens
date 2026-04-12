// TimelineState.swift — Observable UI state for the timeline.
//
// Owns: filter selection, unread toggle, new-items banner.
// Does NOT own @Query — queries live in TimelineView where SwiftData reactivity works.
//
// EventBus subscription: listens for .backgroundRefreshCompleted to drive the
// "N new items" banner. The Task captures self weakly to avoid a retain cycle
// (self → eventTask → Task → [strong self] would prevent deallocation).
import SwiftUI
import LensCore

// MARK: - Supporting types

struct NewItemsBanner: Equatable {
    let count: Int
}

// MARK: - TimelineState

@Observable
@MainActor
public final class TimelineState {
    var filterMode: TimelineFilter = .all
    /// When true, stacks on top of filterMode to show only unread items.
    var unreadOnly: Bool = false
    /// Non-nil while the "N new items" pill should be shown.
    var newItemsBanner: NewItemsBanner? = nil

    /// Designated init. Accepts an EventBus so unit tests can inject a fresh bus.
    public init(eventBus: EventBus = .shared) {
        // Weak self: when TimelineState is deallocated, `guard let self else { break }`
        // exits the loop on the next iteration — no explicit cancellation needed.
        Task { @MainActor [weak self] in
            for await event in await eventBus.makeStream() {
                guard let self else { break }
                switch event {
                case .backgroundRefreshCompleted(let count) where count > 0:
                    // Banner only on the unfiltered timeline — per-feed and
                    // per-category views are already scoped, so a global count
                    // would be misleading (spec §4.4).
                    if self.filterMode == .all {
                        self.newItemsBanner = NewItemsBanner(count: count)
                    }
                default:
                    break
                }
            }
        }
    }
}
