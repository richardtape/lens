// ArticlePageBuilder.swift — Assembles the full HTML document for WKWebView rendering.
//
// Three-layer CSS composition (spec §2.4) via ThemeEngine:
//   1. BuiltInTheme.structuralCSS   — layout, typography, code blocks (not overridable)
//   2. TokenLayer.tokenCSS(from:)   — --lens-* custom properties from UserReadingPreferences
//   3. themeCSS parameter           — active theme (built-in default or addon replacement)
//
// The base URL passed to WKWebView.loadHTMLString should be set to item.link
// (if non-nil) so relative URLs in the feed content resolve correctly online.
// External images may not load offline — full asset caching is Phase 6.
import Foundation

public enum ArticlePageBuilder {

    /// Build a complete HTML5 page ready for `WKWebView.loadHTMLString(_:baseURL:)`.
    ///
    /// - Parameters:
    ///   - item: The article to render. Uses `contentHTML` first, then `summaryHTML`,
    ///     then empty string if both are nil.
    ///   - preferences: Reader preferences that drive the token layer.
    ///   - themeCSS: Layer-3 CSS. Pass an addon theme's CSS here to override the
    ///     built-in default. Defaults to `BuiltInTheme.defaultThemeCSS`.
    public static func buildPage(
        for item: FeedItem,
        preferences: UserReadingPreferences,
        themeCSS: String = BuiltInTheme.defaultThemeCSS
    ) -> String {
        let css = ThemeEngine.composedCSS(preferences: preferences, themeCSS: themeCSS)
        let rawHTML = item.contentHTML ?? item.summaryHTML ?? ""
        let body = HTMLSanitizer.sanitize(rawHTML)
        let escapedTitle = item.title.htmlEscaped

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta name="color-scheme" content="light dark">
          <title>\(escapedTitle)</title>
          <style>
        \(css)
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

// MARK: - Private helpers

private extension String {
    /// Escapes characters that are special inside an HTML attribute or element context.
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
