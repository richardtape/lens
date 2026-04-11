# Lens Phase 2E — Engine Scaffolding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `ThemeEngine` CSS composition skeleton, the `DeepLinkRouter` URL parser, and wire `lens://` URL handling at scene level in both app targets.

**Architecture:** `ThemeEngine` is a pure static namespace (`enum`) in `LensCore/Theme/` that composes three CSS layers (structural, token, theme) into a single injection string — no WKWebView interaction yet (that is Phase 4). `TokenLayer` is a second static namespace that generates the `--lens-*` CSS custom properties from `UserReadingPreferences`; its property name constants are the versioned public contract for addon authors (spec §9). `DeepLinkRouter` is a static namespace in `LensCore/Routing/` that parses `lens://` URLs into a `LensRoute` enum, then emits the appropriate navigation event on `EventBus`. Scene-level `onOpenURL` wiring is added to both `LensIOS` and `LensMac`. All `LensCore` code is free of SwiftUI imports.

**Tech Stack:** Swift 6, Foundation (`URL`, `URLComponents`), SwiftData (`UserReadingPreferences` for token generation), `EventBus` from Phase 2B, Swift Testing, Xcode 26.3.

**Depends on:** Phase 2B (`EventBus` + `LensEvent` must exist before `DeepLinkRouter` can emit navigation events); Phase 2A (`UserReadingPreferences` model is needed by `TokenLayer`).

---

## Driver legend

- **(Agent)** — agent writes files; no Xcode interaction needed.
- **(Human)** — requires Xcode GUI or shell command.
- **(Both)** — agent writes content, human runs a command or verifies.

---

## File structure

```
LensCore/Theme/
├── BuiltInTheme.swift           (Create) Layer 1 (structural CSS) + layer 3 (default theme CSS)
├── TokenLayer.swift             (Create) Layer 2: tokenCSS(from:) + public token name constants
└── ThemeEngine.swift            (Create) composedCSS(preferences:themeCSS:) — three-layer join

LensCore/Routing/
├── LensRoute.swift              (Create) Parsed lens:// destination enum + Equatable
└── DeepLinkRouter.swift         (Create) route(from:) URL parser + handle(_:bus:) emitter

LensCore/Events/LensEvent.swift  (Modify) Add six .navigateTo* cases

LensIOS/LensApp.swift            (Modify) Add .onOpenURL view modifier to WindowGroup root view
LensMac/LensMacApp.swift         (Modify) Add .onOpenURL view modifier to WindowGroup root view

LensCoreTests/Theme/
├── TokenLayerTests.swift        (Create) tokenCSS output for preference field values
└── ThemeEngineTests.swift       (Create) composedCSS three-layer composition

LensCoreTests/Routing/
└── DeepLinkRouterTests.swift    (Create) URL parsing + route matching + event emission

LensCoreTests/Events/LensEventTests.swift  (Modify) Add new navigation cases to allCasesRoundTrip
```

> **`.gitkeep` cleanup:** `LensCore/Theme/` and `LensCore/Routing/` each have a `.gitkeep` from Phase 0. Delete them from disk and from the Xcode groups when adding the first real file to each directory.

---

## Task 1: Add navigation events to LensEvent.swift and update LensEventTests.swift

**(Agent)**

**Files:**
- Modify: `LensCore/Events/LensEvent.swift`
- Modify: `LensCoreTests/Events/LensEventTests.swift`

- [ ] **Step 1: Add six navigation cases to LensEvent.swift**

Open `LensCore/Events/LensEvent.swift`. Find the `// MARK: Addon lifecycle` section added in Phase 2D. Add the following new section immediately after it (after the `addonInstallFailed` case):

```swift
    // MARK: Navigation (emitted by DeepLinkRouter; consumed by scene-level coordinators)

    /// Open the add-feed sheet, optionally pre-filled with a URL.
    /// Emitted for `lens://feed/add` and `lens://feed/add?url=<encoded>` (spec §4.12).
    case navigateToAddFeed(prefillURL: URL?)
    /// Navigate to a specific feed's article list.
    /// Emitted for `lens://feed/<id>` (spec §4.12).
    case navigateToFeed(feedId: UUID)
    /// Open a specific article in the reader view.
    /// Emitted for `lens://item/<id>` (spec §4.12).
    case navigateToItem(itemId: UUID)
    /// Navigate to the Saved Items view.
    /// Emitted for `lens://saved` (spec §4.12).
    case navigateToSaved
    /// Navigate to the Settings screen.
    /// Emitted for `lens://settings` (spec §4.12).
    case navigateToSettings
    /// Import OPML subscriptions from the given URL.
    /// Emitted for `lens://import?opml=<url>` (spec §4.12).
    case navigateToOPMLImport(sourceURL: URL)
