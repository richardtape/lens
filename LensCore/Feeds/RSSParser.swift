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
