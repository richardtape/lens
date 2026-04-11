# Lens — Agent orientation

**Status:** Active  
**Last updated:** 2026-04-10  
**Audience:** Coding agents receiving a phase plan for this project

---

## What this project is

Lens is a native RSS/Atom/JSON Feed reader for iOS and macOS, built with SwiftUI and SwiftData. It aggregates subscribed feeds into a single chronological timeline. The full product spec is in [`specs/2026-04-09-lens-design.md`](./specs/2026-04-09-lens-design.md) — treat it as the source of truth for every product decision. Do not invent behaviour the spec does not describe.

---

## Current state

**Phase 1 complete.** All three destinations build and run cleanly:

| Destination | Scheme | Verified |
|-------------|--------|---------|
| iOS Simulator (iPhone 16 Pro) | LensIOS | ✓ |
| Physical iPhone | LensIOS | ✓ |
| macOS (My Mac) | LensMac | ✓ |

`LensCoreTests` builds and runs 0 tests (correct for Phase 1).

**Project structure:**

| Target | Type | Source folder | Deployment target |
|--------|------|---------------|-------------------|
| `LensIOS` | iOS App | `LensIOS/` | iOS 26.0 |
| `LensMac` | macOS App | `LensMac/` | macOS 26.0 |
| `LensCore` | iOS + macOS Framework | `LensCore/` | iOS 26.0 / macOS 26.0 |
| `LensUI` | iOS + macOS Framework | `LensUI/` | iOS 26.0 / macOS 26.0 |
| `LensCoreTests` | Unit Test (LensCore) | `LensCoreTests/` | iOS 26.0 |

`LensCore/` subdirectory scaffold: `Models/`, `Persistence/`, `Feeds/`, `Events/`, `Theme/`, `Routing/` — each with `.gitkeep`. The `.gitkeep` files must **not** appear in any target's Copy Bundle Resources build phase.

**App Group** `group.com.richardtape.lens` is documented; Xcode capability wired in Phase 2.

**Next:** Phase 2 — LensCore foundation (SwiftData, event bus, addon registry, minimal feed fetch).

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

The event bus is the backbone of cross-module communication. When in doubt, emit an event rather than calling across layers directly.

```swift
// Define event types in LensCore/Events/
enum LensEvent {
    case feedFetchStarted(feedId: UUID)
    case feedFetchCompleted(feedId: UUID, newItemCount: Int)
    case feedHealthChanged(feedId: UUID, status: FeedHealthStatus)
    case itemMarkedRead(itemId: UUID)
    // …
}

// EventBus lives in LensCore; subscribers attach in LensUI / app targets
```

Every event name and payload is part of the public addon API (see spec §3.7). Use clear, descriptive names — they cannot be renamed later without a versioning notice.

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
