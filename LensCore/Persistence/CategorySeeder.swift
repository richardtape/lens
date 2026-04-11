// CategorySeeder.swift — seeds the ten predefined categories on first launch.
//
// Call seedIfNeeded(in:) once per launch from the App struct after the
// ModelContainer is created. The method is idempotent: it checks whether
// any built-in categories exist before inserting and exits early if found.
import SwiftData
import Foundation

public struct CategorySeeder {

    /// The ten predefined starter categories, in display order.
    /// Matches the list in product spec §3.2.
    public static let predefinedCategories: [String] = [
        "Technology", "Science", "News", "Health", "Arts & Culture",
        "Business", "Sports", "Entertainment", "Politics", "Education",
    ]

    /// Inserts the predefined categories if none exist yet.
    /// Safe to call on every launch — returns immediately if already seeded.
    public static func seedIfNeeded(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }

        for (index, name) in predefinedCategories.enumerated() {
            context.insert(Category(name: name, sortOrder: index, isBuiltIn: true))
        }
        try context.save()
    }
}
