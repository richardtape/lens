# Lens Phase 2A — Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define every SwiftData entity the spec requires, configure the App Group–backed `ModelContainer`, seed predefined categories on first launch, and verify it all with unit tests — leaving LensCore with a stable, tested data layer ready for Phase 2B (event bus) and Phase 2C (feed pipeline).

**Architecture:** All entities and persistence logic live in `LensCore` (no SwiftUI imports). `@Model` classes go in `LensCore/Models/`; the container factory, seeder, and preference helpers go in `LensCore/Persistence/`. App targets (`LensIOS`, `LensMac`) import `LensCore` and call `PersistenceController.makeModelContainer()` in their `App.init()`; they do not configure the container themselves. Unit tests use an in-memory container via a `DEBUG`-gated factory — this avoids the App Group entitlement requirement during testing.

**Tech Stack:** Swift 6, SwiftData (iOS 26 / macOS 26), Swift Testing framework (`@Test` / `#expect`), Xcode 26.3.

---

## File structure

```
LensCore/Models/
├── Feed.swift                      (Create) @Model Feed entity
├── FeedItem.swift                  (Create) @Model FeedItem entity + SavedState enum
├── Category.swift                  (Create) @Model Category entity
├── OfflineAsset.swift              (Create) @Model OfflineAsset entity
├── UserReadingPreferences.swift    (Create) @Model + AppearanceOverride + LinkBehavior enums
└── UserInterfacePreferences.swift  (Create) @Model + FeedSortOrder + RetentionPolicy enums

LensCore/Persistence/
├── PersistenceController.swift     (Create) ModelContainer factory + PersistenceError
├── CategorySeeder.swift            (Create) Seeds predefined categories on first launch
└── PreferenceStore.swift           (Create) Singleton-row accessors for preference records

LensIOS/LensApp.swift               (Modify) Add ModelContainer creation + category seeding
LensMac/LensMacApp.swift            (Modify) Add ModelContainer creation + category seeding

LensCoreTests/Models/
├── FeedTests.swift                 (Create)
├── FeedItemTests.swift             (Create)
├── UserReadingPreferencesTests.swift (Create)
└── UserInterfacePreferencesTests.swift (Create)

LensCoreTests/Persistence/
├── CategorySeederTests.swift       (Create)
└── PreferenceStoreTests.swift      (Create)
```

> **Xcode note:** New files created on disk are not automatically added to the Xcode project. After each agent batch, a human step instructs you to add them via **File → Add Files to "Lens"…** before running tests.

---

## Task 1: Write the Feed entity

**(Agent)**

**Files:**
- Create: `LensCore/Models/Feed.swift`
- Create: `LensCoreTests/Models/FeedTests.swift`

- [ ] **Step 1: Write Feed.swift**

```swift
// Feed.swift — SwiftData entity representing a subscribed RSS/Atom/JSON feed.
//
// categoryId uses a plain UUID foreign key (not a SwiftData relationship) per
// the product spec's data model. This keeps cross-entity queries simple and
// avoids cascade-delete complexity in Phase 2A.
import SwiftData
import Foundation

@Model
public final class Feed {
    // @Attribute(.unique) prevents inserting the same feed URL twice.
    // SwiftData throws if a duplicate is attempted — the caller must handle this.
    @Attribute(.unique) public var url: URL
    public var id: UUID
    public var displayName: String
    public var categoryId: UUID?
    public var iconRef: String?
    public var createdAt: Date
    public var lastFetchedAt: Date?
    public var lastFetchError: String?
    public var consecutiveFailureCount: Int
    // afforded: active in v2 — per-feed refresh override
    public var refreshInterval: TimeInterval?

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        categoryId: UUID? = nil,
        iconRef: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.categoryId = categoryId
        self.iconRef = iconRef
        self.createdAt = createdAt
        self.lastFetchedAt = nil
        self.lastFetchError = nil
        self.consecutiveFailureCount = 0
        self.refreshInterval = nil // afforded: active in v2
    }
}
```

- [ ] **Step 2: Write FeedTests.swift**

```swift
// FeedTests.swift — unit tests for the Feed SwiftData model.
import Testing
import SwiftData
@testable import LensCore

@Suite("Feed model")
struct FeedTests {

    @Test("default values are correct")
    func defaultValues() {
        let feed = Feed(url: URL(string: "https://example.com/feed.xml")!,
                        displayName: "Example")

        #expect(feed.consecutiveFailureCount == 0)
        #expect(feed.lastFetchedAt == nil)
        #expect(feed.lastFetchError == nil)
        #expect(feed.categoryId == nil)
        #expect(feed.iconRef == nil)
        #expect(feed.refreshInterval == nil) // afforded field: nil by default
    }

    @Test("inserts and fetches via in-memory SwiftData container")
    func persistAndFetch() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        // Use ModelContext(container) rather than container.mainContext:
        // mainContext is @MainActor-bound; ModelContext(container) is actor-agnostic
        // and safe to use from unspecified Swift Testing isolation contexts.
        let context = ModelContext(container)

        let url = URL(string: "https://example.com/feed.xml")!
        context.insert(Feed(url: url, displayName: "Example Feed"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Feed>())
        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Example Feed")
        #expect(fetched[0].url == url)
    }

    @Test("inserting duplicate URL throws")
    func duplicateURLThrows() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        let url = URL(string: "https://example.com/feed.xml")!

        context.insert(Feed(url: url, displayName: "First"))
        try context.save()

        context.insert(Feed(url: url, displayName: "Duplicate"))
        #expect(throws: (any Error).self) {
            try context.save()
        }
    }
}
```

