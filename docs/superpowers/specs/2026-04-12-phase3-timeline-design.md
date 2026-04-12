# Lens Phase 3 — Timeline UI Design

**Status:** Approved  
**Date:** 2026-04-12  
**Phase:** 3 — Timeline UI  
**Depends on:** [Build phases](./2026-04-10-lens-build-phases.md) · [Product spec](./2026-04-09-lens-design.md) · [Agent orientation](../2026-04-10-lens-agent-orientation.md)

---

## 1. Overview

Phase 3 replaces the Phase 1 hello-world placeholder with the real application shell and a fully functional timeline. It establishes the navigation structure every subsequent phase builds on, and delivers the complete article list experience on both iOS and macOS.

**What ships in Phase 3:**
- Full navigation shell (tab bar iOS/iPad, split view Mac) with stubbed non-timeline destinations
- Chronological timeline of all `FeedItem` rows with read/unread state
- Article row with density-aware layout, accent-bar unread indicator, and favicon/monogram
- Quick filters: Unread toggle + category/feed filter sheet
- New items banner (glass pill, scroll-to-top dismiss)
- Empty state
- Full iOS swipe/long-press gesture set
- Full macOS single-letter keyboard shortcuts
- Reader stub — navigation stack wired, placeholder replaced in Phase 4

**What does NOT ship in Phase 3:**
- Real reader (Phase 4) — `ReaderStubView` placeholder only
- Feed add/edit UI (Phase 5) — Feeds tab is a stub
- Offline pipeline (Phase 6) — save action emits event but does not store content
- Settings UI (Phase 7) — Settings tab is a stub; `accentColor` preference field is afforded

---

## 2. Navigation shell

### 2.1 iOS / iPadOS — `RootTabView`

```swift
TabView {
    Tab("Timeline", systemImage: "newspaper") { TimelineView() }
    Tab("Feeds",    systemImage: "antenna.radiowaves.left.and.right") { StubDestinationView(name: "Feeds", symbol: "antenna.radiowaves.left.and.right") }
    Tab("Saved",    systemImage: "bookmark") { StubDestinationView(name: "Saved", symbol: "bookmark") }
    Tab("Settings", systemImage: "gear") { StubDestinationView(name: "Settings", symbol: "gear") }
}
.tabViewStyle(.sidebarAdaptable)
.tabBarMinimizeBehavior(.onScrollDown)
```

- **iPhone:** Floating Liquid Glass pill tab bar at the bottom — automatic on iOS 26.
- **iPad portrait:** Tab bar near the top of the screen.
- **iPad landscape:** Converts to sidebar automatically.
- Tab bar collapses while scrolling via `.tabBarMinimizeBehavior(.onScrollDown)`.
- Tint: user accent colour (default `#4A90D9`).

### 2.2 macOS — `RootSplitView`

Three-column `NavigationSplitView`:

| Column | Phase 3 content |
|--------|----------------|
| Sidebar (leading) | "Timeline" nav link; stubbed "Feeds", "Categories" section headers |
| List (middle) | `TimelineView` — article list |
| Detail (trailing) | `ReaderStubView` — replaced in Phase 4 |

Sidebar uses `.listStyle(.sidebar)` for automatic Liquid Glass treatment on macOS 26. Content extends beneath the sidebar using `.backgroundExtensionEffect()` on the list column.

### 2.3 Stub destination view

`StubDestinationView` is a shared view used for the three non-timeline tabs (Feeds, Saved, Settings):

```
[SF Symbol — large, secondary opacity]
Destination Name
```

No "coming soon" copy. Intentionally minimal — internal scaffolding only.

`ReaderStubView` is a separate stub used specifically for the macOS detail column (and the iOS navigation push target when tapping a row). It shows the article title and source when an item is selected, or "Select an article to read" when nothing is selected. Phase 4 replaces it with the real `WKWebView` reader.

### 2.4 Deep link wiring

`onOpenURL` in both app entry points calls `DeepLinkRouter.handle(_:)` (already wired in Phase 2E). Navigation events emitted by the router (`.navigateToSaved`, `.navigateToSettings`, `.navigateToFeed`, `.navigateToItem`) are consumed by a coordinator in `RootTabView` / `RootSplitView` that switches the active tab or pushes to the correct destination. In Phase 3, links to unbuilt destinations navigate to their stub view — they don't crash.

---

## 3. State management

### 3.1 `TimelineState`

An `@Observable` class instantiated once at the root and injected as an environment object. Owns all UI-layer state for the timeline; does not own SwiftData queries.

