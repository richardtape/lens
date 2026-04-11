# Lens Phase 2C — Feed Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build three working feed parsers (RSS 2.0/RDF, Atom 1.0, JSON Feed 1.1), an extensible `FeedFactory` that selects a parser by MIME type or content sniffing, and a minimal `FeedService` actor that fetches a feed URL, stores new items in SwiftData, and emits typed events.

**Architecture:** All files go in `LensCore/Feeds/`. Parsers are pure value types (`struct`) with no SwiftData or networking dependency — they take `Data` and return a `ParsedFeed` struct, making them fully unit-testable without infrastructure. `FeedFactory` is an actor to support concurrent fetches and future addon-registered parsers. `FeedService` is an actor that owns the fetch/parse/persist loop; it creates a background `ModelContext` per operation (never touching the main-thread context) and emits to `EventBus`. No background scheduling in this phase — that is Phase 5.

**Tech Stack:** Swift 6, Foundation (`XMLParser`, `URLSession`, `ISO8601DateFormatter`), SwiftData (`ModelContext`, `FetchDescriptor`), Swift Testing, Xcode 26.3.

---

## Driver legend

- **(Agent)** — agent writes files; no Xcode interaction needed.
- **(Human)** — requires Xcode GUI.
- **(Both)** — agent writes, human runs a command or verifies.

---

## File structure

```
LensCore/Feeds/
├── ParsedFeed.swift            (Create) ParsedFeed + ParsedFeedItem value types; shared helpers
├── FeedParser.swift            (Create) FeedParser protocol + FeedParseError enum
├── RSSParser.swift             (Create) RSS 2.0 / RDF parser using XMLParser
├── AtomParser.swift            (Create) Atom 1.0 parser using XMLParser
├── JSONFeedParser.swift        (Create) JSON Feed 1.1 parser using Codable
├── FeedFactory.swift           (Create) Extensible factory; selects parser by MIME / sniff
└── FeedService.swift           (Create) Fetch → parse → persist → emit; minimal, no scheduling

LensCoreTests/Feeds/
├── RSSParserTests.swift        (Create)
├── AtomParserTests.swift       (Create)
├── JSONFeedParserTests.swift   (Create)
└── FeedFactoryTests.swift      (Create)
```

> **Xcode note:** After each agent task, files exist on disk but must be added to Xcode. A dedicated Human step tells you exactly when and how.
>
> **`.gitkeep` cleanup:** `LensCore/Feeds/` has a `.gitkeep` from Phase 0. Delete it (Xcode group + Trash) when adding the first real file.

---

## Task 1: Shared types — ParsedFeed.swift and FeedParser.swift

**(Agent)**

**Files:**
- Create: `LensCore/Feeds/ParsedFeed.swift`
- Create: `LensCore/Feeds/FeedParser.swift`

- [ ] **Step 1: Write ParsedFeed.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/ParsedFeed.swift`:

```swift
// ParsedFeed.swift — Intermediate value types produced by feed parsers.
//
// These types are pure Swift — no SwiftData, no SwiftUI. They live between
// the wire format (XML / JSON bytes) and the SwiftData store, allowing parsers
// to be unit-tested without any infrastructure.
import Foundation

// MARK: - ParsedFeed

/// The top-level result of parsing a feed document.
public struct ParsedFeed: Sendable {
    /// Feed title from the document (may be empty if the feed omits it).
    public var title: String
    /// All items found in the document, in document order (not sorted by date).
    public var items: [ParsedFeedItem]

    public init(title: String, items: [ParsedFeedItem] = []) {
        self.title = title
        self.items = items
    }
}

// MARK: - ParsedFeedItem

/// One item/entry from a parsed feed.
///
/// All fields map directly to `FeedItem` SwiftData properties (spec §7.1).
/// Afforded fields (`thumbnailURL`, `estimatedReadMinutes`, `enclosureURL`,
/// `enclosureMIMEType`) are populated at parse time per the spec's note
/// "populated at parse time" — they are stored but not displayed in v1 UI.
public struct ParsedFeedItem: Sendable {
    public var stableId: String        // guid / entry id / JSON Feed id
    public var title: String
    public var link: URL?
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var summaryHTML: String?
    public var contentHTML: String?
    public var thumbnailURL: URL?      // afforded: card view not active in v1
    public var estimatedReadMinutes: Int?  // afforded: not displayed in v1
    public var enclosureURL: URL?      // afforded: not active in v1
    public var enclosureMIMEType: String?  // afforded: not active in v1

    public init(stableId: String, title: String) {
        self.stableId = stableId
        self.title = title
    }
}

// MARK: - Shared helpers

extension ParsedFeedItem {
    /// Estimates reading time from HTML, or nil if the content is too short to bother.
    /// Strips HTML tags with a regex and counts whitespace-separated words at ~200 wpm.
    static func estimateReadMinutes(fromHTML html: String?) -> Int? {
        guard let html, !html.isEmpty else { return nil }
        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= 50 else { return nil }
        return max(1, wordCount / 200)
    }
}
```

- [ ] **Step 2: Write FeedParser.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/FeedParser.swift`:

```swift
// FeedParser.swift — Protocol and errors for all feed parsers.
//
// Concrete parsers (RSSParser, AtomParser, JSONFeedParser) conform to this
// protocol. The addon system will register additional parsers via FeedFactory.
import Foundation

// MARK: - FeedParser protocol

/// A parser that converts raw feed bytes into a `ParsedFeed` value.
///
/// Parsers are stateless value types (`struct`). The two-method contract lets
/// `FeedFactory` probe parsers cheaply via `canParse` before committing to a
/// full parse. All methods are synchronous — XML and JSON parsing is CPU-bound
/// and fast enough to run inline; callers dispatch to a background context.
public protocol FeedParser: Sendable {
    /// Returns true if this parser can handle the given data and MIME type.
    ///
    /// Implementations should first check `mimeType` (authoritative when present),
    /// then inspect the leading bytes of `data` as a fallback.
    /// `mimeType` may be nil when the server omits a Content-Type header.
    func canParse(data: Data, mimeType: String?) -> Bool

    /// Parse `data` into a `ParsedFeed`.
    ///
    /// - Throws: `FeedParseError` for malformed or unrecognised content.
    func parse(data: Data, feedURL: URL) throws -> ParsedFeed
}

// MARK: - FeedParseError

public enum FeedParseError: Error, Sendable {
    /// The data does not match any format this parser handles.
    case unrecognisedFormat
    /// XML was syntactically invalid. The associated string is from `XMLParser.parserError`.
    case malformedXML(String)
    /// JSON was syntactically invalid or missing required fields.
    case malformedJSON(String)
    /// The feed contained no items.
    case emptyFeed
}
```

