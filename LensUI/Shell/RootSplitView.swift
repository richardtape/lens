// RootSplitView.swift — macOS three-column navigation shell.
//
// Columns:
//   Sidebar (leading)  — nav links; Timeline active; Feeds/Categories stubbed
//   List (middle)      — TimelineView article list
//   Detail (trailing)  — ReaderStubView; replaced by real reader in Phase 4
//
// .listStyle(.sidebar) on the sidebar gives automatic Liquid Glass treatment.
// .backgroundExtensionEffect() on the middle column extends content edge-to-edge.
//
// The keyboard shortcut reference sheet (?) is triggered via FocusedValues
// so the Commands block in LensMacApp can reach into the view hierarchy without
// direct coupling.
import SwiftUI
import SwiftData
import LensCore

// Category conflicts with an ObjC runtime type when Foundation is in scope.
private typealias Category = LensCore.Category

// MARK: - FocusedValues extension for ? shortcut

extension FocusedValues {
    @Entry var showKeyboardShortcuts: Binding<Bool>? = nil
}

// MARK: - Sidebar destination

enum MacDestination: Hashable {
    case timeline
    case feeds
    case categories
}

struct RootSplitView: View {
    @Environment(TimelineState.self) private var timelineState

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var destination: MacDestination = .timeline
    @State private var selectedItem: FeedItem? = nil
    @State private var showingKeyboardShortcuts = false

    @Query private var prefsQuery: [UserReadingPreferences]
    private var prefs: UserReadingPreferences? { prefsQuery.first }

    var body: some View {
        let accentColor = Color(hex: prefs?.accentColorHex ?? "#4A90D9")

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            contentColumn
                .backgroundExtensionEffect()
        } detail: {
            ReaderStubView(item: selectedItem)
        }
        .tint(accentColor)
        .environment(\.lensAccentColor, accentColor)
        .environment(\.lensListDensity, prefs?.listDensity ?? 0.5)
        .focusedSceneValue(\.showKeyboardShortcuts, $showingKeyboardShortcuts)
        .sheet(isPresented: $showingKeyboardShortcuts) {
            KeyboardShortcutsSheet()
        }
        .task { await subscribeToNavigationEvents() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $destination) {
            NavigationLink(value: MacDestination.timeline) {
                Label("Timeline", systemImage: "newspaper")
            }

            Section("Library") {
                NavigationLink(value: MacDestination.feeds) {
                    Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink(value: MacDestination.categories) {
                    Label("Categories", systemImage: "folder")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Lens")
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch destination {
        case .timeline:
            NavigationStack {
                TimelineView(selectedItem: $selectedItem)
            }
        case .feeds:
            StubDestinationView(name: "Feeds", symbol: "antenna.radiowaves.left.and.right")
        case .categories:
            StubDestinationView(name: "Categories", symbol: "folder")
        }
    }

    // MARK: - Deep link routing

    private func subscribeToNavigationEvents() async {
        for await event in await EventBus.shared.makeStream() {
            switch event {
            case .navigateToFeed, .navigateToItem, .navigateToAddFeed:
                destination = .timeline
            default:
                break
            }
        }
    }
}

// MARK: - Keyboard shortcuts reference sheet

private struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(key: String, description: String)] = [
        ("j", "Next item"),
        ("k", "Previous item"),
        ("u", "Toggle read / unread"),
        ("r", "Refresh all feeds"),
        ("s", "Toggle offline save"),
        ("f", "Toggle star"),
        ("o", "Open in browser"),
        ("?", "Show this reference"),
        ("Esc", "Deselect / go back"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            ForEach(shortcuts, id: \.key) { item in
                HStack {
                    Text(item.key)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40, alignment: .leading)
                    Text(item.description)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 320)
        .presentationDetents([.medium])
    }
}

#Preview {
    RootSplitView()
        .environment(TimelineState())
        .modelContainer(for: [FeedItem.self, Feed.self, Category.self, UserReadingPreferences.self], inMemory: true)
        .frame(minWidth: 900, minHeight: 600)
}
