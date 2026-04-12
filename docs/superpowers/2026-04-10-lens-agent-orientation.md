# Lens — Agent orientation

**Status:** Active  
**Last updated:** 2026-04-12  
**Audience:** Coding agents receiving a phase plan for this project

---

## What this project is

Lens is a native RSS/Atom/JSON Feed reader for iOS and macOS, built with SwiftUI and SwiftData. It aggregates subscribed feeds into a single chronological timeline. The full product spec is in [`specs/2026-04-09-lens-design.md`](./specs/2026-04-09-lens-design.md) — treat it as the source of truth for every product decision. Do not invent behaviour the spec does not describe.

---

## Current state

**Phase 2 complete. Phase 3 complete.**

| Target | Type | Source folder |
|--------|------|---------------|
| `LensIOS` | iOS App | `LensIOS/` |
| `LensMac` | macOS App | `LensMac/` |
| `LensCore` | iOS + macOS Framework | `LensCore/` |
| `LensUI` | iOS + macOS Framework | `LensUI/` |

**LensCore modules built so far:**

| Module | Files | Status |
|--------|-------|--------|
| `Models/` | `Feed.swift`, `FeedItem.swift`, `Category.swift`, `OfflineAsset.swift`, `UserReadingPreferences.swift`, `UserInterfacePreferences.swift` | Phase 2A ✓ |
| `Persistence/` | `PersistenceController.swift`, `CategorySeeder.swift`, `PreferenceStore.swift` | Phase 2A ✓ |
| `Events/` | `LensEvent.swift`, `EventBus.swift` | Phase 2B ✓ |
| `Feeds/` | `ParsedFeed.swift`, `FeedParser.swift`, `RSSParser.swift`, `AtomParser.swift`, `JSONFeedParser.swift`, `FeedFactory.swift`, `FeedService.swift` | Phase 2C ✓ |
| `Addons/` | `AddonManifest.swift`, `AddonRecord.swift`, `AddonError.swift`, `AddonRegistry.swift`, `AddonInstaller.swift` (macOS only) | Phase 2D ✓ |
| `Theme/` | `BuiltInTheme.swift`, `TokenLayer.swift`, `ThemeEngine.swift` | Phase 2E ✓ |
| `Routing/` | `LensRoute.swift`, `DeepLinkRouter.swift` | Phase 2E ✓ |

**App Group** `group.com.richardtape.lens` wired in Phase 2A.

**FeedService** is an actor in `LensCore/Feeds/FeedService.swift`. Call `fetchFeed(feedId:)` to
trigger a fetch → parse → persist → event-emit cycle. No background scheduling yet (Phase 5).

**Addon system (Phase 2D):**
- `AddonRegistry.shared` — in-memory actor registry; cross-platform.
- `AddonInstaller.shared` — macOS-only; `install(from:expectedSHA256:)` runs the full pipeline.
- Reference addon at `docs/reference-addon/` (Lens Dark Pro theme).
- Two `LensEvent` cases: `.addonInstalled(addonId:)`, `.addonInstallFailed(addonId:error:)`.

**ThemeEngine (Phase 2E):**
- `ThemeEngine.composedCSS(preferences:themeCSS:)` — joins three layers; no WKWebView yet.
- `TokenLayer` — generates `--lens-*` CSS custom properties; names are public addon contract.
- `BuiltInTheme` — structural CSS (layer 1) + default theme CSS (layer 3) constants.

**DeepLinkRouter (Phase 2E):**
- `DeepLinkRouter.route(from:)` — parses `lens://` URLs → `LensRoute` enum.
- `DeepLinkRouter.handle(_:bus:)` — emits navigation events on EventBus.
- `lens://` URL scheme must be registered in both iOS and macOS Xcode targets (Info tab → URL Types).
- Six new `LensEvent` cases: `.navigateToAddFeed`, `.navigateToFeed`, `.navigateToItem`, `.navigateToSaved`, `.navigateToSettings`, `.navigateToOPMLImport`.