```

- [ ] **Step 2: Update LensEventTests.swift — add new cases to allCasesRoundTrip**

Open `LensCoreTests/Events/LensEventTests.swift`. Find the `allCasesRoundTrip` test. Add these lines to the `cases` array (after the `.addonInstallFailed` entries added in Phase 2D):

```swift
            .navigateToAddFeed(prefillURL: URL(string: "https://example.com/feed.xml")),
            .navigateToAddFeed(prefillURL: nil),
            .navigateToFeed(feedId: id1),
            .navigateToItem(itemId: id2),
            .navigateToSaved,
            .navigateToSettings,
            .navigateToOPMLImport(sourceURL: URL(string: "https://example.com/feeds.opml")!),
```

- [ ] **Step 3: Build and run LensCore tests** **(Human)**

Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: All existing tests still pass (the `allCasesRoundTrip` test now covers the six new cases). No failures.

---

## Task 2: Write BuiltInTheme.swift, TokenLayer.swift, ThemeEngine.swift

**(Agent)**

**Files:**
- Create: `LensCore/Theme/BuiltInTheme.swift`
- Create: `LensCore/Theme/TokenLayer.swift`
- Create: `LensCore/Theme/ThemeEngine.swift`

- [ ] **Step 1: Write BuiltInTheme.swift**

Create `/Users/rich/Developer/lens/LensCore/Theme/BuiltInTheme.swift`:

```swift
// BuiltInTheme.swift — CSS layer 1 (structural) and layer 3 (default theme) constants.
//
// Layer 1 owns the reading layout: resets, max-width, image sizing, code block
// basics. It is always the first layer in the composed output; addon themes
// cannot override it (spec §2.4).
//
// Layer 3 is the default built-in reading aesthetic. An addon theme replaces this
// layer entirely by passing its CSS to ThemeEngine.composedCSS(preferences:themeCSS:).
// Phase 4 will expand both stubs into a full polished reading experience.
import Foundation

public enum BuiltInTheme {

    // MARK: - Layer 1: Structural CSS

    /// App-owned layout and reset rules. Always the first CSS layer. (spec §2.4)
    /// References --lens-* variables so token values propagate here automatically.
    public static let structuralCSS = """
    /* Lens structural layer — v1 */
    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0 auto;
      padding: 1.5rem;
      max-width: var(--lens-content-width, 680px);
      overflow-wrap: break-word;
    }
    img, video { max-width: 100%; height: auto; display: block; }
    pre { overflow-x: auto; }
    code, pre { font-family: var(--lens-code-font, ui-monospace, monospace); }
    a { text-decoration: underline; }
    """

    // MARK: - Layer 3: Default theme CSS

    /// Built-in default reading theme. Replace by passing addon CSS to
    /// ThemeEngine.composedCSS(preferences:themeCSS:). Phase 4 will expand this. (spec §2.4)
    public static let defaultThemeCSS = """
    /* Lens default theme layer — v1 */
    body {
      background-color: var(--lens-bg);
      color: var(--lens-text);
      font-family: var(--lens-font-family);
      font-size: var(--lens-font-size);
      line-height: var(--lens-line-height);
    }
    a { color: var(--lens-link); }
    pre {
      background: rgba(128, 128, 128, 0.1);
      border-radius: 6px;
      padding: 1em 1.25em;
    }
    blockquote {
      border-left: 3px solid rgba(128, 128, 128, 0.4);
      margin-left: 0;
      padding-left: 1.25em;
      opacity: 0.8;
    }
    """
}
```

- [ ] **Step 2: Write TokenLayer.swift**

Create `/Users/rich/Developer/lens/LensCore/Theme/TokenLayer.swift`:

```swift
// TokenLayer.swift — CSS layer 2: custom property tokens from UserReadingPreferences.
//
// The --lens-* CSS variable names are a versioned public contract for theme addon
// authors (spec §9 token contract). Renaming any constant here is a breaking
// change that requires a version notice in the event catalog.
//
// Colour strategy (spec §2.4, §3.8):
//   .system appearance → CSS system-colour keywords (Canvas / CanvasText) so
//     WKWebView's built-in dark-mode support handles adaptive colouring.
//   .light / .dark → explicit hex values that override the adaptive behaviour.
// Phase 4 will refine this when WKWebView appearance is wired up.
import Foundation

public enum TokenLayer {

    // MARK: - Token name constants (public API — do not rename)

    /// CSS variable name for background colour. (spec §3.8)
    public static let bg            = "--lens-bg"
    /// CSS variable name for body text colour. (spec §3.8)
    public static let text          = "--lens-text"
    /// CSS variable name for link colour. (spec §3.8)
    public static let link          = "--lens-link"
    /// CSS variable name for font family. (spec §3.8)
    public static let fontFamily    = "--lens-font-family"
    /// CSS variable name for base font size. (spec §3.8)
    public static let fontSize      = "--lens-font-size"
    /// CSS variable name for line height. (spec §3.8)
    public static let lineHeight    = "--lens-line-height"
    /// CSS variable name for maximum content width. (spec §3.8)
    public static let contentWidth  = "--lens-content-width"
    /// CSS variable name for code/monospace font. (spec §3.8)
    public static let codeFont      = "--lens-code-font"

