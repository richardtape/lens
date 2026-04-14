# Lens — Phase 5 design: Feeds management

**Status:** Approved  
**Date:** 2026-04-14  
**Phase:** 5 (follows Phase 4 — Reader)  
**Related:** [Product spec](./2026-04-09-lens-design.md) · [Build phases](./2026-04-10-lens-build-phases.md) · [Agent orientation](../2026-04-10-lens-agent-orientation.md)

---

## Goal

Phase 5 is the first phase where users can actually add, edit, and delete feeds. It replaces all remaining `StubDestinationView` placeholders in the Feeds and Categories destinations, wires up the `navigateToAddFeed` deep link, implements full category management, and adds `j`/`k` keyboard navigation to the macOS timeline.

---

## Scope

### In scope

- Feed CRUD: add (with URL discovery), edit (name + category), delete
- Category CRUD: add (with fuzzy-match duplicate warning), rename, delete
- Feed list views on iOS and macOS (replacing stubs)
- Category list view on macOS (replacing stub)
- Feed health badges and Retry button on feed rows
- Per-feed manual refresh from feed list context menu / long-press
- Feed sort order picker wired to `UserInterfacePreferences.feedSortOrder`
- `j`/`k` keyboard shortcuts on macOS (deferred from Phase 4)
- Deep link correction: `navigateToAddFeed` → Feeds tab, not Timeline
- macOS toolbar + sidebar + Commands menu wiring for Add Feed

### Out of scope — see deferrals section

- `BGAppRefreshTask` / background refresh scheduling
- OPML import UI
- Per-feed refresh interval setting (afforded field, UI in v2)

---

## LensCore additions

### `FeedDiscoveryService.swift` (struct, static API)

New file: `LensCore/Feeds/FeedDiscoveryService.swift`

**Return type:**
```swift
public struct DiscoveredFeed: Sendable {
    public let feedURL: URL
    public let title: String
    public let itemCount: Int
    public let iconURL: URL?
}
```

**Primary method:** `discover(url: URL) async throws -> DiscoveredFeed`

Discovery algorithm (in order, first success wins):
1. Fetch `url`, try all parsers registered in `FeedFactory`.
2. If response is HTML, parse for `<link rel="alternate" type="application/rss+xml" href="...">` and follow that URL.
3. Probe well-known suffixes on the base domain: `/feed`, `/rss`, `/atom.xml`, `/feed.xml`, `/rss.xml`.
4. Throw `FeedDiscoveryError.notFound` if all paths fail.

`itemCount` is derived from the parsed feed — no extra network request needed.

**Error type:**
```swift
public enum FeedDiscoveryError: Error, Sendable {
    case notFound
    case networkError(underlying: Error)
}
```

---

### `FeedManagementService.swift` (actor)

New file: `LensCore/Feeds/FeedManagementService.swift`

Handles all feed and category mutations. `FeedService` remains focused on fetch/refresh and is unchanged.

#### Feed methods

**`addFeed(url: URL, categoryId: UUID?) async throws -> Feed`**
1. Calls `FeedDiscoveryService.discover(url:)`.
2. Checks for an existing feed with the same URL — throws `FeedManagementError.alreadySubscribed(feedId:)` if found.
3. Creates and inserts a `Feed` record using the discovered `feedURL` (the canonical feed URL, which may differ from what the user typed).
4. Emits `.feedAdded(feedId:)`.
5. Triggers an initial `FeedService.fetchFeed(feedId:)` to populate items immediately.

**`deleteFeed(feedId: UUID) async throws`**
1. Deletes all `FeedItem` records with `feedId`.
2. Deletes the `Feed` record.
3. Emits `.feedDeleted(feedId:)`.

**`editFeed(feedId: UUID, displayName: String, categoryId: UUID?) async throws`**
1. Updates `feed.displayName` and `feed.categoryId`.
2. Emits `.feedUpdated(feedId:)`.

#### Category methods

**`addCategory(name: String) async throws -> LensCore.Category`**
1. Fuzzy-match check: if an existing category name is very similar (case-insensitive prefix match or Levenshtein distance ≤ 2), throws `CategoryError.similarExists(existingId:existingName:)`. The UI surfaces this as a warning the user can dismiss and proceed.
2. Inserts the new `Category` record with `isBuiltIn = false`.
3. Assigns `sortOrder` as max existing + 1.
4. Emits `.categoryAdded(categoryId:)`.