---

## Task 2: Write the FeedItem entity

**(Agent)**

**Files:**
- Create: `LensCore/Models/FeedItem.swift`
- Create: `LensCoreTests/Models/FeedItemTests.swift`

- [ ] **Step 1: Write FeedItem.swift**

```swift
// FeedItem.swift — SwiftData entity for a single article/entry from a feed.
//
// Fields marked "afforded: active in vN" must be stored from day one but
// must not be read, written, or surfaced in UI until the stated version.
import SwiftData
import Foundation

/// The download / save-for-offline status of a feed item.
public enum SavedState: String, Codable, Sendable {
    case notSaved
    case saving
    case saved
    case error
}

@Model
public final class FeedItem {
    public var id: UUID
    /// UUID of the parent Feed. Plain FK — not a SwiftData relationship.
    public var feedId: UUID
    /// GUID from the feed, or a content hash if absent.
    /// Used for deduplication (Phase 4.7) and stable references.
    public var stableId: String
    public var title: String
    public var link: URL?
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var summaryHTML: String?
    public var contentHTML: String?
    public var isRead: Bool
    public var isStarred: Bool
    public var savedOfflineState: SavedState
    /// Escape hatch for feed-format-specific metadata not modelled above.
    public var rawMetadata: Data?
    // afforded: card view not active in v1
    public var thumbnailURL: URL?
    // afforded: not displayed in v1
    public var estimatedReadMinutes: Int?
    // afforded: not active in v1
    public var enclosureURL: URL?
    // afforded: not active in v1
    public var enclosureMIMEType: String?

    public init(
        id: UUID = UUID(),
        feedId: UUID,
        stableId: String,
        title: String,
        link: URL? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        summaryHTML: String? = nil,
        contentHTML: String? = nil
    ) {
        self.id = id
        self.feedId = feedId
        self.stableId = stableId
        self.title = title
        self.link = link
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.summaryHTML = summaryHTML
        self.contentHTML = contentHTML
        self.isRead = false
        self.isStarred = false
        self.savedOfflineState = .notSaved
        self.rawMetadata = nil
        self.thumbnailURL = nil       // afforded: card view not active in v1
        self.estimatedReadMinutes = nil // afforded: not displayed in v1
        self.enclosureURL = nil        // afforded: not active in v1
        self.enclosureMIMEType = nil   // afforded: not active in v1
    }
}
```

- [ ] **Step 2: Write FeedItemTests.swift**

```swift
// FeedItemTests.swift — unit tests for FeedItem and SavedState.
import Testing
import SwiftData
@testable import LensCore

@Suite("FeedItem model")
struct FeedItemTests {

    @Test("default values are correct")
    func defaultValues() {
        let item = FeedItem(feedId: UUID(), stableId: "abc123", title: "Test Article")

        #expect(item.isRead == false)
        #expect(item.isStarred == false)
        #expect(item.savedOfflineState == .notSaved)
        #expect(item.contentHTML == nil)
        #expect(item.summaryHTML == nil)
        // Verify afforded fields are nil — do not activate them
        #expect(item.thumbnailURL == nil)
        #expect(item.estimatedReadMinutes == nil)
        #expect(item.enclosureURL == nil)
        #expect(item.enclosureMIMEType == nil)
    }

    @Test("inserts and fetches via in-memory container")
    func persistAndFetch() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        let feedId = UUID()
        let item = FeedItem(feedId: feedId, stableId: "s1", title: "Hello SwiftData")
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<FeedItem>())
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Hello SwiftData")
        #expect(fetched[0].feedId == feedId)
    }

    @Test("SavedState round-trips through Codable")
    func savedStateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in [SavedState.notSaved, .saving, .saved, .error] {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(SavedState.self, from: data)
            #expect(decoded == state)
        }
    }
}
```

---

## Task 3: Write Category and OfflineAsset entities

**(Agent)**

These are simple container types with no logic to unit-test in isolation. They are exercised by `CategorySeederTests` in Task 8.

**Files:**
- Create: `LensCore/Models/Category.swift`
- Create: `LensCore/Models/OfflineAsset.swift`

- [ ] **Step 1: Write Category.swift**

