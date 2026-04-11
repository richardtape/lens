# Lens Phase 2D — Addon System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the addon registry, typed manifest model, and the macOS-only download → SHA-256 verify → unzip → register pipeline, then prove it end-to-end with one hosted reference theme addon.

**Architecture:** All types (`AddonManifest`, `AddonRecord`, `AddonError`, `AddonRegistry`) are cross-platform and live in `LensCore/Addons/`. `AddonInstaller` is wrapped in `#if os(macOS)` because remote zip install is macOS-only in v1 (spec §5.1, §5.3). `AddonRegistry` is a Swift actor with an in-memory store (no disk persistence in this phase — that is Phase B). The installer orchestrates download → SHA-256 verification → `/usr/bin/unzip` extraction → manifest parse → registry registration → event emission. It emits two new `LensEvent` cases added in this phase. No SwiftUI imports anywhere in `LensCore`.

**Tech Stack:** Swift 6, Foundation (`URLSession`, `Process`, `FileManager`, `JSONDecoder`), CryptoKit (`SHA256`), `EventBus` from Phase 2B, Swift Testing, Xcode 26.3.

**Depends on:** Phase 2B (EventBus actor and `LensEvent` enum must exist before `AddonInstaller` can emit events).

---

## Driver legend

- **(Agent)** — agent writes files; no Xcode interaction needed.
- **(Human)** — requires Xcode GUI or shell command.
- **(Both)** — agent writes content, human runs a command or verifies.

---

## File structure

```
LensCore/Addons/
├── AddonManifest.swift          (Create) AddonCapability, AddonPermission enums + AddonManifest struct
├── AddonRecord.swift            (Create) AddonRecord value type
├── AddonError.swift             (Create) AddonError enum + LocalizedError
├── AddonRegistry.swift          (Create) AddonRegistry actor — in-memory store
└── AddonInstaller.swift         (Create) #if os(macOS) download/verify/unzip/register actor

LensCore/Events/LensEvent.swift  (Modify) Add .addonInstalled and .addonInstallFailed cases

LensCoreTests/Addons/
├── AddonManifestTests.swift     (Create) Codable round-trip, validation, unknown-capability handling
├── AddonRegistryTests.swift     (Create) Register, lookup, duplicate guard, unregister, allAddons
└── AddonInstallerTests.swift    (Create) #if os(macOS) SHA-256 helper tests + manifest parse from Data

LensCoreTests/Events/LensEventTests.swift  (Modify) Add new addon cases to allCasesRoundTrip

docs/reference-addon/
├── manifest.json                (Create) Reference theme addon manifest
├── theme.css                    (Create) Reference "Lens Dark Pro" CSS using --lens-* tokens
└── README.md                    (Create) Packaging instructions for the human driver
```

> **`.gitkeep` cleanup:** `LensCore/Addons/` has a `.gitkeep` from Phase 0. Delete it from disk and from the Xcode group when you add the first real files in Task 2.

---

## Task 1: Write AddonManifest.swift, AddonRecord.swift, AddonError.swift

**(Agent)**

**Files:**
- Create: `LensCore/Addons/AddonManifest.swift`
- Create: `LensCore/Addons/AddonRecord.swift`
- Create: `LensCore/Addons/AddonError.swift`

- [ ] **Step 1: Write AddonManifest.swift**

Create `/Users/rich/Developer/lens/LensCore/Addons/AddonManifest.swift`:

```swift
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
```

- [ ] **Step 2: Write AddonRecord.swift**

Create `/Users/rich/Developer/lens/LensCore/Addons/AddonRecord.swift`:

```swift
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
```

- [ ] **Step 3: Write AddonError.swift**

Create `/Users/rich/Developer/lens/LensCore/Addons/AddonError.swift`:

