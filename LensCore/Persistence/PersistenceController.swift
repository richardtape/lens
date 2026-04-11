// PersistenceController.swift — creates the app's single ModelContainer.
//
// The container is backed by an App Group shared container so that future
// extensions (Share Extension, widgets) can access the same store without
// a migration. Every app target calls makeModelContainer() once at launch.
//
// Unit tests use makeInMemoryContainer() (DEBUG only) which bypasses the
// App Group URL requirement and creates a fresh, isolated store per test.
import SwiftData
import Foundation

/// Errors thrown during ModelContainer initialisation.
public enum PersistenceError: Error, LocalizedError {
    /// The App Group container URL could not be resolved.
    /// Cause: the App Groups capability is not enabled for this target.
    /// Fix: see build strategy §7.2.
    case appGroupContainerUnavailable

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable:
            return "App Group 'group.com.richardtape.lens' is unavailable. " +
                   "Enable the App Groups capability in Xcode for all app targets."
        }
    }
}

public struct PersistenceController {

    /// The full schema — every @Model type registered here.
    /// Add new types in the same order across all call sites to avoid migration issues.
    static let schema = Schema([
        Feed.self,
        FeedItem.self,
        Category.self,
        OfflineAsset.self,
        UserReadingPreferences.self,
        UserInterfacePreferences.self,
    ])

    /// Creates the production ModelContainer backed by the App Group shared store.
    /// Call once from the App struct's `init()`. Pass the result to `.modelContainer()`.
    public static func makeModelContainer() throws -> ModelContainer {
        let url = try appGroupStoreURL()
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Private

    private static func appGroupStoreURL() throws -> URL {
        let groupID = "group.com.richardtape.lens"
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            throw PersistenceError.appGroupContainerUnavailable
        }
        return containerURL.appending(path: "lens.sqlite")
    }
}

// MARK: - Testing support

#if DEBUG
extension PersistenceController {
    /// Creates an isolated in-memory container using the same schema as production.
    /// Each test should call this independently — in-memory stores are not shared.
    /// Does not require the App Groups entitlement.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
#endif