---

## Task 2: RSS 2.0 / RDF parser

**(Agent)**

**Files:**
- Create: `LensCore/Feeds/RSSParser.swift`

RSS 2.0 and RSS 1.0 (RDF) both use an `<item>` element for entries. The key difference (root element `<rss>` vs `<rdf:RDF>`) is handled in `canParse`. The SAX delegate uses an `inItem` flag to distinguish channel-level `<title>` from item-level `<title>`.

- [ ] **Step 1: Write RSSParser.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/RSSParser.swift`:

```swift
// RSSParser.swift — Parses RSS 2.0 and RSS 1.0 (RDF) feeds using XMLParser.
//
// XMLParser is a SAX-style parser: it calls delegate methods as it reads
// through the document rather than building a full DOM. This keeps memory
// constant regardless of feed size.
//
// Namespace handling: XMLParser.shouldProcessNamespaces defaults to false,
// so qualified names like "content:encoded" arrive as-is in elementName.
// We rely on this behaviour for content:encoded and media:thumbnail matching.
import Foundation

// MARK: - RSSParser

public struct RSSParser: FeedParser {
    public init() {}

    public func canParse(data: Data, mimeType: String?) -> Bool {
        if let mime = mimeType?.lowercased() {
            if mime.contains("rss") || mime.contains("rdf") { return true }
        }
        // Sniff the first 512 bytes for RSS / RDF root-element signatures.
        let prefix = String(data: data.prefix(512), encoding: .utf8) ?? ""
        return prefix.contains("<rss") || prefix.contains("<rdf:RDF")
    }

    public func parse(data: Data, feedURL: URL) throws -> ParsedFeed {
        let delegate = RSSXMLDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        // shouldProcessNamespaces stays false (default) so we see "content:encoded"
        // and "media:thumbnail" as literal elementName strings.
        guard xmlParser.parse() else {
            let msg = xmlParser.parserError?.localizedDescription ?? "Unknown XML error"
            throw FeedParseError.malformedXML(msg)
        }
        return ParsedFeed(title: delegate.feedTitle, items: delegate.items)
    }
}

// MARK: - SAX delegate (private)

/// Mutable accumulator for one RSS item during SAX parsing.
private struct RSSItemAccumulator {
    var stableId: String = ""
    var title: String = ""
    var link: URL? = nil
    var publishedAt: Date? = nil
    var summaryHTML: String? = nil
    var contentHTML: String? = nil
    var thumbnailURL: URL? = nil
    var enclosureURL: URL? = nil
    var enclosureMIMEType: String? = nil

    func toParseItem() -> ParsedFeedItem {
        var item = ParsedFeedItem(
            stableId: stableId.isEmpty ? (link?.absoluteString ?? UUID().uuidString) : stableId,
            title: title
        )
        item.link = link
        item.publishedAt = publishedAt
        item.summaryHTML = summaryHTML
        item.contentHTML = contentHTML
        item.thumbnailURL = thumbnailURL
        item.enclosureURL = enclosureURL
        item.enclosureMIMEType = enclosureMIMEType
        item.estimatedReadMinutes = ParsedFeedItem.estimateReadMinutes(fromHTML: contentHTML ?? summaryHTML)
        return item
    }
}

private final class RSSXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var feedTitle: String = ""
    private(set) var items: [ParsedFeedItem] = []

    private var inItem = false
    private var currentElement = ""
    private var currentText = ""
    private var accumulator = RSSItemAccumulator()

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName _: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "item":
            inItem = true
            accumulator = RSSItemAccumulator()

        case "enclosure" where inItem:
            // <enclosure url="..." type="audio/mpeg" length="..."/>
            accumulator.enclosureURL = attributeDict["url"].flatMap(URL.init(string:))
            accumulator.enclosureMIMEType = attributeDict["type"]

        case "media:thumbnail" where inItem:
            // <media:thumbnail url="..."/>
            accumulator.thumbnailURL = attributeDict["url"].flatMap(URL.init(string:))

        case "media:content" where inItem:
            // <media:content url="..." medium="image"/> — use as thumbnail fallback
            if accumulator.thumbnailURL == nil,
               attributeDict["medium"] == "image" || attributeDict["type"]?.hasPrefix("image") == true {
                accumulator.thumbnailURL = attributeDict["url"].flatMap(URL.init(string:))
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // CDATA sections are common for description and content:encoded.
        currentText += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName _: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            switch elementName {
            case "title":           accumulator.title = text
            case "link":            accumulator.link = URL(string: text)
            case "guid":            accumulator.stableId = text
            case "pubDate":         accumulator.publishedAt = Self.parseRSSDate(text)
            case "description":     accumulator.summaryHTML = text.isEmpty ? nil : text
            case "content:encoded": accumulator.contentHTML = text.isEmpty ? nil : text
            case "item":
                items.append(accumulator.toParseItem())
                inItem = false
                accumulator = RSSItemAccumulator()
            default: break
            }
        } else {
            // Channel-level elements. We only care about <title> here.
            if elementName == "title" && feedTitle.isEmpty {
                feedTitle = text
            }
        }

        currentText = ""
    }

    // MARK: - Date parsing

    /// RSS uses RFC 2822 dates: "Mon, 01 Jan 2024 12:00:00 +0000" or "…GMT".
    private static func parseRSSDate(_ string: String) -> Date? {
        // Try formats in order: numeric offset, then timezone abbreviation.
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss zzz",
        ]
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let date = f.date(from: string) { return date }
        }
        return nil
    }
}
```

---

## Task 3: Atom 1.0 parser

**(Agent)**

**Files:**
- Create: `LensCore/Feeds/AtomParser.swift`

Atom uses `<link href="…"/>` (attribute, not text content) and ISO 8601 dates. The `<content>` element often has `type="html"`.

- [ ] **Step 1: Write AtomParser.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/AtomParser.swift`:

```swift
// AtomParser.swift — Parses Atom 1.0 feeds using XMLParser.
//
// Key Atom quirks vs RSS:
//   • <link> carries its URL in the `href` attribute, not text content.
//     We capture it in didStartElement, not didEndElement.
//   • Dates are ISO 8601 (handled by ISO8601DateFormatter).
//   • The feed title and entry titles may be plain text or have type="html".
//   • <content type="html"> is common; we also accept type="xhtml" bodies
//     (rare; treated as text for simplicity in v1).
import Foundation

// MARK: - AtomParser

public struct AtomParser: FeedParser {
    public init() {}

    public func canParse(data: Data, mimeType: String?) -> Bool {
        if let mime = mimeType?.lowercased(), mime.contains("atom") { return true }
        // Sniff for the Atom namespace or root element name.
        let prefix = String(data: data.prefix(512), encoding: .utf8) ?? ""
        return prefix.contains("http://www.w3.org/2005/Atom")
    }

    public func parse(data: Data, feedURL: URL) throws -> ParsedFeed {
        let delegate = AtomXMLDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        guard xmlParser.parse() else {
            let msg = xmlParser.parserError?.localizedDescription ?? "Unknown XML error"
            throw FeedParseError.malformedXML(msg)
        }
        return ParsedFeed(title: delegate.feedTitle, items: delegate.items)
    }
}

// MARK: - SAX delegate (private)

private struct AtomEntryAccumulator {
    var stableId: String = ""
    var title: String = ""
    var link: URL? = nil
    var publishedAt: Date? = nil
    var updatedAt: Date? = nil
    var summaryHTML: String? = nil
    var contentHTML: String? = nil
    var thumbnailURL: URL? = nil

    func toParseItem() -> ParsedFeedItem {
        var item = ParsedFeedItem(
            stableId: stableId.isEmpty ? (link?.absoluteString ?? UUID().uuidString) : stableId,
            title: title
        )
        item.link = link
        item.publishedAt = publishedAt
        item.updatedAt = updatedAt
        item.summaryHTML = summaryHTML
        item.contentHTML = contentHTML
        item.thumbnailURL = thumbnailURL
        item.estimatedReadMinutes = ParsedFeedItem.estimateReadMinutes(fromHTML: contentHTML ?? summaryHTML)
        return item
    }
}

private final class AtomXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var feedTitle: String = ""
    private(set) var items: [ParsedFeedItem] = []

    private var inEntry = false
    // Track whether we're directly inside <feed> (depth == 1) or <entry> (depth == 2+)
    private var elementDepth = 0
    private var currentElement = ""
    private var currentText = ""
    private var accumulator = AtomEntryAccumulator()

    private static let iso8601 = ISO8601DateFormatter()

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName _: String?,
                attributes attributeDict: [String: String] = [:]) {
        elementDepth += 1
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "entry":
            inEntry = true
            accumulator = AtomEntryAccumulator()

        case "link" where inEntry:
            // <link rel="alternate" href="…"/> or <link href="…"/>
            // We want the article permalink; rel="alternate" or absent rel both qualify.
            let rel = attributeDict["rel"] ?? "alternate"
            if (rel == "alternate" || rel.isEmpty), accumulator.link == nil {
                accumulator.link = attributeDict["href"].flatMap(URL.init(string:))
            }

        case "link" where !inEntry:
            // Feed-level link — ignore for now (we have feedURL from the caller).
            break

        case "media:thumbnail" where inEntry:
            accumulator.thumbnailURL = attributeDict["url"].flatMap(URL.init(string:))

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        currentText += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName _: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        elementDepth -= 1

        if inEntry {
            switch elementName {
            case "id":        accumulator.stableId = text
            case "title":     accumulator.title = text
            case "published": accumulator.publishedAt = Self.iso8601.date(from: text)
            case "updated":   accumulator.updatedAt = Self.iso8601.date(from: text)
            case "summary":   accumulator.summaryHTML = text.isEmpty ? nil : text
            case "content":   accumulator.contentHTML = text.isEmpty ? nil : text
            case "entry":
                items.append(accumulator.toParseItem())
                inEntry = false
                accumulator = AtomEntryAccumulator()
            default: break
            }
        } else {
            // Feed-level <title> only (ignore <subtitle>, <author>, etc. for v1).
            if elementName == "title" && feedTitle.isEmpty {
                feedTitle = text
            }
        }

        currentText = ""
    }
}
```

---

## Task 4: JSON Feed 1.1 parser

**(Agent)**

**Files:**
- Create: `LensCore/Feeds/JSONFeedParser.swift`

JSON Feed uses a versioned `application/feed+json` MIME type and ISO 8601 dates. The `Codable` models are kept `private`; the public surface is just the `FeedParser` conformance.

- [ ] **Step 1: Write JSONFeedParser.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/JSONFeedParser.swift`:

```swift
// JSONFeedParser.swift — Parses JSON Feed 1.1 documents.
//
// JSON Feed spec: https://jsonfeed.org/version/1.1
// The `version` field is a URL string ("https://jsonfeed.org/version/1.1").
// Private Codable types map the wire format; the public API is just the
// FeedParser conformance which returns ParsedFeed.
import Foundation

// MARK: - JSONFeedParser

public struct JSONFeedParser: FeedParser {
    public init() {}

    public func canParse(data: Data, mimeType: String?) -> Bool {
        if let mime = mimeType?.lowercased(), mime.contains("feed+json") { return true }
        // Sniff: JSON Feed documents contain the jsonfeed.org version URL near the top.
        let prefix = String(data: data.prefix(256), encoding: .utf8) ?? ""
        return prefix.contains("jsonfeed.org")
    }

    public func parse(data: Data, feedURL: URL) throws -> ParsedFeed {
        let decoder = JSONDecoder()
        // JSON Feed dates are RFC 3339 / ISO 8601.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try full ISO 8601 with fractional seconds first, then without.
            let formatters: [ISO8601DateFormatter] = [
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }(),
            ]
            for formatter in formatters {
                if let date = formatter.date(from: string) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Unrecognised date format: \(string)")
        }

        let document: JSONFeedDocument
        do {
            document = try decoder.decode(JSONFeedDocument.self, from: data)
        } catch let error as FeedParseError {
            throw error
        } catch {
            throw FeedParseError.malformedJSON(error.localizedDescription)
        }

        let items: [ParsedFeedItem] = document.items.map { raw in
            var item = ParsedFeedItem(stableId: raw.id, title: raw.title ?? "")
            item.link = raw.url.flatMap(URL.init(string:))
            item.publishedAt = raw.datePublished
            item.updatedAt = raw.dateModified
            item.contentHTML = raw.contentHtml
            item.summaryHTML = raw.summary
            item.thumbnailURL = raw.image.flatMap(URL.init(string:))
            item.enclosureURL = raw.attachments?.first?.url.flatMap(URL.init(string:))
            item.enclosureMIMEType = raw.attachments?.first?.mimeType
            item.estimatedReadMinutes = ParsedFeedItem.estimateReadMinutes(
                fromHTML: raw.contentHtml ?? raw.summary
            )
            return item
        }

        return ParsedFeed(title: document.title, items: items)
    }
}

// MARK: - Codable wire types (private)

private struct JSONFeedDocument: Decodable {
    let title: String
    let items: [JSONFeedItem]
}