    // MARK: - CSS generation

    /// Generate the token layer CSS from the user's reading preferences.
    ///
    /// Returns a `:root { … }` block setting all eight --lens-* custom properties.
    /// Inject this as the second CSS layer (after structural, before theme).
    public static func tokenCSS(from preferences: UserReadingPreferences) -> String {
        """
        /* Lens token layer — generated from UserReadingPreferences */
        :root {
          \(bg): \(backgroundValue(for: preferences.appearanceOverride));
          \(text): \(textValue(for: preferences.appearanceOverride));
          \(link): #007aff;
          \(fontFamily): \(preferences.fontFamily);
          \(fontSize): \(preferences.fontSize)px;
          \(lineHeight): \(preferences.lineHeight);
          \(contentWidth): \(preferences.contentWidth)px;
          \(codeFont): ui-monospace, monospace;
        }
        """
    }

    // MARK: - Colour helpers

    private static func backgroundValue(for override: AppearanceOverride) -> String {
        switch override {
        case .system: return "Canvas"     // CSS system-colour; adapts to WKWebView dark mode
        case .light:  return "#ffffff"
        case .dark:   return "#1c1c1e"
        }
    }

    private static func textValue(for override: AppearanceOverride) -> String {
        switch override {
        case .system: return "CanvasText"
        case .light:  return "#000000"
        case .dark:   return "#ffffff"
        }
    }
}
```

- [ ] **Step 3: Write ThemeEngine.swift**

Create `/Users/rich/Developer/lens/LensCore/Theme/ThemeEngine.swift`:

```swift
// ThemeEngine.swift — Joins three CSS layers into a single injection string.
//
// Layer order (spec §2.4):
//   1. Structural  — BuiltInTheme.structuralCSS. Always present; not overridable.
//   2. Token       — TokenLayer.tokenCSS(from:). --lens-* custom properties from prefs.
//   3. Theme       — Active theme CSS (addon or BuiltInTheme.defaultThemeCSS).
//
// Output is a single CSS string for injection into WKWebView.
// WKWebView injection itself is Phase 4 work. ThemeEngine's only job is composition.
import Foundation

public enum ThemeEngine {

    /// Compose all three CSS layers into a single string ready for WKWebView injection.
    ///
    /// - Parameters:
    ///   - preferences: The user's current reading preferences (drives layer 2 tokens).
    ///   - themeCSS: Layer 3 CSS. Pass an addon theme's CSS here to replace the
    ///     built-in default. Defaults to `BuiltInTheme.defaultThemeCSS`.
    /// - Returns: Three layers joined by blank lines — structural, then token, then theme.
    public static func composedCSS(
        preferences: UserReadingPreferences,
        themeCSS: String = BuiltInTheme.defaultThemeCSS
    ) -> String {
        [
            BuiltInTheme.structuralCSS,
            TokenLayer.tokenCSS(from: preferences),
            themeCSS
        ].joined(separator: "\n\n")
    }
}
```

---

## Task 3: Write ThemeEngine tests, add files to Xcode, run tests

**(Both)**

**Files:**
- Create: `LensCoreTests/Theme/TokenLayerTests.swift`
- Create: `LensCoreTests/Theme/ThemeEngineTests.swift`

- [ ] **Step 1: Write TokenLayerTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Theme/TokenLayerTests.swift`:

```swift
// TokenLayerTests.swift — Verify that tokenCSS(from:) produces correct
// CSS custom property values for each UserReadingPreferences field.
//
// Tests use an in-memory ModelContainer so UserReadingPreferences is a proper
// SwiftData-managed instance, matching how it is used at runtime.
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("TokenLayer")
struct TokenLayerTests {

    // MARK: - Setup

    let container: ModelContainer
    let preferences: UserReadingPreferences

    init() throws {
        container = try ModelContainer(
            for: UserReadingPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        preferences = UserReadingPreferences()
        context.insert(preferences)
        try context.save()
    }

    // MARK: - Default values (spec §3.8: fontSize=18, lineHeight=1.6, contentWidth=680)

    @Test("Default preferences produce token CSS with spec-specified defaults")
    func defaultValues() {
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-font-size: 18px"))
        #expect(css.contains("--lens-line-height: 1.6"))
        #expect(css.contains("--lens-content-width: 680px"))
    }

    // MARK: - Individual token fields

    @Test("Font size preference appears as --lens-font-size in token CSS")
    func fontSizeToken() {
        preferences.fontSize = 22
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-font-size: 22px"))
    }

    @Test("Font family preference appears as --lens-font-family in token CSS")
    func fontFamilyToken() {
        preferences.fontFamily = "Georgia"
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-font-family: Georgia"))
    }

    @Test("Line height preference appears as --lens-line-height in token CSS")
    func lineHeightToken() {
        preferences.lineHeight = 1.8
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-line-height: 1.8"))
    }

    @Test("Content width preference appears as --lens-content-width in token CSS")
    func contentWidthToken() {
        preferences.contentWidth = 760
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-content-width: 760px"))
    }

    // MARK: - Appearance override colours

    @Test("System appearance emits CSS Canvas keyword for --lens-bg")
    func systemAppearanceBackground() {
        preferences.appearanceOverride = .system
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-bg: Canvas"))
        #expect(css.contains("--lens-text: CanvasText"))
    }

    @Test("Light appearance override emits white background")
    func lightAppearanceBackground() {
        preferences.appearanceOverride = .light
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-bg: #ffffff"))
        #expect(css.contains("--lens-text: #000000"))
    }

    @Test("Dark appearance override emits dark background")
    func darkAppearanceBackground() {
        preferences.appearanceOverride = .dark
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-bg: #1c1c1e"))
        #expect(css.contains("--lens-text: #ffffff"))
    }

    // MARK: - All eight tokens present

    @Test("Token CSS contains all eight --lens-* custom properties")
    func allEightTokensPresent() {
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains(TokenLayer.bg))
        #expect(css.contains(TokenLayer.text))
        #expect(css.contains(TokenLayer.link))
        #expect(css.contains(TokenLayer.fontFamily))
        #expect(css.contains(TokenLayer.fontSize))
        #expect(css.contains(TokenLayer.lineHeight))
        #expect(css.contains(TokenLayer.contentWidth))
        #expect(css.contains(TokenLayer.codeFont))
    }

    @Test("Public token name constants match variable names in generated CSS output")
    func tokenNameConstantsMatchOutput() {
        let css = TokenLayer.tokenCSS(from: preferences)
        // Spot-check that the constants we expose to addon authors are what appears in output.
        for name in [TokenLayer.bg, TokenLayer.text, TokenLayer.fontFamily,
                     TokenLayer.fontSize, TokenLayer.codeFont] {
            #expect(css.contains(name), "Expected to find \(name) in token CSS")
        }
    }
}
```

- [ ] **Step 2: Write ThemeEngineTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Theme/ThemeEngineTests.swift`:

```swift
// ThemeEngineTests.swift — Verify that composedCSS joins all three layers
// in the correct order and that preference values flow through to the output.
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("ThemeEngine")
struct ThemeEngineTests {

    // MARK: - Setup

    let container: ModelContainer
    let preferences: UserReadingPreferences

    init() throws {
        container = try ModelContainer(
            for: UserReadingPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        preferences = UserReadingPreferences()
        context.insert(preferences)
        try context.save()
    }

    // MARK: - Layer presence

    @Test("composedCSS output contains markers from all three layers")
    func containsAllThreeLayers() {
        let output = ThemeEngine.composedCSS(
            preferences: preferences,
            themeCSS: "/* sentinel-theme */"
        )
        #expect(output.contains("Lens structural layer"))
        #expect(output.contains("Lens token layer"))
        #expect(output.contains("/* sentinel-theme */"))
    }

    @Test("composedCSS uses BuiltInTheme default when no themeCSS provided")
    func defaultThemeFallback() {
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("Lens default theme layer"))
    }

    // MARK: - Layer ordering

    @Test("Structural layer appears before token layer in output")
    func structuralBeforeToken() {
        let output = ThemeEngine.composedCSS(preferences: preferences)
        let structuralRange = output.range(of: "Lens structural layer")
        let tokenRange = output.range(of: "Lens token layer")
        guard let s = structuralRange, let t = tokenRange else {
            Issue.record("Layer markers not found in output")
            return
        }
        #expect(s.lowerBound < t.lowerBound)
    }

    @Test("Token layer appears before theme layer in output")
    func tokenBeforeTheme() {
        let output = ThemeEngine.composedCSS(
            preferences: preferences,
            themeCSS: "/* sentinel-theme */"
        )
        let tokenRange = output.range(of: "Lens token layer")
        let themeRange = output.range(of: "/* sentinel-theme */")
        guard let t = tokenRange, let th = themeRange else {
            Issue.record("Layer markers not found in output")
            return
        }
        #expect(t.lowerBound < th.lowerBound)
    }

    // MARK: - Preference values flow through