```swift
// Category.swift — SwiftData entity for a feed category (predefined or custom).
//
// `isBuiltIn` distinguishes the ten predefined starter categories from user-created ones.
// The CategorySeeder uses this flag to avoid re-seeding on subsequent launches.
import SwiftData
import Foundation

@Model
public final class Category {
    public var id: UUID
    public var name: String
    /// Position in the sidebar category list.
    public var sortOrder: Int
    /// True for the ten predefined categories seeded on first launch.
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isBuiltIn: Bool
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }
}
```

- [ ] **Step 2: Write OfflineAsset.swift**

```swift
// OfflineAsset.swift — tracks a single file saved for offline reading.
//
// One FeedItem may have many OfflineAssets (its HTML body plus embedded images).
// itemId is a plain UUID foreign key to FeedItem — not a SwiftData relationship.
import SwiftData
import Foundation

@Model
public final class OfflineAsset {
    public var id: UUID
    /// UUID of the parent FeedItem.
    public var itemId: UUID
    /// Path in the app sandbox where the file is stored.
    public var localFileURL: URL
    /// Original remote URL (for cache validation / re-download).
    public var remoteURL: URL
    public var mimeType: String

    public init(
        id: UUID = UUID(),
        itemId: UUID,
        localFileURL: URL,
        remoteURL: URL,
        mimeType: String
    ) {
        self.id = id
        self.itemId = itemId
        self.localFileURL = localFileURL
        self.remoteURL = remoteURL
        self.mimeType = mimeType
    }
}
```

---

## Task 4: Write UserReadingPreferences entity

**(Agent)**

**Files:**
- Create: `LensCore/Models/UserReadingPreferences.swift`
- Create: `LensCoreTests/Models/UserReadingPreferencesTests.swift`

- [ ] **Step 1: Write UserReadingPreferences.swift**

```swift
// UserReadingPreferences.swift — singleton SwiftData record for reader settings.
//
// Fetched via PreferenceStore.readingPreferences(in:), which creates the row
// on first access. Never insert more than one row — all reads use a
// FetchDescriptor<UserReadingPreferences>() and take the first result.
//
// The CSS token contract (--lens-bg, --lens-text, etc.) is derived from
// these fields by ThemeEngine (Phase 2E). Token names are a versioned public
// API for addon authors — do not rename without a breaking-change notice.
import SwiftData
import Foundation

/// Controls the app's light/dark appearance independently of the system setting.
public enum AppearanceOverride: String, Codable, Sendable {
    case system
    case light
    case dark
}

/// Determines how tapped external links open.
public enum LinkBehavior: String, Codable, Sendable {
    case systemBrowser
    case inAppBrowser
}

@Model
public final class UserReadingPreferences {
    public var appearanceOverride: AppearanceOverride
    /// CSS font-family value fed into the --lens-font-family token.
    public var fontFamily: String
    /// Font size in points / px, fed into --lens-font-size.
    public var fontSize: Int
    /// Unitless line-height multiplier → --lens-line-height.
    public var lineHeight: Double
    /// Max content column width in px → --lens-content-width.
    public var contentWidth: Int
    public var bionicReadingEnabled: Bool
    // afforded: not implemented in v1
    public var imageLightboxEnabled: Bool
    public var externalLinkBehavior: LinkBehavior
    /// 0.0–1.0 slider value; maps to ~4 discrete density modes in the article list.
    /// Card density (top of range) is deferred to v2.
    public var listDensity: Double

    public init() {
        appearanceOverride = .system
        fontFamily = "-apple-system"
        fontSize = 18
        lineHeight = 1.6
        contentWidth = 680
        bionicReadingEnabled = false
        imageLightboxEnabled = false // afforded: not implemented in v1
        externalLinkBehavior = .systemBrowser
        listDensity = 0.5
    }
}
```

- [ ] **Step 2: Write UserReadingPreferencesTests.swift**

```swift
// UserReadingPreferencesTests.swift
import Testing
import SwiftData
@testable import LensCore

@Suite("UserReadingPreferences model")
struct UserReadingPreferencesTests {

    @Test("default values match the product spec")
    func specDefaults() {
        let prefs = UserReadingPreferences()

        #expect(prefs.appearanceOverride == .system)
        #expect(prefs.fontFamily == "-apple-system")
        #expect(prefs.fontSize == 18)
        #expect(prefs.lineHeight == 1.6)
        #expect(prefs.contentWidth == 680)
        #expect(prefs.bionicReadingEnabled == false)
        #expect(prefs.imageLightboxEnabled == false) // afforded field
        #expect(prefs.externalLinkBehavior == .systemBrowser)
        #expect(prefs.listDensity == 0.5)
    }

    @Test("AppearanceOverride round-trips through Codable")
    func appearanceOverrideCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in [AppearanceOverride.system, .light, .dark] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(AppearanceOverride.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("LinkBehavior round-trips through Codable")
    func linkBehaviorCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in [LinkBehavior.systemBrowser, .inAppBrowser] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(LinkBehavior.self, from: data)
            #expect(decoded == value)
        }
    }
}
```

---

## Task 5: Write UserInterfacePreferences entity

**(Agent)**

