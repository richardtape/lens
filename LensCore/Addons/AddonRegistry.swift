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