    @Test("Font size from preferences appears in composed output")
    func fontSizeFlowsThrough() {
        preferences.fontSize = 20
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("--lens-font-size: 20px"))
    }

    @Test("Content width from preferences appears in composed output")
    func contentWidthFlowsThrough() {
        preferences.contentWidth = 800
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("--lens-content-width: 800px"))
    }

    @Test("Dark appearance produces dark token values in composed output")
    func darkAppearanceTokenInOutput() {
        preferences.appearanceOverride = .dark
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("--lens-bg: #1c1c1e"))
    }

    // MARK: - Addon theme override

    @Test("Passing addon CSS string replaces the default theme layer")
    func addonThemeReplaceDefault() {
        let addonCSS = "body { background: hotpink; } /* addon-override */"
        let output = ThemeEngine.composedCSS(preferences: preferences, themeCSS: addonCSS)
        #expect(output.contains("/* addon-override */"))
        // Default theme layer should not be present when a custom theme is supplied.
        #expect(!output.contains("Lens default theme layer"))
    }
}
```

- [ ] **Step 3: Add files to Xcode** **(Human)**

1. In Xcode Project Navigator, right-click **LensCore** → **New Group** → `Theme`.
2. Right-click **LensCore/Theme** → **Add Files to "Lens"…**
3. Select `BuiltInTheme.swift`, `TokenLayer.swift`, `ThemeEngine.swift` → **Add** (Create groups, uncheck "Copy items if needed"), target: **LensCore** only.
4. Delete `LensCore/Theme/.gitkeep` from the Xcode group (right-click → Delete → Move to Trash) and from disk: `rm LensCore/Theme/.gitkeep`.
5. In **LensCoreTests**, right-click → **New Group** → `Theme`.
6. Right-click **LensCoreTests/Theme** → **Add Files to "Lens"…**
7. Select `TokenLayerTests.swift`, `ThemeEngineTests.swift` → **Add**, target: **LensCoreTests**.
8. Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: All prior tests pass. `TokenLayerTests` reports **10 tests pass**. `ThemeEngineTests` reports **9 tests pass**. No failures.

---

## Task 4: Write LensRoute.swift and DeepLinkRouter.swift

**(Agent)**

**Files:**
- Create: `LensCore/Routing/LensRoute.swift`
- Create: `LensCore/Routing/DeepLinkRouter.swift`

- [ ] **Step 1: Write LensRoute.swift**

Create `/Users/rich/Developer/lens/LensCore/Routing/LensRoute.swift`:

```swift
// LensRoute.swift — Parsed result of a lens:// deep link URL.
//
// DeepLinkRouter.route(from:) produces a LensRoute from a URL.
// DeepLinkRouter.handle(_:bus:) converts the route to the appropriate
// LensEvent navigation case and emits it on EventBus.
//
// Each case maps 1:1 to a URL pattern in spec §4.12.
// LensRoute is separate from LensEvent to keep URL parsing testable
// without requiring an actor or async context.
import Foundation

/// A fully-parsed `lens://` deep link destination.
///
/// Produced by `DeepLinkRouter.route(from:)`. Corresponds to the URL scheme
/// table in spec §4.12. Unrecognised URLs return `nil` from the parser.
public enum LensRoute: Equatable, Sendable {
    /// `lens://feed/add` or `lens://feed/add?url=<encoded>`
    case addFeed(prefillURL: URL?)
    /// `lens://feed/<uuid>`
    case viewFeed(feedId: UUID)
    /// `lens://item/<uuid>`
    case viewItem(itemId: UUID)
    /// `lens://saved`
    case saved
    /// `lens://settings`
    case settings
    /// `lens://import?opml=<url>`
    case importOPML(sourceURL: URL)
}
```

- [ ] **Step 2: Write DeepLinkRouter.swift**

Create `/Users/rich/Developer/lens/LensCore/Routing/DeepLinkRouter.swift`:

```swift
// DeepLinkRouter.swift — Parses lens:// URLs and emits navigation events.
//
// URL structure parsed (spec §4.12):
//
//   lens://feed/add[?url=<encoded>]    → .navigateToAddFeed(prefillURL:)
//   lens://feed/<uuid>                 → .navigateToFeed(feedId:)
//   lens://item/<uuid>                 → .navigateToItem(itemId:)
//   lens://saved                       → .navigateToSaved
//   lens://settings                    → .navigateToSettings
//   lens://import?opml=<url>           → .navigateToOPMLImport(sourceURL:)
//
// Wire this at scene level in LensIOS and LensMac:
//
//   .onOpenURL { url in
//       Task { await DeepLinkRouter.handle(url) }
//   }
//
// This also enables Shortcuts app integration for free (spec §4.12).
import Foundation

public enum DeepLinkRouter {

    // MARK: - URL parsing

