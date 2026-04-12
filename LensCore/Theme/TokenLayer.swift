// TokenLayer.swift — CSS layer 2: custom property tokens from UserReadingPreferences.
//
// The --lens-* CSS variable names are a versioned public contract for theme addon
// authors (spec §9 token contract). Renaming any constant here is a breaking
// change that requires a version notice in the event catalog.
//
// Colour strategy (spec §2.4, §3.8):
//   .system appearance → CSS system-colour keywords (Canvas / CanvasText) so
//     WKWebView's built-in dark-mode support handles adaptive colouring.
//   .light / .dark → explicit hex values that override the adaptive behaviour.
// Phase 4 will refine this when WKWebView appearance is wired up.
import Foundation

public enum TokenLayer {

    // MARK: - Token name constants (public API — do not rename)

    /// CSS variable name for background colour. (spec §3.8)
    public static let bg            = "--lens-bg"
    /// CSS variable name for body text colour. (spec §3.8)
    public static let text          = "--lens-text"
    /// CSS variable name for link colour. (spec §3.8)
    public static let link          = "--lens-link"
    /// CSS variable name for font family. (spec §3.8)
    public static let fontFamily    = "--lens-font-family"
    /// CSS variable name for base font size. (spec §3.8)
    public static let fontSize      = "--lens-font-size"
    /// CSS variable name for line height. (spec §3.8)
    public static let lineHeight    = "--lens-line-height"
    /// CSS variable name for maximum content width. (spec §3.8)
    public static let contentWidth  = "--lens-content-width"
    /// CSS variable name for code/monospace font. (spec §3.8)
    public static let codeFont      = "--lens-code-font"

    // MARK: - CSS generation

    /// Generate the token layer CSS from the user's reading preferences.
    ///
    /// Returns a `:root { … }` block setting all eight --lens-* custom properties.
    /// Inject this as the second CSS layer (after structural, before theme).
    public static func tokenCSS(from preferences: UserReadingPreferences) -> String {
        """
        /* Lens token layer — generated from UserReadingPreferences */
        :root {
          \(bg): \(backgroundValue(for: preferences.appearanceOverride));
          \(text): \(textValue(for: preferences.appearanceOverride));
          \(link): #007aff;
          \(fontFamily): \(preferences.fontFamily);
          \(fontSize): \(preferences.fontSize)px;
          \(lineHeight): \(preferences.lineHeight);
          \(contentWidth): \(preferences.contentWidth)px;
          \(codeFont): ui-monospace, monospace;
        }
        """
    }

    // MARK: - Colour helpers

    private static func backgroundValue(for override: AppearanceOverride) -> String {
        switch override {
        case .system: return "Canvas"     // CSS system-colour; adapts to WKWebView dark mode
        case .light:  return "#ffffff"
        case .dark:   return "#1c1c1e"
        }
    }

    private static func textValue(for override: AppearanceOverride) -> String {
        switch override {
        case .system: return "CanvasText"
        case .light:  return "#000000"
        case .dark:   return "#ffffff"
        }
    }
}