**`renameCategory(categoryId: UUID, name: String) async throws`**
1. Updates `category.name`.
2. Emits `.categoryRenamed(categoryId:)`.

**`deleteCategory(categoryId: UUID) async throws`**
1. Sets `categoryId = nil` on all feeds assigned to this category.
2. Deletes the `Category` record.
3. Emits `.categoryDeleted(categoryId:)`.

Note: built-in categories (where `isBuiltIn == true`) can be deleted. The `isBuiltIn` flag exists only to prevent re-seeding on launch, not to restrict user actions.

#### Error types

```swift
public enum FeedManagementError: Error, Sendable {
    case feedNotFound(UUID)
    case alreadySubscribed(feedId: UUID)
    case discoveryFailed(FeedDiscoveryError)
}

public enum CategoryError: Error, Sendable {
    case notFound(UUID)
    // UUID + name rather than LensCore.Category — @Model is not Sendable.
    case similarExists(existingId: UUID, existingName: String)
}
```

---

### New `LensEvent` cases

Added to `LensCore/Events/LensEvent.swift` (additive — no renames):

```swift
// Feed CRUD
case feedAdded(feedId: UUID)
case feedDeleted(feedId: UUID)
case feedUpdated(feedId: UUID)

// Category CRUD
case categoryAdded(categoryId: UUID)
case categoryDeleted(categoryId: UUID)
case categoryRenamed(categoryId: UUID)
```

All six cases are part of the public addon API from the moment they ship.

---

## LensUI additions

New directory: `LensUI/Feeds/`

---

### `FeedRowView`

Shared component used in `FeedListView` (iOS and macOS) and, on macOS, in the sidebar feed list if individual feeds are shown there in a future phase.

**Displays:**
- `MonogramView` as the primary icon. If `feed.iconRef` is a valid URL, loads it async and replaces the monogram on success.
- `feed.displayName` as primary label; domain extracted from `feed.url` as secondary label.
- Unread count badge (blue pill) when unread count > 0.
- Health indicator dot: red for `.unhealthy`, amber for `.degraded`, nothing for `.healthy`.
- For unhealthy feeds: an expanded second row showing `feed.lastFetchError` + "Last updated X ago" (formatted relative date from `feed.lastFetchedAt`) + an inline **Retry** button.

**Retry button** emits `userInitiatedFeedRefresh(feedId: feed.id)` on tap. Does not call `FeedService` directly.

**Unread count:** queried via `@Query` in the parent `FeedListView`, passed into `FeedRowView` as a `let` constant to avoid per-row queries.

---

### `FeedListView`

Replaces `StubDestinationView` for the Feeds destination on both platforms.

**iOS (Feeds tab):**
- `List` with `Section` headers grouped by category.
- When `feedSortOrder == .byCategory`: one section per category (populated categories only) + an "Other" section at the bottom for uncategorised feeds.
- When sort is alphabetical / unreadCount / lastUpdated: a single unsectioned list, sorted accordingly. Category headers are hidden in these modes.
- Toolbar trailing: `+` button → `AddFeedSheet`, plus a sort `Menu` button (icon: `line.3.horizontal.decrease.circle`) listing the four sort options.
- Toolbar trailing: **Manage Categories** menu item inside the sort menu → presents `CategoryListView` as a sheet.
- Swipe-to-delete: confirmation alert, then calls `FeedManagementService.deleteFeed(feedId:)`.
- Long-press context menu: **Refresh Feed**, **Edit**, **Delete**.

**macOS (Feeds content column):**
- Same grouping logic as iOS.
- Right-click context menu: **Refresh Feed**, **Edit…**, **Delete**.
- Sort picker accessible from the macOS View → Sort Feeds submenu (see Commands section).
- No swipe actions; deletion via context menu or `Delete` key.

**Navigation:** tapping a feed row on macOS pushes `.feed(id: feed.id)` as a `MacDestination`, showing a filtered `TimelineView` for that feed in the content column. On iOS, tapping a feed row navigates via `NavigationStack` to a filtered `TimelineView`.

---

### `AddFeedSheet`

Presented as a `.sheet` from:
- iOS: `+` toolbar button in `FeedListView`
- macOS: toolbar button in `RootSplitView`, sidebar bottom `+`, and File → New Feed… command
- Deep link: `navigateToAddFeed(prefillURL:)` — pre-fills the URL field if a URL is provided

