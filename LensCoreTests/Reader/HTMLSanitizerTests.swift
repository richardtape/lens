// HTMLSanitizerTests.swift
import Testing
@testable import LensCore

struct HTMLSanitizerTests {

    @Test func stripsScriptTagsAndContent() {
        let html = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("<script>"))
        #expect(!result.contains("alert"))
        #expect(result.contains("Hello"))
        #expect(result.contains("World"))
    }

    @Test func stripsMultilineScript() {
        let html = "<p>Before</p>\n<script>\n  var x = 1;\n  alert(x);\n</script>\n<p>After</p>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("<script>"))
        #expect(!result.contains("var x"))
        #expect(result.contains("Before"))
        #expect(result.contains("After"))
    }

    @Test func stripsStyleBlocks() {
        let html = "<p>Content</p><style>body { color: red; }</style>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("<style>"))
        #expect(!result.contains("color: red"))
        #expect(result.contains("Content"))
    }

    @Test func stripsIframeTags() {
        let html = "<p>Text</p><iframe src=\"https://evil.com\"></iframe>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("iframe"))
        #expect(!result.contains("evil.com"))
    }

    @Test func stripsOnClickAttribute() {
        let html = "<a href=\"https://example.com\" onclick=\"alert(1)\">Link</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("onclick"))
        #expect(!result.contains("alert(1)"))
        #expect(result.contains("https://example.com"))
    }

    @Test func stripsOnLoadAttribute() {
        let html = "<img src=\"photo.jpg\" onload=\"stealCookies()\">"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("onload"))
        #expect(!result.contains("stealCookies"))
    }

    @Test func stripsJavascriptHref() {
        let html = "<a href=\"javascript:alert(1)\">Click me</a>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(!result.contains("javascript:"))
    }

    @Test func preservesSafeLinksAndImages() {
        let html = "<a href=\"https://example.com\">Safe link</a><img src=\"photo.jpg\">"
        let result = HTMLSanitizer.sanitize(html)
        #expect(result.contains("https://example.com"))
        #expect(result.contains("Safe link"))
        #expect(result.contains("photo.jpg"))
    }

    @Test func preservesParagraphsHeadingsAndLists() {
        let html = "<h1>Title</h1><p>Para</p><ul><li>Item</li></ul>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(result == html) // no mutations to safe content
    }
}