**Files:**
- Create: `LensCore/Models/UserInterfacePreferences.swift`
- Create: `LensCoreTests/Models/UserInterfacePreferencesTests.swift`

- [ ] **Step 1: Write UserInterfacePreferences.swift**

`RetentionPolicy` has an associated value so we implement `Codable` manually.

```swift
// UserInterfacePreferences.swift — singleton SwiftData record for UI/behaviour settings.
import SwiftData
import Foundation

/// Controls the sort order of feeds in the sidebar.
public enum FeedSortOrder: String, Codable, Sendable {
    case alphabetical
    case unreadCount
    case lastUpdated
    case byCategory
}

/// How long feed items are kept before background eviction.
/// Items that are starred, saved offline, or unread are never evicted.
public enum RetentionPolicy: Codable, Sendable {
    case days(Int)
    case keepAll

    // Manual Codable implementation required for enum with associated value.
    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "days":
            self = .days(try c.decode(Int.self, forKey: .value))
        case "keepAll":
            self = .keepAll
        default:
            self = .days(90) // safe fallback; unknown types treated as default
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .days(let n):
            try c.encode("days", forKey: .type)
            try c.encode(n, forKey: .value)
        case .keepAll:
            try c.encode("keepAll", forKey: .type)
        }
    }
}

@Model
public final class UserInterfacePreferences {
    public var feedSortOrder: FeedSortOrder
    public var retentionPolicy: RetentionPolicy
    /// When false, background refresh and badge updates are both disabled.
    public var backgroundRefreshEnabled: Bool

    public init() {
        feedSortOrder = .alphabetical
        retentionPolicy = .days(90)
        backgroundRefreshEnabled = true
    }
}
```

- [ ] **Step 2: Write UserInterfacePreferencesTests.swift**

```swift
// UserInterfacePreferencesTests.swift
import Testing
import SwiftData
@testable import LensCore

@Suite("UserInterfacePreferences model")
struct UserInterfacePreferencesTests {

    @Test("default values match the product spec")
    func specDefaults() {
        let prefs = UserInterfacePreferences()

        #expect(prefs.feedSortOrder == .alphabetical)
        #expect(prefs.backgroundRefreshEnabled == true)
        // RetentionPolicy.days(90) — verify via pattern matching
        guard case .days(let n) = prefs.retentionPolicy else {
            Issue.record("Expected .days(90); got \(prefs.retentionPolicy)")
            return
        }
        #expect(n == 90)
    }

    @Test("RetentionPolicy.days round-trips through Codable")
    func retentionDaysCodable() throws {
        let encoded = try JSONEncoder().encode(RetentionPolicy.days(30))
        let decoded = try JSONDecoder().decode(RetentionPolicy.self, from: encoded)
        guard case .days(let n) = decoded else {
            Issue.record("Expected .days(30)")
            return
        }
        #expect(n == 30)
    }

    @Test("RetentionPolicy.keepAll round-trips through Codable")
    func retentionKeepAllCodable() throws {
        let encoded = try JSONEncoder().encode(RetentionPolicy.keepAll)
        let decoded = try JSONDecoder().decode(RetentionPolicy.self, from: encoded)
        guard case .keepAll = decoded else {
            Issue.record("Expected .keepAll")
            return
        }
    }

    @Test("FeedSortOrder round-trips through Codable")
    func feedSortOrderCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for value in [FeedSortOrder.alphabetical, .unreadCount, .lastUpdated, .byCategory] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(FeedSortOrder.self, from: data)
            #expect(decoded == value)
        }
    }
}
```

---

## Task 6: Add model files to Xcode and run model tests

**(Human)**

- [ ] **Step 1: Add LensCore model files**

In Xcode, right-click the **LensCore → Models** group in the Project Navigator.

Choose **Add Files to "Lens"…**

Navigate to `/Users/rich/Developer/lens/LensCore/Models/` and select all six new `.swift` files:
`Feed.swift`, `FeedItem.swift`, `Category.swift`, `OfflineAsset.swift`, `UserReadingPreferences.swift`, `UserInterfacePreferences.swift`

In the dialog:
- **Destination:** LensCore target checked; others unchecked
- **Create groups** selected (not folder references)
- **Copy items if needed:** unchecked

Click **Add**.

- [ ] **Step 2: Create test subdirectory groups in Xcode**

In the Project Navigator, right-click **LensCoreTests** → **New Group** → name it `Models`.

Right-click **LensCoreTests** again → **New Group** → name it `Persistence`.

- [ ] **Step 3: Add test files to Xcode**

Right-click the **LensCoreTests → Models** group → **Add Files to "Lens"…**

Navigate to `/Users/rich/Developer/lens/LensCoreTests/Models/` and add all four test files:
`FeedTests.swift`, `FeedItemTests.swift`, `UserReadingPreferencesTests.swift`, `UserInterfacePreferencesTests.swift`

Target: **LensCoreTests** only.

- [ ] **Step 4: Run model tests**

