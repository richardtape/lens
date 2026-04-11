// AddonManifestTests.swift — Codable round-trip, validation, and
// forward-compatible unknown-capability handling for AddonManifest.
import Testing
import Foundation
@testable import LensCore

@Suite("AddonManifest")
struct AddonManifestTests {

    // MARK: - Helpers

    static let validJSON = """
    {
      "identifier": "com.example.dark-theme",
      "version": "1.0.0",
      "minimumLensVersion": "1.0.0",
      "displayName": "Dark Theme",
      "description": "A dark reading theme.",
      "capabilities": ["theme"],
      "permissions": [],
      "assets": ["theme.css"]
    }
    """.data(using: .utf8)!

    // MARK: - Decode

    @Test("Valid JSON decodes to AddonManifest with correct fields")
    func decodesValidManifest() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Self.validJSON)
        #expect(manifest.identifier == "com.example.dark-theme")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.minimumLensVersion == "1.0.0")
        #expect(manifest.displayName == "Dark Theme")
        #expect(manifest.description == "A dark reading theme.")
        #expect(manifest.capabilities == [.theme])
        #expect(manifest.permissions == [])
        #expect(manifest.assets == ["theme.css"])
    }

    @Test("All known capabilities decode correctly")
    func decodesKnownCapabilities() throws {
        let json = """
        {
          "identifier": "x", "version": "1", "minimumLensVersion": "1",
          "displayName": "X", "description": "X",
          "capabilities": ["feedParser", "theme", "action", "languagePack"],
          "permissions": ["network", "fileAccess"],
          "assets": []
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: json)
        #expect(manifest.capabilities == [.feedParser, .theme, .action, .languagePack])
        #expect(manifest.permissions == [.network, .fileAccess])
    }

    @Test("Unknown capability string is preserved as .unknown rather than throwing")
    func unknownCapabilityPreserved() throws {
        let json = """
        {
          "identifier": "x", "version": "1", "minimumLensVersion": "1",
          "displayName": "X", "description": "X",
          "capabilities": ["theme", "futureCapability"],
          "permissions": [],
          "assets": []
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: json)
        #expect(manifest.capabilities == [.theme, .unknown("futureCapability")])
    }

    // MARK: - Encode round-trip

    @Test("Manifest survives encode then decode round-trip")
    func encodeDecodeRoundTrip() throws {
        let original = AddonManifest(
            identifier: "com.example.round-trip",
            version: "2.3.1",
            minimumLensVersion: "1.0.0",
            displayName: "Round Trip",
            description: "Test round-trip.",
            capabilities: [.theme, .action],
            permissions: [.network],
            assets: ["style.css", "logo.png"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AddonManifest.self, from: data)
        #expect(decoded.identifier == original.identifier)
        #expect(decoded.version == original.version)
        #expect(decoded.capabilities == original.capabilities)
        #expect(decoded.permissions == original.permissions)
        #expect(decoded.assets == original.assets)
    }

    // MARK: - isValid

    @Test("isValid returns true for a complete manifest")
    func isValidComplete() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Self.validJSON)
        #expect(manifest.isValid)
    }

    @Test("isValid returns false when identifier is empty")
    func isValidEmptyIdentifier() {
        let manifest = AddonManifest(
            identifier: "",
            version: "1.0.0",
            minimumLensVersion: "1.0.0",
            displayName: "X",
            description: "X",
            capabilities: [.theme],
            permissions: [],
            assets: []
        )
        #expect(!manifest.isValid)
    }

    @Test("isValid returns false when capabilities is empty")
    func isValidEmptyCapabilities() {
        let manifest = AddonManifest(
            identifier: "com.example.test",
            version: "1.0.0",
            minimumLensVersion: "1.0.0",
            displayName: "Test",
            description: "Test.",
            capabilities: [],
            permissions: [],
            assets: []
        )
        #expect(!manifest.isValid)
    }
}
