// CategorySeederTests.swift
import Testing
import SwiftData
import Foundation
@testable import LensCore

// Foundation's ObjC runtime exports a `Category` opaque type that clashes with
// LensCore.Category. Pinning the name here resolves the ambiguity for this file.
private typealias Category = LensCore.Category

@Suite("CategorySeeder")
struct CategorySeederTests {

    @Test("seeds exactly 10 built-in categories on first call")
    func seedsOnFirstLaunch() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: context)

        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = try context.fetch(descriptor)

        #expect(categories.count == 10)
        #expect(categories[0].name == "Technology")
        #expect(categories[9].name == "Education")
        #expect(categories.allSatisfy { $0.isBuiltIn })
    }

    @Test("does not duplicate categories on repeated calls")
    func idempotent() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: context)
        try CategorySeeder.seedIfNeeded(in: context) // second call must be a no-op

        let categories = try context.fetch(FetchDescriptor<Category>())
        #expect(categories.count == 10)
    }

    @Test("categories match the predefined list in order")
    func orderMatchesSpec() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: context)

        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = try context.fetch(descriptor)
        let names = categories.map { $0.name }

        #expect(names == CategorySeeder.predefinedCategories)
    }
}
