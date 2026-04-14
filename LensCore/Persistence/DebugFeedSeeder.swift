// DebugFeedSeeder.swift — PHASE-4-DEBUG temporary feed seeder.
//
// DELETE THIS FILE before Phase 5 work begins.
//
// Inserts one real feed and triggers FeedService to fetch it on first launch,
// so the Phase 4 reader can be tested before Phase 5 adds feed-management UI.
//
// Feed chosen: https://cms.ubc.ca/feed/ — WordPress RSS with real articles,
// SVG graphics, inline styles, and style blocks; good exercise for the sanitizer.
//
// What you'll see:
//   • <svg> blocks stripped (in our block-tag list)
//   • <style> blocks stripped (same)
//   • Inline style="" attributes preserved (not a security risk; may occasionally
//     conflict with our layout CSS — expected and acceptable for debug purposes)
//   • All text, headings, links, and inline formatting intact
//
// To reset (clear all seeded data): delete the app from the simulator/device,
// then run again. The seeder checks for any existing Feed and skips if found.
//
// If the network is unavailable on first launch the timeline will be empty —
// restart the app when connected. No retry UI exists until Phase 5.
import Foundation
import SwiftData

// PHASE-4-DEBUG — delete before Phase 5
public enum DebugFeedSeeder {

    private static let feedURL  = URL(string: "https://cms.ubc.ca/feed/")!
    private static let feedName = "UBC CMS (debug)"

    /// Inserts the debug feed and fetches it if no feeds are present.
    /// Safe to call on every launch — returns immediately if a Feed already exists.
    @MainActor
    public static func seedIfNeeded(in container: ModelContainer) async {
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        guard existing.isEmpty else { return }

        let feed = Feed(url: feedURL, displayName: feedName)
        context.insert(feed)
        try? context.save()

        // FeedService creates its own ModelContext internally — safe to call here.
        let service = FeedService(container: container)
        await service.fetchFeed(feedId: feed.id)
    }
}
