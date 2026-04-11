// PreferenceStoreTests.swift
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("PreferenceStore")
struct PreferenceStoreTests {

    @Test("reading preferences created with correct spec defaults")
    func readingPreferencesDefaults() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let prefs = try PreferenceStore.readingPreferences(in: ModelContext(container))

        #expect(prefs.appearanceOverride == .system)
        #expect(prefs.fontFamily == "-apple-system")
        #expect(prefs.fontSize == 18)
        #expect(prefs.lineHeight == 1.6)
        #expect(prefs.contentWidth == 680)
        #expect(prefs.bionicReadingEnabled == false)
        #expect(prefs.imageLightboxEnabled == false) // afforded field
        #expect(prefs.externalLinkBehavior == .systemBrowser)
        #expect(prefs.listDensity == 0.5)
    }

    @Test("interface preferences created with correct spec defaults")
    func interfacePreferencesDefaults() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let prefs = try PreferenceStore.interfacePreferences(in: ModelContext(container))

        #expect(prefs.feedSortOrder == .alphabetical)
        #expect(prefs.backgroundRefreshEnabled == true)
        guard case .days(let n) = prefs.retentionPolicy else {
            Issue.record("Expected .days(90); got \(prefs.retentionPolicy)")
            return
        }
        #expect(n == 90)
    }

    @Test("reading preferences is a singleton — second call returns same row")
    func readingPreferencesSingleton() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        let first = try PreferenceStore.readingPreferences(in: context)
        first.fontSize = 24
        try context.save()

        let second = try PreferenceStore.readingPreferences(in: context)
        #expect(second.fontSize == 24)

        let all = try context.fetch(FetchDescriptor<UserReadingPreferences>())
        #expect(all.count == 1)
    }

    @Test("interface preferences is a singleton — second call returns same row")
    func interfacePreferencesSingleton() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        let first = try PreferenceStore.interfacePreferences(in: context)
        first.feedSortOrder = .byCategory
        try context.save()

        let second = try PreferenceStore.interfacePreferences(in: context)
        #expect(second.feedSortOrder == .byCategory)

        let all = try context.fetch(FetchDescriptor<UserInterfacePreferences>())
        #expect(all.count == 1)
    }
}
