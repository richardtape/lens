// LensApp.swift — iOS app entry point.
//
// Responsibilities: create the ModelContainer once and inject it into the
// SwiftUI environment. All views below use @Query or the modelContext
// environment value — never create their own containers.
//
// fatalError on container creation failure is intentional: without a
// working database the app cannot function. The most likely cause is a
// missing App Groups capability (see build strategy §7.2).
import SwiftUI
import LensCore

@main
struct LensApp: App {
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

    // Seeding runs asynchronously so it doesn't block the first frame.
    // Category seeding is idempotent — safe to call on every launch.
    @MainActor
    private func seedOnLaunch() async {
        do {
            try CategorySeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            // Seeding failure is non-fatal: the app works without categories;
            // seeding will retry on the next launch.
            print("[Lens] Category seeding failed: \(error)")
        }
    }
}