    /// Parse a `lens://` URL into a `LensRoute`.
    ///
    /// Returns `nil` for:
    /// - Non-`lens` schemes
    /// - Recognised hosts with malformed path components (e.g. non-UUID where UUID expected)
    /// - Unrecognised hosts
    ///
    /// Silent `nil` on failure is intentional — unrecognised URLs should not crash
    /// or surface errors to the user (they may come from future Lens versions).
    public static func route(from url: URL) -> LensRoute? {
        guard url.scheme == "lens" else { return nil }

        let host = url.host ?? ""
        // lastPathComponent is "" for URLs with no path (lens://saved → host="saved", path="")
        // and the final path segment otherwise (lens://feed/add → "add").
        let lastComponent = url.lastPathComponent

        switch host {
        case "feed":
            if lastComponent == "add" {
                // lens://feed/add or lens://feed/add?url=<encoded>
                let prefillURL = queryItems(from: url)
                    .first(where: { $0.name == "url" })
                    .flatMap { $0.value.flatMap(URL.init(string:)) }
                return .addFeed(prefillURL: prefillURL)
            } else if let id = UUID(uuidString: lastComponent) {
                // lens://feed/<uuid>
                return .viewFeed(feedId: id)
            }
            return nil

        case "item":
            // lens://item/<uuid>
            guard let id = UUID(uuidString: lastComponent) else { return nil }
            return .viewItem(itemId: id)

        case "saved":
            return .saved

        case "settings":
            return .settings

        case "import":
            // lens://import?opml=<url>
            guard
                let opmlValue = queryItems(from: url).first(where: { $0.name == "opml" })?.value,
                let sourceURL = URL(string: opmlValue)
            else { return nil }
            return .importOPML(sourceURL: sourceURL)

        default:
            return nil
        }
    }

    // MARK: - Event emission

    /// Parse `url` and emit the corresponding navigation event on `bus`.
    ///
    /// Unrecognised or malformed URLs are silently ignored — no event is emitted.
    ///
    /// - Parameters:
    ///   - url: The URL received from `onOpenURL` or a Shortcuts automation.
    ///   - bus: Event bus to emit on. Defaults to `EventBus.shared`.
    ///     Pass a fresh `EventBus()` in tests to keep test runs isolated.
    public static func handle(_ url: URL, bus: EventBus = EventBus.shared) async {
        guard let route = route(from: url) else { return }

        let event: LensEvent
        switch route {
        case .addFeed(let prefillURL):
            event = .navigateToAddFeed(prefillURL: prefillURL)
        case .viewFeed(let feedId):
            event = .navigateToFeed(feedId: feedId)
        case .viewItem(let itemId):
            event = .navigateToItem(itemId: itemId)
        case .saved:
            event = .navigateToSaved
        case .settings:
            event = .navigateToSettings
        case .importOPML(let sourceURL):
            event = .navigateToOPMLImport(sourceURL: sourceURL)
        }

        await bus.emit(event)
    }

    // MARK: - Private helpers

    private static func queryItems(from url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }
}
```

---

## Task 5: Write DeepLinkRouterTests.swift, add to Xcode, run tests

**(Both)**

**Files:**
- Create: `LensCoreTests/Routing/DeepLinkRouterTests.swift`

- [ ] **Step 1: Write DeepLinkRouterTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Routing/DeepLinkRouterTests.swift`:

```swift
// DeepLinkRouterTests.swift — Tests for URL parsing (route(from:)) and
// event emission (handle(_:bus:)) in DeepLinkRouter.
//
// Parsing tests are synchronous — route(from:) is a pure function.
// Emission tests are async — handle(_:bus:) calls EventBus.emit which is actor-isolated.
// Each emission test uses a fresh EventBus() to avoid shared-state interference.
import Testing
import Foundation
@testable import LensCore

@Suite("DeepLinkRouter")
struct DeepLinkRouterTests {

    // MARK: - route(from:) — parsing

    @Test("lens://feed/add with url param returns addFeed with prefill URL")
    func addFeedWithURL() throws {
        let url = try #require(URL(string: "lens://feed/add?url=https://example.com/feed.xml"))
        let route = DeepLinkRouter.route(from: url)
        #expect(route == .addFeed(prefillURL: URL(string: "https://example.com/feed.xml")))
    }

    @Test("lens://feed/add without url param returns addFeed with nil prefillURL")
    func addFeedWithoutURL() throws {
        let url = try #require(URL(string: "lens://feed/add"))
        let route = DeepLinkRouter.route(from: url)
        #expect(route == .addFeed(prefillURL: nil))
    }

    @Test("lens://feed/<uuid> returns viewFeed with correct feedId")
    func viewFeedRoute() throws {
        let id = UUID()
        let url = try #require(URL(string: "lens://feed/\(id.uuidString)"))
        #expect(DeepLinkRouter.route(from: url) == .viewFeed(feedId: id))
    }

    @Test("lens://item/<uuid> returns viewItem with correct itemId")
    func viewItemRoute() throws {
        let id = UUID()
        let url = try #require(URL(string: "lens://item/\(id.uuidString)"))
        #expect(DeepLinkRouter.route(from: url) == .viewItem(itemId: id))
    }

    @Test("lens://saved returns .saved")
    func savedRoute() throws {
        let url = try #require(URL(string: "lens://saved"))
        #expect(DeepLinkRouter.route(from: url) == .saved)
    }

    @Test("lens://settings returns .settings")
    func settingsRoute() throws {
        let url = try #require(URL(string: "lens://settings"))
        #expect(DeepLinkRouter.route(from: url) == .settings)
    }

    @Test("lens://import with opml param returns importOPML with source URL")
    func importOPMLRoute() throws {
        let url = try #require(URL(string: "lens://import?opml=https://example.com/feeds.opml"))
        let route = DeepLinkRouter.route(from: url)
        #expect(route == .importOPML(sourceURL: URL(string: "https://example.com/feeds.opml")!))
    }

    @Test("Unrecognised lens:// host returns nil")
    func unknownHostReturnsNil() throws {
        let url = try #require(URL(string: "lens://unrecognised"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("Non-lens scheme returns nil")
    func nonLensSchemeReturnsNil() throws {
        let url = try #require(URL(string: "https://example.com/feed/123"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("lens://feed with non-UUID path component returns nil")
    func nonUUIDFeedPathReturnsNil() throws {
        let url = try #require(URL(string: "lens://feed/not-a-uuid"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("lens://item with non-UUID path component returns nil")
    func nonUUIDItemPathReturnsNil() throws {
        let url = try #require(URL(string: "lens://item/not-a-uuid"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("lens://import without opml param returns nil")
    func importWithoutOPMLParamReturnsNil() throws {
        let url = try #require(URL(string: "lens://import"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    // MARK: - handle(_:bus:) — event emission

    @Test("handle emits .navigateToSaved for lens://saved")
    func emitsNavigateToSaved() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let url = try #require(URL(string: "lens://saved"))

        await DeepLinkRouter.handle(url, bus: bus)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .navigateToSaved)
    }

    @Test("handle emits .navigateToSettings for lens://settings")
    func emitsNavigateToSettings() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let url = try #require(URL(string: "lens://settings"))

        await DeepLinkRouter.handle(url, bus: bus)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .navigateToSettings)
    }

    @Test("handle emits .navigateToFeed for lens://feed/<uuid>")
    func emitsNavigateToFeed() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let id = UUID()
        let url = try #require(URL(string: "lens://feed/\(id.uuidString)"))

        await DeepLinkRouter.handle(url, bus: bus)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .navigateToFeed(feedId: id))
    }

    @Test("handle emits nothing for an unrecognised URL")
    func emitsNothingForUnknownURL() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let unknownURL = try #require(URL(string: "https://example.com"))

        await DeepLinkRouter.handle(unknownURL, bus: bus)

        // Emit a sentinel after the unknown URL.
        // If the unknown URL produced no event, the sentinel is the first thing received.
        await bus.emit(.userInitiatedRefresh)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .userInitiatedRefresh)
    }
}
```