Scheme: **LensCoreTests** → Destination: **iPhone Simulator** (any) → **⌘U**

Expected: all tests in `FeedTests`, `FeedItemTests`, `UserReadingPreferencesTests`, `UserInterfacePreferencesTests` pass.

> **If tests fail to compile:**
> - *"Cannot find type 'PersistenceController'"* — PersistenceController.swift hasn't been added yet; skip to after Task 7 and re-run.
> - *"@testable import LensCore: no such module"* — LensCore framework is not linked to LensCoreTests. In LensCoreTests target → Build Phases → Target Dependencies → add LensCore.
> - Paste any build errors (full text + file:line) here for the agent to fix.

---

## Task 7: Write PersistenceController

**(Agent)**

**Files:**
- Create: `LensCore/Persistence/PersistenceController.swift`

- [ ] **Step 1: Write PersistenceController.swift**

```swift
// PersistenceController.swift — creates the app's single ModelContainer.
//
// The container is backed by an App Group shared container so that future
// extensions (Share Extension, widgets) can access the same store without
// a migration. Every app target calls makeModelContainer() once at launch.
//
// Unit tests use makeInMemoryContainer() (DEBUG only) which bypasses the
// App Group URL requirement and creates a fresh, isolated store per test.
import SwiftData
import Foundation

/// Errors thrown during ModelContainer initialisation.
public enum PersistenceError: Error, LocalizedError {
    /// The App Group container URL could not be resolved.
    /// Cause: the App Groups capability is not enabled for this target.
    /// Fix: see build strategy §7.2.
    case appGroupContainerUnavailable

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable:
            return "App Group 'group.com.richardtape.lens' is unavailable. " +
                   "Enable the App Groups capability in Xcode for all app targets."
        }
    }
}

public struct PersistenceController {

    /// The full schema — every @Model type registered here.
    /// Add new types in the same order across all call sites to avoid migration issues.
    static let schema = Schema([
        Feed.self,
        FeedItem.self,
        Category.self,
        OfflineAsset.self,
        UserReadingPreferences.self,
        UserInterfacePreferences.self,
    ])

    /// Creates the production ModelContainer backed by the App Group shared store.
    /// Call once from the App struct's `init()`. Pass the result to `.modelContainer()`.
    public static func makeModelContainer() throws -> ModelContainer {
        let url = try appGroupStoreURL()
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Private

    private static func appGroupStoreURL() throws -> URL {
        let groupID = "group.com.richardtape.lens"
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            throw PersistenceError.appGroupContainerUnavailable
        }
        return containerURL.appending(path: "lens.sqlite")
    }
}

// MARK: - Testing support

#if DEBUG
extension PersistenceController {
    /// Creates an isolated in-memory container using the same schema as production.
    /// Each test should call this independently — in-memory stores are not shared.
    /// Does not require the App Groups entitlement.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
#endif
```

---

## Task 8: Write CategorySeeder

**(Agent)**

**Files:**
- Create: `LensCore/Persistence/CategorySeeder.swift`
- Create: `LensCoreTests/Persistence/CategorySeederTests.swift`

- [ ] **Step 1: Write CategorySeeder.swift**

```swift
// CategorySeeder.swift — seeds the ten predefined categories on first launch.
//
// Call seedIfNeeded(in:) once per launch from the App struct after the
// ModelContainer is created. The method is idempotent: it checks whether
// any built-in categories exist before inserting and exits early if found.
import SwiftData
import Foundation

public struct CategorySeeder {

    /// The ten predefined starter categories, in display order.
    /// Matches the list in product spec §3.2.
    public static let predefinedCategories: [String] = [
        "Technology", "Science", "News", "Health", "Arts & Culture",
        "Business", "Sports", "Entertainment", "Politics", "Education",
    ]

    /// Inserts the predefined categories if none exist yet.
    /// Safe to call on every launch — returns immediately if already seeded.
    public static func seedIfNeeded(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }

        for (index, name) in predefinedCategories.enumerated() {
            context.insert(Category(name: name, sortOrder: index, isBuiltIn: true))
        }
        try context.save()
    }
}
```

- [ ] **Step 2: Write CategorySeederTests.swift**

```swift
// CategorySeederTests.swift
import Testing
import SwiftData
@testable import LensCore

@Suite("CategorySeeder")
struct CategorySeederTests {

    @Test("seeds exactly 10 built-in categories on first call")
    func seedsOnFirstLaunch() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: context)

        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = try context.fetch(descriptor)

        #expect(categories.count == 10)
        #expect(categories[0].name == "Technology")
        #expect(categories[9].name == "Education")
        #expect(categories.allSatisfy { $0.isBuiltIn })
    }

    @Test("does not duplicate categories on repeated calls")
    func idempotent() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: context)
        try CategorySeeder.seedIfNeeded(in: context) // second call must be a no-op

        let categories = try context.fetch(FetchDescriptor<Category>())
        #expect(categories.count == 10)
    }

    @Test("categories match the predefined list in order")
    func orderMatchesSpec() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: context)

        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = try context.fetch(descriptor)
        let names = categories.map { $0.name }

        #expect(names == CategorySeeder.predefinedCategories)
    }
}
```

