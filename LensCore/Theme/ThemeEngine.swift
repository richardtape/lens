// ThemeEngine.swift — Joins three CSS layers into a single injection string.
//
// Layer order (spec §2.4):
//   1. Structural  — BuiltInTheme.structuralCSS. Always present; not overridable.
//   2. Token       — TokenLayer.tokenCSS(from:). --lens-* custom properties from prefs.
//   3. Theme       — Active theme CSS (addon or BuiltInTheme.defaultThemeCSS).
//
// Output is a single CSS string for injection into WKWebView.
// WKWebView injection itself is Phase 4 work. ThemeEngine's only job is composition.
import Foundation

public enum ThemeEngine {

    /// Compose all three CSS layers into a single string ready for WKWebView injection.
    ///
    /// - Parameters:
    ///   - preferences: The user's current reading preferences (drives layer 2 tokens).
    ///   - themeCSS: Layer 3 CSS. Pass an addon theme's CSS here to replace the
    ///     built-in default. Defaults to `BuiltInTheme.defaultThemeCSS`.
    /// - Returns: Three layers joined by blank lines — structural, then token, then theme.
    public static func composedCSS(
        preferences: UserReadingPreferences,
        themeCSS: String = BuiltInTheme.defaultThemeCSS
    ) -> String {
        [
            BuiltInTheme.structuralCSS,
            TokenLayer.tokenCSS(from: preferences),
            themeCSS
        ].joined(separator: "\n\n")
    }
}