private struct JSONFeedItem: Decodable {
    let id: String
    let title: String?
    let url: String?
    let contentHtml: String?
    let summary: String?
    let datePublished: Date?
    let dateModified: Date?
    let image: String?
    let attachments: [JSONFeedAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, title, url, summary, image, attachments
        case contentHtml    = "content_html"
        case datePublished  = "date_published"
        case dateModified   = "date_modified"
    }
}

private struct JSONFeedAttachment: Decodable {
    let url: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case url
        case mimeType = "mime_type"
    }
}
```

---

## Task 5: FeedFactory

**(Agent)**

**Files:**
- Create: `LensCore/Feeds/FeedFactory.swift`

`FeedFactory` is an actor so parser registration and lookup are safe under concurrent feed fetches and future addon installs.

- [ ] **Step 1: Write FeedFactory.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/FeedFactory.swift`:

```swift
// FeedFactory.swift — Selects the right parser for a given feed payload.
//
// Built-in parsers (RSS, Atom, JSON Feed) are registered at app startup.
// The addon system (Phase 2D+) registers additional parsers at runtime via
// the same `register(_:)` method — this is why FeedFactory is an actor
// rather than a plain value: concurrent registration must be safe.
//
// Selection strategy: the factory returns the FIRST registered parser whose
// `canParse(data:mimeType:)` returns true. Register more specific parsers
// before more generic ones (e.g. JSONFeedParser before a generic JSONParser).
import Foundation

public actor FeedFactory {

    // MARK: - Shared instance

    /// App-wide shared factory, pre-loaded with the three built-in parsers.
    /// The addon system calls `register(_:)` on this instance when installing parsers.
    public static let shared: FeedFactory = {
        let factory = FeedFactory()
        // Registration order matters: more specific MIME types first.
        // JSON Feed before generic XML parsers; Atom before RSS (both are XML).
        Task { await factory.registerBuiltins() }
        return factory
    }()

    // MARK: - Private state

    private var parsers: [any FeedParser] = []

    // MARK: - Init

    public init() {}

    // MARK: - Registration

    /// Register a parser. Parsers are tried in registration order; register
    /// more specific parsers before fallback ones.
    public func register(_ parser: any FeedParser) {
        parsers.append(parser)
    }

    // MARK: - Selection

    /// Returns the first registered parser that reports it can handle `data`.
    ///
    /// Returns `nil` if no registered parser matches — callers should treat
    /// this as an unsupported feed format and emit `feedFetchFailed`.
    public func parser(for data: Data, mimeType: String?) -> (any FeedParser)? {
        parsers.first { $0.canParse(data: data, mimeType: mimeType) }
    }

    // MARK: - Private

    private func registerBuiltins() {
        register(JSONFeedParser())
        register(AtomParser())
        register(RSSParser())
    }
}
```

---

## Task 6: Write all parser tests

**(Agent)**

All four test files share the same pattern: embed a minimal but realistic feed document as a Swift raw string, parse it, and assert on specific field values. No networking, no SwiftData, no file system access.

**Files:**
- Create: `LensCoreTests/Feeds/RSSParserTests.swift`
- Create: `LensCoreTests/Feeds/AtomParserTests.swift`
- Create: `LensCoreTests/Feeds/JSONFeedParserTests.swift`
- Create: `LensCoreTests/Feeds/FeedFactoryTests.swift`

- [ ] **Step 1: Write RSSParserTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Feeds/RSSParserTests.swift`:

```swift
import Testing
import Foundation
@testable import LensCore

@Suite("RSSParser")
struct RSSParserTests {
    let parser = RSSParser()

    // MARK: - canParse

    @Test("Recognises application/rss+xml MIME type")
    func canParseRSSMime() {
        let data = Data("<rss/>".utf8)
        #expect(parser.canParse(data: data, mimeType: "application/rss+xml"))
    }

    @Test("Recognises RDF MIME type")
    func canParseRDFMime() {
        let data = Data("<rdf:RDF/>".utf8)
        #expect(parser.canParse(data: data, mimeType: "application/rdf+xml"))
    }

    @Test("Sniffs <rss root element without MIME type")
    func sniffsRSSElement() {
        let xml = #"<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>"#
        #expect(parser.canParse(data: Data(xml.utf8), mimeType: nil))
    }

    @Test("Does not claim JSON Feed data")
    func doesNotClaimJSON() {
        let json = #"{"version":"https://jsonfeed.org/version/1.1","title":"T","items":[]}"#
        #expect(!parser.canParse(data: Data(json.utf8), mimeType: "application/feed+json"))
    }

    // MARK: - parse

