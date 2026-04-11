# Lens Phase 2B — Event Bus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `LensEvent` enum and `EventBus` actor in `LensCore/Events/`, establishing the typed event backbone that all subsequent phases (feed pipeline, addon system, engine scaffolding) depend on.

**Architecture:** `LensEvent` is a `Sendable`, `Equatable` enum listing every substantive domain event described in spec §3.7. `EventBus` is a Swift actor with a `shared` singleton; it distributes events to subscribers via `AsyncStream<LensEvent>`. Each subscriber calls `makeStream()` and drives its own consuming `Task`. Because `EventBus` is an actor, `emit(_:)` is safe to call from any concurrency context. No SwiftUI imports anywhere in this module — `LensCore` rule.

**Tech Stack:** Swift 6, Swift concurrency (`actor`, `async`/`await`, `AsyncStream`), Swift Testing (`@Test` / `#expect`), Xcode 26.3.

---

## Driver legend

- **(Agent)** — agent writes files; no Xcode interaction needed.
- **(Human)** — requires Xcode GUI.
- **(Both)** — agent produces content, human runs a command.

---

## File structure

```
LensCore/Events/
├── LensEvent.swift           (Create) LensEvent enum + FeedHealthStatus enum
└── EventBus.swift            (Create) EventBus actor with shared instance

LensCoreTests/Events/
├── LensEventTests.swift      (Create) Enum case coverage + Equatable smoke tests
└── EventBusTests.swift       (Create) Emit / subscribe integration tests
```

> **Xcode note:** Files written to disk are not visible in Xcode until you add them manually. Each Human step below tells you exactly when and how to add new files.

> **`.gitkeep` cleanup:** `LensCore/Events/` currently contains a `.gitkeep` placeholder from Phase 0. When you add the new Swift files to Xcode in Task 2, also delete the `.gitkeep` from both disk and the Xcode group.

---

## Task 1: Write LensEvent.swift

**(Agent)**

**Files:**
- Create: `LensCore/Events/LensEvent.swift`

- [ ] **Step 1: Write LensEvent.swift**

Create `/Users/rich/Developer/lens/LensCore/Events/LensEvent.swift`:

```swift
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
}
```

---

## Task 2: Write LensEventTests.swift and add files to Xcode

**(Agent then Human)**

**Files:**
- Create: `LensCoreTests/Events/LensEventTests.swift`

- [ ] **Step 1: Write LensEventTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Events/LensEventTests.swift`:

```swift
// LensEventTests.swift — Smoke tests confirming all LensEvent cases are
// constructable, pattern-matchable, and Equatable-comparable.
//
// These tests guard against future refactors accidentally breaking the
// public addon API surface (spec §3.7).
import Testing
import Foundation
@testable import LensCore

@Suite("LensEvent")
struct LensEventTests {

    // MARK: - Equatable

    @Test("Identical events compare equal")
    func equatableIdentical() {
        let id = UUID()
        #expect(LensEvent.feedFetchStarted(feedId: id) == LensEvent.feedFetchStarted(feedId: id))
        #expect(LensEvent.userInitiatedRefresh == LensEvent.userInitiatedRefresh)
        #expect(LensEvent.appLaunched == LensEvent.appLaunched)
    }

