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

        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<FeedItem>())) ?? []

        let feedId: UUID

        if feeds.isEmpty {
            // First launch — insert the feed.
            print("[DebugSeeder] No feeds found — inserting \(feedURL)")
            let feed = Feed(url: feedURL, displayName: feedName)
            context.insert(feed)
            do {
                try context.save()
                print("[DebugSeeder] Feed saved with id \(feed.id)")
            } catch {
                print("[DebugSeeder] ERROR saving feed: \(error)")
                return
            }
            feedId = feed.id
        } else if items.isEmpty {
            // Feed exists but no items — previous fetch failed. Retry.
            feedId = feeds[0].id
            print("[DebugSeeder] Feed exists (id \(feedId)) but 0 items — retrying fetch")
        } else {
            print("[DebugSeeder] \(feeds.count) feed(s), \(items.count) item(s) — nothing to do")
            return
        }

        // Subscribe to the event bus BEFORE fetching so we catch the result.
        let monitorTask = Task {
            for await event in await EventBus.shared.makeStream() {
                switch event {
                case .feedFetchCompleted(let id, let count) where id == feedId:
                    print("[DebugSeeder] Fetch completed — \(count) new items inserted")
                    return
                case .feedFetchFailed(let id, let error) where id == feedId:
                    print("[DebugSeeder] ERROR fetch failed: \(error)")
                    return
                default:
                    break
                }
            }
        }

        print("[DebugSeeder] Starting FeedService fetch…")
        let service = FeedService(container: container)
        await service.fetchFeed(feedId: feedId)
        monitorTask.cancel()

        let itemCount = (try? context.fetch(FetchDescriptor<FeedItem>()))?.count ?? -1
        print("[DebugSeeder] Items now in store: \(itemCount)")
    }
}
