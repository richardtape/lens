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
        // Require the <feed> root element AND the Atom namespace URI.
        // WordPress RSS feeds declare xmlns:atom="http://www.w3.org/2005/Atom" in their
        // <rss> root — checking the namespace alone would select AtomParser for those feeds.
        let prefix = String(data: data.prefix(512), encoding: .utf8) ?? ""
        return prefix.contains("<feed") && prefix.contains("http://www.w3.org/2005/Atom")
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