```swift
// AddonError.swift — Typed errors for every failure point in the addon pipeline.
//
// Each case maps to one stage: download, integrity check, extraction, manifest
// parsing, validation, or registration. Surface these inline — no modal dialogs
// (spec §8 reliability requirement).
import Foundation

public enum AddonError: Error, Sendable {
    /// HTTP download failed. `statusCode` is nil if the error was non-HTTP (e.g. network timeout).
    case downloadFailed(url: URL, statusCode: Int?)
    /// SHA-256 digest of the downloaded zip does not match the provided expected value.
    case sha256Mismatch(expected: String, actual: String)
    /// `/usr/bin/unzip` exited with a non-zero status.
    case extractionFailed(terminationStatus: Int32)
    /// No manifest.json was found at the root of the extracted directory.
    case manifestNotFound
    /// manifest.json was found but could not be decoded as AddonManifest.
    case manifestDecodingFailed(underlying: String)
    /// Manifest decoded but failed `isValid` check (missing required fields).
    case invalidManifest
    /// An addon with this identifier is already registered.
    case duplicateIdentifier(String)
    /// The Application Support directory could not be resolved.
    case installDirectoryUnavailable
}

extension AddonError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let url, let code):
            if let code {
                return "Download failed for \(url.absoluteString) (HTTP \(code))"
            }
            return "Download failed for \(url.absoluteString)"
        case .sha256Mismatch(let expected, let actual):
            return "Integrity check failed — expected \(expected), got \(actual)"
        case .extractionFailed(let status):
            return "ZIP extraction failed with exit code \(status)"
        case .manifestNotFound:
            return "No manifest.json found in addon package"
        case .manifestDecodingFailed(let msg):
            return "Failed to parse manifest.json: \(msg)"
        case .invalidManifest:
            return "Addon manifest is missing required fields"
        case .duplicateIdentifier(let id):
            return "An addon with identifier '\(id)' is already registered"
        case .installDirectoryUnavailable:
            return "Could not access Application Support directory"
        }
    }
}
```

---

## Task 2: Write AddonManifestTests.swift, add files to Xcode, run tests

**(Both)**

**Files:**
- Create: `LensCoreTests/Addons/AddonManifestTests.swift`

- [ ] **Step 1: Write AddonManifestTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Addons/AddonManifestTests.swift`:

```swift
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
```

- [ ] **Step 2: Add files to Xcode** **(Human)**

1. In Xcode Project Navigator, right-click the **LensCore** group → **New Group** → name it `Addons`.
2. Right-click the new **LensCore/Addons** group → **Add Files to "Lens"…**
3. Select `LensCore/Addons/AddonManifest.swift`, `AddonRecord.swift`, `AddonError.swift` → **Add** (Create groups, uncheck "Copy items if needed", add to **LensCore** target only).
4. Delete `LensCore/Addons/.gitkeep` from the Xcode group (right-click → Delete → Move to Trash). Also delete it from disk: `rm LensCore/Addons/.gitkeep`.
5. In **LensCoreTests**, right-click the group → **New Group** → name it `Addons`.
6. Right-click **LensCoreTests/Addons** → **Add Files to "Lens"…**
7. Select `LensCoreTests/Addons/AddonManifestTests.swift` → **Add**, adding to the **LensCoreTests** target.
8. Select the **LensCoreTests** scheme, destination **Any Mac** → **⌘U**.

Expected: All prior tests still pass. `AddonManifestTests` reports **7 tests pass**. No failures.

If tests fail, paste the full error here (include file:line).

---

## Task 3: Write AddonRegistry.swift

**(Agent)**

**Files:**
- Create: `LensCore/Addons/AddonRegistry.swift`

- [ ] **Step 1: Write AddonRegistry.swift**

Create `/Users/rich/Developer/lens/LensCore/Addons/AddonRegistry.swift`:

```swift
// AddonRegistry.swift — In-memory store of registered addons.
//
// AddonRegistry is a Swift actor so registration and lookup are safe to call
// from any concurrency context. The store is in-memory only for the vertical
// slice — addons do not persist across app restarts until Phase B.
//
// The registry is shared via `AddonRegistry.shared`. In unit tests, always
// create a fresh `AddonRegistry()` to avoid cross-test contamination.
import Foundation

