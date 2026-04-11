# Lens — Product & Architecture Specification (v0.5)

**Status:** Draft for review  
**Last updated:** 2026-04-10  
**Purpose:** Single source of truth for what Lens is, what it must do, and how we will phase work before writing detailed implementation plans.

---

## 1. Vision

**Lens** is a native Apple-platform reader that aggregates many sources into one chronological stream, with a fast, elegant reading experience and an architecture designed for extensions ("addons") and long-term evolution.

**Principles (non-negotiable):**

- **Speed first:** UI must feel instant; heavy work off the main thread; predictable memory use for large feeds.
- **Native by default:** SwiftUI patterns, platform HIG, NavigationSplitView on iPad/Mac, tab/compact flows on iPhone, menus and shortcuts on macOS.
- **Event-driven core:** App behavior is composed from documented lifecycle and domain events so features (and future addons) hook in without forking the app.
- **Honest offline:** Saved articles and assets work fully on-device; scope of sync is explicitly versioned (local-only first).
- **Privacy first:** No account required to use Lens; data stays on device unless the user later opts into sync; no telemetry that isn't explicit, optional, and documented.

---

## 2. Target platforms & reuse strategy

### 2.1 Platforms

- **macOS** and **iOS** (iPhone primary; iPad benefits from adaptive layouts).
- **Minimum deployment (locked):** **iOS 26** and **macOS 26**. No older OS support in v1.

### 2.2 Code reuse (recommended default)

| Layer | Contents | Shared? |
|--------|-----------|---------|
| **LensCore** | Feed models, parsers, fetch pipeline, **SwiftData** persistence, merge rules for timeline, event bus types, addon protocol surfaces, `ThemeEngine`, `DeepLinkRouter` | Yes (macOS + iOS) |
| **LensUI** | SwiftUI views where feasible; use `#if os(macOS)` / `horizontalSizeClass` / `NavigationSplitView` for adaptation | Mostly shared with platform branches |
| **LensMac** / **LensIOS** | App entry, menu bar commands, windowing (Mac), scene lifecycle, platform-specific background tasks | Thin shells |

**Why this split:** Maximum shared business logic and one timeline implementation; UI stays native by branching where Apple's patterns diverge (menus, drag-drop, inspector columns).

### 2.3 Persistence & data stack

- **Persistence:** **SwiftData** is the system of record for all entities—shared across macOS and iOS targets.
- **App Group container (required from day one):** The `ModelContainer` must be initialized using an App Group shared container URL (e.g. `group.com.richardtape.lens`) rather than the default private app container. This is a one-line configuration that makes the store accessible to future app extensions (share extension, widgets) without requiring a store migration. Do not skip this even before extensions exist.
- **Saved-item search (§4.1):** Implemented against locally stored saved content; indexing strategy (e.g. predicates, auxiliary index) is an implementation detail in the build plan.

### 2.4 Reader implementation

- **Rendering:** Article bodies are shown in **`WKWebView`** with **strict HTML sanitization** (no arbitrary scripts), **sandboxed navigation**, and CSS injected by the **`ThemeEngine`**.
- **`ThemeEngine` (in `LensCore`):** Composes three CSS layers in order before injecting into the web view:
  1. **Structural layer** — app-owned reset, layout rules, image sizing, code block handling. Never overridable by themes.
  2. **Token layer** — generated at runtime from `UserReadingPreferences`; exposes CSS custom properties that define the default reading aesthetic (see §3.8). Theme CSS may use or ignore these.
  3. **Theme layer** — CSS provided by the active built-in or addon theme. May reference token variables or override them entirely.
- **Token contract:** The CSS custom property names (e.g. `--lens-bg`, `--lens-text`, `--lens-font-size`) are a **versioned public API** for theme addon authors. Changes are breaking; document them in the event catalog (§9).
- **Rationale:** Predictable handling of real-world feed HTML; token system lets average users adjust reading appearance via simple settings while power users and addon authors can fully override via theme CSS.

### 2.5 Screen sizes & layout strategy

- **iPhone:** Single column: feed list → article list → reader (stacked navigation). Bottom tab bar for primary destinations (Timeline, Feeds, Saved, Settings).
- **iPad / Mac:** Multi-column when width allows: sidebar (feeds/categories) + list + reader detail (`NavigationSplitView` / inspector).
- **Reader:** Full-bleed reading pane with typography controlled by theme; optional chrome auto-hide on scroll.
- **Adaptive typography:** Dynamic Type on iOS; equivalent text scaling on macOS for accessibility.

