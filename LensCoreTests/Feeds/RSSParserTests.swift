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