    static let rssFixture = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
         xmlns:media="http://search.yahoo.com/mrss/">
      <channel>
        <title>Example Blog</title>
        <link>https://example.com</link>
        <item>
          <title>Hello World</title>
          <link>https://example.com/hello</link>
          <guid>https://example.com/hello</guid>
          <pubDate>Mon, 01 Jan 2024 12:00:00 +0000</pubDate>
          <description>&lt;p&gt;Summary paragraph&lt;/p&gt;</description>
          <content:encoded><![CDATA[<p>Full article content here.</p>]]></content:encoded>
        </item>
        <item>
          <title>Second Post</title>
          <guid>post-2</guid>
          <description>Short summary.</description>
        </item>
      </channel>
    </rss>
    """#

    @Test("Parses feed title")
    func parsesFeedTitle() throws {
        let feed = try parser.parse(data: Data(Self.rssFixture.utf8), feedURL: URL(string: "https://example.com/feed")!)
        #expect(feed.title == "Example Blog")
    }

    @Test("Parses correct item count")
    func parsesItemCount() throws {
        let feed = try parser.parse(data: Data(Self.rssFixture.utf8), feedURL: URL(string: "https://example.com/feed")!)
        #expect(feed.items.count == 2)
    }

    @Test("Parses first item fields")
    func parsesFirstItemFields() throws {
        let feed = try parser.parse(data: Data(Self.rssFixture.utf8), feedURL: URL(string: "https://example.com/feed")!)
        let item = try #require(feed.items.first)
        #expect(item.title == "Hello World")
        #expect(item.stableId == "https://example.com/hello")
        #expect(item.link?.absoluteString == "https://example.com/hello")
        #expect(item.summaryHTML?.contains("Summary paragraph") == true)
        #expect(item.contentHTML?.contains("Full article content") == true)
    }

    @Test("Parses pubDate into Date")
    func parsesPubDate() throws {
        let feed = try parser.parse(data: Data(Self.rssFixture.utf8), feedURL: URL(string: "https://example.com/feed")!)
        let item = try #require(feed.items.first)
        #expect(item.publishedAt != nil)
        // 2024-01-01 12:00:00 UTC
        let expected = ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")
        #expect(item.publishedAt == expected)
    }

    @Test("Second item uses guid as stableId when no link present")
    func secondItemStableId() throws {
        let feed = try parser.parse(data: Data(Self.rssFixture.utf8), feedURL: URL(string: "https://example.com/feed")!)
        #expect(feed.items[1].stableId == "post-2")
    }

    @Test("Throws malformedXML for invalid XML")
    func throwsMalformedXML() {
        let bad = Data("<rss><channel><item>UNCLOSED".utf8)
        // XMLParser may or may not error on unclosed tags depending on version;
        // verify parse does not crash and either succeeds or throws FeedParseError.
        // A minimal check: calling parse does not raise a fatal error.
        _ = try? parser.parse(data: bad, feedURL: URL(string: "https://example.com")!)
    }
}
```

- [ ] **Step 2: Write AtomParserTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Feeds/AtomParserTests.swift`:

```swift
import Testing
import Foundation
@testable import LensCore

@Suite("AtomParser")
struct AtomParserTests {
    let parser = AtomParser()

    // MARK: - canParse

    @Test("Recognises application/atom+xml MIME type")
    func canParseAtomMime() {
        let data = Data("<feed/>".utf8)
        #expect(parser.canParse(data: data, mimeType: "application/atom+xml"))
    }

    @Test("Sniffs Atom namespace in document bytes")
    func sniffsAtomNamespace() {
        let xml = #"<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"></feed>"#
        #expect(parser.canParse(data: Data(xml.utf8), mimeType: nil))
    }

    @Test("Does not claim plain RSS data")
    func doesNotClaimRSS() {
        let xml = #"<rss version="2.0"><channel></channel></rss>"#
        #expect(!parser.canParse(data: Data(xml.utf8), mimeType: "application/rss+xml"))
    }

    // MARK: - parse

    static let atomFixture = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Example</title>
      <link href="https://example.com/" rel="alternate"/>
      <entry>
        <id>https://example.com/entry-1</id>
        <title>First Entry</title>
        <link href="https://example.com/entry-1" rel="alternate"/>
        <published>2024-03-15T09:00:00Z</published>
        <updated>2024-03-15T10:00:00Z</updated>
        <summary>A short summary.</summary>
        <content type="html"><![CDATA[<p>Full entry content.</p>]]></content>
      </entry>
      <entry>
        <id>https://example.com/entry-2</id>
        <title>Second Entry</title>
        <link href="https://example.com/entry-2"/>
        <published>2024-03-14T08:00:00Z</published>
        <summary>Another summary.</summary>
      </entry>
    </feed>
    """#

    @Test("Parses feed title")
    func parsesFeedTitle() throws {
        let feed = try parser.parse(data: Data(Self.atomFixture.utf8), feedURL: URL(string: "https://example.com/feed.atom")!)
        #expect(feed.title == "Atom Example")
    }

    @Test("Parses correct entry count")
    func parsesEntryCount() throws {
        let feed = try parser.parse(data: Data(Self.atomFixture.utf8), feedURL: URL(string: "https://example.com/feed.atom")!)
        #expect(feed.items.count == 2)
    }

    @Test("Parses first entry fields")
    func parsesFirstEntryFields() throws {
        let feed = try parser.parse(data: Data(Self.atomFixture.utf8), feedURL: URL(string: "https://example.com/feed.atom")!)
        let item = try #require(feed.items.first)
        #expect(item.title == "First Entry")
        #expect(item.stableId == "https://example.com/entry-1")
        #expect(item.link?.absoluteString == "https://example.com/entry-1")
        #expect(item.summaryHTML?.contains("short summary") == true)
        #expect(item.contentHTML?.contains("Full entry content") == true)
    }

    @Test("Parses ISO 8601 published date")
    func parsesPublishedDate() throws {
        let feed = try parser.parse(data: Data(Self.atomFixture.utf8), feedURL: URL(string: "https://example.com/feed.atom")!)
        let item = try #require(feed.items.first)
        let expected = ISO8601DateFormatter().date(from: "2024-03-15T09:00:00Z")
        #expect(item.publishedAt == expected)
    }

    @Test("Parses updated date separately from published")
    func parsesUpdatedDate() throws {
        let feed = try parser.parse(data: Data(Self.atomFixture.utf8), feedURL: URL(string: "https://example.com/feed.atom")!)
        let item = try #require(feed.items.first)
        let expected = ISO8601DateFormatter().date(from: "2024-03-15T10:00:00Z")
        #expect(item.updatedAt == expected)
    }

    @Test("Entry without content:encoded has nil contentHTML")
    func entryWithoutContentHTML() throws {
        let feed = try parser.parse(data: Data(Self.atomFixture.utf8), feedURL: URL(string: "https://example.com/feed.atom")!)
        #expect(feed.items[1].contentHTML == nil)
        #expect(feed.items[1].summaryHTML != nil)
    }
}
```

- [ ] **Step 3: Write JSONFeedParserTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Feeds/JSONFeedParserTests.swift`:

```swift
import Testing
import Foundation
@testable import LensCore

@Suite("JSONFeedParser")
struct JSONFeedParserTests {
    let parser = JSONFeedParser()

    // MARK: - canParse

    @Test("Recognises application/feed+json MIME type")
    func canParseFeedJSON() {
        let data = Data("{}".utf8)
        #expect(parser.canParse(data: data, mimeType: "application/feed+json"))
    }

    @Test("Sniffs jsonfeed.org version URL in document bytes")
    func sniffsJSONFeed() {
        let json = #"{"version":"https://jsonfeed.org/version/1.1","title":"T","items":[]}"#
        #expect(parser.canParse(data: Data(json.utf8), mimeType: nil))
    }

    @Test("Does not claim Atom XML data")
    func doesNotClaimAtom() {
        let xml = #"<feed xmlns="http://www.w3.org/2005/Atom"></feed>"#
        #expect(!parser.canParse(data: Data(xml.utf8), mimeType: "application/atom+xml"))
    }

    // MARK: - parse

    static let jsonFixture = #"""
    {
      "version": "https://jsonfeed.org/version/1.1",
      "title": "JSON Feed Example",
      "home_page_url": "https://example.com",
      "items": [
        {
          "id": "item-uuid-1",
          "title": "JSON Item One",
          "url": "https://example.com/item-1",
          "date_published": "2024-06-01T10:00:00Z",
          "date_modified": "2024-06-01T11:00:00Z",
          "content_html": "<p>Full HTML content for item one.</p>",
          "summary": "A summary of item one.",
          "image": "https://example.com/image.jpg",
          "attachments": [
            {
              "url": "https://example.com/audio.mp3",
              "mime_type": "audio/mpeg"
            }
          ]
        },
        {
          "id": "item-uuid-2",
          "title": "JSON Item Two",
          "url": "https://example.com/item-2",
          "date_published": "2024-05-30T08:00:00Z",
          "summary": "Summary only, no full content."
        }
      ]
    }
    """#

    @Test("Parses feed title")
    func parsesFeedTitle() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        #expect(feed.title == "JSON Feed Example")
    }

    @Test("Parses correct item count")
    func parsesItemCount() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        #expect(feed.items.count == 2)
    }

    @Test("Parses first item fields")
    func parsesFirstItemFields() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        let item = try #require(feed.items.first)
        #expect(item.stableId == "item-uuid-1")
        #expect(item.title == "JSON Item One")
        #expect(item.link?.absoluteString == "https://example.com/item-1")
        #expect(item.contentHTML?.contains("Full HTML content") == true)
        #expect(item.summaryHTML?.contains("summary of item one") == true)
    }

    @Test("Parses ISO 8601 dates")
    func parsesDates() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        let item = try #require(feed.items.first)
        let expectedPublished = ISO8601DateFormatter().date(from: "2024-06-01T10:00:00Z")
        let expectedModified  = ISO8601DateFormatter().date(from: "2024-06-01T11:00:00Z")
        #expect(item.publishedAt == expectedPublished)
        #expect(item.updatedAt == expectedModified)
    }

    @Test("Parses thumbnail URL from image field")
    func parsesThumbnailURL() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        #expect(feed.items[0].thumbnailURL?.absoluteString == "https://example.com/image.jpg")
    }

    @Test("Parses enclosure URL and MIME type from attachments")
    func parsesEnclosure() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        #expect(feed.items[0].enclosureURL?.absoluteString == "https://example.com/audio.mp3")
        #expect(feed.items[0].enclosureMIMEType == "audio/mpeg")
    }

    @Test("Item without content_html has nil contentHTML")
    func itemWithoutContentHTML() throws {
        let feed = try parser.parse(data: Data(Self.jsonFixture.utf8), feedURL: URL(string: "https://example.com/feed.json")!)
        #expect(feed.items[1].contentHTML == nil)
        #expect(feed.items[1].summaryHTML != nil)
    }

    @Test("Throws malformedJSON for invalid JSON")
    func throwsMalformedJSON() {
        let bad = Data("not json at all".utf8)
        #expect(throws: FeedParseError.self) {
            try parser.parse(data: bad, feedURL: URL(string: "https://example.com")!)
        }
    }
}
```

- [ ] **Step 4: Write FeedFactoryTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Feeds/FeedFactoryTests.swift`:

```swift
import Testing
import Foundation
@testable import LensCore

@Suite("FeedFactory")
struct FeedFactoryTests {

    // MARK: - Helpers

