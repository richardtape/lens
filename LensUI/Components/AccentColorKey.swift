// AccentColorKey.swift — Custom environment keys for user preferences + Color(hex:) utility.
//
// Why custom keys instead of plain .tint: the article row's accent Rectangle
// needs a concrete Color value (not a ShapeStyle alias) for conditional
// transparency, and MonogramView needs the same color for its background.
// Root views set both .tint(accentColor) and .environment(\.lensAccentColor, accentColor)
// so standard controls (buttons) and custom views both pick up the user's choice.
import SwiftUI

// MARK: - Color hex extension

extension Color {
    /// Creates a `Color` from a CSS-style hex string.
    /// Accepts "#RRGGBB", "RRGGBB", "#RGB", or "RGB" (case-insensitive).
    /// Falls back to `.accentColor` on parse failure so nothing is ever blank.
    init(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        guard Scanner(string: stripped).scanHexInt64(&rgb) else {
            self = .accentColor; return
        }
        switch stripped.count {
        case 6:
            self = Color(
                red:   Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >>  8) & 0xFF) / 255,
                blue:  Double( rgb        & 0xFF) / 255
            )
        case 3:
            // Expand: #RGB → #RRGGBB
            let r = (rgb >> 8) & 0xF
            let g = (rgb >> 4) & 0xF
            let b =  rgb       & 0xF
            self = Color(
                red:   Double(r | (r << 4)) / 255,
                green: Double(g | (g << 4)) / 255,
                blue:  Double(b | (b << 4)) / 255
            )
        default:
            self = .accentColor
        }
    }
}

// MARK: - lensAccentColor

/// The user's chosen accent color, derived from `UserReadingPreferences.accentColorHex`.
/// Used by article rows (accent bar, monogram) and active filter buttons.
private struct LensAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = Color(hex: "#4A90D9")
}

extension EnvironmentValues {
    var lensAccentColor: Color {
        get { self[LensAccentColorKey.self] }
        set { self[LensAccentColorKey.self] = newValue }
    }
}

// MARK: - lensListDensity

/// The article list density (0.0–1.0) from `UserReadingPreferences.listDensity`.
/// Read by `ArticleRowView` to adjust which elements are shown and vertical padding.
private struct LensListDensityKey: EnvironmentKey {
    static let defaultValue: Double = 0.5
}

extension EnvironmentValues {
    var lensListDensity: Double {
        get { self[LensListDensityKey.self] }
        set { self[LensListDensityKey.self] = newValue }
    }
}