```swift
@Observable
final class TimelineState {
    var filterMode: TimelineFilter = .all
    var unreadOnly: Bool = false           // stacks with filterMode
    var newItemsBanner: NewItemsBanner? = nil

    // Event bus subscription — started on init, cancelled on deinit
    private var eventTask: Task<Void, Never>?
}

enum TimelineFilter: Equatable {
    case all
    case category(UUID)
    case feed(UUID)
}

struct NewItemsBanner: Equatable {
    let count: Int      // shown in "↑ N new items"
}
```

`unreadOnly` is a separate boolean that stacks on top of `filterMode` — you can be in "Unread + Technology category" simultaneously. The `@Query` predicate is derived from the combination of `filterMode` and `unreadOnly`.

**Event bus subscriptions in `TimelineState`:**
- `.backgroundRefreshCompleted(newItemCount:)` where `newItemCount > 0` → sets `newItemsBanner`
- `.backgroundRefreshCompleted(newItemCount: 0)` → no banner
- `.itemMarkedRead` / `.itemMarkedUnread` → no direct state change needed; SwiftData `@Query` reacts automatically

### 3.2 `@Query` in `TimelineView`

`TimelineView` owns the `@Query` and recomputes its predicate when `timelineState.filterMode` or `timelineState.unreadOnly` changes. SwiftData's reactive machinery handles list updates.

```swift
struct TimelineView: View {
    @Environment(TimelineState.self) private var timelineState
    @Query private var items: [FeedItem]

    // Predicate and sort rebuilt from timelineState via .onChange
}
```

Sort order: `publishedAt` descending; items with nil `publishedAt` sorted to the bottom.

---

## 4. Timeline view

### 4.1 Layout

```
┌─ NavigationStack ──────────────────────────┐
│  Large title: "Timeline"                   │  ← glass nav bar (automatic)
│  Toolbar: [Unread toggle] [Filter button]  │
├────────────────────────────────────────────┤
│  [New items banner — glass pill, optional] │  ← safeAreaInset(edge: .top)
│                                            │
│  List of ArticleRowView                    │
│  ...                                       │
│  ...                                       │
└────────────────────────────────────────────┘
     [Glass tab bar — automatic]               ← iOS only
```

The list uses `.listStyle(.plain)` with no section headers in the default timeline view.

### 4.2 Pull-to-refresh

Standard `refreshable` modifier on the `List`. On trigger:
1. Emit `.userInitiatedRefresh` on `EventBus`
2. Call `FeedService.fetchAllFeeds()` (iterates all `Feed` records and calls `fetchFeed(feedId:)`)
3. Await completion before dismissing the refresh indicator

### 4.3 Empty state

Shown when `@Query` returns zero items:

```
        [newspaper SF Symbol — large, secondary opacity]
     Your timeline is quiet
  Add some feeds and your articles
         will appear here.
    [  Add your first feed  ]        ← .buttonStyle(.glassProminent)
```

The CTA button navigates to the Feeds tab (stub in Phase 3). On macOS it selects the Feeds sidebar item.

### 4.4 New items banner

Shown when `timelineState.newItemsBanner != nil`, anchored via `.safeAreaInset(edge: .top)`:

```
        ↑ 12 new items
```

Implementation:
- `GlassEffectContainer` wrapping a `Capsule`-shaped label
- `.glassEffect(.regular.interactive(), in: .capsule)`
- Centred horizontally with padding
- **Tap:** scroll to top via `ScrollViewProxy`, then `timelineState.newItemsBanner = nil`
- **Auto-dismiss:** a scroll position preference key detects when the user reaches the top of the list; banner nils out automatically
- Only shown on the main timeline (`filterMode == .all`); per-feed and per-category views never show the banner

---

## 5. Article row — `ArticleRowView`

### 5.1 Visual anatomy

```
┃  [icon 17×17]  Source name        ← source row
┃  Article title here               ← .headline unread / .subheadline read
┃  Two-line excerpt from the…       ← .secondary / heavily dimmed read
┃  2 minutes ago                    ← .tertiary always
▲
3pt accent bar (full row height)
```

The accent bar is a `Rectangle` in an `HStack` wrapping the row content — not a list row separator — so it spans the full dynamic height of the row.

### 5.2 Unread / read states

| Element | Unread | Read |
|---------|--------|------|
| Accent bar | Accent colour | Transparent |
| Icon/monogram | Full opacity | 30% opacity |
| Source name | `.secondary` | `.tertiary` dimmed |
| Title | `.headline` (bold) | `.subheadline` (regular) |
| Excerpt | `.secondary` | Heavily dimmed |
| Timestamp | `.tertiary` | `.tertiary` |

