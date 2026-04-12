// DeepLinkRouter.swift — Parses lens:// URLs and emits navigation events.
//
// URL structure parsed (spec §4.12):
//
//   lens://feed/add[?url=<encoded>]    → .navigateToAddFeed(prefillURL:)
//   lens://feed/<uuid>                 → .navigateToFeed(feedId:)
//   lens://item/<uuid>                 → .navigateToItem(itemId:)
//   lens://saved                       → .navigateToSaved
//   lens://settings                    → .navigateToSettings
//   lens://import?opml=<url>           → .navigateToOPMLImport(sourceURL:)
//
// Wire this at scene level in LensIOS and LensMac:
//
//   .onOpenURL { url in
//       Task { await DeepLinkRouter.handle(url) }
//   }
//
// This also enables Shortcuts app integration for free (spec §4.12).
import Foundation

public enum DeepLinkRouter {

    // MARK: - URL parsing

    /// Parse a `lens://` URL into a `LensRoute`.
    ///
    /// Returns `nil` for:
    /// - Non-`lens` schemes
    /// - Recognised hosts with malformed path components (e.g. non-UUID where UUID expected)
    /// - Unrecognised hosts
    ///
    /// Silent `nil` on failure is intentional — unrecognised URLs should not crash
    /// or surface errors to the user (they may come from future Lens versions).
    public static func route(from url: URL) -> LensRoute? {
        guard url.scheme == "lens" else { return nil }

        let host = url.host ?? ""
        // lastPathComponent is "" for URLs with no path (lens://saved → host="saved", path="")
        // and the final path segment otherwise (lens://feed/add → "add").
        let lastComponent = url.lastPathComponent

        switch host {
        case "feed":
            if lastComponent == "add" {
                // lens://feed/add or lens://feed/add?url=<encoded>
                let prefillURL = queryItems(from: url)
                    .first(where: { $0.name == "url" })
                    .flatMap { $0.value.flatMap(URL.init(string:)) }
                return .addFeed(prefillURL: prefillURL)
            } else if let id = UUID(uuidString: lastComponent) {
                // lens://feed/<uuid>
                return .viewFeed(feedId: id)
            }
            return nil

        case "item":
            // lens://item/<uuid>
            guard let id = UUID(uuidString: lastComponent) else { return nil }
            return .viewItem(itemId: id)

        case "saved":
            return .saved

        case "settings":
            return .settings

        case "import":
            // lens://import?opml=<url>
            guard
                let opmlValue = queryItems(from: url).first(where: { $0.name == "opml" })?.value,
                let sourceURL = URL(string: opmlValue)
            else { return nil }
            return .importOPML(sourceURL: sourceURL)

        default:
            return nil
        }
    }

    // MARK: - Event emission

    /// Parse `url` and emit the corresponding navigation event on `bus`.
    ///
    /// Unrecognised or malformed URLs are silently ignored — no event is emitted.
    ///
    /// - Parameters:
    ///   - url: The URL received from `onOpenURL` or a Shortcuts automation.
    ///   - bus: Event bus to emit on. Defaults to `EventBus.shared`.
    ///     Pass a fresh `EventBus()` in tests to keep test runs isolated.
    public static func handle(_ url: URL, bus: EventBus = EventBus.shared) async {
        guard let route = route(from: url) else { return }

        let event: LensEvent
        switch route {
        case .addFeed(let prefillURL):
            event = .navigateToAddFeed(prefillURL: prefillURL)
        case .viewFeed(let feedId):
            event = .navigateToFeed(feedId: feedId)
        case .viewItem(let itemId):
            event = .navigateToItem(itemId: itemId)
        case .saved:
            event = .navigateToSaved
        case .settings:
            event = .navigateToSettings
        case .importOPML(let sourceURL):
            event = .navigateToOPMLImport(sourceURL: sourceURL)
        }

        await bus.emit(event)
    }

    // MARK: - Private helpers

    private static func queryItems(from url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }
}
