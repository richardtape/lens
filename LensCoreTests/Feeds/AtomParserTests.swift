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
