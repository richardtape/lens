// ArticlePageBuilderTests.swift
import Testing
import Foundation
@testable import LensCore

struct ArticlePageBuilderTests {

    // MARK: - Helpers

    private func item(contentHTML: String? = nil, summaryHTML: String? = nil) -> FeedItem {
        let fi = FeedItem(feedId: UUID(), stableId: "t", title: "Test Title")
        fi.contentHTML = contentHTML
        fi.summaryHTML = summaryHTML
        return fi
    }

    // MARK: - Tests

    @Test func outputIsValidHTMLDocument() {
        let page = ArticlePageBuilder.buildPage(for: item(contentHTML: "<p>Hi</p>"),
                                               preferences: UserReadingPreferences())
        #expect(page.hasPrefix("<!DOCTYPE html>"))
        #expect(page.contains("<html"))
        #expect(page.contains("</html>"))
        #expect(page.contains("<body>"))
        #expect(page.contains("</body>"))
    }

    @Test func outputContainsComposedCSS() {
        let page = ArticlePageBuilder.buildPage(for: item(contentHTML: "<p>Hi</p>"),
                                               preferences: UserReadingPreferences())
        // ThemeEngine emits token layer which always contains these properties.
        #expect(page.contains("--lens-font-size"))
        #expect(page.contains("--lens-bg"))
        #expect(page.contains("<style>"))
    }

    @Test func prefersContentHTMLOverSummaryHTML() {
        let fi = item(contentHTML: "<p>Full content</p>", summaryHTML: "<p>Summary only text</p>")
        let page = ArticlePageBuilder.buildPage(for: fi, preferences: UserReadingPreferences())
        #expect(page.contains("Full content"))
        #expect(!page.contains("Summary only text"))
    }

    @Test func fallsBackToSummaryHTMLWhenContentIsNil() {
        let fi = item(summaryHTML: "<p>Summary only</p>")
        let page = ArticlePageBuilder.buildPage(for: fi, preferences: UserReadingPreferences())
        #expect(page.contains("Summary only"))
    }

    @Test func emptyBodyWhenNoContent() {
        let fi = item()
        let page = ArticlePageBuilder.buildPage(for: fi, preferences: UserReadingPreferences())
        // Page must still be a valid HTML document even with an empty body.
        #expect(page.contains("<body>"))
        #expect(page.contains("</body>"))
    }

    @Test func sanitizesBodyContent() {
        let fi = item(contentHTML: "<p>Safe</p><script>evil()</script>")
        let page = ArticlePageBuilder.buildPage(for: fi, preferences: UserReadingPreferences())
        #expect(!page.contains("<script>"))
        #expect(!page.contains("evil()"))
        #expect(page.contains("Safe"))
    }

    @Test func escapesSpecialCharsInTitle() {
        let fi = FeedItem(
            feedId: UUID(),
            stableId: "s1",
            title: "A <b>Bold</b> & \"Quoted\" Title"
        )
        fi.contentHTML = "<p>Body</p>"
        let page = ArticlePageBuilder.buildPage(for: fi, preferences: UserReadingPreferences())
        // The <title> must not contain raw HTML.
        #expect(page.contains("&lt;b&gt;"))
        #expect(page.contains("&amp;"))
        #expect(page.contains("&quot;"))
    }

    @Test func acceptsCustomThemeCSS() {
        let customCSS = "/* my custom theme */"
        let fi = item(contentHTML: "<p>Hi</p>")
        let page = ArticlePageBuilder.buildPage(for: fi, preferences: UserReadingPreferences(),
                                               themeCSS: customCSS)
        #expect(page.contains("my custom theme"))
    }
}
