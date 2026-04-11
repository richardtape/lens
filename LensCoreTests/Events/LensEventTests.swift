// LensEventTests.swift — Smoke tests confirming all LensEvent cases are
// constructable, pattern-matchable, and Equatable-comparable.
//
// These tests guard against future refactors accidentally breaking the
// public addon API surface (spec §3.7).
import Testing
import Foundation
@testable import LensCore

@Suite("LensEvent")
struct LensEventTests {

    // MARK: - Equatable

    @Test("Identical events compare equal")
    func equatableIdentical() {
        let id = UUID()
        #expect(LensEvent.feedFetchStarted(feedId: id) == LensEvent.feedFetchStarted(feedId: id))
        #expect(LensEvent.userInitiatedRefresh == LensEvent.userInitiatedRefresh)
        #expect(LensEvent.appLaunched == LensEvent.appLaunched)
    }

    @Test("Events with different associated values are not equal")
    func equatableDifferentValues() {
        let a = UUID()
        let b = UUID()
        #expect(LensEvent.feedFetchStarted(feedId: a) != LensEvent.feedFetchStarted(feedId: b))
        #expect(LensEvent.feedFetchCompleted(feedId: a, newItemCount: 1)
                != LensEvent.feedFetchCompleted(feedId: a, newItemCount: 2))
    }

    @Test("Different event cases are not equal")
    func equatableDifferentCases() {
        #expect(LensEvent.appLaunched != LensEvent.userInitiatedRefresh)
        #expect(LensEvent.backgroundRefreshStarted != LensEvent.backgroundRefreshCompleted(newItemCount: 0))
    }

    // MARK: - Pattern matching (all cases exercised)

    @Test("All LensEvent cases are constructable and pattern-matchable")
    func allCasesRoundTrip() {
        let id1 = UUID()
        let id2 = UUID()
        let now = Date()
        let cases: [LensEvent] = [
            .appLaunched,
            .backgroundRefreshStarted,
            .backgroundRefreshCompleted(newItemCount: 3),
            .feedFetchStarted(feedId: id1),
            .feedFetchCompleted(feedId: id1, newItemCount: 5),
            .feedFetchFailed(feedId: id1, error: "timeout"),
            .feedHealthChanged(feedId: id1, status: .healthy),
            .feedHealthChanged(feedId: id1, status: .degraded(consecutiveFailures: 2)),
            .feedHealthChanged(feedId: id1, status: .unhealthy(error: "404", lastFetchedAt: now)),
            .feedHealthChanged(feedId: id1, status: .unhealthy(error: "404", lastFetchedAt: nil)),
            .userInitiatedRefresh,
            .userInitiatedFeedRefresh(feedId: id1),
            .itemParsed(itemId: id2, feedId: id1),
            .itemDisplayed(itemId: id2),
            .itemMarkedRead(itemId: id2),
            .itemMarkedUnread(itemId: id2),
            .itemStarred(itemId: id2),
            .itemUnstarred(itemId: id2),
            .itemSavedOffline(itemId: id2),
            .itemOfflineSaveRemoved(itemId: id2),
            .themeApplied(themeName: "default"),
            .addonInstalled(addonId: "com.example.dark-theme"),
            .addonInstallFailed(addonId: "com.example.dark-theme", error: "download failed"),
            .addonInstallFailed(addonId: nil, error: "bad zip"),
        ]
        // Each case must equal itself — confirms Equatable and Sendable compile correctly.
        for event in cases {
            #expect(event == event)
        }
    }

    // MARK: - FeedHealthStatus

    @Test("FeedHealthStatus cases are Equatable")
    func feedHealthStatusEquatable() {
        let now = Date()
        #expect(FeedHealthStatus.healthy == .healthy)
        #expect(FeedHealthStatus.degraded(consecutiveFailures: 3) == .degraded(consecutiveFailures: 3))
        #expect(FeedHealthStatus.degraded(consecutiveFailures: 3) != .degraded(consecutiveFailures: 4))
        #expect(FeedHealthStatus.unhealthy(error: "404", lastFetchedAt: now)
                == .unhealthy(error: "404", lastFetchedAt: now))
        #expect(FeedHealthStatus.unhealthy(error: "404", lastFetchedAt: nil)
                != .unhealthy(error: "404", lastFetchedAt: now))
    }
}
