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
