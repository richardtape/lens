// TokenLayerTests.swift — Verify that tokenCSS(from:) produces correct
// CSS custom property values for each UserReadingPreferences field.
//
// Tests use an in-memory ModelContainer so UserReadingPreferences is a proper
// SwiftData-managed instance, matching how it is used at runtime.
import Testing
import SwiftData
import Foundation
@testable import LensCore

@Suite("TokenLayer")
struct TokenLayerTests {

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

    // MARK: - Default values (spec §3.8: fontSize=18, lineHeight=1.6, contentWidth=680)

    @Test("Default preferences produce token CSS with spec-specified defaults")
    func defaultValues() {
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-font-size: 18px"))
        #expect(css.contains("--lens-line-height: 1.6"))
        #expect(css.contains("--lens-content-width: 680px"))
    }

    // MARK: - Individual token fields

    @Test("Font size preference appears as --lens-font-size in token CSS")
    func fontSizeToken() {
        preferences.fontSize = 22
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-font-size: 22px"))
    }

    @Test("Font family preference appears as --lens-font-family in token CSS")
    func fontFamilyToken() {
        preferences.fontFamily = "Georgia"
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-font-family: Georgia"))
    }

    @Test("Line height preference appears as --lens-line-height in token CSS")
    func lineHeightToken() {
        preferences.lineHeight = 1.8
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-line-height: 1.8"))
    }

    @Test("Content width preference appears as --lens-content-width in token CSS")
    func contentWidthToken() {
        preferences.contentWidth = 760
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-content-width: 760px"))
    }

    // MARK: - Appearance override colours

    @Test("System appearance emits CSS Canvas keyword for --lens-bg")
    func systemAppearanceBackground() {
        preferences.appearanceOverride = .system
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-bg: Canvas"))
        #expect(css.contains("--lens-text: CanvasText"))
    }

    @Test("Light appearance override emits white background")
    func lightAppearanceBackground() {
        preferences.appearanceOverride = .light
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-bg: #ffffff"))
        #expect(css.contains("--lens-text: #000000"))
    }

    @Test("Dark appearance override emits dark background")
    func darkAppearanceBackground() {
        preferences.appearanceOverride = .dark
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains("--lens-bg: #1c1c1e"))
        #expect(css.contains("--lens-text: #ffffff"))
    }

    // MARK: - All eight tokens present

    @Test("Token CSS contains all eight --lens-* custom properties")
    func allEightTokensPresent() {
        let css = TokenLayer.tokenCSS(from: preferences)
        #expect(css.contains(TokenLayer.bg))
        #expect(css.contains(TokenLayer.text))
        #expect(css.contains(TokenLayer.link))
        #expect(css.contains(TokenLayer.fontFamily))
        #expect(css.contains(TokenLayer.fontSize))
        #expect(css.contains(TokenLayer.lineHeight))
        #expect(css.contains(TokenLayer.contentWidth))
        #expect(css.contains(TokenLayer.codeFont))
    }

    @Test("Public token name constants match variable names in generated CSS output")
    func tokenNameConstantsMatchOutput() {
        let css = TokenLayer.tokenCSS(from: preferences)
        // Spot-check that the constants we expose to addon authors are what appears in output.
        for name in [TokenLayer.bg, TokenLayer.text, TokenLayer.fontFamily,
                     TokenLayer.fontSize, TokenLayer.codeFont] {
            #expect(css.contains(name), "Expected to find \(name) in token CSS")
        }
    }
}