---

## Task 9: Write PreferenceStore

**(Agent)**

**Files:**
- Create: `LensCore/Persistence/PreferenceStore.swift`
- Create: `LensCoreTests/Persistence/PreferenceStoreTests.swift`

- [ ] **Step 1: Write PreferenceStore.swift**

```swift
// PreferenceStore.swift — singleton-row accessors for preference records.
//
// Both preference types are "singleton" SwiftData records: exactly one row
// per store, created on first access and never deleted. Fetch the single
// record via fetchOrCreate() rather than querying by a unique field.
import SwiftData
import Foundation

public struct PreferenceStore {

    /// Returns the app's UserReadingPreferences, creating the row if absent.
    public static func readingPreferences(in context: ModelContext) throws -> UserReadingPreferences {
        let existing = try context.fetch(FetchDescriptor<UserReadingPreferences>())
        if let prefs = existing.first { return prefs }
        let prefs = UserReadingPreferences()
        context.insert(prefs)
        try context.save()
        return prefs
    }

    /// Returns the app's UserInterfacePreferences, creating the row if absent.
    public static func interfacePreferences(in context: ModelContext) throws -> UserInterfacePreferences {
        let existing = try context.fetch(FetchDescriptor<UserInterfacePreferences>())
        if let prefs = existing.first { return prefs }
        let prefs = UserInterfacePreferences()
        context.insert(prefs)
        try context.save()
        return prefs
    }
}
```

- [ ] **Step 2: Write PreferenceStoreTests.swift**

```swift
// PreferenceStoreTests.swift
import Testing
import SwiftData
@testable import LensCore

@Suite("PreferenceStore")
struct PreferenceStoreTests {

    @Test("reading preferences created with correct spec defaults")
    func readingPreferencesDefaults() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let prefs = try PreferenceStore.readingPreferences(in: ModelContext(container))

        #expect(prefs.appearanceOverride == .system)
        #expect(prefs.fontFamily == "-apple-system")
        #expect(prefs.fontSize == 18)
        #expect(prefs.lineHeight == 1.6)
        #expect(prefs.contentWidth == 680)
        #expect(prefs.bionicReadingEnabled == false)
        #expect(prefs.imageLightboxEnabled == false) // afforded field
        #expect(prefs.externalLinkBehavior == .systemBrowser)
        #expect(prefs.listDensity == 0.5)
    }

    @Test("interface preferences created with correct spec defaults")
    func interfacePreferencesDefaults() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let prefs = try PreferenceStore.interfacePreferences(in: ModelContext(container))

        #expect(prefs.feedSortOrder == .alphabetical)
        #expect(prefs.backgroundRefreshEnabled == true)
        guard case .days(let n) = prefs.retentionPolicy else {
            Issue.record("Expected .days(90); got \(prefs.retentionPolicy)")
            return
        }
        #expect(n == 90)
    }

    @Test("reading preferences is a singleton — second call returns same row")
    func readingPreferencesSingleton() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        let first = try PreferenceStore.readingPreferences(in: context)
        first.fontSize = 24
        try context.save()

        let second = try PreferenceStore.readingPreferences(in: context)
        #expect(second.fontSize == 24)

        let all = try context.fetch(FetchDescriptor<UserReadingPreferences>())
        #expect(all.count == 1)
    }

    @Test("interface preferences is a singleton — second call returns same row")
    func interfacePreferencesSingleton() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        let first = try PreferenceStore.interfacePreferences(in: context)
        first.feedSortOrder = .byCategory
        try context.save()

        let second = try PreferenceStore.interfacePreferences(in: context)
        #expect(second.feedSortOrder == .byCategory)

        let all = try context.fetch(FetchDescriptor<UserInterfacePreferences>())
        #expect(all.count == 1)
    }
}
```

---

## Task 10: Add persistence files to Xcode and run all tests

**(Human)**

- [ ] **Step 1: Add LensCore persistence files**

Right-click **LensCore → Persistence** group → **Add Files to "Lens"…**

Navigate to `/Users/rich/Developer/lens/LensCore/Persistence/` and add all three files:
`PersistenceController.swift`, `CategorySeeder.swift`, `PreferenceStore.swift`

Target: **LensCore** only.

- [ ] **Step 2: Add persistence test files**

Right-click **LensCoreTests → Persistence** group → **Add Files to "Lens"…**

Navigate to `/Users/rich/Developer/lens/LensCoreTests/Persistence/` and add:
`CategorySeederTests.swift`, `PreferenceStoreTests.swift`

Target: **LensCoreTests** only.

- [ ] **Step 3: Run all tests**

Scheme: **LensCoreTests** → **⌘U**

Expected: all tests in all six test suites pass.