**States:**

| State | UI |
|-------|-----|
| Idle | Text field ("Feed or website URL"), disabled **Subscribe** button, secondary **Look Up** button (visible when field is non-empty and user is typing rather than pasting) |
| Discovering | Spinner inline below text field, "Looking up feed…" |
| Found | Preview card: icon + title + domain + item count. Optional category `Picker`. Enabled **Subscribe** button. |
| Error | Red error message below field. "Try a different URL" hint. Field remains editable. |
| Duplicate | "Already subscribed to [name]" message. No Subscribe button. |

**Paste detection:** monitors field changes via `.onChange(of: urlText)`. Heuristic: if the new value contains `://` and the previous value did not (i.e. the field went from empty or a partial string to a full URL in one change event), treat it as a paste and fire discovery immediately. Character-by-character typing changes the field one character at a time and will not satisfy this condition, so it relies on the **Look Up** button instead.

**Subscribe action:** calls `FeedManagementService.addFeed(url:categoryId:)`, dismisses sheet on success.

---

### `EditFeedSheet`

Presented as a `.sheet` from the long-press / right-click Edit action on a feed row.

- `TextField` pre-filled with `feed.displayName`.
- `Picker` for category assignment (all categories + "None").
- **Save** button → calls `FeedManagementService.editFeed(feedId:displayName:categoryId:)`, dismisses.
- **Cancel** button.
- **Delete Feed** destructive button at bottom → confirmation alert ("Delete [name]? This will remove all downloaded articles.") → calls `FeedManagementService.deleteFeed(feedId:)`, dismisses.

---

### `CategoryListView`

**macOS:** Replaces `StubDestinationView` for the Categories content column.  
**iOS:** Presented as a sheet from the Manage Categories option in the Feeds tab toolbar menu, and reachable from the category picker in `AddFeedSheet` / `EditFeedSheet`.

- `List` of all categories, each row showing name + feed count.
- **Add:** text field inline at the bottom of the list (like Finder new folder). On commit, calls `FeedManagementService.addCategory(name:)`. If `CategoryError.similarExists` is thrown, shows a warning banner: "Similar to existing category '[name]'. Add anyway?" with two buttons.
- **Rename:** double-click (macOS) or swipe → Edit button (iOS). Inline `TextField` replacing the label, on commit calls `renameCategory`.
- **Delete:** swipe-to-delete (iOS) or right-click Delete (macOS). Confirmation alert for categories with feeds: "This will unassign [n] feeds from '[name]'."

---

## Shell wiring

### Per-feed refresh coordinator

Both `LensIOS/LensApp.swift` and `LensMac/LensMacApp.swift` add a `.task` subscribing to `EventBus.shared.makeStream()`. When `.userInitiatedFeedRefresh(feedId:)` fires, the coordinator calls `FeedService.fetchFeed(feedId:)`. This is the same pattern used for global refresh.

### Deep link correction

`RootTabView.subscribeToNavigationEvents()`: `.navigateToAddFeed` now switches `selection = .feeds` and sets `showingAddFeed = true` (presenting `AddFeedSheet`). Previously it routed to `.timeline` — that was incorrect.

`RootSplitView.subscribeToNavigationEvents()`: same correction — switches `destination = .feeds` and presents the sheet.

If `.navigateToAddFeed(prefillURL: url)` carries a URL, it is passed into `AddFeedSheet` as a pre-filled value.

### macOS toolbar (RootSplitView)

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Add Feed", systemImage: "plus") {
            showingAddFeed = true
        }
    }
}
```

### macOS sidebar bottom `+`

The sidebar `List` gains a pinned row at the bottom of the Library section:
```swift
Button { showingAddFeed = true } label: {
    Label("Add Feed", systemImage: "plus")
}
.foregroundStyle(.secondary)
```

Both entry points share a single `showingAddFeed: Bool` state flag on `RootSplitView`.

### macOS Commands (`LensMacApp.swift`)

```swift
CommandGroup(after: .newItem) {
    Button("New Feed…") {
        Task { await EventBus.shared.emit(.navigateToAddFeed(prefillURL: nil)) }
    }
    .keyboardShortcut("n", modifiers: [.command, .shift])
}