public actor AddonRegistry {

    // MARK: - Shared instance

    /// App-wide shared registry. Use a fresh `AddonRegistry()` in unit tests.
    public static let shared = AddonRegistry()

    // MARK: - Private state

    private var records: [String: AddonRecord] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Registration

    /// Registers an addon record. Throws `AddonError.duplicateIdentifier` if an
    /// addon with the same identifier is already registered.
    public func register(_ record: AddonRecord) throws {
        guard records[record.id] == nil else {
            throw AddonError.duplicateIdentifier(record.id)
        }
        records[record.id] = record
    }

    // MARK: - Lookup

    /// Returns the registered addon with the given identifier, or nil if not found.
    public func addon(withId id: String) -> AddonRecord? {
        records[id]
    }

    /// All currently registered addons, sorted by identifier for determinism.
    public var allAddons: [AddonRecord] {
        records.values.sorted { $0.id < $1.id }
    }

    // MARK: - Removal

    /// Removes the addon with the given identifier. No-op if not found.
    public func unregister(id: String) {
        records.removeValue(forKey: id)
    }
}
```

---

## Task 4: Write AddonRegistryTests.swift, add to Xcode, run tests

**(Both)**

**Files:**
- Create: `LensCoreTests/Addons/AddonRegistryTests.swift`

- [ ] **Step 1: Write AddonRegistryTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Addons/AddonRegistryTests.swift`:

```swift
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
```

- [ ] **Step 2: Add AddonRegistry.swift and AddonRegistryTests.swift to Xcode** **(Human)**

1. In Xcode, right-click **LensCore/Addons** group → **Add Files to "Lens"…**
2. Select `LensCore/Addons/AddonRegistry.swift` → **Add**, target: **LensCore** only.
3. Right-click **LensCoreTests/Addons** group → **Add Files to "Lens"…**
4. Select `LensCoreTests/Addons/AddonRegistryTests.swift` → **Add**, target: **LensCoreTests**.
5. Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: All prior tests pass. `AddonRegistryTests` reports **6 tests pass**. No failures.

---

## Task 5: Add addon events to LensEvent.swift and update LensEventTests.swift

**(Agent)**

**Files:**
- Modify: `LensCore/Events/LensEvent.swift`
- Modify: `LensCoreTests/Events/LensEventTests.swift`

- [ ] **Step 1: Add addon events to LensEvent.swift**

Open `LensCore/Events/LensEvent.swift`. Find the `// MARK: Reader / theme` section near the bottom and add the new section immediately after the `case themeApplied(...)` line:

```swift
    // MARK: Addon lifecycle

    /// An addon was successfully downloaded, verified, extracted, and registered.
    /// `addonId` is the `identifier` field from the addon's manifest.json.
    case addonInstalled(addonId: String)
    /// An addon installation attempt failed at any stage.
    /// `addonId` is nil if the failure occurred before the manifest was parsed
    /// (e.g. download or ZIP extraction failure).
    case addonInstallFailed(addonId: String?, error: String)
```

- [ ] **Step 2: Add the new cases to the allCasesRoundTrip test in LensEventTests.swift**

Open `LensCoreTests/Events/LensEventTests.swift`. Find the `allCasesRoundTrip` test and add these two lines to the `cases` array (after `.themeApplied(themeName: "default")`):

```swift
            .addonInstalled(addonId: "com.example.dark-theme"),
            .addonInstallFailed(addonId: "com.example.dark-theme", error: "download failed"),
            .addonInstallFailed(addonId: nil, error: "bad zip"),
```

- [ ] **Step 3: Run LensCore tests to confirm the changes compile and existing tests pass** **(Human)**

Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: All existing tests pass. The `allCasesRoundTrip` test now covers the two new addon cases. No failures.

---

## Task 6: Write AddonInstaller.swift

**(Agent)**

**Files:**
- Create: `LensCore/Addons/AddonInstaller.swift`

