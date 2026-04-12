// RootTabView.swift — iOS/iPadOS root navigation.
//
// Uses .sidebarAdaptable so the tab bar becomes a sidebar on iPad landscape.
// .tabBarMinimizeBehavior(.onScrollDown) collapses the glass pill while reading.
//
// Deep link routing: subscribes to navigation events from DeepLinkRouter and
// switches the active tab or pushes to the appropriate destination.
// Unbuilt destinations (Feeds, Saved, Settings) navigate to their stub view —
// they won't crash.
import SwiftUI
import SwiftData
import LensCore


// Tab identifiers for programmatic selection (deep linking).
enum RootTab: Hashable {
    case timeline, feeds, saved, settings
}

public struct RootTabView: View {
    public init() {}
    @Environment(TimelineState.self) private var timelineState
    @Environment(\.modelContext) private var modelContext

    @State private var selection: RootTab = .timeline
    @State private var selectedItem: FeedItem? = nil

    // Queries user preferences to set .tint and density environment values.
    @Query private var prefsQuery: [UserReadingPreferences]
    private var prefs: UserReadingPreferences? { prefsQuery.first }

    var body: some View {
        let accentColor = Color(hex: prefs?.accentColorHex ?? "#4A90D9")

        TabView(selection: $selection) {
            Tab("Timeline", systemImage: "newspaper", value: RootTab.timeline) {
                NavigationStack {
                    TimelineView(selectedItem: $selectedItem)
                        .navigationDestination(item: $selectedItem) { item in
                            ReaderStubView(item: item)
                        }
                }
            }

            Tab("Feeds", systemImage: "antenna.radiowaves.left.and.right", value: RootTab.feeds) {
                StubDestinationView(name: "Feeds", symbol: "antenna.radiowaves.left.and.right")
            }

            Tab("Saved", systemImage: "bookmark", value: RootTab.saved) {
                StubDestinationView(name: "Saved", symbol: "bookmark")
            }

            Tab("Settings", systemImage: "gear", value: RootTab.settings) {
                StubDestinationView(name: "Settings", symbol: "gear")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tint(accentColor)
        .environment(\.lensAccentColor, accentColor)
        .environment(\.lensListDensity, prefs?.listDensity ?? 0.5)
        .task { await subscribeToNavigationEvents() }
    }

    // MARK: - Deep link routing

    private func subscribeToNavigationEvents() async {
        for await event in await EventBus.shared.makeStream() {
            switch event {
            case .navigateToSaved:
                selection = .saved
            case .navigateToSettings:
                selection = .settings
            case .navigateToAddFeed, .navigateToFeed, .navigateToItem:
                selection = .timeline
            default:
                break
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(TimelineState())
        .modelContainer(for: [FeedItem.self, Feed.self, LensCore.Category.self, UserReadingPreferences.self], inMemory: true)
}