    static let rssData  = Data(#"<rss version="2.0"><channel><title>T</title></channel></rss>"#.utf8)
    static let atomData = Data(#"<feed xmlns="http://www.w3.org/2005/Atom"><title>T</title></feed>"#.utf8)
    static let jsonData = Data(#"{"version":"https://jsonfeed.org/version/1.1","title":"T","items":[]}"#.utf8)

    /// Builds a fresh factory with the three built-in parsers registered.
    func makeFactory() async -> FeedFactory {
        let f = FeedFactory()
        await f.register(JSONFeedParser())
        await f.register(AtomParser())
        await f.register(RSSParser())
        return f
    }

    // MARK: - Selection by MIME type

    @Test("Selects JSONFeedParser for application/feed+json")
    func selectsJSONFeedByMime() async {
        let factory = await makeFactory()
        let parser = await factory.parser(for: Self.jsonData, mimeType: "application/feed+json")
        #expect(parser is JSONFeedParser)
    }

    @Test("Selects AtomParser for application/atom+xml")
    func selectsAtomByMime() async {
        let factory = await makeFactory()
        let parser = await factory.parser(for: Self.atomData, mimeType: "application/atom+xml")
        #expect(parser is AtomParser)
    }

    @Test("Selects RSSParser for application/rss+xml")
    func selectsRSSByMime() async {
        let factory = await makeFactory()
        let parser = await factory.parser(for: Self.rssData, mimeType: "application/rss+xml")
        #expect(parser is RSSParser)
    }

    // MARK: - Selection by content sniffing (nil MIME type)

    @Test("Sniffs JSON Feed when MIME type is nil")
    func sniffsJSONFeed() async {
        let factory = await makeFactory()
        let parser = await factory.parser(for: Self.jsonData, mimeType: nil)
        #expect(parser is JSONFeedParser)
    }

    @Test("Sniffs Atom when MIME type is nil")
    func sniffsAtom() async {
        let factory = await makeFactory()
        let parser = await factory.parser(for: Self.atomData, mimeType: nil)
        #expect(parser is AtomParser)
    }

    @Test("Sniffs RSS when MIME type is nil")
    func sniffsRSS() async {
        let factory = await makeFactory()
        let parser = await factory.parser(for: Self.rssData, mimeType: nil)
        #expect(parser is RSSParser)
    }

    // MARK: - No match

    @Test("Returns nil for unrecognised data")
    func returnsNilForUnknownFormat() async {
        let factory = await makeFactory()
        let garbage = Data("this is not a feed".utf8)
        let parser = await factory.parser(for: garbage, mimeType: nil)
        #expect(parser == nil)
    }

    // MARK: - Dynamic registration

    @Test("Custom parser registered after builtins is tried in order")
    func customParserRegistered() async {
        let factory = await makeFactory()
        // A trivial custom parser that claims everything.
        struct AlwaysParser: FeedParser {
            func canParse(data: Data, mimeType: String?) -> Bool { true }
            func parse(data: Data, feedURL: URL) throws -> ParsedFeed { ParsedFeed(title: "custom") }
        }
        await factory.register(AlwaysParser())
        // Built-in parsers are first; AlwaysParser is last. RSS data → RSSParser still wins.
        let parser = await factory.parser(for: Self.rssData, mimeType: nil)
        #expect(parser is RSSParser)
        // Garbage data → no builtin matches → AlwaysParser wins.
        let fallbackParser = await factory.parser(for: Data("garbage".utf8), mimeType: nil)
        #expect(fallbackParser is AlwaysParser)
    }
}
```

---

## Task 7: Add all Feeds files to Xcode and run tests

**(Human)**

- [ ] **Step 1: Add LensCore/Feeds files**

1. In Project Navigator, right-click the **LensCore/Feeds** group → **Add Files to "Lens"…**
2. Select all six Swift files:
   - `LensCore/Feeds/ParsedFeed.swift`
   - `LensCore/Feeds/FeedParser.swift`
   - `LensCore/Feeds/RSSParser.swift`
   - `LensCore/Feeds/AtomParser.swift`
   - `LensCore/Feeds/JSONFeedParser.swift`
   - `LensCore/Feeds/FeedFactory.swift`
3. In the dialog: **Create groups**, uncheck "Copy items if needed", target **LensCore** only.
4. Click **Add**.
5. Delete `LensCore/Feeds/.gitkeep` from the Xcode group (right-click → Delete → Move to Trash).

- [ ] **Step 2: Add LensCoreTests/Feeds files**

1. In Project Navigator, right-click **LensCoreTests** → **New Group** → name it `Feeds`.
2. Right-click the new **LensCoreTests/Feeds** group → **Add Files to "Lens"…**
3. Select all four test files:
   - `LensCoreTests/Feeds/RSSParserTests.swift`
   - `LensCoreTests/Feeds/AtomParserTests.swift`
   - `LensCoreTests/Feeds/JSONFeedParserTests.swift`
   - `LensCoreTests/Feeds/FeedFactoryTests.swift`
4. Target: **LensCoreTests** only. Click **Add**.

- [ ] **Step 3: Run all tests**

Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected results:
- All Phase 2A tests pass.
- All Phase 2B `EventBusTests` and `LensEventTests` pass.
- `RSSParserTests`: 8 tests pass.
- `AtomParserTests`: 6 tests pass.
- `JSONFeedParserTests`: 8 tests pass.
- `FeedFactoryTests`: 8 tests pass.

If any test fails, paste the full failure message including file:line.

---

## Task 8: Write FeedService

**(Agent)**

`FeedService` glues the parser layer to SwiftData and the event bus. It is minimal for Phase 2C: it performs one synchronous fetch per call, no retry scheduling, no background registration. Health status tracking uses the `consecutiveFailureCount` field already present on `Feed` (from Phase 2A).

**Files:**
- Create: `LensCore/Feeds/FeedService.swift`

- [ ] **Step 1: Write FeedService.swift**

Create `/Users/rich/Developer/lens/LensCore/Feeds/FeedService.swift`:

```swift
// FeedService.swift — Orchestrates fetch → parse → persist → emit for a single feed.
//
// Called by: app targets (LensIOS/LensMac) when the user triggers a refresh
// (pull-to-refresh, `r` key) or when a background task fires (Phase 5).
//
// Concurrency notes:
//   • FeedService is an actor; `fetchFeed(feedId:)` is safe to call concurrently
//     for multiple feeds.
//   • Each call creates a fresh ModelContext from the shared ModelContainer.
//     ModelContext is NOT Sendable — we never pass it across the actor boundary.
//   • URLSession.shared is used for simplicity; Phase 5 may introduce a
//     custom session with background download support.
import Foundation
import SwiftData

public actor FeedService {

    // MARK: - Dependencies

    private let container: ModelContainer
    private let eventBus: EventBus
    private let feedFactory: FeedFactory

    // MARK: - Init

    public init(
        container: ModelContainer,
        eventBus: EventBus = .shared,
        feedFactory: FeedFactory = .shared
    ) {
        self.container = container
        self.eventBus = eventBus
        self.feedFactory = feedFactory
    }

    // MARK: - Public API

    /// Fetch and refresh a single feed identified by its UUID.
    ///
    /// Emits:
    ///   1. `feedFetchStarted(feedId:)`
    ///   2. `feedFetchCompleted(feedId:newItemCount:)` on success, or
    ///      `feedFetchFailed(feedId:error:)` on failure.
    ///   3. `feedHealthChanged(feedId:status:)` reflecting the updated health.
    ///
    /// Never throws — errors are surfaced via emitted events so callers do not
    /// need to handle them at the call site.
    public func fetchFeed(feedId: UUID) async {
        await eventBus.emit(.feedFetchStarted(feedId: feedId))

        do {
            let newItemCount = try await performFetch(feedId: feedId)
            await eventBus.emit(.feedFetchCompleted(feedId: feedId, newItemCount: newItemCount))
            await eventBus.emit(.feedHealthChanged(feedId: feedId, status: .healthy))
        } catch {
            let message = error.localizedDescription
            await eventBus.emit(.feedFetchFailed(feedId: feedId, error: message))
            // Record the failure and read back the resulting health status.
            let status = await recordFailure(feedId: feedId, error: message)
            await eventBus.emit(.feedHealthChanged(feedId: feedId, status: status))
        }
    }

    // MARK: - Private

    /// Core fetch/parse/persist logic. Returns the count of newly inserted items.
    private func performFetch(feedId: UUID) async throws -> Int {
        let context = ModelContext(container)

        // Load the Feed record.
        var descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedId })
        descriptor.fetchLimit = 1
        guard let feed = try context.fetch(descriptor).first else {
            throw FeedServiceError.feedNotFound(feedId)
        }

        // HTTP fetch. URLSession validates TLS by default (platform certificate pinning).
        let (data, response) = try await URLSession.shared.data(from: feed.url)
        // Extract MIME type from Content-Type header (e.g. "application/rss+xml; charset=utf-8").
        let rawContentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        let mimeType = rawContentType.map { $0.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) } ?? nil

        // Select a parser.
        guard let parser = await feedFactory.parser(for: data, mimeType: mimeType) else {
            throw FeedServiceError.unsupportedFormat
        }

        // Parse.
        let parsedFeed = try parser.parse(data: data, feedURL: feed.url)

        // Seed displayName from feed metadata if the user hasn't set it yet.
        if feed.displayName.isEmpty {
            feed.displayName = parsedFeed.title
        }

        // Insert new items; skip items whose stableId already exists for this feed.
        var newItemCount = 0
        for parsed in parsedFeed.items {
            let sid = parsed.stableId
            var itemDescriptor = FetchDescriptor<FeedItem>(
                predicate: #Predicate { $0.stableId == sid && $0.feedId == feedId }
            )
            itemDescriptor.fetchLimit = 1
            let existing = try context.fetch(itemDescriptor)
            guard existing.isEmpty else { continue }

            let item = FeedItem(
                feedId: feedId,
                stableId: parsed.stableId,
                title: parsed.title,
                link: parsed.link,
                publishedAt: parsed.publishedAt,
                updatedAt: parsed.updatedAt,
                summaryHTML: parsed.summaryHTML,
                contentHTML: parsed.contentHTML,
                thumbnailURL: parsed.thumbnailURL,
                estimatedReadMinutes: parsed.estimatedReadMinutes,
                enclosureURL: parsed.enclosureURL,
                enclosureMIMEType: parsed.enclosureMIMEType
            )
            context.insert(item)
            newItemCount += 1

            // Capture id before crossing async boundary.
            let itemId = item.id
            await eventBus.emit(.itemParsed(itemId: itemId, feedId: feedId))
        }

        // Update feed success metadata.
        feed.lastFetchedAt = Date()
        feed.consecutiveFailureCount = 0
        feed.lastFetchError = nil
        try context.save()

        return newItemCount
    }

