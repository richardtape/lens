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