    @Test("Events with different associated values are not equal")
    func equatableDifferentValues() {
        let a = UUID()
        let b = UUID()
        #expect(LensEvent.feedFetchStarted(feedId: a) != LensEvent.feedFetchStarted(feedId: b))
        #expect(LensEvent.feedFetchCompleted(feedId: a, newItemCount: 1)
                != LensEvent.feedFetchCompleted(feedId: a, newItemCount: 2))
    }

    @Test("Different event cases are not equal")
    func equatableDifferentCases() {
        #expect(LensEvent.appLaunched != LensEvent.userInitiatedRefresh)
        #expect(LensEvent.backgroundRefreshStarted != LensEvent.backgroundRefreshCompleted(newItemCount: 0))
    }

    // MARK: - Pattern matching (all cases exercised)

    @Test("All LensEvent cases are constructable and pattern-matchable")
    func allCasesRoundTrip() {
        let id1 = UUID()
        let id2 = UUID()
        let now = Date()
        let cases: [LensEvent] = [
            .appLaunched,
            .backgroundRefreshStarted,
            .backgroundRefreshCompleted(newItemCount: 3),
            .feedFetchStarted(feedId: id1),
            .feedFetchCompleted(feedId: id1, newItemCount: 5),
            .feedFetchFailed(feedId: id1, error: "timeout"),
            .feedHealthChanged(feedId: id1, status: .healthy),
            .feedHealthChanged(feedId: id1, status: .degraded(consecutiveFailures: 2)),
            .feedHealthChanged(feedId: id1, status: .unhealthy(error: "404", lastFetchedAt: now)),
            .feedHealthChanged(feedId: id1, status: .unhealthy(error: "404", lastFetchedAt: nil)),
            .userInitiatedRefresh,
            .userInitiatedFeedRefresh(feedId: id1),
            .itemParsed(itemId: id2, feedId: id1),
            .itemDisplayed(itemId: id2),
            .itemMarkedRead(itemId: id2),
            .itemMarkedUnread(itemId: id2),
            .itemStarred(itemId: id2),
            .itemUnstarred(itemId: id2),
            .itemSavedOffline(itemId: id2),
            .itemOfflineSaveRemoved(itemId: id2),
            .themeApplied(themeName: "default"),
        ]
        // Each case must equal itself — confirms Equatable and Sendable compile correctly.
        for event in cases {
            #expect(event == event)
        }
    }

    // MARK: - FeedHealthStatus

    @Test("FeedHealthStatus cases are Equatable")
    func feedHealthStatusEquatable() {
        let now = Date()
        #expect(FeedHealthStatus.healthy == .healthy)
        #expect(FeedHealthStatus.degraded(consecutiveFailures: 3) == .degraded(consecutiveFailures: 3))
        #expect(FeedHealthStatus.degraded(consecutiveFailures: 3) != .degraded(consecutiveFailures: 4))
        #expect(FeedHealthStatus.unhealthy(error: "404", lastFetchedAt: now)
                == .unhealthy(error: "404", lastFetchedAt: now))
        #expect(FeedHealthStatus.unhealthy(error: "404", lastFetchedAt: nil)
                != .unhealthy(error: "404", lastFetchedAt: now))
    }
}
```

- [ ] **Step 2: Add files to Xcode and run the tests** **(Human)**

1. In Xcode Project Navigator, right-click **LensCore/Events** group → **Add Files to "Lens"…**
2. Select `LensCore/Events/LensEvent.swift` → **Add** (Create groups, uncheck "Copy items if needed").
3. In the dialog, confirm the file is added to the **LensCore** target only.
4. Delete `LensCore/Events/.gitkeep` from the Xcode group (right-click → Delete → Move to Trash).
5. Right-click **LensCoreTests** group → **New Group** → name it `Events`.
6. Right-click the new **LensCoreTests/Events** group → **Add Files to "Lens"…**
7. Select `LensCoreTests/Events/LensEventTests.swift` → **Add**, adding to the **LensCoreTests** target.
8. Select the **LensCoreTests** scheme, destination **Any Mac** → **⌘U** to run tests.

Expected: **21 tests pass** (one per event + FeedHealthStatus checks). No failures.

If tests fail, paste the full error here.

---

## Task 3: Write EventBus.swift

**(Agent)**

**Files:**
- Create: `LensCore/Events/EventBus.swift`

- [ ] **Step 1: Write EventBus.swift**

Create `/Users/rich/Developer/lens/LensCore/Events/EventBus.swift`:

```swift
// EventBus.swift — Central event dispatch for LensCore.
//
// EventBus is a Swift actor, so `emit(_:)` is safe to call from any
// concurrency context (main actor, background tasks, other actors).
//
// Subscription model: callers call `makeStream()` to get an
// AsyncStream<LensEvent>. Each call returns a fresh, independent stream
// that buffers events without bound (policy: .unbounded) until the
// consuming Task reads them. The caller owns the Task driving iteration
// and must cancel it (or let it go out of scope) when the observer is
// done — this automatically terminates the stream and removes it from
// the bus.
//
// Why AsyncStream: it integrates cleanly with structured concurrency
// (for-await loops, task cancellation) and requires no additional
// dependencies. The unbounded buffer ensures that brief bursts of events
// (e.g. bulk item inserts) are not dropped.
import Foundation

