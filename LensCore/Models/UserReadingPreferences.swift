// UserReadingPreferences.swift — singleton SwiftData record for reader settings.
//
// Fetched via PreferenceStore.readingPreferences(in:), which creates the row
// on first access. Never insert more than one row — all reads use a
// FetchDescriptor<UserReadingPreferences>() and take the first result.
//
// The CSS token contract (--lens-bg, --lens-text, etc.) is derived from
// these fields by ThemeEngine (Phase 2E). Token names are a versioned public
// API for addon authors — do not rename without a breaking-change notice.
import SwiftData
import Foundation

/// Controls the app's light/dark appearance independently of the system setting.
public enum AppearanceOverride: String, Codable, Sendable {
    case system
    case light
    case dark
}

/// Determines how tapped external links open.
public enum LinkBehavior: String, Codable, Sendable {
    case systemBrowser
    case inAppBrowser
}

@Model
public final class UserReadingPreferences {
    public var appearanceOverride: AppearanceOverride
    /// CSS font-family value fed into the --lens-font-family token.
    public var fontFamily: String
    /// Font size in points / px, fed into --lens-font-size.
    public var fontSize: Int
    /// Unitless line-height multiplier → --lens-line-height.
    public var lineHeight: Double
    /// Max content column width in px → --lens-content-width.
    public var contentWidth: Int
    public var bionicReadingEnabled: Bool
    // afforded: not implemented in v1
    public var imageLightboxEnabled: Bool
    public var externalLinkBehavior: LinkBehavior
    /// 0.0–1.0 slider value; maps to ~4 discrete density modes in the article list.
    /// Card density (top of range) is deferred to v2.
    public var listDensity: Double
    /// Hex string for the unread accent bar, monogram, and active filter button.
    /// Default matches system blue. Phase 7 provides the settings UI to change this.
    public var accentColorHex: String

    public init() {
        appearanceOverride = .system
        fontFamily = "-apple-system"
        fontSize = 18
        lineHeight = 1.6
        contentWidth = 680
        bionicReadingEnabled = false
        imageLightboxEnabled = false // afforded: not implemented in v1
        externalLinkBehavior = .systemBrowser
        listDensity = 0.5
        accentColorHex = "#4A90D9"
    }
}