- [ ] **Step 1: Write AddonInstaller.swift**

Create `/Users/rich/Developer/lens/LensCore/Addons/AddonInstaller.swift`:

```swift
// AddonInstaller.swift — macOS-only pipeline: download → SHA-256 verify →
// unzip → parse manifest → register → emit event.
//
// Remote addon install is macOS-only in v1 (spec §5.1, §5.3).
// On iOS, `AddonInstaller` does not compile; use `#if os(macOS)` guards at
// any call site if you need to check availability.
//
// Install flow:
//   1. Download zip bytes via URLSession
//   2. Verify SHA-256 of downloaded bytes against caller-supplied expected hash
//   3. Write zip to a temp file
//   4. Extract to a temp staging directory using /usr/bin/unzip
//   5. Parse manifest.json from the staging root
//   6. Validate manifest (isValid check)
//   7. Move staging directory to permanent install path in Application Support
//   8. Build AddonRecord and register with AddonRegistry.shared
//   9. Emit .addonInstalled or .addonInstallFailed on EventBus.shared
#if os(macOS)
import CryptoKit
import Foundation

public actor AddonInstaller {

    // MARK: - Shared instance

    /// App-wide shared installer. Use a fresh `AddonInstaller()` in unit tests
    /// if you need to inject a custom URLSession or isolate registry state.
    public static let shared = AddonInstaller()

    // MARK: - Init

    public init() {}

    // MARK: - Public install API

    /// Downloads and installs an addon from a zip URL.
    ///
    /// - Parameters:
    ///   - zipURL: Direct HTTPS URL to the addon `.zip` file.
    ///   - expectedSHA256: Lowercase hex-encoded SHA-256 of the zip bytes.
    ///     The caller obtains this from the addon author's distribution page.
    /// - Returns: The registered `AddonRecord` on success.
    /// - Throws: `AddonError` describing the failure stage.
    @discardableResult
    public func install(from zipURL: URL, expectedSHA256: String) async throws -> AddonRecord {
        let addonId: String?

        do {
            // 1. Download
            let zipData = try await download(from: zipURL)

            // 2. Verify SHA-256
            let actualHash = Self.sha256Hex(of: zipData)
            guard actualHash == expectedSHA256.lowercased() else {
                throw AddonError.sha256Mismatch(
                    expected: expectedSHA256.lowercased(),
                    actual: actualHash
                )
            }

            // 3. Write to temp file
            let tmpDir = FileManager.default.temporaryDirectory
            let tmpZip = tmpDir.appending(path: UUID().uuidString + ".zip")
            try zipData.write(to: tmpZip)
            defer { try? FileManager.default.removeItem(at: tmpZip) }

            // 4. Extract to staging directory
            let stagingDir = tmpDir.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try await extractZip(at: tmpZip, to: stagingDir)
            defer { try? FileManager.default.removeItem(at: stagingDir) }

            // 5 & 6. Parse and validate manifest
            let manifest = try parseManifest(in: stagingDir)
            guard manifest.isValid else {
                throw AddonError.invalidManifest
            }
            addonId = manifest.identifier

            // 7. Move to permanent install directory
            let installDir = try Self.installDirectory(for: manifest.identifier)
            if FileManager.default.fileExists(atPath: installDir.path) {
                try FileManager.default.removeItem(at: installDir)
            }
            // Copy rather than move: staging dir is temp; copy is safer across volumes.
            try FileManager.default.copyItem(at: stagingDir, to: installDir)

            // 8. Build and register record
            let record = AddonRecord(
                manifest: manifest,
                installedAt: Date(),
                installDirectoryURL: installDir
            )
            try await AddonRegistry.shared.register(record)

            // 9. Emit success event
            await EventBus.shared.emit(.addonInstalled(addonId: manifest.identifier))

            return record

        } catch let addonErr as AddonError {
            // Emit failure event before re-throwing so observers (UI, analytics) know what happened.
            await EventBus.shared.emit(
                .addonInstallFailed(addonId: addonId ?? nil, error: addonErr.localizedDescription ?? "unknown error")
            )
            throw addonErr
        } catch {
            await EventBus.shared.emit(
                .addonInstallFailed(addonId: nil, error: error.localizedDescription)
            )
            throw error
        }
    }

    // MARK: - SHA-256 helper (public for testing)

    /// Returns the lowercase hex-encoded SHA-256 digest of `data`.
    ///
    /// This is the canonical integrity check used before accepting any addon zip.
    /// Exposed as `public static` so tests can call it without instantiating the actor.
    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install directory

    /// Returns the permanent install directory for an addon identifier,
    /// creating intermediate directories as needed.
    ///
    /// Path: ~/Library/Application Support/Lens/Addons/<identifier>/
    public static func installDirectory(for identifier: String) throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AddonError.installDirectoryUnavailable
        }
        let dir = appSupport.appending(
            path: "Lens/Addons/\(identifier)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private helpers

    private func download(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode
        // Treat anything outside 2xx as a failure — surface HTTP status for debugging.
        guard let status, (200..<300).contains(status) else {
            throw AddonError.downloadFailed(
                url: url,
                statusCode: (response as? HTTPURLResponse)?.statusCode
            )
        }
        return data
    }

    private func extractZip(at zipURL: URL, to destinationURL: URL) async throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        // Use /usr/bin/unzip (always present on macOS) to avoid a zip library dependency.
        // -q: quiet, -o: overwrite without prompting, -d: destination.
        // The zip must have no top-level directory — files at the archive root land
        // directly in destinationURL. See docs/reference-addon/README.md for packaging.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", "-o", zipURL.path, "-d", destinationURL.path]
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: AddonError.extractionFailed(terminationStatus: proc.terminationStatus)
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseManifest(in directory: URL) throws -> AddonManifest {
        let manifestURL = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw AddonError.manifestNotFound
        }
        let data = try Data(contentsOf: manifestURL)
        do {
            return try JSONDecoder().decode(AddonManifest.self, from: data)
        } catch {
            throw AddonError.manifestDecodingFailed(underlying: error.localizedDescription)
        }
    }
}
#endif
```

---

## Task 7: Write AddonInstallerTests.swift, add to Xcode, run tests

**(Both)**

**Files:**
- Create: `LensCoreTests/Addons/AddonInstallerTests.swift`

- [ ] **Step 1: Write AddonInstallerTests.swift**

Create `/Users/rich/Developer/lens/LensCoreTests/Addons/AddonInstallerTests.swift`:

```swift
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
```

- [ ] **Step 2: Add AddonInstaller.swift and AddonInstallerTests.swift to Xcode** **(Human)**

1. In Xcode, right-click **LensCore/Addons** group → **Add Files to "Lens"…**
2. Select `LensCore/Addons/AddonInstaller.swift` → **Add**, target: **LensCore** only.
3. Right-click **LensCoreTests/Addons** → **Add Files to "Lens"…**
4. Select `LensCoreTests/Addons/AddonInstallerTests.swift` → **Add**, target: **LensCoreTests**.
5. Select scheme **LensCoreTests**, destination **Any Mac** → **⌘U**.

Expected: All prior tests pass. `AddonInstallerTests` reports **6 tests pass**. No failures.

---

## Task 8: Create reference addon files

**(Agent)**

**Files:**
- Create: `docs/reference-addon/manifest.json`
- Create: `docs/reference-addon/theme.css`
- Create: `docs/reference-addon/README.md`

- [ ] **Step 1: Write manifest.json**

Create `/Users/rich/Developer/lens/docs/reference-addon/manifest.json`:

```json
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
```

- [ ] **Step 2: Write theme.css**

Create `/Users/rich/Developer/lens/docs/reference-addon/theme.css`:

```css
/*
 * Lens Dark Pro — reference theme addon
 * Identifier: com.richardtape.lens.reference-theme
 *
 * This theme uses the --lens-* CSS custom properties defined by ThemeEngine
 * (spec §2.4, §9 token contract). Overriding them here changes the reading
 * experience without touching the structural layer.
 *
 * This file is the reference implementation for the Phase 2D addon vertical
 * slice — its primary purpose is to prove the manifest → zip → install →
 * ThemeEngine pipeline, not to be a polished production theme.
 */

