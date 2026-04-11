// Category.swift — SwiftData entity for a feed category (predefined or custom).
//
// `isBuiltIn` distinguishes the ten predefined starter categories from user-created ones.
// The CategorySeeder uses this flag to avoid re-seeding on subsequent launches.
import SwiftData
import Foundation

@Model
public final class Category {
    public var id: UUID
    public var name: String
    /// Position in the sidebar category list.
    public var sortOrder: Int
    /// True for the ten predefined categories seeded on first launch.
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isBuiltIn: Bool
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }
}