CommandMenu("Sort Feeds") {
    // Four toggle buttons mirroring FeedSortOrder cases,
    // reading/writing UserInterfacePreferences via environment.
}
```

### `MacDestination` enum

Gains a new case:
```swift
case feed(id: UUID)
```

`RootSplitView.contentColumn` adds a branch for this case, rendering `TimelineView` filtered to the selected feed.

---

## `j`/`k` keyboard shortcuts (macOS)

### `TimelineState` additions

`selectedItem: FeedItem?` moves from shell `@State` onto `TimelineState` so the selection is accessible to the j/k closures without needing a `ModelContext` parameter.

```swift
// The article currently open in the reader. Moved here from shell @State.
var selectedItem: FeedItem? = nil

// Kept in sync by TimelineView after each displayedItems recompute.
// Storing [FeedItem] (not just IDs) avoids a context fetch in selectNextItem.
var displayedItems: [FeedItem] = []

// Called by FocusedValues closures from the Commands block.
func selectNextItem() { … }
func selectPreviousItem() { … }
```

`selectNextItem` finds `selectedItem` in `displayedItems`, advances by one, and sets `selectedItem`. No-ops if already at the last item. `RootSplitView` and `RootTabView` read `selectedItem` from `TimelineState` rather than holding their own `@State` copy — both shells update their binding accordingly.

### `FocusedValues` additions

```swift
extension FocusedValues {
    @Entry var selectNextItem: (() -> Void)? = nil
    @Entry var selectPreviousItem: (() -> Void)? = nil
}
```

`RootSplitView` provides these via `.focusedSceneValue`. The `Commands` block in `LensMacApp` reads them and binds `j` / `k` as `.keyboardShortcut` modifiers — identical pattern to the existing `?` shortcut.

---

## Deferrals

These items were explicitly considered for Phase 5 and deferred. Future agents must not implement them in Phase 5 without a deliberate scope change.

### `BGAppRefreshTask` / background refresh scheduling — deferred to Phase 7

**Why deferred:** The `backgroundRefreshEnabled` toggle that controls background refresh lives in `UserInterfacePreferences` and its settings UI lands in Phase 7. Wiring `BGAppRefreshTask` before the settings toggle exists would make background refresh always-on with no user control, which contradicts the spec's explicit user-control requirement (§4.5). iOS Background App Refresh also requires Info.plist capability registration (human driver work) — this is easier to batch with the Phase 7 settings work.

Phase 5 does add per-feed *manual* refresh from the feed list (long-press / context menu → `userInitiatedFeedRefresh`), which is the more immediately useful UX piece.

### OPML import UI — deferred to Phase 8

**Why deferred:** OPML import/export is explicitly Phase 8 in the build roadmap. The `navigateToOPMLImport(sourceURL:)` event and the `lens://import?opml=<url>` deep link are already defined, but the import UI (file picker, progress, conflict resolution) belongs in Phase 8 alongside OPML export and system share sheet integration.

### Per-feed refresh interval UI — deferred to v2

**Why deferred:** `Feed.refreshInterval` is an afforded field (present in the model, UI not active in v1 per spec §7.1). The spec explicitly defers the per-feed UI control to v2. Do not surface this in any Phase 5 UI.

---

## Implementation notes for Phase 5 agents

- `FeedManagementService` takes a `ModelContainer` and `EventBus` in its `init` — same pattern as `FeedService`. Inject at the app target level.
- `FeedDiscoveryService` is a `struct` with only `static` or `func` methods (no stored state) — no injection needed; call directly from `FeedManagementService`.
- Unread counts per feed: compute as a `@Query` in `FeedListView` (count of `FeedItem` where `feedId == id && isRead == false`). Pass the result as a `[UUID: Int]` dictionary into child views to avoid per-row queries.
- `LensCore.Category` naming: always fully-qualify as `LensCore.Category` in SwiftUI files — do not use a `typealias`. See orientation for why.
- `@Query` sort on `LensCore.Category`: use `@Query var categories: [LensCore.Category]` with no sort arg and sort in-view (known SwiftData limitation — see orientation).
- Delete cascade for `FeedItem` on feed deletion: SwiftData does not automatically cascade. `FeedManagementService.deleteFeed` must explicitly fetch and delete all `FeedItem` records before deleting the `Feed`.
- The `isBuiltIn` flag on `Category` only prevents re-seeding in `CategorySeeder` — it does not restrict the user from deleting or renaming built-in categories.
- End-of-phase: update `agent-orientation.md` — Current state, Module layout (new `LensUI/Feeds/` directory), and any new implementation notes.
