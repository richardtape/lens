// ThemeEngineTests.swift — Verify that composedCSS joins all three layers
// in the correct order and that preference values flow through to the output.
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("ThemeEngine")
struct ThemeEngineTests {

    // MARK: - Setup

    let container: ModelContainer
    let preferences: UserReadingPreferences

    init() throws {
        container = try ModelContainer(
            for: UserReadingPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        preferences = UserReadingPreferences()
        context.insert(preferences)
        try context.save()
    }

    // MARK: - Layer presence

    @Test("composedCSS output contains markers from all three layers")
    func containsAllThreeLayers() {
        let output = ThemeEngine.composedCSS(
            preferences: preferences,
            themeCSS: "/* sentinel-theme */"
        )
        #expect(output.contains("Lens structural layer"))
        #expect(output.contains("Lens token layer"))
        #expect(output.contains("/* sentinel-theme */"))
    }

    @Test("composedCSS uses BuiltInTheme default when no themeCSS provided")
    func defaultThemeFallback() {
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("Lens default theme layer"))
    }

    // MARK: - Layer ordering

    @Test("Structural layer appears before token layer in output")
    func structuralBeforeToken() {
        let output = ThemeEngine.composedCSS(preferences: preferences)
        let structuralRange = output.range(of: "Lens structural layer")
        let tokenRange = output.range(of: "Lens token layer")
        guard let s = structuralRange, let t = tokenRange else {
            Issue.record("Layer markers not found in output")
            return
        }
        #expect(s.lowerBound < t.lowerBound)
    }

    @Test("Token layer appears before theme layer in output")
    func tokenBeforeTheme() {
        let output = ThemeEngine.composedCSS(
            preferences: preferences,
            themeCSS: "/* sentinel-theme */"
        )
        let tokenRange = output.range(of: "Lens token layer")
        let themeRange = output.range(of: "/* sentinel-theme */")
        guard let t = tokenRange, let th = themeRange else {
            Issue.record("Layer markers not found in output")
            return
        }
        #expect(t.lowerBound < th.lowerBound)
    }

    // MARK: - Preference values flow through

    @Test("Font size from preferences appears in composed output")
    func fontSizeFlowsThrough() {
        preferences.fontSize = 20
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("--lens-font-size: 20px"))
    }

    @Test("Content width from preferences appears in composed output")
    func contentWidthFlowsThrough() {
        preferences.contentWidth = 800
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("--lens-content-width: 800px"))
    }

    @Test("Dark appearance produces dark token values in composed output")
    func darkAppearanceTokenInOutput() {
        preferences.appearanceOverride = .dark
        let output = ThemeEngine.composedCSS(preferences: preferences)
        #expect(output.contains("--lens-bg: #1c1c1e"))
    }

    // MARK: - Addon theme override

    @Test("Passing addon CSS string replaces the default theme layer")
    func addonThemeReplaceDefault() {
        let addonCSS = "body { background: hotpink; } /* addon-override */"
        let output = ThemeEngine.composedCSS(preferences: preferences, themeCSS: addonCSS)
        #expect(output.contains("/* addon-override */"))
        // Default theme layer should not be present when a custom theme is supplied.
        #expect(!output.contains("Lens default theme layer"))
    }
}
