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
      padding: 1.5rem 1.5rem 4rem;
      max-width: var(--lens-content-width, 680px);
      overflow-wrap: break-word;
      word-break: break-word;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
    }

    /* Headings */
    h1, h2, h3, h4, h5, h6 {
      line-height: 1.25;
      margin-top: 1.75em;
      margin-bottom: 0.5em;
    }
    h1 { font-size: 1.75em; }
    h2 { font-size: 1.4em; }
    h3 { font-size: 1.2em; }
    h4, h5, h6 { font-size: 1em; }
    h1:first-child, h2:first-child { margin-top: 0; }

    /* Paragraphs and lists */
    p { margin: 0 0 1em; }
    ul, ol { padding-left: 1.75em; margin: 0 0 1em; }
    li { margin-bottom: 0.35em; }

    /* Images and media */
    img, video {
      max-width: 100%;
      height: auto;
      display: block;
      border-radius: 6px;
      margin: 1em auto;
    }
    figure { margin: 1.5em 0; padding: 0; }
    figcaption {
      font-size: 0.875em;
      opacity: 0.65;
      text-align: center;
      margin-top: 0.5em;
    }

    /* Code */
    pre {
      overflow-x: auto;
      border-radius: 8px;
      padding: 1em 1.25em;
      margin: 1.25em 0;
      font-size: 0.875em;
      line-height: 1.5;
    }
    pre code { background: none; padding: 0; border-radius: 0; font-size: inherit; }
    code {
      font-family: var(--lens-code-font, ui-monospace, monospace);
      font-size: 0.875em;
      padding: 0.15em 0.35em;
      border-radius: 4px;
    }

    /* Links */
    a { text-decoration: underline; text-underline-offset: 2px; }

    /* Blockquotes */
    blockquote {
      margin: 1.25em 0;
      padding: 0.75em 1.25em;
      border-left: 3px solid;
      border-radius: 0 4px 4px 0;
    }

    /* Horizontal rules */
    hr { border: none; border-top: 1px solid; margin: 2em 0; opacity: 0.2; }

    /* Tables */
    table {
      width: 100%;
      border-collapse: collapse;
      overflow-x: auto;
      display: block;
      margin: 1.25em 0;
      font-size: 0.9em;
    }
    th, td { padding: 0.5em 0.75em; border: 1px solid; text-align: left; }

    /* Summary / details */
    details { margin: 1em 0; }
    summary { cursor: pointer; font-weight: 600; }
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

    /* Links */
    a { color: var(--lens-link); text-decoration-color: color-mix(in srgb, var(--lens-link) 40%, transparent); }
    a:hover { text-decoration-color: var(--lens-link); }

    /* Headings — slightly dimmed for visual hierarchy */
    h1, h2, h3 { opacity: 0.9; }
    h4, h5, h6 { opacity: 0.8; }

    /* Code */
    pre { background: color-mix(in srgb, var(--lens-text) 8%, transparent); }
    code {
      background: color-mix(in srgb, var(--lens-text) 8%, transparent);
      color: var(--lens-text);
    }

    /* Blockquotes */
    blockquote {
      border-left-color: color-mix(in srgb, var(--lens-text) 30%, transparent);
      background: color-mix(in srgb, var(--lens-text) 4%, transparent);
    }

    /* Horizontal rule */
    hr { border-top-color: var(--lens-text); }

    /* Tables */
    th, td { border-color: color-mix(in srgb, var(--lens-text) 20%, transparent); }
    th { background: color-mix(in srgb, var(--lens-text) 6%, transparent); font-weight: 600; }
    """
}
