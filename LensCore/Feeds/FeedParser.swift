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
