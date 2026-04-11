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
            item.enclosureURL = raw.attachments?.first.flatMap { URL(string: $0.url) }
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
