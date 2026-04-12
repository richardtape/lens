// LensRoute.swift — Parsed result of a lens:// deep link URL.
//
// DeepLinkRouter.route(from:) produces a LensRoute from a URL.
// DeepLinkRouter.handle(_:bus:) converts the route to the appropriate
// LensEvent navigation case and emits it on EventBus.
//
// Each case maps 1:1 to a URL pattern in spec §4.12.
// LensRoute is separate from LensEvent to keep URL parsing testable
// without requiring an actor or async context.
import Foundation

/// A fully-parsed `lens://` deep link destination.
///
/// Produced by `DeepLinkRouter.route(from:)`. Corresponds to the URL scheme
/// table in spec §4.12. Unrecognised URLs return `nil` from the parser.
public enum LensRoute: Equatable, Sendable {
    /// `lens://feed/add` or `lens://feed/add?url=<encoded>`
    case addFeed(prefillURL: URL?)
    /// `lens://feed/<uuid>`
    case viewFeed(feedId: UUID)
    /// `lens://item/<uuid>`
    case viewItem(itemId: UUID)
    /// `lens://saved`
    case saved
    /// `lens://settings`
    case settings
    /// `lens://import?opml=<url>`
    case importOPML(sourceURL: URL)
}