- [ ] **Step 2: Add files to Xcode** **(Human)**

1. In Xcode Project Navigator, right-click **LensCore** → **New Group** → `Routing`.
2. Right-click **LensCore/Routing** → **Add Files to "Lens"…**
3. Select `LensRoute.swift`, `DeepLinkRouter.swift` → **Add**, target: **LensCore** only.
4. Delete `LensCore/Routing/.gitkeep` from the Xcode group and from disk: `rm LensCore/Routing/.gitkeep`.
5. In **LensCoreTests**, right-click → **New Group** → `Routing`.
6. Right-click **LensCoreTests/Routing** → **Add Files to "Lens"…**
7. Select `DeepLinkRouterTests.swift` → **Add**, target: **LensCoreTests**.
8. Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: All prior tests pass. `DeepLinkRouterTests` reports **16 tests pass**. No failures.

---

## Task 6: Add onOpenURL wiring to LensIOS and LensMac; register lens:// scheme

**(Both)**

**Files:**
- Modify: `LensIOS/LensApp.swift`
- Modify: `LensMac/LensMacApp.swift`

- [ ] **Step 1: Add onOpenURL to LensIOS/LensApp.swift** **(Agent)**

Read `LensIOS/LensApp.swift` in full, then add the `.onOpenURL` modifier to the root view inside the `WindowGroup`. The modifier is a view-level addition — it wraps whatever view is currently at the root:

```swift
// Add this import at the top if not already present:
import LensCore

// Find the WindowGroup body and add the modifier to the root view.
// Example — if the current root view is ContentView(), change it to:
WindowGroup {
    ContentView()
        .onOpenURL { url in
            // Route lens:// URLs to DeepLinkRouter on a background Task.
            // onOpenURL provides the URL synchronously; async bridged here.
            Task {
                await DeepLinkRouter.handle(url)
            }
        }
}
```

If the root view is something other than `ContentView()` (e.g. a placeholder from Phase 1), apply the modifier to whatever view is currently there. Do not change the view itself — only append `.onOpenURL { … }`.

- [ ] **Step 2: Add onOpenURL to LensMac/LensMacApp.swift** **(Agent)**

Read `LensMac/LensMacApp.swift` in full, then apply the identical pattern:

```swift
// Add this import at the top if not already present:
import LensCore

// Modify the WindowGroup root view to include:
WindowGroup {
    ContentView()   // or whatever the current root view is
        .onOpenURL { url in
            Task {
                await DeepLinkRouter.handle(url)
            }
        }
}
```

- [ ] **Step 3: Register the lens:// URL scheme in Xcode** **(Human)**