**Phase 3 — All tasks completed:**

| Task | File(s) | Status |
|------|---------|--------|
| 1 | `LensCore/Models/UserReadingPreferences.swift` — `accentColorHex` field + test | ✓ |
| 2 | `LensUITests/` Xcode target (created by human driver) | ✓ |
| 3 | `LensUI/Components/AccentColorKey.swift` + `LensUITests/ColorHexTests.swift` | ✓ |
| 4 | `LensUI/Components/MonogramView.swift` | ✓ |
| 5 | `LensUI/Shell/StubDestinationView.swift` + `LensUI/Timeline/ReaderStubView.swift` | ✓ |
| 6 | `LensUI/Timeline/TimelineFilter.swift` + `LensUITests/TimelineFilterTests.swift` | ✓ |
| 7 | `LensUI/Timeline/TimelineState.swift` + `LensUITests/TimelineStateTests.swift` | ✓ |
| 8 | `LensUI/Timeline/ArticleRowView.swift` | ✓ |
| 9 | `LensUI/Timeline/FilterSheetView.swift` | ✓ |
| 10 | `LensUI/Timeline/NewItemsBannerView.swift` | ✓ |
| 11 | `LensUI/Timeline/TimelineView.swift` (incl. `.itemDisplayed` fix) | ✓ |
| 12 | `LensUI/Shell/RootTabView.swift` | ✓ |
| 13 | `LensUI/Shell/RootSplitView.swift` | ✓ |
| 14 | `LensIOS/LensApp.swift` + `LensIOS/ContentView.swift` — TimelineState injected, RootTabView | ✓ |
| 15 | `LensMac/LensMacApp.swift` + `LensMac/ContentView.swift` — TimelineState injected, RootSplitView, Commands | ✓ |

**Next:** Phase 4 (WKWebView reader engine).

**Implementation notes for future agents:**
- `RetentionPolicy` (enum with associated value) cannot be stored directly as a SwiftData `@Model` property — SwiftData corrupts it on mutation. It is backed by `_retentionPolicyDays: Int?` with a computed `retentionPolicy` accessor.
- `Category` conflicts with an ObjC runtime type when `Foundation` is imported. **Always use `LensCore.Category` fully-qualified** in SwiftUI files — do NOT use a `typealias`. The typealias approach breaks `@Query` macro expansion.
- `@Query` with a sort key path on a cross-module `@Model` type (e.g. `\LensCore.Category.sortOrder`) triggers fileprivate backing storage conflicts. Use `@Query var items: [T]` with no sort arg and sort in-view instead.
- `.buttonStyle(condition ? .glassProminent : .glass)` does not compile — the two are different concrete types. Use `if/else` with separate `.buttonStyle()` modifiers on each branch.
- `.tabBarMinimizeBehavior(.onScrollDown)` is iOS-only — guard with `#if os(iOS)`.
- `RootSplitView` (and any view using `List(selection:)`) must be wrapped in `#if os(macOS)`.
- `Color(.systemGroupedBackground)` is iOS-only — use `#if os(iOS)` / `#else Color(.windowBackgroundColor)` in cross-platform previews.
- `@Attribute(.unique)` in SwiftData performs an upsert, not a throw — tests reflect this.
- All source directories use `PBXFileSystemSynchronizedRootGroup` — files placed on disk are automatically included in their target. No "Add Files" step needed in Xcode.
- The `LensCoreTests` scheme lives in `Lens.xcodeproj/xcshareddata/xcschemes/LensCoreTests.xcscheme` (created manually; not auto-generated by Xcode for test bundle targets).