### 5.3 Icon / monogram

- **Favicon available** (`feed.iconRef` resolves): async image load, cached, 17×17pt rounded rect. Falls back to monogram on load failure.
- **No favicon** (`iconRef` nil or load fails): first letter of `feed.displayName`, rendered in accent colour on a tinted-accent background. Monogram dims to `.tertiary` on read.

### 5.4 Density variants

Driven by `UserReadingPreferences.listDensity` (0.0–1.0):

| Range | Name | Shows |
|-------|------|-------|
| 0.0–0.33 | Title only | Source row + title |
| 0.33–0.67 | Compact | Source row + title + timestamp |
| 0.67–1.0 | Standard (default 0.5) | Full layout |
| Card (v2) | — | Field present; not rendered |

Row padding scales with density: more compact at lower values.

### 5.5 Timestamp formatting

Relative display using `RelativeDateTimeFormatter`:
- Under 1 hour: "2 minutes ago"
- 1–24 hours: "3 hours ago"
- 1–6 days: "2 days ago"
- Older: absolute date, locale-formatted
- Nil `publishedAt`: "Date unknown" (spec §7.2)

### 5.6 iOS swipe actions

| Gesture | Action |
|---------|--------|
| Swipe right | Toggle read/unread — checkmark icon, `.primary` tint |
| Swipe left (short reveal) | Three buttons: Star (`star.fill`), Save (`arrow.down.circle`), Share (`square.and.arrow.up`) |
| Swipe left (full) | Save for offline (commits immediately; emits event; pipeline Phase 6) |
| Long press | Context menu (see §5.7) + haptic feedback |

When "unread only" filter is active and the user marks an item read via swipe, the item vanishes from the list immediately (spec §3.1).

### 5.7 Context menu (iOS long press / macOS right-click)

Actions in order:
1. Mark Read / Mark Unread
2. Star / Unstar
3. Save for Offline / Remove Save
4. Share (system share sheet)
5. Open in Browser
6. Copy Link

### 5.8 Tap behaviour

Tap navigates to `ReaderStubView` (Phase 3) / real reader (Phase 4):
- iOS: pushes onto `NavigationStack` inside the Timeline tab
- macOS: populates the detail column of `NavigationSplitView`

Emits `.itemDisplayed(itemId:)` before navigation.

---

## 6. Filter system

### 6.1 Toolbar controls

Both platforms show two controls in the navigation toolbar:

**Unread toggle** (`circle` / `circle.fill` SF Symbol or text "Unread"):
- `.buttonStyle(.glass)` inactive; `.buttonStyle(.glassProminent)` active
- Toggles `timelineState.unreadOnly`

**Filter button** (`line.3.horizontal.decrease.circle` SF Symbol):
- `.buttonStyle(.glass)` always
- Badge showing count of active non-default filters (0 = no badge)
- iOS: opens a modal sheet
- macOS: opens a popover

### 6.2 Filter sheet / popover

Two sections:

**Category** — list of seeded `Category` records from SwiftData (the 10 built-in + any user-added; Phase 5 adds user-created ones). Single selection. "All categories" option clears the filter.

**Feed** — list of subscribed `Feed` records. Single selection. "All feeds" option clears the filter. Searchable on iOS.

Category and feed filters are mutually exclusive. Selecting a category clears any active feed filter and vice versa. `unreadOnly` stacks on top of either.

**Clear all** button at bottom resets `filterMode = .all` and `unreadOnly = false`.

### 6.3 `TimelineFilter` → `#Predicate`

```swift
// Pseudocode — exact predicate syntax per SwiftData APIs
switch (timelineState.filterMode, timelineState.unreadOnly) {
case (.all, false):           // no predicate — fetch all
case (.all, true):            // isRead == false
case (.category(let id), false): // categoryId == id (via Feed join)
case (.category(let id), true):  // categoryId == id AND isRead == false
case (.feed(let id), false):     // feedId == id
case (.feed(let id), true):      // feedId == id AND isRead == false
}
```

---

## 7. macOS keyboard shortcuts

Implemented via SwiftUI `.keyboardShortcut` on hidden `Button` views in the macOS scene. All shortcuts are single-letter, no modifier. Disabled when a text field is focused (standard SwiftUI behaviour).

