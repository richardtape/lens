// AddonRegistryTests.swift — Tests for AddonRegistry actor: register, lookup,
// duplicate guard, unregister, and allAddons.
//
// Each test uses a fresh AddonRegistry() — never AddonRegistry.shared — to
// ensure tests are isolated from each other.
import Testing
import Foundation
@testable import LensCore

// MARK: - Fixture helpers

extension AddonManifest {
    /// A minimal valid manifest for use in tests.
    static func fixture(
        identifier: String = "com.example.test-addon",
        capabilities: [AddonCapability] = [.theme]
    ) -> AddonManifest {
        AddonManifest(
            identifier: identifier,
            version: "1.0.0",
            minimumLensVersion: "1.0.0",
            displayName: "Test Addon",
            description: "A test addon.",
            capabilities: capabilities,
            permissions: [],
            assets: ["style.css"]
        )
    }
}

extension AddonRecord {
    static func fixture(identifier: String = "com.example.test-addon") -> AddonRecord {
        AddonRecord(
            manifest: .fixture(identifier: identifier),
            installedAt: Date(),
            installDirectoryURL: URL(fileURLWithPath: "/tmp/\(identifier)")
        )
    }
}

// MARK: - Tests

@Suite("AddonRegistry")
struct AddonRegistryTests {

    @Test("Registered addon can be retrieved by identifier")
    func registerAndRetrieve() async throws {
        let registry = AddonRegistry()
        let record = AddonRecord.fixture()
        try await registry.register(record)
        let retrieved = await registry.addon(withId: "com.example.test-addon")
        #expect(retrieved?.id == "com.example.test-addon")
    }

    @Test("Registering a duplicate identifier throws duplicateIdentifier error")
    func duplicateRegistrationThrows() async throws {
        let registry = AddonRegistry()
        let record = AddonRecord.fixture()
        try await registry.register(record)
        await #expect(throws: AddonError.duplicateIdentifier("com.example.test-addon")) {
            try await registry.register(record)
        }
    }

    @Test("Unregistering removes the addon from the registry")
    func unregisterRemovesAddon() async throws {
        let registry = AddonRegistry()
        let record = AddonRecord.fixture()
        try await registry.register(record)
        await registry.unregister(id: "com.example.test-addon")
        let retrieved = await registry.addon(withId: "com.example.test-addon")
        #expect(retrieved == nil)
    }

    @Test("Unregistering a non-existent ID is a no-op")
    func unregisterNonExistentIsNoOp() async {
        let registry = AddonRegistry()
        // Should not crash or throw
        await registry.unregister(id: "com.example.does-not-exist")
    }

    @Test("allAddons returns all registered records sorted by identifier")
    func allAddonsSorted() async throws {
        let registry = AddonRegistry()
        let b = AddonRecord.fixture(identifier: "com.example.b-addon")
        let a = AddonRecord.fixture(identifier: "com.example.a-addon")
        let c = AddonRecord.fixture(identifier: "com.example.c-addon")
        try await registry.register(b)
        try await registry.register(a)
        try await registry.register(c)
        let all = await registry.allAddons
        #expect(all.map(\.id) == ["com.example.a-addon", "com.example.b-addon", "com.example.c-addon"])
    }

    @Test("allAddons returns empty array when registry is empty")
    func allAddonsEmpty() async {
        let registry = AddonRegistry()
        let all = await registry.allAddons
        #expect(all.isEmpty)
    }

    @Test("After re-registering following unregister, addon is retrievable")
    func reregisterAfterUnregister() async throws {
        let registry = AddonRegistry()
        let record = AddonRecord.fixture()
        try await registry.register(record)
        await registry.unregister(id: record.id)
        // Should not throw the second time
        try await registry.register(record)
        let retrieved = await registry.addon(withId: record.id)
        #expect(retrieved?.id == record.id)
    }
}
