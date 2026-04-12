// DeepLinkRouterTests.swift — Tests for URL parsing (route(from:)) and
// event emission (handle(_:bus:)) in DeepLinkRouter.
//
// Parsing tests are synchronous — route(from:) is a pure function.
// Emission tests are async — handle(_:bus:) calls EventBus.emit which is actor-isolated.
// Each emission test uses a fresh EventBus() to avoid shared-state interference.
import Testing
import Foundation
@testable import LensCore

@Suite("DeepLinkRouter")
struct DeepLinkRouterTests {

    // MARK: - route(from:) — parsing

    @Test("lens://feed/add with url param returns addFeed with prefill URL")
    func addFeedWithURL() throws {
        let url = try #require(URL(string: "lens://feed/add?url=https://example.com/feed.xml"))
        let route = DeepLinkRouter.route(from: url)
        #expect(route == .addFeed(prefillURL: URL(string: "https://example.com/feed.xml")))
    }

    @Test("lens://feed/add without url param returns addFeed with nil prefillURL")
    func addFeedWithoutURL() throws {
        let url = try #require(URL(string: "lens://feed/add"))
        let route = DeepLinkRouter.route(from: url)
        #expect(route == .addFeed(prefillURL: nil))
    }

    @Test("lens://feed/<uuid> returns viewFeed with correct feedId")
    func viewFeedRoute() throws {
        let id = UUID()
        let url = try #require(URL(string: "lens://feed/\(id.uuidString)"))
        #expect(DeepLinkRouter.route(from: url) == .viewFeed(feedId: id))
    }

    @Test("lens://item/<uuid> returns viewItem with correct itemId")
    func viewItemRoute() throws {
        let id = UUID()
        let url = try #require(URL(string: "lens://item/\(id.uuidString)"))
        #expect(DeepLinkRouter.route(from: url) == .viewItem(itemId: id))
    }

    @Test("lens://saved returns .saved")
    func savedRoute() throws {
        let url = try #require(URL(string: "lens://saved"))
        #expect(DeepLinkRouter.route(from: url) == .saved)
    }

    @Test("lens://settings returns .settings")
    func settingsRoute() throws {
        let url = try #require(URL(string: "lens://settings"))
        #expect(DeepLinkRouter.route(from: url) == .settings)
    }

    @Test("lens://import with opml param returns importOPML with source URL")
    func importOPMLRoute() throws {
        let url = try #require(URL(string: "lens://import?opml=https://example.com/feeds.opml"))
        let route = DeepLinkRouter.route(from: url)
        #expect(route == .importOPML(sourceURL: URL(string: "https://example.com/feeds.opml")!))
    }

    @Test("Unrecognised lens:// host returns nil")
    func unknownHostReturnsNil() throws {
        let url = try #require(URL(string: "lens://unrecognised"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("Non-lens scheme returns nil")
    func nonLensSchemeReturnsNil() throws {
        let url = try #require(URL(string: "https://example.com/feed/123"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("lens://feed with non-UUID path component returns nil")
    func nonUUIDFeedPathReturnsNil() throws {
        let url = try #require(URL(string: "lens://feed/not-a-uuid"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("lens://item with non-UUID path component returns nil")
    func nonUUIDItemPathReturnsNil() throws {
        let url = try #require(URL(string: "lens://item/not-a-uuid"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    @Test("lens://import without opml param returns nil")
    func importWithoutOPMLParamReturnsNil() throws {
        let url = try #require(URL(string: "lens://import"))
        #expect(DeepLinkRouter.route(from: url) == nil)
    }

    // MARK: - handle(_:bus:) — event emission

    @Test("handle emits .navigateToSaved for lens://saved")
    func emitsNavigateToSaved() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let url = try #require(URL(string: "lens://saved"))

        await DeepLinkRouter.handle(url, bus: bus)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .navigateToSaved)
    }

    @Test("handle emits .navigateToSettings for lens://settings")
    func emitsNavigateToSettings() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let url = try #require(URL(string: "lens://settings"))

        await DeepLinkRouter.handle(url, bus: bus)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .navigateToSettings)
    }

    @Test("handle emits .navigateToFeed for lens://feed/<uuid>")
    func emitsNavigateToFeed() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let id = UUID()
        let url = try #require(URL(string: "lens://feed/\(id.uuidString)"))

        await DeepLinkRouter.handle(url, bus: bus)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .navigateToFeed(feedId: id))
    }

    @Test("handle emits nothing for an unrecognised URL")
    func emitsNothingForUnknownURL() async throws {
        let bus = EventBus()
        let stream = await bus.makeStream()
        let unknownURL = try #require(URL(string: "https://example.com"))

        await DeepLinkRouter.handle(unknownURL, bus: bus)

        // Emit a sentinel after the unknown URL.
        // If the unknown URL produced no event, the sentinel is the first thing received.
        await bus.emit(.userInitiatedRefresh)

        var received: LensEvent?
        for await event in stream { received = event; break }
        #expect(received == .userInitiatedRefresh)
    }
}