public actor EventBus {

    // MARK: - Shared instance

    /// App-wide shared bus. Inject a fresh `EventBus()` in unit tests
    /// to keep test runs isolated from each other.
    public static let shared = EventBus()

    // MARK: - Private state

    /// Keyed by a per-subscriber UUID so each stream can be individually removed
    /// without the caller needing to hold a reference to the continuation itself.
    private var continuations: [UUID: AsyncStream<LensEvent>.Continuation] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Subscribe

    /// Returns an `AsyncStream` that delivers every event emitted to this bus
    /// until the consuming Task is cancelled or the continuation is terminated.
    ///
    /// Typical usage in a view model or app-layer coordinator:
    /// ```swift
    /// let task = Task {
    ///     for await event in await EventBus.shared.makeStream() {
    ///         handle(event)
    ///     }
    /// }
    /// // Later, when the observer is done:
    /// task.cancel()
    /// ```
    public func makeStream() -> AsyncStream<LensEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LensEvent>.makeStream()
        continuations[id] = continuation
        // onTermination fires when the consuming Task is cancelled or the
        // continuation is explicitly finished. Dispatch removal back onto the
        // actor to keep `continuations` mutation actor-isolated.
        continuation.onTermination = { [id] _ in
            Task { [weak self] in
                await self?.removeContinuation(id: id)
            }
        }
        return stream
    }

    // MARK: - Publish

    /// Broadcast `event` to every active subscriber.
    ///
    /// Safe to call from any concurrency context; actor isolation serialises
    /// the yield calls so subscribers always see events in emission order.
    public func emit(_ event: LensEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    // MARK: - Private

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
```

---

## Task 4: Write EventBusTests.swift and add files to Xcode

**(Agent then Human)**

**Files:**
- Create: `LensCoreTests/Events/EventBusTests.swift`

- [ ] **Step 1: Write EventBusTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Events/EventBusTests.swift`:

```swift
// EventBusTests.swift — Integration tests for EventBus emit/subscribe behaviour.
//
// Each test creates its own EventBus() instance to avoid shared state.
// Tests are async because EventBus is an actor and AsyncStream is consumed
// with `for await`.
import Testing
import Foundation
@testable import LensCore

@Suite("EventBus")
struct EventBusTests {

    // MARK: - Single subscriber

    @Test("Emitted event is received by a single subscriber")
    func singleSubscriberReceivesEvent() async {
        let bus = EventBus()
        let stream = await bus.makeStream()

        await bus.emit(.userInitiatedRefresh)

        var received: LensEvent? = nil
        for await event in stream {
            received = event
            break
        }

        #expect(received == .userInitiatedRefresh)
    }

    @Test("Subscriber receives events in emission order")
    func eventsDeliveredInOrder() async {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let id = UUID()

        await bus.emit(.feedFetchStarted(feedId: id))
        await bus.emit(.feedFetchCompleted(feedId: id, newItemCount: 3))

        var received: [LensEvent] = []
        for await event in stream {
            received.append(event)
            if received.count == 2 { break }
        }

        #expect(received == [
            .feedFetchStarted(feedId: id),
            .feedFetchCompleted(feedId: id, newItemCount: 3),
        ])
    }

    // MARK: - Multiple subscribers

    @Test("All active subscribers receive each emitted event")
    func multipleSubscribersAllReceive() async {
        let bus = EventBus()
        let stream1 = await bus.makeStream()
        let stream2 = await bus.makeStream()

        await bus.emit(.appLaunched)

        var received1: LensEvent? = nil
        var received2: LensEvent? = nil

        for await event in stream1 { received1 = event; break }
        for await event in stream2 { received2 = event; break }

        #expect(received1 == .appLaunched)
        #expect(received2 == .appLaunched)
    }

    // MARK: - Cancellation / cleanup

    @Test("Cancelled task stops receiving events and is removed from the bus")
    func cancelledSubscriberRemoved() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()

        // Drive the stream in a task we will cancel immediately.
        let consumerTask = Task {
            for await _ in stream { }
        }
        consumerTask.cancel()

        // Give the actor a moment to process the termination callback.
        // We yield the current task a few times; no fixed sleep needed.
        for _ in 0..<10 {
            await Task.yield()
        }

        // After cancellation, emitting should not crash or hang.
        // (The removed continuation no longer receives yields.)
        await bus.emit(.userInitiatedRefresh)
        // No assertion needed — success is reaching this line without hanging.
    }

    // MARK: - shared instance

    @Test("EventBus.shared is non-nil and usable")
    func sharedInstanceUsable() async {
        // Just confirms the singleton compiles and the actor is reachable.
        // We do NOT emit events on the shared instance to avoid polluting
        // any other test that might share the process's shared bus.
        let bus = EventBus.shared
        #expect(bus !== nil as AnyObject?)
    }
}
```

- [ ] **Step 2: Add EventBus.swift to Xcode** **(Human)**

1. In Xcode Project Navigator, right-click **LensCore/Events** group → **Add Files to "Lens"…**
2. Select `LensCore/Events/EventBus.swift` → **Add**, adding to the **LensCore** target only.

- [ ] **Step 3: Add EventBusTests.swift to Xcode** **(Human)**

1. Right-click **LensCoreTests/Events** group → **Add Files to "Lens"…**
2. Select `LensCoreTests/Events/EventBusTests.swift` → **Add**, adding to **LensCoreTests** target.

- [ ] **Step 4: Run all LensCore tests** **(Human)**

Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected:
- All Phase 2A tests still pass.
- All `LensEventTests` pass (from Task 2).
- All `EventBusTests` pass.

If any test fails, paste the full error text here (include file:line).

---

## Task 5: Update agent-orientation.md

**(Agent)**

**Files:**
- Modify: `docs/superpowers/2026-04-10-lens-agent-orientation.md`

- [ ] **Step 1: Update the Current state section**

Replace the existing `## Current state` block with:

```markdown
## Current state

**Phase 2A complete; Phase 2B complete.**

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
| `Feeds/` | *(empty — Phase 2C)* | — |
| `Theme/` | *(empty — Phase 2E)* | — |
| `Routing/` | *(empty — Phase 2E)* | — |

**App Group** `group.com.richardtape.lens` wired in Phase 2A.

**Next:** Phase 2C (feed pipeline — RSS/Atom/JSON Feed parsers + feed factory).
```

- [ ] **Step 2: Update the Event bus section**

Replace the existing `## Event bus — pattern to follow` block with:

```markdown
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
```

---

## Task 6: Commit

**(Human)**

- [ ] **Step 1: Stage and commit**

```bash
cd /Users/rich/Developer/lens
git add \
  LensCore/Events/LensEvent.swift \
  LensCore/Events/EventBus.swift \
  LensCoreTests/Events/LensEventTests.swift \
  LensCoreTests/Events/EventBusTests.swift \
  docs/superpowers/2026-04-10-lens-agent-orientation.md \
  Lens.xcodeproj/project.pbxproj
git status
git commit -m "feat(phase-2b): EventBus actor + LensEvent enum"
```

Expected: commit succeeds with those files listed.

---

## Phase 2B exit criteria

Before declaring Phase 2B done:

- [ ] `LensCore/Events/LensEvent.swift` exists and defines all enum cases from spec §3.7.
- [ ] `LensCore/Events/EventBus.swift` exists; `EventBus` is an actor with `shared`, `makeStream()`, and `emit(_:)`.
- [ ] All `LensEventTests` pass (21 cases — enum + FeedHealthStatus Equatable checks).
- [ ] All `EventBusTests` pass (5 tests — single subscriber, ordering, multiple subscribers, cancellation, shared instance).
- [ ] All Phase 2A tests still pass.
- [ ] `agent-orientation.md` **Current state** section reflects Phase 2B completion.
- [ ] Changes committed.

---

## What's next

**Phase 2C** — Feed pipeline:
- RSS 2.0 / RDF, Atom 1.0, and JSON Feed 1.1 parsers.
- Extensible `FeedFactory` that selects a parser by MIME type / URL hint / content sniffing.
- Parsers produce `FeedItem` values that are inserted into the SwiftData store.
- Depends on: Phase 2A models, Phase 2B event bus (parsers emit `itemParsed` events).