**Phase 3 implementation notes (for Phase 4 agents):**
- `TimelineState` is `@MainActor` `@Observable`. Inject via `.environment(timelineState)` at the root; read with `@Environment(TimelineState.self)` in descendant views.
- `@Query` with dynamic predicates: use the parent/child split pattern from `TimelineView.swift`. The inner view (`TimelineContentView`) takes filter params as `let` constants (not bindings), which causes SwiftUI to reinit it (and thus rebuild the `@Query`) when params change.
- Category filter in `TimelineFilter` cannot be expressed as a SwiftData `#Predicate` because `FeedItem` stores only `feedId`, not `categoryId`. Use `TimelineFilter.fetchDescriptor` for all/feed/unread cases; apply category membership in-memory in `displayedItems`.
- Accent color is set via `.tint()` on root views AND `.environment(\.lensAccentColor, ...)`. Standard controls (buttons, toggles) pick up `.tint`; custom shapes (accent bar, monogram background) read `@Environment(\.lensAccentColor)`.
- `ReaderStubView` is the Phase 4 replacement target — it already receives `FeedItem?` and is wired into both the iOS `NavigationStack` (via `.navigationDestination`) and the macOS detail column.
- macOS `?` keyboard shortcut uses `FocusedValues.showKeyboardShortcuts` — the Commands block in `LensMacApp.swift` reads it; `RootSplitView` provides it via `.focusedSceneValue`.

---

## Module layout

The project uses a multi-target structure. All new code goes in the **lowest** layer that can own it.

```
Lens.xcodeproj
├── LensCore/               # iOS + macOS framework target
│   ├── LensCore.swift      # Xcode stub — do not delete
│   ├── Models/             # SwiftData entities (Feed, FeedItem, Category, …)
│   ├── Persistence/        # ModelContainer setup, App Group config
│   ├── Feeds/              # Fetch pipeline, parsers, feed factory
│   ├── Events/             # Event bus types and EventBus actor
│   ├── Theme/              # ThemeEngine, CSS composition
│   └── Routing/            # DeepLinkRouter
├── LensCoreTests/          # Unit tests for LensCore (populated from Phase 2)
├── LensUI/                 # iOS + macOS framework; shared SwiftUI views
│   ├── LensUI.swift        # framework stub
│   ├── Components/         # AccentColorKey.swift, MonogramView.swift
│   ├── Shell/              # RootTabView (iOS), RootSplitView (Mac), StubDestinationView
│   └── Timeline/           # TimelineView, TimelineState, ArticleRowView, filters, banner, stubs
├── LensUITests/            # Unit tests for LensUI (target created by human driver — Task 2)
├── LensIOS/                # iOS app entry, scene lifecycle, tab bar
└── LensMac/                # macOS app entry, menus, window management
```

Rule: `LensCore` has no SwiftUI imports. `LensIOS`/`LensMac` are thin shells — scenes, app lifecycle, platform-specific wiring only.

---

## Locked decisions — do not revisit

| Decision | Detail |
|----------|--------|
| **Minimum deployment** | iOS 26, macOS 26 — use modern APIs freely |
| **Persistence** | SwiftData only. `ModelContainer` initialized from the App Group container (`group.com.richardtape.lens`), never the default private container |
| **Dependency management** | SPM only — no CocoaPods, no Carthage |
| **Reader engine** | `WKWebView` with sanitized HTML + `ThemeEngine`-injected CSS; no raw `eval` |
| **Concurrency** | `async`/`await` and Swift structured concurrency; no blocking the main thread for network or parsing |
| **SwiftUI data flow** | `@Observable`, `@Bindable`, `@Query` — not the legacy `ObservableObject`/`@Published` stack |
| **Event bus** | Every substantive side effect emits or consumes a typed event; direct cross-module calls for side effects are not acceptable |
| **"Afforded" fields** | Fields marked *(afforded; not active in v1)* in the spec must be present in the SwiftData model from day one but must not be read, written, or surfaced in UI |

---

## Event bus — pattern to follow

`EventBus` is a Swift actor in `LensCore/Events/EventBus.swift`.
`LensEvent` (all cases) is in `LensCore/Events/LensEvent.swift`.

**Emit an event:**
```swift
await EventBus.shared.emit(.feedFetchStarted(feedId: feed.id))
```