---

## 3. Core features

### 3.1 Reading & timeline

- **Main timeline:** Single chronological stream of all items from all subscribed feeds, ordered by published date (see §7.2 for tie-breaks and missing dates).
- **Per-feed views:** Optional filtered list for one feed or one category.
- **Read / unread:** Persistent state per item; bulk actions (mark read, mark all read in feed) available early.
- **Starred:** Per-item flag, independent of offline save (see §3.4).
- **New items banner:** When background refresh finds new items, a banner ("↑ 12 new items") pins to the top of the **main timeline only**. Tapping it scrolls to the newest item. The banner auto-dismisses when the user manually scrolls to the top. Per-feed views reload silently without a banner.
- **Swipe-in-unread-filter behaviour:** When "unread only" filter is active and the user marks an item as read (via swipe), the item vanishes immediately from the list (consistent with Mail app behaviour).

#### Keyboard shortcuts (macOS — single-letter, no modifier required)

Shortcuts are disabled when the saved-items search field is focused.

| Key | Action |
|-----|--------|
| `j` / `k` | Next / previous item in list |
| `s` | Toggle save for offline (second press removes) |
| `f` | Toggle favourite / star (second press removes) |
| `r` | Refresh current feed or all feeds |
| `o` | Open current item in browser |
| `u` | Mark current item as unread |
| `?` | Show keyboard shortcut reference sheet |
| `Escape` | Back / close reader |

#### iOS interaction model

- **Tap:** Opens the reader view.
- **Swipe right:** Toggle read / unread. Primary action (checkmark icon).
- **Swipe left (short reveal):** Expose three action buttons — **Star**, **Save**, **Share** — in that order (most-used closest to the finger).
- **Swipe left (full):** Commits "Save for offline."
- **Long press:** iOS context menu with full action set: Mark Read/Unread, Star/Unstar, Save for Offline/Remove Save, Share, Open in Browser, Copy Link. Triggers haptic feedback.

### 3.2 Content ingestion

- **Multiple feed kinds:** Not only RSS 2.0 / RDF / Atom; extensible **feed factory** that selects a parser by content type, URL hints, or sniffing.
- **Discovery:** If URL is not a feed, probe well-known paths (`/feed`, `/rss`, `/atom.xml`, etc.); allow each feed type registration to contribute discovery patterns and MIME expectations.
- **Feed metadata fields:** URL, resolved title (editable), favicon or monogram fallback (first letter of site name), **category** (see below), `refreshInterval` (see §7.1).

#### Categories (predefined + custom)

Lens ships with a starter set of categories that covers common use cases without overwhelming new users:

> Technology · Science · News · Health · Arts & Culture · Business · Sports · Entertainment · Politics · Education

Users may rename, delete, or add their own categories at any time. When adding a new category, the UI should fuzzy-match against existing category names and suggest a match if one is very similar — preventing accidental duplicates (e.g. "Tech" when "Technology" exists). This suggestion feature is noted here as a design intent; implementation detail is left to the UI plan.

#### Feed ordering (sidebar)

Users choose how feeds are sorted in the sidebar. Options:

- **Alphabetical** (A→Z by display name)
- **By unread count** (highest unread first)
- **By last updated** (most recently fetched first)
- **By category** (groups feeds under their category heading)

Sort preference is stored in `UserInterfacePreferences`. No manual drag-to-reorder in v1.

#### Feed health state

Each `Feed` tracks its fetch health (see §7.1 for model fields). When a feed has exceeded the consecutive-failure threshold:

- A red badge / error indicator appears on the feed row in the sidebar.
- A short error message is shown beneath the feed name (e.g. "Could not reach server · Last updated 3 days ago").
- A **Retry** button triggers a `userInitiatedFeedRefresh(feedId:)` event (distinct from background refresh, so addons can react to it).

Manual refresh for an individual feed is also reachable via right-click / long-press context menu on the feed row.

### 3.3 Reader ("our viewer")

- **Engine:** `WKWebView` with sanitized HTML, sandboxed navigation, and `ThemeEngine`-injected CSS (see §2.4).
- **External link handling:** Tapping an inline link is intercepted in `WKNavigationDelegate.decidePolicyFor`. Default behaviour is to open in the **system browser** (Safari). A user setting can switch to an in-app **`SFSafariViewController`** instead. This setting lives in the reading preferences screen.
- **Beautiful defaults:** Comfortable line length, spacing, embedded image handling, code blocks—driven by shared theme stylesheets plus token defaults.
- **Performance:** Defer heavy layout where possible; cache rendered output when safe.
- **Accessibility:** Meet platform expectations (VoiceOver, resizing); web content requires explicit verification alongside native chrome.