```
FeedTests              ✓ 3 tests
FeedItemTests          ✓ 3 tests
UserReadingPreferencesTests  ✓ 3 tests
UserInterfacePreferencesTests ✓ 4 tests
CategorySeederTests    ✓ 3 tests
PreferenceStoreTests   ✓ 4 tests
─────────────────────────────
Total: 20 tests, 0 failures
```

> **Common failures:**
> - *"PersistenceController.makeInMemoryContainer is only available in DEBUG"* — you're running a Release build. In Xcode: Product → Scheme → Edit Scheme → Test action → Build Configuration → **Debug**.
> - *"@Model requires macOS 17.0 / iOS 17.0"* — your deployment target is set lower than iOS 26. Check each target's General → Minimum Deployments.
> - Paste any failure with full message + file:line for the agent.

---

## Task 11: Commit Phase 2A models and persistence

**(Both)**

- [ ] **Step 1: Stage all new files**

```bash
cd /Users/rich/Developer/lens
git add \
  LensCore/Models/Feed.swift \
  LensCore/Models/FeedItem.swift \
  LensCore/Models/Category.swift \
  LensCore/Models/OfflineAsset.swift \
  LensCore/Models/UserReadingPreferences.swift \
  LensCore/Models/UserInterfacePreferences.swift \
  LensCore/Persistence/PersistenceController.swift \
  LensCore/Persistence/CategorySeeder.swift \
  LensCore/Persistence/PreferenceStore.swift \
  LensCoreTests/Models/FeedTests.swift \
  LensCoreTests/Models/FeedItemTests.swift \
  LensCoreTests/Models/UserReadingPreferencesTests.swift \
  LensCoreTests/Models/UserInterfacePreferencesTests.swift \
  LensCoreTests/Persistence/CategorySeederTests.swift \
  LensCoreTests/Persistence/PreferenceStoreTests.swift \
  Lens.xcodeproj/project.pbxproj
git status
```

Review: only the files above should be staged. Verify no `xcuserdata/` or `DerivedData/` paths appear.

- [ ] **Step 2: Commit**

```bash
git commit -m "feat(phase-2a): SwiftData models, persistence controller, category seeder — 20 tests passing"
```

---

## Task 12: Update app entry points to use ModelContainer

**(Agent)**

Both app targets import `LensCore` and call `PersistenceController.makeModelContainer()` once at launch. The resulting container is injected into the SwiftUI environment; all views access data via `@Query` or the `modelContext` environment value.

**Files:**
- Modify: `LensIOS/LensApp.swift`
- Modify: `LensMac/LensMacApp.swift`

- [ ] **Step 1: Write LensApp.swift**

> The exact filename depends on what Xcode generated. Check the `LensIOS/` source folder for the file containing `@main`. Typical name: `LensApp.swift`. Replace its full contents with:

```swift
// LensApp.swift — iOS app entry point.
//
// Responsibilities: create the ModelContainer once and inject it into the
// SwiftUI environment. All views below use @Query or the modelContext
// environment value — never create their own containers.
//
// fatalError on container creation failure is intentional: without a
// working database the app cannot function. The most likely cause is a
// missing App Groups capability (see build strategy §7.2).
import SwiftUI
import LensCore

@main
struct LensApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try PersistenceController.makeModelContainer()
        } catch {
            fatalError("ModelContainer creation failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await seedOnLaunch() }
        }
        .modelContainer(container)
    }

    // Seeding runs asynchronously so it doesn't block the first frame.
    // Category seeding is idempotent — safe to call on every launch.
    @MainActor
    private func seedOnLaunch() async {
        do {
            try CategorySeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            // Seeding failure is non-fatal: the app works without categories;
            // seeding will retry on the next launch.
            print("[Lens] Category seeding failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Write LensMacApp.swift**

> Check the `LensMac/` folder for the file containing `@main`. Typical name: `LensMacApp.swift`. Replace its full contents with:

```swift
// LensMacApp.swift — macOS app entry point.
//
// Same setup as LensApp (iOS): ModelContainer created once, injected into
// the environment. Category seeding is identical.
import SwiftUI
import LensCore

