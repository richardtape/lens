// AddonRecord.swift — Represents a successfully installed addon in memory.
//
// AddonRegistry holds a dictionary of these keyed by manifest.identifier.
// The registry is in-memory only for the vertical slice; persistence is Phase B.
import Foundation

/// An addon that has been downloaded, verified, and registered with AddonRegistry.
public struct AddonRecord: Sendable, Identifiable {
    /// Stable addon identifier from the manifest (e.g. "com.example.dark-theme").
    public var id: String { manifest.identifier }
    /// The full parsed manifest for this addon.
    public let manifest: AddonManifest
    /// When the addon was installed in this session.
    public let installedAt: Date
    /// Directory in the app sandbox where addon files were extracted.
    /// macOS path: ~/Library/Application Support/Lens/Addons/<identifier>/
    public let installDirectoryURL: URL

    public init(manifest: AddonManifest, installedAt: Date, installDirectoryURL: URL) {
        self.manifest = manifest
        self.installedAt = installedAt
        self.installDirectoryURL = installDirectoryURL
    }
}
