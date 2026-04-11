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
