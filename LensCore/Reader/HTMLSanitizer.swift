// HTMLSanitizer.swift — Strips unsafe HTML from feed content before WKWebView rendering.
//
// Three passes in order:
//   1. Block tags — removes <script>, <style>, <iframe>, <embed>, <object>,
//      <form>, <template>, <svg>, <math> along with all their content.
//   2. Event handlers — removes on* attributes (onclick, onload, …) from any element.
//   3. Dangerous URL schemes — blanks out href/src/action pointing to javascript: or data:.
//
// Defence-in-depth: WKWebView also has JavaScript disabled (see WebViewWrapper).
// This sanitizer handles real-world feed HTML well; it is not adversarially hardened
// (no full HTML parser). Do not use it as a general-purpose XSS sanitizer.
import Foundation

public enum HTMLSanitizer {

    // MARK: - Public API

    /// Returns a sanitized copy of `html` safe for rendering in a sandboxed WKWebView.
    public static func sanitize(_ html: String) -> String {
        var result = html
        result = stripBlockTags(from: result)
        result = stripEventHandlers(from: result)
        result = stripDangerousURLSchemes(from: result)
        return result
    }

    // MARK: - Passes

    private static let tagsWithContent = [
        "script", "style", "iframe", "embed", "object",
        "form", "template", "svg", "math"
    ]

    /// Strip tags whose entire content must be removed (script bodies, style blocks, …).
    private static func stripBlockTags(from html: String) -> String {
        tagsWithContent.reduce(html) { current, tag in
            stripTagWithContent(tag, from: current)
        }
    }

    /// Remove `on<event>` attributes from all elements.
    private static func stripEventHandlers(from html: String) -> String {
        // Matches: space(s) + on<word> + optional-spaces = "..." or '...' or bare value.
        let pattern = #"\s+on[a-zA-Z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]*)"#
        return applying(pattern: pattern, to: html, replacement: "")
    }

    /// Blank out href/src/action attributes that use javascript: or data: schemes.
    private static func stripDangerousURLSchemes(from html: String) -> String {
        let pattern = #"(href|src|action)\s*=\s*(?:"(?:javascript|data):[^"]*"|'(?:javascript|data):[^']*')"#
        // Replace the whole attribute with an empty value so the tag remains valid HTML.
        return applying(pattern: pattern, to: html, replacement: #"$1=""#)
    }

    // MARK: - Helpers

    private static func stripTagWithContent(_ tag: String, from html: String) -> String {
        // Optional attributes after the tag name, then all content (including newlines)
        // up to and including the closing tag.
        let pattern = "<\(tag)(\\s[^>]*)?>.*?</\(tag)>"
        return applying(
            pattern: pattern,
            to: html,
            replacement: "",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }

    private static func applying(
        pattern: String,
        to string: String,
        replacement: String,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return string
        }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: replacement)
    }
}