:root {
  --lens-bg:            #1a1b1e;
  --lens-text:          #e8e8e8;
  --lens-link:          #7cb7f7;
  --lens-font-family:   "Georgia", serif;
  --lens-font-size:     19px;
  --lens-line-height:   1.75;
  --lens-content-width: 720px;
  --lens-code-font:     "Menlo", ui-monospace, monospace;
}

body {
  background-color: var(--lens-bg);
  color:            var(--lens-text);
  font-family:      var(--lens-font-family);
  font-size:        var(--lens-font-size);
  line-height:      var(--lens-line-height);
  max-width:        var(--lens-content-width);
  margin:           0 auto;
  padding:          2rem 1.5rem;
}

a {
  color: var(--lens-link);
}

pre,
code {
  font-family:      var(--lens-code-font);
  background-color: #2d2e32;
  padding:          0.15em 0.4em;
  border-radius:    4px;
}

pre {
  padding:    1em 1.25em;
  overflow-x: auto;
}

blockquote {
  border-left: 3px solid #4a4b50;
  margin-left: 0;
  padding-left: 1.25em;
  color: #aaa;
}

img {
  max-width: 100%;
  height:    auto;
}
```

- [ ] **Step 3: Write README.md**

Create `/Users/rich/Developer/lens/docs/reference-addon/README.md`:

```markdown
# Reference addon — Lens Dark Pro

