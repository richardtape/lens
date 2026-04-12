// UserReadingPreferencesTests.swift
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("UserReadingPreferences model")
struct UserReadingPreferencesTests {

    @Test("default values match the product spec")
    func specDefaults() {
        let prefs = UserReadingPreferences()

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

    @Test("default accentColorHex is system blue")
    func defaultAccentColorHex() throws {
        let prefs = UserReadingPreferences()
        #expect(prefs.accentColorHex == "#4A90D9")
    }

    @Test("AppearanceOverride round-trips through Codable")
    func appearanceOverrideCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in [AppearanceOverride.system, .light, .dark] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(AppearanceOverride.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("LinkBehavior round-trips through Codable")
    func linkBehaviorCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in [LinkBehavior.systemBrowser, .inAppBrowser] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(LinkBehavior.self, from: data)
            #expect(decoded == value)
        }
    }
}