### 3.4 Starred vs saved (distinct user jobs)

| Concept | User benefit | Typical cost |
|--------|----------------|----------------|
| **Starred** | Lightweight **bookmark / favourite**: "come back to this" or "I liked this." Fast to toggle; good for triage and highlights. | Negligible storage (metadata only). |
| **Saved (offline)** | **Read without network** and **keep full content** (HTML + images) in the sandbox. Stored via `s` key / save gesture. | Larger storage; toggle removes saved copy. |

**Why both:** A user may star many articles for quick recall but only save a few for offline reading. Conversely, they may save long-form pieces without starring. Search (§4.1) applies to **saved** items only; the main timeline stays fast and search-free.

### 3.5 Offline & storage

- **Save for offline:** User action stores article HTML and associated images in the app sandbox; available without network.
- **Scope:** Device-local only in v1; no requirement to sync saved bodies across devices.

### 3.6 Onboarding & settings

- **Onboarding:** In-app first-run flow: add one or more feeds, choose categories, minimal explanation. Polish can come later but the flow exists from early builds.
- **Settings:** Scaffolded screen covering: refresh behaviour, badge / unread-total controls (§4.5), reading preferences (§3.8), link-open behaviour, storage / retention (§4.13), keyboard reference, about. Expand over time.

### 3.7 Events as public API

- **Everything substantive emits or consumes events:** e.g. app launch, background refresh tick, feed fetch started/completed/failed, feed health changed, item parsed, item displayed, item marked read, item starred/unstarred, item saved offline, theme applied, user-initiated refresh.
- **Documentation requirement:** Event catalog (names, payloads, ordering guarantees, threading model) is part of the shipped developer-facing contract for future addons.

### 3.8 Reader & interface preferences

User preferences are stored in `UserReadingPreferences` (SwiftData, see §7.1).

#### Reader token values (feed into ThemeEngine layer 2)

| Token | CSS variable | Default |
|-------|-------------|---------|
| Background colour | `--lens-bg` | Adaptive (system) |
| Text colour | `--lens-text` | Adaptive (system) |
| Link colour | `--lens-link` | System accent |
| Font family | `--lens-font-family` | `-apple-system` |
| Font size | `--lens-font-size` | `18px` |
| Line height | `--lens-line-height` | `1.6` |
| Content width | `--lens-content-width` | `680px` |
| Code font | `--lens-code-font` | `ui-monospace` |

#### Appearance

- **Dark / light mode:** Follows system by default. User can pin to light or dark regardless of system setting (`appearanceOverride: AppearanceOverride` — `.system`, `.light`, `.dark`).
- **List density:** A continuous slider (`listDensity: Double`, 0.0–1.0) mapping to ~4 discrete visual modes in the article list: title-only → compact (title + source + time) → standard (compact + 2-line excerpt) → card (standard + thumbnail, **v2 only**). The card mode field is present in preferences but the card layout is deferred to v2.
- **Bionic reading:** Boolean, default **off**. When on, `ThemeEngine` injects a JS transformation that bolds the first half of each word. Can be implemented as an addon in a future phase.

#### Deferred reader settings (v2+)
- **Image lightbox:** Boolean setting, default **off**. Tapping an inline image shows it full-screen. Not implemented in v1 but the setting is scaffolded.

---

## 4. Product decisions

### 4.1 Search

- **In scope:** Full-text (or equivalent) search **within saved/offline items only**—where we have local HTML/text worth indexing.
- **Search bar location:** Pinned to the top of the **Saved Items view**. Not a global search.
- **Out of scope for main timeline:** No search across the unified chronological feed.

### 4.2 Filters (main feed & lists)

- **Confirmed:** Quick filters: unread only, by category, by feed, date range. Exact UX to be refined in UI plans.

### 4.3 Sharing

- **Confirmed:** System share sheet, copy link, open in system browser. Follow platform conventions.

### 4.4 OPML

- **Confirmed:** Import and export of subscriptions.

### 4.5 Background polling & badges

