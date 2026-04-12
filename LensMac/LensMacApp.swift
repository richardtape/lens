// LensMacApp.swift — macOS app entry point.
//
// Commands block wires the keyboard shortcut reference sheet (?) to the focused
// scene via FocusedValues, so the Commands menu item can trigger the sheet
// without direct coupling to the view hierarchy.
import SwiftUI
import SwiftData
import LensCore
import LensUI

@main
struct LensMacApp: App {
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
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .help) {
                // ? shortcut — the view provides this binding via .focusedSceneValue
                KeyboardShortcutCommand()
            }
        }
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

// Reads the showKeyboardShortcuts binding from the focused scene and
// provides the "Keyboard Shortcuts..." menu item + ? key binding.
private struct KeyboardShortcutCommand: View {
    @FocusedValue(\.showKeyboardShortcuts) private var showKeyboardShortcuts

    var body: some View {
        Button("Keyboard Shortcuts…") {
            showKeyboardShortcuts?.wrappedValue = true
        }
        .keyboardShortcut("?", modifiers: [])
        .disabled(showKeyboardShortcuts == nil)
    }
}
