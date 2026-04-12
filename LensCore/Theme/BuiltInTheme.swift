// BuiltInTheme.swift — CSS layer 1 (structural) and layer 3 (default theme) constants.
//
// Layer 1 owns the reading layout: resets, max-width, image sizing, code block
// basics. It is always the first layer in the composed output; addon themes
// cannot override it (spec §2.4).
//
// Layer 3 is the default built-in reading aesthetic. An addon theme replaces this
// layer entirely by passing its CSS to ThemeEngine.composedCSS(preferences:themeCSS:).
// Phase 4 will expand both stubs into a full polished reading experience.
import Foundation

public enum BuiltInTheme {

    // MARK: - Layer 1: Structural CSS

    /// App-owned layout and reset rules. Always the first CSS layer. (spec §2.4)
    /// References --lens-* variables so token values propagate here automatically.
    public static let structuralCSS = """
    /* Lens structural layer — v1 */
    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0 auto;
      padding: 1.5rem;
      max-width: var(--lens-content-width, 680px);
      overflow-wrap: break-word;
    }
    img, video { max-width: 100%; height: auto; display: block; }
    pre { overflow-x: auto; }
    code, pre { font-family: var(--lens-code-font, ui-monospace, monospace); }
    a { text-decoration: underline; }
    """

    // MARK: - Layer 3: Default theme CSS

    /// Built-in default reading theme. Replace by passing addon CSS to
    /// ThemeEngine.composedCSS(preferences:themeCSS:). Phase 4 will expand this. (spec §2.4)
    public static let defaultThemeCSS = """
    /* Lens default theme layer — v1 */
    body {
      background-color: var(--lens-bg);
      color: var(--lens-text);
      font-family: var(--lens-font-family);
      font-size: var(--lens-font-size);
      line-height: var(--lens-line-height);
    }
    a { color: var(--lens-link); }
    pre {
      background: rgba(128, 128, 128, 0.1);
      border-radius: 6px;
      padding: 1em 1.25em;
    }
    blockquote {
      border-left: 3px solid rgba(128, 128, 128, 0.4);
      margin-left: 0;
      padding-left: 1.25em;
      opacity: 0.8;
    }
    """
}