This directory contains the source files for the Phase 2D reference theme addon.
Its purpose is to prove the end-to-end macOS addon pipeline (download → SHA-256
verify → unzip → manifest parse → register).

## Files

| File | Role |
|------|------|
| `manifest.json` | Addon manifest (identifier, capabilities, asset list) |
| `theme.css` | CSS that overrides `--lens-*` custom properties |

## Packaging and hosting (human driver steps)

Run these once to create the distributable zip and get its hash.

### 1. Create the zip

```bash
cd /Users/rich/Developer/lens/docs/reference-addon
zip -j addon.zip manifest.json theme.css
```

`-j` (junk paths) ensures `manifest.json` and `theme.css` are at the **root** of
the archive with no subdirectory. `AddonInstaller` expects this layout.

### 2. Compute SHA-256

```bash
shasum -a 256 addon.zip
```

Copy the 64-character hex string. You will need it when calling `AddonInstaller.install(from:expectedSHA256:)`.

### 3. Host the zip

Upload `addon.zip` to your HTTPS server at a stable URL, e.g.:

```
https://addons.richardtape.com/reference-theme/1.0.0/addon.zip
```

Keep the URL and SHA-256 together in your notes — both are required to install.

## Running the integration test

Once the zip is hosted, verify the full pipeline from Swift:

```swift
// Paste into a macOS Playground or a temporary LensMac debug action.
import LensCore

let zipURL = URL(string: "https://addons.richardtape.com/reference-theme/1.0.0/addon.zip")!
let sha256  = "<paste the 64-char hex from shasum output>"

let record = try await AddonInstaller.shared.install(from: zipURL, expectedSHA256: sha256)
print("Installed: \(record.manifest.displayName) @ \(record.installDirectoryURL.path)")

let all = await AddonRegistry.shared.allAddons
print("Registry count: \(all.count)")
```

Expected output:
```
Installed: Lens Dark Pro @ /Users/<you>/Library/Application Support/Lens/Addons/com.richardtape.lens.reference-theme
Registry count: 1
```

The EventBus will have emitted `.addonInstalled(addonId: "com.richardtape.lens.reference-theme")`.

## Updating the addon