Repeat for **both** the `LensIOS` target and the `LensMac` target:

1. Select the target in the project navigator → **Info** tab → **URL Types** section.
2. Click **+** to add a new URL type.
3. Set **Identifier** to `com.richardtape.lens`.
4. Set **URL Schemes** to `lens`.
5. Leave **Role** as **Editor**.

This registers the scheme so the OS routes `lens://…` URLs to Lens rather than a browser.

- [ ] **Step 4: Build both targets and verify** **(Human)**

1. Select scheme **LensIOS**, destination **iPhone Simulator** → **⌘B**.
   Expected: Clean build. No errors.
2. Select scheme **LensMac**, destination **My Mac** → **⌘B**.
   Expected: Clean build. No errors.
3. On macOS: Run the LensMac scheme (⌘R), then open Safari and type `lens://settings` in the address bar and press Enter.
   Expected: Lens activates (or comes to the foreground) and the event `LensEvent.navigateToSettings` is emitted on the bus. (There is no Settings UI yet — what matters is that the app handles the URL without crashing. Add a `print` statement in the `onOpenURL` handler temporarily if you need to confirm receipt.)

---

## Task 7: Update agent-orientation.md and commit

**(Both)**

**Files:**
- Modify: `docs/superpowers/2026-04-10-lens-agent-orientation.md`

- [ ] **Step 1: Update the Current state section** **(Agent)**

Replace the `## Current state` block with:

```markdown
## Current state

**Phase 2A complete; Phase 2B complete; Phase 2C complete; Phase 2D complete; Phase 2E complete.**

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
- `lens://` URL scheme registered in both iOS and macOS targets.
- Six new `LensEvent` cases: `.navigateToAddFeed`, `.navigateToFeed`, `.navigateToItem`, `.navigateToSaved`, `.navigateToSettings`, `.navigateToOPMLImport`.

**Phase 2 complete.** Next: Phase 3 — Timeline UI.
```

- [ ] **Step 2: Stage and commit** **(Human)**

```bash
cd /Users/rich/Developer/lens
git add \
  LensCore/Theme/BuiltInTheme.swift \
  LensCore/Theme/TokenLayer.swift \
  LensCore/Theme/ThemeEngine.swift \
  LensCore/Routing/LensRoute.swift \
  LensCore/Routing/DeepLinkRouter.swift \
  LensCore/Events/LensEvent.swift \
  LensCoreTests/Theme/TokenLayerTests.swift \
  LensCoreTests/Theme/ThemeEngineTests.swift \
  LensCoreTests/Routing/DeepLinkRouterTests.swift \
  LensCoreTests/Events/LensEventTests.swift \
  LensIOS/LensApp.swift \
  LensMac/LensMacApp.swift \
  docs/superpowers/2026-04-10-lens-agent-orientation.md \
  Lens.xcodeproj/project.pbxproj
git status
git commit -m "feat(phase-2e): ThemeEngine skeleton + DeepLinkRouter + lens:// URL handling"
```

Expected: commit succeeds with those files listed.

---

## Phase 2E exit criteria

Before declaring Phase 2E done:

- [ ] `LensCore/Theme/` contains `BuiltInTheme.swift`, `TokenLayer.swift`, `ThemeEngine.swift`.
- [ ] `LensCore/Routing/` contains `LensRoute.swift`, `DeepLinkRouter.swift`.
- [ ] `LensEvent` has six `.navigateTo*` cases (addFeed, feed, item, saved, settings, OPMLImport).
- [ ] `ThemeEngine.composedCSS` joins three layers; `TokenLayer.tokenCSS` generates all eight `--lens-*` variables.
- [ ] `DeepLinkRouter.route(from:)` correctly parses all six `lens://` URL patterns from spec §4.12.
- [ ] `DeepLinkRouter.handle(_:bus:)` emits the correct `LensEvent` for each route.
- [ ] All `TokenLayerTests` pass (10 tests).
- [ ] All `ThemeEngineTests` pass (9 tests).
- [ ] All `DeepLinkRouterTests` pass (16 tests).
- [ ] All Phase 2A / 2B / 2C / 2D tests still pass.
- [ ] `lens://` URL scheme registered in both LensIOS and LensMac Xcode targets.
- [ ] Both targets build cleanly; macOS target handles `lens://settings` URL without crashing.
- [ ] `agent-orientation.md` **Current state** section reflects Phase 2 completion.
- [ ] Changes committed.

---

## What's next

**Phase 3** — Timeline UI:
- Main chronological stream (`NavigationSplitView` on iPad/Mac, stacked navigation on iPhone).
- Read/unread state, bulk actions, new-items banner (main timeline only).
- Quick filters (unread only, by category, by feed).
- macOS single-letter keyboard shortcuts (spec §3.1).
- iOS swipe and long-press gestures (spec §3.1).
- Feed health indicators (badges, error rows, Retry button).
- Depends on: Phase 2 (all modules now in place).