- **Confirmed:** Background refresh so Lens can detect new items and reflect unread totals in the UI — badge counts on app icon / Dock / tab destinations.
- **User control (v1):** Single global setting turns badge updates and background refresh on or off together.
- **Per-feed refresh interval:** The `Feed` model stores an optional `refreshInterval: TimeInterval?` (`nil` = use global setting). The per-feed UI control is deferred to v2, but the data model field exists from day one.
- **Manual refresh:** Pull-to-refresh on iOS; `r` key on macOS.
- **Platform reality:** iOS Background App Refresh is opportunistic. Settings copy should set expectations.

### 4.6 Widgets

- **Deferred** to a future phase.

### 4.7 Duplicate detection

- **Deferred** to a future phase.

### 4.8 Full article / full page content

- **Product direction:** Support fetching full article content where the feed only provides a summary. Strong fit for an **add-on** rather than core v1 behaviour.

### 4.9 Accessibility

- **Required:** VoiceOver, full keyboard navigation on Mac, Dynamic Type / text sizing, Reduce Motion, sufficient contrast. Treat as a release gate, not a polish pass.

### 4.10 Privacy

- **Required:** No account required; feeds and saved content stay on device; any future sync is opt-in; no hidden analytics.

### 4.11 Internationalization (i18n)

- **Engineering habit from day one:** Externalized strings, locale-aware dates/numbers, UI that accommodates longer strings and RTL.
- **Future:** Language packs as add-ons.

### 4.12 URL scheme & deep links

Lens registers the `lens://` custom URL scheme from day one, handled by a `DeepLinkRouter` in `LensCore` that parses incoming URLs and emits navigation events on the event bus.

| URL | Action |
|-----|--------|
| `lens://feed/add?url=<encoded>` | Open "add feed" sheet pre-filled with URL |
| `lens://feed/<id>` | Navigate to a specific feed |
| `lens://item/<id>` | Open a specific article in the reader |
| `lens://saved` | Open the Saved Items view |
| `lens://settings` | Open Settings |
| `lens://import?opml=<url>` | Import OPML from a URL |

SwiftUI handles incoming URLs via `onOpenURL` at the scene level. This also enables Shortcuts app integration for free.

### 4.13 Item retention policy

- **Default:** Time-based eviction — items older than **90 days** are removed on a background schedule.
- **Exclusions:** Items that are starred, saved for offline, or currently unread are never evicted regardless of age.
- **User setting:** A single setting in the storage section of Settings. Options: 30 days / 60 days / 90 days (default) / 6 months / Keep all. Where feasible, the UI shows an estimated storage impact.
- **Model field:** `Feed` does not store retention; retention is a global preference in `UserInterfacePreferences`.

### 4.14 Feed health & error states

When a feed has failed to fetch beyond a threshold (e.g. 5 consecutive failures), it is marked unhealthy. The data model tracks: `lastFetchError: String?`, `lastFetchedAt: Date?`, `consecutiveFailureCount: Int` on `Feed`.

UI behaviour:
- Red badge / error indicator on the feed row.
- Short error message below the feed name in the sidebar (e.g. "Could not reach server · Last updated 3 days ago").
- A **Retry** button on the feed row triggers `userInitiatedFeedRefresh(feedId:)`.
- The `feedHealthChanged(feedId:status:)` event is emitted whenever health state changes.

### 4.15 List density

A slider in reading preferences controls article list density. The value (`listDensity: Double`, 0.0–1.0) drives approximately four discrete visual modes:

| Level | What is shown |
|-------|--------------|
| Title only | Title + source name |
| Compact | Title + source + timestamp |
| Standard (default) | Compact + 2-line excerpt |
| Card *(v2 only)* | Standard + thumbnail image |

The card density level is present in the preference model but its UI and rendering are deferred to v2. The `thumbnailURL` field on `FeedItem` is populated from day one (see §7.1) so that card mode can be added without a model migration.

### 4.16 Share extension (future)

A Share Extension (letting users add feeds or save articles from Safari and other apps) is planned for a future phase. The App Group container requirement in §2.3 ensures the SwiftData store is accessible to the extension without a migration when it ships.

---

## 5. Addon architecture (prove early, expand later)

### 5.1 Goals

- **Base app** is fully useful without addons.
- **Addons** extend parsers, themes, actions, and optional UI (within sandbox rules).
- **Prove the system early (macOS):** The **first implementation wave** ships **core app functionality together with one minimal add-on** installed from **your** HTTPS server **on Mac**, validating manifests, download, verification, registration, and observable behaviour. **Remote installable add-ons are macOS-only to start.**
- **iOS later:** Declarative packs and/or hooks implemented in the main binary remain the likely path when iOS add-ons ship.

### 5.2 Phased approach

