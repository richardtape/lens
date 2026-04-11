// UserInterfacePreferencesTests.swift
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("UserInterfacePreferences model")
struct UserInterfacePreferencesTests {

    @Test("default values match the product spec")
    func specDefaults() {
        let prefs = UserInterfacePreferences()

        #expect(prefs.feedSortOrder == .alphabetical)
        #expect(prefs.backgroundRefreshEnabled == true)
        // RetentionPolicy.days(90) — verify via pattern matching
        guard case .days(let n) = prefs.retentionPolicy else {
            Issue.record("Expected .days(90); got \(prefs.retentionPolicy)")
            return
        }
        #expect(n == 90)
    }

    @Test("RetentionPolicy.days round-trips through Codable")
    func retentionDaysCodable() throws {
        let encoded = try JSONEncoder().encode(RetentionPolicy.days(30))
        let decoded = try JSONDecoder().decode(RetentionPolicy.self, from: encoded)
        guard case .days(let n) = decoded else {
            Issue.record("Expected .days(30)")
            return
        }
        #expect(n == 30)
    }

    @Test("RetentionPolicy.keepAll round-trips through Codable")
    func retentionKeepAllCodable() throws {
        let encoded = try JSONEncoder().encode(RetentionPolicy.keepAll)
        let decoded = try JSONDecoder().decode(RetentionPolicy.self, from: encoded)
        guard case .keepAll = decoded else {
            Issue.record("Expected .keepAll")
            return
        }
    }

    @Test("FeedSortOrder round-trips through Codable")
    func feedSortOrderCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for value in [FeedSortOrder.alphabetical, .unreadCount, .lastUpdated, .byCategory] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(FeedSortOrder.self, from: data)
            #expect(decoded == value)
        }
    }
}