Increment `version` in `manifest.json`, re-zip, re-host under a new URL, recompute SHA-256.
The identifier `com.richardtape.lens.reference-theme` is stable.
```

---

## Task 9: Package, host, and end-to-end test the reference addon

**(Human)**

- [ ] **Step 1: Package the reference addon**

```bash
cd /Users/rich/Developer/lens/docs/reference-addon
zip -j addon.zip manifest.json theme.css
shasum -a 256 addon.zip
```

Note the 64-character hex SHA-256. You will need it in Step 3.

- [ ] **Step 2: Host the zip on your HTTPS server**

Upload `docs/reference-addon/addon.zip` to your server at a stable URL over HTTPS.
Example: `https://addons.richardtape.com/reference-theme/1.0.0/addon.zip`

Verify the file is reachable: `curl -I <your-url>` should return `HTTP/2 200`.

- [ ] **Step 3: Run the integration test from a macOS Playground or LensMac debug entry point**

Open Xcode, create a new macOS Playground (File → New → Playground → macOS → Blank),
add `LensCore` as a framework import, and run:

```swift
import PlaygroundSupport
import LensCore
PlaygroundPage.current.needsIndefiniteExecution = true

Task {
    do {
        let zipURL = URL(string: "<your hosted zip URL>")!
        let sha256  = "<paste 64-char hex from Step 1>"

        let record = try await AddonInstaller.shared.install(from: zipURL, expectedSHA256: sha256)
        print("✓ Installed: \(record.manifest.displayName)")
        print("  Path: \(record.installDirectoryURL.path)")

        let all = await AddonRegistry.shared.allAddons
        print("  Registry count: \(all.count)")
    } catch {
        print("✗ Install failed: \(error.localizedDescription)")
    }
    PlaygroundPage.current.finishExecution()
}
```

Expected console output:
```
✓ Installed: Lens Dark Pro
  Path: /Users/<you>/Library/Application Support/Lens/Addons/com.richardtape.lens.reference-theme
  Registry count: 1
```

Also verify the installed files on disk:

```bash
ls ~/Library/Application\ Support/Lens/Addons/com.richardtape.lens.reference-theme/
# Expected: manifest.json  theme.css
```

If the playground approach is not available, an equivalent Swift script in a temporary `LensMac` `@main` body or a one-off test target achieves the same result.

- [ ] **Step 4: Test SHA-256 mismatch rejection**

Re-run the install call with a deliberately wrong hash:

```swift
let record = try await AddonInstaller.shared.install(
    from: zipURL,
    expectedSHA256: "0000000000000000000000000000000000000000000000000000000000000000"
)
```

Expected: throws `AddonError.sha256Mismatch(...)`. Confirm the `.addonInstallFailed` event was emitted by subscribing to `EventBus.shared` before calling install.

---

## Task 10: Update agent-orientation.md and commit

**(Both)**

**Files:**
- Modify: `docs/superpowers/2026-04-10-lens-agent-orientation.md`

- [ ] **Step 1: Update the Current state section** **(Agent)**

Replace the `## Current state` block with:

```markdown
## Current state

**Phase 2A complete; Phase 2B complete; Phase 2C complete; Phase 2D complete.**

| Target | Type | Source folder |
|--------|------|---------------|
| `LensIOS` | iOS App | `LensIOS/` |
| `LensMac` | macOS App | `LensMac/` |
| `LensCore` | iOS + macOS Framework | `LensCore/` |
| `LensUI` | iOS + macOS Framework | `LensUI/` |

**LensCore modules built so far:**

| Module | Files | Status |
|--------|-------|--------|
| `Models/` | `Feed.swift`, `FeedItem.swift`, `Category.swift`, `OfflineAsset.swift`, `UserReadingPreferences.swift`, `UserInterfacePreferences.swift` | Phase 2A ✓ |
| `Persistence/` | `PersistenceController.swift`, `CategorySeeder.swift`, `PreferenceStore.swift` | Phase 2A ✓ |
| `Events/` | `LensEvent.swift`, `EventBus.swift` | Phase 2B ✓ |
| `Feeds/` | `ParsedFeed.swift`, `FeedParser.swift`, `RSSParser.swift`, `AtomParser.swift`, `JSONFeedParser.swift`, `FeedFactory.swift`, `FeedService.swift` | Phase 2C ✓ |
| `Addons/` | `AddonManifest.swift`, `AddonRecord.swift`, `AddonError.swift`, `AddonRegistry.swift`, `AddonInstaller.swift` (macOS only) | Phase 2D ✓ |
| `Theme/` | *(empty — Phase 2E)* | — |
| `Routing/` | *(empty — Phase 2E)* | — |

**App Group** `group.com.richardtape.lens` wired in Phase 2A.

**Addon system (Phase 2D):**
- `AddonRegistry.shared` — in-memory actor registry; cross-platform.
- `AddonInstaller.shared` — macOS-only; `install(from:expectedSHA256:)` runs the full pipeline.
- Reference addon at `docs/reference-addon/` (Lens Dark Pro theme); zip hosted by human driver.
- Two new `LensEvent` cases: `.addonInstalled(addonId:)`, `.addonInstallFailed(addonId:error:)`.
- Registry is in-memory only (no persistence across restarts until Phase B).

**Next:** Phase 2E (ThemeEngine skeleton + DeepLinkRouter + `lens://` URL handling).
```

- [ ] **Step 2: Stage and commit** **(Human)**

```bash
cd /Users/rich/Developer/lens
git add \
  LensCore/Addons/AddonManifest.swift \
  LensCore/Addons/AddonRecord.swift \
  LensCore/Addons/AddonError.swift \
  LensCore/Addons/AddonRegistry.swift \
  LensCore/Addons/AddonInstaller.swift \
  LensCoreTests/Addons/AddonManifestTests.swift \
  LensCoreTests/Addons/AddonRegistryTests.swift \
  LensCoreTests/Addons/AddonInstallerTests.swift \
  LensCore/Events/LensEvent.swift \
  LensCoreTests/Events/LensEventTests.swift \
  docs/reference-addon/manifest.json \
  docs/reference-addon/theme.css \
  docs/reference-addon/README.md \
  docs/superpowers/2026-04-10-lens-agent-orientation.md \
  Lens.xcodeproj/project.pbxproj
git status
git commit -m "feat(phase-2d): addon system — registry, macOS installer, reference theme"
```

Expected: commit succeeds with those files listed.

---

## Phase 2D exit criteria

Before declaring Phase 2D done:

- [ ] `LensCore/Addons/` contains all five Swift files: `AddonManifest.swift`, `AddonRecord.swift`, `AddonError.swift`, `AddonRegistry.swift`, `AddonInstaller.swift`.
- [ ] `AddonInstaller.swift` is wrapped in `#if os(macOS)` — the file must compile on iOS without it.
- [ ] `LensEvent` has `.addonInstalled(addonId: String)` and `.addonInstallFailed(addonId: String?, error: String)`.
- [ ] All `AddonManifestTests` pass (7 tests).
- [ ] All `AddonRegistryTests` pass (6 tests).
- [ ] All `AddonInstallerTests` pass (6 tests).
- [ ] All Phase 2A / 2B / 2C tests still pass.
- [ ] `docs/reference-addon/` contains `manifest.json`, `theme.css`, `README.md`.
- [ ] Human driver has run the end-to-end install of the reference addon and confirmed the registry count and file paths.
- [ ] `agent-orientation.md` **Current state** section reflects Phase 2D completion.
- [ ] Changes committed.

---

## What's next

**Phase 2E** — Engine scaffolding:
- `ThemeEngine` skeleton in `LensCore/Theme/` — three CSS-layer composition (structural, token, theme).
- `DeepLinkRouter` in `LensCore/Routing/` — parses `lens://` URLs and emits navigation events.
- `onOpenURL` wiring at scene level in `LensIOS` and `LensMac`.
- Depends on: Phase 2B event bus (`DeepLinkRouter` emits events).
