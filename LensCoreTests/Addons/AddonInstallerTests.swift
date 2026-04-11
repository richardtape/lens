// AddonInstallerTests.swift — Tests for the pure/testable parts of AddonInstaller:
// the SHA-256 helper and manifest parsing from Data.
//
// The full download → verify → unzip → register pipeline is exercised by the
// human integration step (Task 9) which requires a live hosted reference addon.
// This file tests the deterministic, network-free helpers.
#if os(macOS)
import Testing
import Foundation
@testable import LensCore

@Suite("AddonInstaller")
struct AddonInstallerTests {

    // MARK: - SHA-256 helper

    @Test("SHA-256 of empty data is the known empty-string digest")
    func sha256EmptyData() {
        let hash = AddonInstaller.sha256Hex(of: Data())
        // This is the well-known SHA-256 of zero bytes.
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("SHA-256 of known ASCII input matches expected digest")
    func sha256KnownInput() {
        let data = Data("hello".utf8)
        let hash = AddonInstaller.sha256Hex(of: data)
        #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test("SHA-256 output is always 64 lowercase hex characters")
    func sha256OutputFormat() {
        let hash = AddonInstaller.sha256Hex(of: Data("lens".utf8))
        #expect(hash.count == 64)
        #expect(hash == hash.lowercased())
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("Different inputs produce different SHA-256 digests")
    func sha256Uniqueness() {
        let h1 = AddonInstaller.sha256Hex(of: Data("abc".utf8))
        let h2 = AddonInstaller.sha256Hex(of: Data("xyz".utf8))
        #expect(h1 != h2)
    }

    // MARK: - Manifest parsing from Data

    @Test("parseManifest-equivalent: JSONDecoder decodes reference manifest JSON correctly")
    func parsesReferenceManifestJSON() throws {
        // This JSON mirrors the content of docs/reference-addon/manifest.json.
        // If that file changes, update this test to match.
        let json = """
        {
          "identifier": "com.richardtape.lens.reference-theme",
          "version": "1.0.0",
          "minimumLensVersion": "1.0.0",
          "displayName": "Lens Dark Pro",
          "description": "A focused dark reading theme for Lens. Reference addon for the Phase 2D vertical slice.",
          "capabilities": ["theme"],
          "permissions": [],
          "assets": ["theme.css"]
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: json)
        #expect(manifest.identifier == "com.richardtape.lens.reference-theme")
        #expect(manifest.capabilities == [.theme])
        #expect(manifest.isValid)
    }

    @Test("Manifest with missing identifier fails isValid check")
    func invalidManifestFailsValidation() throws {
        let json = """
        {
          "identifier": "",
          "version": "1.0.0",
          "minimumLensVersion": "1.0.0",
          "displayName": "X",
          "description": "X",
          "capabilities": ["theme"],
          "permissions": [],
          "assets": []
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: json)
        #expect(!manifest.isValid)
    }
}

#endif