Product-level add-on milestones (letters A–C) are separate from **build phase** numbers. The **remote install vertical slice** (event bus, addon registry, zip format, one reference add-on, **macOS only**) is implemented in **[build Phase 2](2026-04-10-lens-build-phases.md#phase-2--foundation-add-on-shell-minimal-ingestion)** in the master roadmap—**not** “build Phase 0” (build Phase 0 is repository/Xcode bootstrap only). See [`2026-04-10-lens-build-phases.md`](2026-04-10-lens-build-phases.md).

1. **Vertical slice (build Phase 2):** Event bus + addon registry + **remote package format** + **one reference add-on** hosted on your server → **macOS only** for download/install; proves end-to-end pipeline.
2. **Phase A — Bundled add-ons:** Same manifest format; packages ship inside the app for tests (all platforms).
3. **Phase B — Curated remote catalog:** Multiple packages, update checks, revocation list; **macOS** leads.
4. **Phase C — Add-on "store" UX:** Discovery UI in-app, developer docs, signing productized—explicitly after the vertical slice (build Phase 2) is stable.

### 5.3 Remote hosting & package format (locked for the vertical slice / build Phase 2)

- **Artifact:** Add-ons distributed as a **`.zip` bundle** containing a **`manifest.json`** plus assets (CSS, images, declarative rule files).
- **Flow (macOS, first remote install milestone):** User provides add-on URL → download zip → verify integrity (SHA-256) → unpack to app sandbox → parse manifest → register with `LensCore`.
- **Hosting:** Versioned zips and manifests served over **HTTPS** from infrastructure you control.
- **Later:** Stronger authenticity (Ed25519 or Apple-style signing) aligns with Phase C.

### 5.4 Addon manifest (sketch)

- **Inside the zip:** `manifest.json` at bundle root listing identifier, version, minimum Lens version, capabilities (`feedParser`, `theme`, `action`, `languagePack`, …), permissions (network, file access), relative asset paths, checksum metadata.
- **Theme addons:** May provide CSS that uses `--lens-*` token variables (inheriting the user's reading preferences) or may override them entirely. The token variable names are the public contract.
- **Security:** No raw `eval`; declarative payloads validated by Lens; optional signatures verified before activation.

### 5.5 What "installable feed types" means in practice

- **Built-in factory** registers core formats (RSS, Atom, JSON Feed) on all platforms.
- **macOS (from vertical slice onward):** Add-ons contribute declarative rules and/or host-implemented hooks via manifest.
- **iOS:** No remote add-on install until a later milestone (see [build phases](2026-04-10-lens-build-phases.md) and §5.2).

---

## 6. Future: iCloud and cross-device

- **Feeds list, read state, stars:** Reasonable CloudKit/SwiftData sync candidates.
- **Saved offline bodies + images:** Larger payload; optional tier or "optimize storage" sync.
- **Conflict policy:** Last-write-wins or per-field merge; document when enabled.

---

## 7. Data model (high level)

> **Convention for this section:** Fields marked **(afforded; not active in v1)** are present in the SwiftData model from day one so that future features can be added without a store migration, but they are not read, written, or surfaced in the v1 UI unless stated otherwise.

### 7.1 Entities

#### Feed
| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Stable identifier |
| `url` | URL | Canonical feed URL |
| `displayName` | String | User-editable; seeded from feed metadata |
| `categoryId` | UUID? | FK to Category |
| `iconRef` | String? | Favicon URL or monogram fallback |
| `createdAt` | Date | |
| `refreshInterval` | TimeInterval? | `nil` = use global setting. **(afforded; UI not active in v1)** |
| `lastFetchedAt` | Date? | Last successful fetch |
| `lastFetchError` | String? | Human-readable error from most recent failure |
| `consecutiveFailureCount` | Int | Resets to 0 on success |

#### FeedItem
| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Stable identifier |
| `feedId` | UUID | FK to Feed |
| `stableId` | String | GUID from feed or content hash |
| `title` | String | |
| `link` | URL? | Canonical article URL |
| `publishedAt` | Date? | |
| `updatedAt` | Date? | |
| `summaryHTML` | String? | Short excerpt from feed |
| `contentHTML` | String? | Full body if provided by feed |
| `isRead` | Bool | |
| `isStarred` | Bool | |
| `savedOfflineState` | SavedState | `.notSaved`, `.saving`, `.saved`, `.error` |
| `rawMetadata` | Data? | JSON blob; escape hatch for feed-type-specific fields |
| `thumbnailURL` | URL? | `og:image` or first image; populated at parse time. **(afforded; card view not active in v1)** |
| `estimatedReadMinutes` | Int? | Derived from word count at parse time. **(afforded; not displayed in v1)** |
| `enclosureURL` | URL? | Podcast / video attachment URL. **(afforded; not active in v1)** |
| `enclosureMIMEType` | String? | MIME type of enclosure. **(afforded; not active in v1)** |

#### Category
| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `name` | String | User-editable |
| `sortOrder` | Int | Ordering in sidebar |
| `isBuiltIn` | Bool | True for the predefined starter categories |

**Predefined starter categories (seeded on first launch):** Technology, Science, News, Health, Arts & Culture, Business, Sports, Entertainment, Politics, Education.

#### OfflineAsset
| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `itemId` | UUID | FK to FeedItem |
| `localFileURL` | URL | Path within app sandbox |
| `remoteURL` | URL | Original remote URL |
| `mimeType` | String | |

#### UserReadingPreferences
*(Singleton SwiftData record. All fields have defaults.)*

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `appearanceOverride` | AppearanceOverride | `.system` | `.system`, `.light`, `.dark` |
| `fontFamily` | String | `-apple-system` | CSS font-family value |
| `fontSize` | Int | `18` | Points / px |
| `lineHeight` | Double | `1.6` | Unitless multiplier |
| `contentWidth` | Int | `680` | px |
| `bionicReadingEnabled` | Bool | `false` | |
| `imageLightboxEnabled` | Bool | `false` | **(afforded; not implemented in v1)** |
| `externalLinkBehavior` | LinkBehavior | `.systemBrowser` | `.systemBrowser`, `.inAppBrowser` |
| `listDensity` | Double | `0.5` | 0.0–1.0; card mode deferred to v2 |

#### UserInterfacePreferences
*(Singleton SwiftData record.)*

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `feedSortOrder` | FeedSortOrder | `.alphabetical` | `.alphabetical`, `.unreadCount`, `.lastUpdated`, `.byCategory` |
| `retentionPolicy` | RetentionPolicy | `.days(90)` | `.days(Int)`, `.keepAll` |
| `backgroundRefreshEnabled` | Bool | `true` | Also gates badge updates |

### 7.2 Timeline ordering

- Primary: `publishedAt` descending.
- Missing/invalid dates: fallback to `fetchedAt` or place at bottom with clear UI badge ("Date unknown").

---

## 8. Non-functional requirements

- **Performance:** Scroll lists at 120 Hz where supported; fetch work on background queues; image decoding sized to view bounds.
- **Reliability:** Exponential backoff for failing feeds (tracked via `consecutiveFailureCount`); surface errors inline without modal spam.
- **Security:** Sanitize HTML; restrict network access for viewer; certificate validation as per platform defaults; sandboxed WKWebView navigation.
- **Privacy:** No account required; on-device defaults; transparent behaviour for background refresh and badge updates (§4.5).
- **Accessibility:** Meet platform accessibility expectations (§4.9).
- **Testability:** Parsers, timeline merge, `ThemeEngine`, `DeepLinkRouter` — all pure Swift, unit-testable without UI.

---

## 9. Documentation deliverables (for developers / future addon authors)

- **Event catalog** (authoritative): name, payload schema, thread, ordering, cancellation. Includes: `userInitiatedFeedRefresh`, `userInitiatedRefresh`, `feedHealthChanged`, `backgroundRefreshCompleted`, and all item/reader lifecycle events.
- **Token contract** (authoritative): All `--lens-*` CSS custom property names, their semantics, and version they were introduced. Required reading for theme addon authors.
- **Capability matrix:** What addons may register at each phase.
- **Style guide:** How third-party UI hooks must respect HIG when we allow UI addons.
- **Data model changelog:** Every schema version, migration strategy, and rationale. Includes "afforded but not active" fields and when they are expected to become active.

---

## 10. Implementation order vs product behaviour

**Authoritative roadmap:** The numbered build sequence (Phases 0–9), bootstrap steps, and post–v1 backlog pointer live only in **[`2026-04-10-lens-build-phases.md`](2026-04-10-lens-build-phases.md)**. Update that document when implementation order changes.

This product spec defines **what** Lens must do and **how** features behave—not the phase-by-phase delivery list. Work in multiple areas may overlap in time; the add-on vertical slice is scheduled alongside foundation work in **build Phase 2** (see build phases doc) so integration risk is not deferred.