**Subscribe (in a view model or app-layer coordinator):**
```swift
let task = Task {
    for await event in await EventBus.shared.makeStream() {
        switch event {
        case .feedFetchCompleted(let feedId, let count):
            // handle
        default:
            break
        }
    }
}
// Cancel task when observer is deallocated.
```

**In unit tests:** create `EventBus()` (not `.shared`) to keep tests isolated.

Every event name and payload is part of the public addon API (spec §3.7).
Do not rename cases without a versioning notice in the event catalog.

---

## SwiftData model conventions

- All entity types are in `LensCore/Models/`.
- The `ModelContainer` is configured once, in `LensCore/Persistence/`, using the App Group URL. App targets call this setup; they do not configure the container themselves.
- Singleton preference records (`UserReadingPreferences`, `UserInterfacePreferences`) are fetched with a `#Predicate` that always returns the single row; create it on first launch if absent.
- For "afforded" fields: add the property, do not write any code that reads or sets it (other than default-initialisation), and add an inline comment: `// afforded: active in v2`.

---

## Agent / human driver split

| You (agent) | Human driver (Xcode) |
|-------------|----------------------|
| Write and edit Swift, SwiftUI, SPM manifests, project file entries, documentation | Build (⌘B), Run (⌘R), manage signing, test on device/simulator |
| Cannot invoke the compiler or run the app | Owns all verification against a running build |

**Schemes:** `LensIOS` (iOS Simulator + device), `LensMac` (My Mac).

**When you need a build check:** give the human driver exact instructions:

> **In Xcode:** Select scheme `LensIOS`, destination `iPhone 16 Pro Simulator` (or similar), then ⌘B. Paste any errors here (full message + file:line). For Mac: scheme `LensMac`, destination `My Mac`.

Always ask for the *full* compiler error text — "it doesn't compile" is not actionable.

---

## Style rules (condensed)

Full rules: [`2026-04-10-lens-code-rules-for-agents.md`](./2026-04-10-lens-code-rules-for-agents.md)

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) naming.
- `enum` for finite states, `struct` for value types, protocols where abstraction genuinely pays off.
- Comment the *why*, not the what. `// MARK: -` to section larger files. `///` DocC comments on all `public` APIs in `LensCore`.
- Do not add code, fields, or settings outside the current phase plan — the spec has intentional deferments.
- Small, reviewable diffs. No drive-by refactors.

---

## Keeping this document current

**This file is the first thing the next agent reads.** Every phase plan must end with a step to update it:

- **Current state** — describe what now exists (targets created, modules present, key files)
- **Module layout** — add any directories that were created but aren't listed yet
- **Agent / human driver split** — fill in actual scheme names once the Xcode project exists

Do not leave this file describing a state that no longer matches the repo.

---

## Key documents

| Document | Purpose |
|----------|---------|
| [`specs/2026-04-09-lens-design.md`](./specs/2026-04-09-lens-design.md) | **Product truth** — features, data model, product decisions |
| [`specs/2026-04-10-lens-build-phases.md`](./specs/2026-04-10-lens-build-phases.md) | **Build roadmap** — canonical Phases 0–9 and where post–v1 work is listed |
| [`specs/2026-04-10-lens-build-strategy.md`](./specs/2026-04-10-lens-build-strategy.md) | Xcode workflow, signing, SPM — primarily for the human driver |
| [`2026-04-10-lens-code-rules-for-agents.md`](./2026-04-10-lens-code-rules-for-agents.md) | Expanded style and architecture rules |
| Per-session phase plan | The slice you are implementing now (must map to the build roadmap above) |
| **`/Users/rich/Developer/apple-os-documentation`** | **Local clone of Apple developer docs + HIG in markdown.** Grep it first before fetching apple.com. Key dirs: `liquid-glass/`, `human-interface-guidelines/components/`, `human-interface-guidelines/foundations/`, `documentation/`. Use `grep -r -l "keyword" /Users/rich/Developer/apple-os-documentation/` to find relevant files, then read only what you need. |
