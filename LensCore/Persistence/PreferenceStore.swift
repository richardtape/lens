// PreferenceStore.swift — singleton-row accessors for preference records.
//
// Both preference types are "singleton" SwiftData records: exactly one row
// per store, created on first access and never deleted. Fetch the single
// record via fetchOrCreate() rather than querying by a unique field.
import SwiftData
import Foundation

public struct PreferenceStore {

    /// Returns the app's UserReadingPreferences, creating the row if absent.
    public static func readingPreferences(in context: ModelContext) throws -> UserReadingPreferences {
        let existing = try context.fetch(FetchDescriptor<UserReadingPreferences>())
        if let prefs = existing.first { return prefs }
        let prefs = UserReadingPreferences()
        context.insert(prefs)
        try context.save()
        return prefs
    }

    /// Returns the app's UserInterfacePreferences, creating the row if absent.
    public static func interfacePreferences(in context: ModelContext) throws -> UserInterfacePreferences {
        let existing = try context.fetch(FetchDescriptor<UserInterfacePreferences>())
        if let prefs = existing.first { return prefs }
        let prefs = UserInterfacePreferences()
        context.insert(prefs)
        try context.save()
        return prefs
    }
}
