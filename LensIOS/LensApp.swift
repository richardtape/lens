// LensApp.swift — iOS app entry point.
//
// TimelineState is created once here and injected as an @Observable environment
// object. This keeps a single source of truth for filter state and the new-items
// banner across all views.
import SwiftUI
import SwiftData
import LensCore
import LensUI

@main
struct LensApp: App {
    private let container: ModelContainer

    @State private var timelineState = TimelineState()

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
                .environment(timelineState)
                .task { await seedOnLaunch() }
                .onOpenURL { url in
                    Task { await DeepLinkRouter.handle(url) }
                }
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
        // PHASE-4-DEBUG — remove next line before Phase 5
        await DebugFeedSeeder.seedIfNeeded(in: container)
    }
}