@main
struct LensMacApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try PersistenceController.makeModelContainer()
        } catch {
            fatalError("ModelContainer creation failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await seedOnLaunch() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func seedOnLaunch() async {
        do {
            try CategorySeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            print("[Lens] Category seeding failed: \(error)")
        }
    }
}
```

---

## Task 13: Enable App Groups and verify build on iOS Simulator

**(Human)**

The App Group capability is required for `makeModelContainer()` to resolve the shared store URL. Without it the app will fatalError at launch with `"App Groups capability not enabled"`.

- [ ] **Step 1: Enable App Groups for LensIOS**

1. Select the **LensIOS** target → **Signing & Capabilities** tab.
2. Click **+ Capability** → search for **App Groups** → double-click to add.
3. Click the **+** button in the App Groups list.
4. Enter `group.com.richardtape.lens` → **OK**.
5. Confirm the checkbox next to `group.com.richardtape.lens` is checked.

- [ ] **Step 2: Enable App Groups for LensMac**

Repeat the same steps for the **LensMac** target.

> **Note:** LensCore (the framework) does not need the App Groups capability — only the app targets do. Code in an embedded framework inherits the entitlements of the app process it runs in.

- [ ] **Step 3: Build the iOS app**

Scheme: **LensIOS** → Destination: **iPhone Simulator** → **⌘B**

Expected: `Build Succeeded` with zero errors.

- [ ] **Step 4: Run on the Simulator**

**⌘R**

Expected: the app launches and displays the Phase 1 placeholder screen (`iOS · Build verification`). No crash. Check Xcode's console for `[Lens] Category seeding` messages — you should see nothing if seeding succeeds silently, or a printed error if something is wrong.

> **If the app crashes with** `"ModelContainer creation failed: …appGroupContainerUnavailable"`:
> The App Groups capability was not saved correctly. Re-check Step 1 — ensure the group identifier matches exactly (`group.com.richardtape.lens`) and the checkbox is ticked.

---

## Task 14: Verify build on macOS and do final commit

**(Human + Agent)**

- [ ] **Step 1: Build and run on macOS**

Scheme: **LensMac** → Destination: **My Mac** → **⌘B** then **⌘R**

Expected: the macOS window opens (`macOS · Build verification`). No crash.

- [ ] **Step 2 (Agent): Update agent-orientation.md**

In `docs/superpowers/2026-04-10-lens-agent-orientation.md`, replace the **Current state** section with:

```markdown
## Current state

**Phase 2A complete.** SwiftData data layer is in place and all 20 unit tests pass.

**What exists:**

| Layer | What was added |
|-------|---------------|
| `LensCore/Models/` | `Feed`, `FeedItem`, `Category`, `OfflineAsset`, `UserReadingPreferences`, `UserInterfacePreferences` — all as SwiftData `@Model` classes. Supporting enums: `SavedState`, `AppearanceOverride`, `LinkBehavior`, `FeedSortOrder`, `RetentionPolicy`. |
| `LensCore/Persistence/` | `PersistenceController` (App Group–backed `ModelContainer` factory + in-memory DEBUG factory for tests), `CategorySeeder` (idempotent predefined category seeding), `PreferenceStore` (singleton-row accessors for both preference records). |
| `LensIOS/LensApp.swift` | Updated: creates `ModelContainer` on launch, injects via `.modelContainer()`, seeds categories. |
| `LensMac/LensMacApp.swift` | Updated: same as LensApp. |
| `LensCoreTests/` | 20 passing unit tests across `Models/` and `Persistence/` subdirectories. |

**App Group** `group.com.richardtape.lens` capability enabled in LensIOS and LensMac targets.

**Next:** Phase 2B — event bus (`EventBus` actor + `LensEvent` enum + typed event registration).
```

- [ ] **Step 3 (Human): Final commit**

```bash
cd /Users/rich/Developer/lens
git add \
  LensIOS/LensApp.swift \
  LensMac/LensMacApp.swift \
  docs/superpowers/2026-04-10-lens-agent-orientation.md \
  Lens.xcodeproj/project.pbxproj
git commit -m "feat(phase-2a): wire ModelContainer into app entry points; update orientation"
```

---

## Phase 2A exit criteria

- [ ] 20 unit tests pass (`⌘U` on LensCoreTests scheme, Debug build).
- [ ] `LensIOS` builds and runs on iOS Simulator without crashing.
- [ ] `LensMac` builds and runs on macOS without crashing.
- [ ] App Group `group.com.richardtape.lens` is enabled in both app targets.
- [ ] All six `@Model` classes exist in `LensCore/Models/` with "afforded" fields present but dormant.
- [ ] `PersistenceController`, `CategorySeeder`, `PreferenceStore` exist in `LensCore/Persistence/`.
- [ ] `agent-orientation.md` Current state reflects Phase 2A completion.
- [ ] Two clean commits since Phase 1 (models/persistence, then app wiring).

---

## What's next

**Phase 2B** — Event bus:
- `LensCore/Events/EventBus.swift` — `EventBus` as a Swift `actor`; typed async subscription.
- `LensCore/Events/LensEvent.swift` — `LensEvent` enum covering all app lifecycle and domain events (feed fetch lifecycle, item state changes, reader events, addon events).
- This has no dependencies on Phase 2A models — it can be written in parallel or immediately after.

**Phase 2C** — Feed pipeline (depends on 2A + 2B):
- RSS 2.0 / Atom / JSON Feed parsers; extensible feed factory.
- Creates `Feed` and `FeedItem` records in the context from Phase 2A.

**Phase 2D** — Addon system (depends on 2B):
- Addon registry; macOS-only remote `.zip` download + `manifest.json` verification + install.
- One reference add-on proving the end-to-end pipeline.

**Phase 2E** — Engine scaffolding (depends on 2B):
- `ThemeEngine` skeleton (CSS layer composition); `DeepLinkRouter` + `lens://` URL handling at scene level.
