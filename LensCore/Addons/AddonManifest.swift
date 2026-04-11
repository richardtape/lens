// AddonManifest.swift — Codable types describing an addon's declared capabilities.
//
// AddonCapability and AddonPermission use a custom Codable implementation with
// an `.unknown(String)` case so that manifests authored for a future Lens version
// (with new capability strings we haven't seen yet) never cause a crash on decode —
// they just silently round-trip. This is important because the manifest format is
// a versioned public contract (spec §5.4, §9).
//
// AddonManifest is the direct Swift representation of manifest.json found at the
// root of every addon .zip package. It is purely Codable — no SwiftData, no UI.
import Foundation

// MARK: - AddonCapability

/// What an addon can contribute to Lens.
///
/// The raw string values are the stable identifiers used in manifest.json.
/// Adding a case here without a manifest update is a breaking change; see spec §9.
public enum AddonCapability: Sendable, Equatable {
    case feedParser
    case theme
    case action
    case languagePack
    /// A capability string that this version of Lens does not recognise.
    /// Stored so manifests survive round-trips without data loss.
    case unknown(String)
}

extension AddonCapability: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "feedParser":   self = .feedParser
        case "theme":        self = .theme
        case "action":       self = .action
        case "languagePack": self = .languagePack
        default:             self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .feedParser:       try container.encode("feedParser")
        case .theme:            try container.encode("theme")
        case .action:           try container.encode("action")
        case .languagePack:     try container.encode("languagePack")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

// MARK: - AddonPermission

/// Elevated access an addon declares it needs.
///
/// Lens validates that no more permissions than declared are exercised.
/// Future enforcement is Phase C work; in the vertical slice this is recorded but not enforced.
public enum AddonPermission: Sendable, Equatable {
    case network
    case fileAccess
    case unknown(String)
}

extension AddonPermission: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "network":    self = .network
        case "fileAccess": self = .fileAccess
        default:           self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .network:          try container.encode("network")
        case .fileAccess:       try container.encode("fileAccess")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

// MARK: - AddonManifest

/// The full contents of an addon's manifest.json.
///
/// Decode from the manifest.json file at the root of the addon .zip package.
/// Use `isValid` before registering to guard against incomplete manifests.
public struct AddonManifest: Codable, Sendable {
    /// Reverse-DNS identifier, e.g. "com.example.dark-theme". Stable; never changes post-publish.
    public let identifier: String
    /// Semantic version string, e.g. "1.0.0".
    public let version: String
    /// Minimum Lens version required, e.g. "1.0.0". Not enforced in this phase but stored.
    public let minimumLensVersion: String
    /// Human-readable name shown in addon management UI.
    public let displayName: String
    /// Short description of what the addon does.
    public let description: String
    /// What this addon contributes to Lens (spec §5.4).
    public let capabilities: [AddonCapability]
    /// Elevated permissions the addon declares it needs (spec §5.4).
    public let permissions: [AddonPermission]
    /// Relative paths to asset files inside the zip (e.g. ["theme.css"]).
    public let assets: [String]

    public init(
        identifier: String,
        version: String,
        minimumLensVersion: String,
        displayName: String,
        description: String,
        capabilities: [AddonCapability],
        permissions: [AddonPermission],
        assets: [String]
    ) {
        self.identifier = identifier
        self.version = version
        self.minimumLensVersion = minimumLensVersion
        self.displayName = displayName
        self.description = description
        self.capabilities = capabilities
        self.permissions = permissions
        self.assets = assets
    }

    /// Returns false if any required field is empty or capabilities is empty.
    /// Call this before registering an addon to guard against malformed manifests.
    public var isValid: Bool {
        !identifier.isEmpty
            && !version.isEmpty
            && !minimumLensVersion.isEmpty
            && !displayName.isEmpty
            && !capabilities.isEmpty
    }
}