| Key | Action | Event emitted |
|-----|--------|---------------|
| `j` | Next item in list | — |
| `k` | Previous item in list | — |
| `u` | Toggle read/unread on selected item | `.itemMarkedRead` / `.itemMarkedUnread` |
| `r` | Refresh all feeds | `.userInitiatedRefresh` |
| `s` | Toggle offline save on selected item | `.itemSavedOffline` / `.itemOfflineSaveRemoved` |
| `f` | Toggle star on selected item | `.itemStarred` / `.itemUnstarred` |
| `o` | Open selected item in browser | — |
| `?` | Show keyboard shortcut reference sheet | — |
| `Escape` | Deselect / back | — |

The keyboard shortcut reference sheet (`?`) is a simple sheet listing the table above, presented modally.

---

## 8. Liquid Glass application

| Element | Treatment |
|---------|-----------|
| Tab bar (iOS) | Automatic — floating glass pill on iOS 26 |
| Navigation bar | Automatic — glass on iOS/macOS 26 |
| Sidebar (Mac) | Automatic — glass via `NavigationSplitView` |
| Filter buttons (Unread, Filter) | `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` |
| New items banner | `GlassEffectContainer` + `.glassEffect(.regular.interactive(), in: .capsule)` |
| Article rows | Standard content layer — **no glass effects** |
| Empty state CTA button | `.buttonStyle(.glassProminent)` |
| Filter sheet / popover | System sheet — automatic glass |

**Rule:** Glass lives in the navigation/control layer. The content list is glass-free per HIG ("Don't use Liquid Glass in the content layer").

---

## 9. Accent colour

`UserReadingPreferences` gains one new field in Phase 3:

```swift
var accentColorHex: String  // default "#4A90D9" (system blue)
```

Used for:
- Unread accent bar colour
- Monogram background tint and letter colour (when no favicon)
- Active filter button tint

The settings UI to change this is Phase 7. The field is afforded in Phase 3 — present in the model, read by `ArticleRowView` and filter controls, but no picker is built.

A `Color` extension converts the hex string to a `SwiftUI.Color` for rendering.

---

## 10. LensUI module layout

```
LensUI/
├── LensUI.swift                    # framework stub (existing)
├── Shell/
│   ├── RootTabView.swift           # iOS/iPadOS entry point
│   ├── RootSplitView.swift         # macOS entry point
│   └── StubDestinationView.swift   # shared placeholder
├── Timeline/
│   ├── TimelineView.swift          # @Query + list
│   ├── TimelineState.swift         # @Observable UI state
│   ├── ArticleRowView.swift        # single row
│   ├── TimelineFilter.swift        # filter enum + predicate builder
│   ├── FilterSheetView.swift       # category/feed picker sheet
│   ├── NewItemsBannerView.swift    # glass pill banner
│   └── ReaderStubView.swift        # Phase 4 placeholder
└── Components/
    ├── AccentColorKey.swift         # EnvironmentKey for accent Color
    └── MonogramView.swift           # reusable favicon/monogram component
```

`LensCore` gains no new Swift files in Phase 3 — all new code is in `LensUI`, `LensIOS`, and `LensMac`. The `UserReadingPreferences` model in `LensCore` gains the `accentColorHex` field.

---

## 11. App shell wiring — what changes in `LensIOS` and `LensMac`

**`LensIOS/ContentView.swift`** — replaced entirely by `RootTabView` (or `ContentView` becomes a thin wrapper that returns `RootTabView`).

**`LensIOS/LensApp.swift`** — adds `TimelineState` instantiation and environment injection:
```swift
@State private var timelineState = TimelineState()
// …
WindowGroup { RootTabView().environment(timelineState) }
```

**`LensMac/ContentView.swift`** — replaced by `RootSplitView`, same `TimelineState` wiring.

**`LensMac/LensMacApp.swift`** — adds macOS `Commands` block for the `?` keyboard shortcut reference and any `WindowGroup` configuration (min size, title).

---

## 12. Foundations for future phases

| Phase | What Phase 3 provides |
|-------|----------------------|
| 4 — Reader | `NavigationStack` wired; `.itemDisplayed` event; `ReaderStubView` to replace |
| 5 — Feeds | Feeds tab/sidebar item exists; `filterMode` handles `.category` and `.feed` |
| 6 — Offline save | Swipe save action wired and emitting events; `savedOfflineState` field in model |
| 7 — Settings | Settings tab exists; `accentColorHex` field present and read by row views |

---

## 13. Out of scope (explicitly deferred)

- Feed add/edit/delete UI
- Real offline save pipeline
- Settings UI and onboarding
- WKWebView reader
- Background fetch scheduling
- App icon badge updates
- Per-feed refresh intervals
- Duplicate detection
- Search
