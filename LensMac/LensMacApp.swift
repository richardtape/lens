// LensMacApp.swift — macOS app entry point.
//
// Same setup as LensApp (iOS): ModelContainer created once, injected into
// the environment. Category seeding is identical.
import SwiftUI
import SwiftData
import LensCore

@main
struct LensMacApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try PersistenceController.makeModelContainer()
        } catch {
            fatalError("ModelContainer creation failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await seedOnLaunch() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func seedOnLaunch() async {
        do {
            try CategorySeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            print("[Lens] Category seeding failed: \(error)")
        }
    }
}