    /// Increments `consecutiveFailureCount` on the Feed record and returns the new health status.
    private func recordFailure(feedId: UUID, error: String) async -> FeedHealthStatus {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedId })
        descriptor.fetchLimit = 1
        guard let feed = (try? context.fetch(descriptor))?.first else {
            return .unhealthy(error: error, lastFetchedAt: nil)
        }
        feed.consecutiveFailureCount += 1
        feed.lastFetchError = error
        try? context.save()
        return healthStatus(for: feed, error: error)
    }

    /// Maps `consecutiveFailureCount` to the appropriate `FeedHealthStatus`.
    /// Threshold of 5 consecutive failures → unhealthy (spec §4.14).
    private func healthStatus(for feed: Feed, error: String) -> FeedHealthStatus {
        switch feed.consecutiveFailureCount {
        case 0:       return .healthy
        case 1..<5:   return .degraded(consecutiveFailures: feed.consecutiveFailureCount)
        default:      return .unhealthy(error: error, lastFetchedAt: feed.lastFetchedAt)
        }
    }
}

// MARK: - Errors

public enum FeedServiceError: Error, Sendable {
    case feedNotFound(UUID)
    case unsupportedFormat
}
```

---

## Task 9: Add FeedService to Xcode and verify the build

**(Human)**

- [ ] **Step 1: Add FeedService.swift to Xcode**

1. In Project Navigator, right-click **LensCore/Feeds** group → **Add Files to "Lens"…**
2. Select `LensCore/Feeds/FeedService.swift` → **Add**, target **LensCore** only.

- [ ] **Step 2: Build LensCore**

Select scheme **LensCore** (or **LensIOS** — building the iOS target also builds LensCore), destination **iPhone 16 Pro Simulator** → **⌘B**.

Expected: **Build Succeeded**. No new warnings other than any pre-existing ones.

If the build fails, paste the full error (file:line + message) here.

- [ ] **Step 3: Run all tests**

Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: all tests from Phases 2A, 2B, and 2C pass. No regressions.

---

## Task 10: Update agent-orientation.md

**(Agent)**

**Files:**
- Modify: `docs/superpowers/2026-04-10-lens-agent-orientation.md`

- [ ] **Step 1: Update the Current state section**

Replace the `## Current state` block with:

```markdown
## Current state

**Phases 2A, 2B, 2C complete.**

| Target | Type | Source folder |
|--------|------|---------------|
| `LensIOS` | iOS App | `LensIOS/` |
| `LensMac` | macOS App | `LensMac/` |
| `LensCore` | iOS + macOS Framework | `LensCore/` |
| `LensUI` | iOS + macOS Framework | `LensUI/` |

**LensCore modules built so far:**

| Module | Key files | Status |
|--------|-----------|--------|
| `Models/` | `Feed`, `FeedItem`, `Category`, `OfflineAsset`, `UserReadingPreferences`, `UserInterfacePreferences` | Phase 2A ✓ |
| `Persistence/` | `PersistenceController`, `CategorySeeder`, `PreferenceStore` | Phase 2A ✓ |
| `Events/` | `LensEvent`, `EventBus` | Phase 2B ✓ |
| `Feeds/` | `ParsedFeed`, `FeedParser` (protocol), `RSSParser`, `AtomParser`, `JSONFeedParser`, `FeedFactory`, `FeedService` | Phase 2C ✓ |
| `Theme/` | *(empty — Phase 2E)* | — |
| `Routing/` | *(empty — Phase 2E)* | — |

**App Group** `group.com.richardtape.lens` wired in Phase 2A.

**FeedService** is an actor in `LensCore/Feeds/FeedService.swift`. Call `fetchFeed(feedId:)` to
trigger a fetch → parse → persist → event-emit cycle. No background scheduling yet (Phase 5).

**Next:** Phase 2D (addon system — addon registry + macOS zip download/verify/install + one reference addon).
```

---

## Task 11: Commit

**(Human)**

- [ ] **Step 1: Stage and commit**

```bash
cd /Users/rich/Developer/lens
git add \
  LensCore/Feeds/ParsedFeed.swift \
  LensCore/Feeds/FeedParser.swift \
  LensCore/Feeds/RSSParser.swift \
  LensCore/Feeds/AtomParser.swift \
  LensCore/Feeds/JSONFeedParser.swift \
  LensCore/Feeds/FeedFactory.swift \
  LensCore/Feeds/FeedService.swift \
  LensCoreTests/Feeds/RSSParserTests.swift \
  LensCoreTests/Feeds/AtomParserTests.swift \
  LensCoreTests/Feeds/JSONFeedParserTests.swift \
  LensCoreTests/Feeds/FeedFactoryTests.swift \
  docs/superpowers/2026-04-10-lens-agent-orientation.md \
  Lens.xcodeproj/project.pbxproj
git status
git commit -m "feat(phase-2c): RSS/Atom/JSON Feed parsers, FeedFactory, FeedService"
```

Expected: commit succeeds with those files listed.

---

## Phase 2C exit criteria

Before declaring Phase 2C done:

- [ ] `ParsedFeed.swift` and `FeedParser.swift` define the shared types.
- [ ] `RSSParser`, `AtomParser`, `JSONFeedParser` all conform to `FeedParser` and are unit-tested.
- [ ] `FeedFactory` is an actor with `register(_:)` and `parser(for:mimeType:)`.
- [ ] `FeedService` exists as an actor with `fetchFeed(feedId:)` that emits typed events.
- [ ] All 30 new tests pass (8 RSS + 6 Atom + 8 JSON Feed + 8 Factory).
- [ ] All Phase 2A and 2B tests still pass.
- [ ] `LensCore` builds cleanly for both iOS and macOS.
- [ ] `agent-orientation.md` Current state section reflects Phase 2C.
- [ ] Changes committed.

---

## What's next

**Phase 2D** — Addon system:
- `AddonManifest` Codable model (identifier, version, capabilities, asset paths, checksum).
- `AddonRegistry` actor in `LensCore` — stores installed addons, validates manifests.
- macOS-only: download zip from HTTPS URL → verify SHA-256 → unpack to app sandbox → register.
- One reference addon (a minimal theme) hosted on your HTTPS server to prove end-to-end.
- Depends on: Phase 2B event bus (addon install/uninstall emits events).
