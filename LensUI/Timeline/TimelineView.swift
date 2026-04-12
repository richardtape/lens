// TimelineView.swift — Chronological feed item timeline.
//
// Architecture: Two views collaborate to work around SwiftData's constraint
// that @Query descriptors are fixed at init time. TimelineView owns the toolbar
// and banner; TimelineContentView is recreated with new init parameters whenever
// the filter changes, causing @Query to rebuild with the new predicate.
//
// Pull-to-refresh: snapshots the feed ID list synchronously (safe to read
// @Query results before the async boundary), then concurrently fetches each
// feed using a separate FeedService actor instance per feed.
import SwiftUI
import SwiftData
import LensCore


// MARK: - TimelineView (outer)

struct TimelineView: View {
    @Environment(TimelineState.self) private var timelineState
    @Environment(\.modelContext) private var modelContext

    // Shared selection state — the same FeedItem drives both the list highlight
    // (content column) and the detail column on macOS.
    @Binding var selectedItem: FeedItem?

    // Changing this UUID triggers a scroll-to-top in TimelineContentView.
    @State private var scrollTopTrigger = UUID()

    @State private var showFilterSheet = false

    var body: some View {
        @Bindable var state = timelineState

        TimelineContentView(
            filter: timelineState.filterMode,
            unreadOnly: timelineState.unreadOnly,
            selectedItem: $selectedItem,
            scrollTopTrigger: scrollTopTrigger
        )
        .navigationTitle("Timeline")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { timelineToolbar }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Banner only appears on the main unfiltered timeline.
            if let banner = timelineState.newItemsBanner,
               timelineState.filterMode == .all {
                NewItemsBannerView(banner: banner) {
                    // Scroll list to top, then clear the banner.
                    scrollTopTrigger = UUID()
                    timelineState.newItemsBanner = nil
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timelineState.newItemsBanner)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(
                filterMode: $state.filterMode,
                unreadOnly: $state.unreadOnly
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var timelineToolbar: some ToolbarContent {
        ToolbarItem(placement: toolbarTrailingPlacement) {
            // Filter button — badge shows count of active non-default filters.
            Button {
                showFilterSheet = true
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.glass)
            .overlay(alignment: .topTrailing) {
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.red, in: .circle)
                        .offset(x: 6, y: -6)
                }
            }
        }

        ToolbarItem(placement: toolbarLeadingPlacement) {
            Button {
                timelineState.unreadOnly.toggle()
            } label: {
                Label(
                    "Unread Only",
                    systemImage: timelineState.unreadOnly ? "circle.fill" : "circle"
                )
            }
            .buttonStyle(timelineState.unreadOnly ? .glassProminent : .glass)
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if timelineState.filterMode != .all { count += 1 }
        if timelineState.unreadOnly { count += 1 }
        return count
    }

    // Toolbar placements differ by platform.
    private var toolbarTrailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .navigationBarTrailing
        #endif
    }

    private var toolbarLeadingPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .navigationBarLeading
        #endif
    }
}

// MARK: - TimelineContentView (inner — owns @Query)

/// Owns the SwiftData @Query. Rebuilt by SwiftUI whenever `filter` or `unreadOnly`
/// changes (because they're struct parameters, not @Binding), which causes the
/// `init` to run again and produce a new @Query descriptor.
private struct TimelineContentView: View {
    let filter: TimelineFilter
    let unreadOnly: Bool
    @Binding var selectedItem: FeedItem?
    let scrollTopTrigger: UUID

    @Query private var items: [FeedItem]
    @Query private var allFeeds: [Feed]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.lensAccentColor) private var accentColor

    init(
        filter: TimelineFilter,
        unreadOnly: Bool,
        selectedItem: Binding<FeedItem?>,
        scrollTopTrigger: UUID
    ) {
        self.filter = filter
        self.unreadOnly = unreadOnly
        self._selectedItem = selectedItem
        self.scrollTopTrigger = scrollTopTrigger
        self._allFeeds = Query()
        self._items = Query(TimelineFilter.fetchDescriptor(filter: filter, unreadOnly: unreadOnly))
    }

    // Applies in-memory category membership filter that @Predicate can't express.
    private var displayedItems: [FeedItem] {
        guard case .category(let catId) = filter else { return items }
        let feedIds = Set(allFeeds.filter { $0.categoryId == catId }.map(\.id))
        return items.filter { feedIds.contains($0.feedId) }
    }

    private var feedLookup: [UUID: Feed] {
        Dictionary(uniqueKeysWithValues: allFeeds.map { ($0.id, $0) })
    }

    var body: some View {
        if displayedItems.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                List(selection: $selectedItem) {
                    ForEach(displayedItems) { item in
                        ArticleRowView(item: item, feed: feedLookup[item.feedId])
                            .tag(item)
                            .id(item.id)
                    }
                }
                .listStyle(.plain)
                .refreshable { await refreshAllFeeds() }
                #if os(macOS)
                // macOS keyboard shortcuts live in RootSplitView; they need
                // access to displayedItems and selection — wire them here via
                // a preference key rather than prop-drilling.
                .macOSKeyboardShortcuts(
                    items: displayedItems,
                    selectedItem: $selectedItem,
                    modelContext: modelContext
                )
                #endif
                .onChange(of: scrollTopTrigger) { _, _ in
                    if let first = displayedItems.first {
                        withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
                // Emit .itemDisplayed whenever the selected item changes so the
                // event bus reflects what's visible in the reader (spec §3.7).
                .onChange(of: selectedItem) { _, newItem in
                    if let item = newItem {
                        Task { await EventBus.shared.emit(.itemDisplayed(itemId: item.id)) }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your timeline is quiet", systemImage: "newspaper")
        } description: {
            Text("Add some feeds and your articles will appear here.")
        } actions: {
            // Navigates to Feeds tab — handled via tab selection binding in RootTabView.
            // For Phase 3, this emits a navigation event; RootTabView responds to it.
            Button("Add your first feed") {
                Task { await EventBus.shared.emit(.navigateToAddFeed(prefillURL: nil)) }
            }
            .buttonStyle(.glassProminent)
        }
    }

    // MARK: - Pull-to-refresh

    /// Concurrently refreshes all subscribed feeds.
    /// Each feed gets its own FeedService instance (separate actors run in parallel).
    /// Snapshotting feed IDs before the async boundary avoids capturing a SwiftData
    /// query result across actor hops.
    private func refreshAllFeeds() async {
        let container = modelContext.container
        let feedIds = allFeeds.map(\.id)  // snapshot before async boundary
        await EventBus.shared.emit(.userInitiatedRefresh)
        await withTaskGroup(of: Void.self) { group in
            for feedId in feedIds {
                group.addTask {
                    await FeedService(container: container).fetchFeed(feedId: feedId)
                }
            }
        }
    }
}

// MARK: - macOS keyboard shortcut wiring

#if os(macOS)
/// Attaches j/k/u/r/s/f/o keyboard shortcuts to the timeline list on macOS.
/// Hidden buttons receive keyboard events; they're excluded from accessibility trees.
private extension View {
    func macOSKeyboardShortcuts(
        items: [FeedItem],
        selectedItem: Binding<FeedItem?>,
        modelContext: ModelContext
    ) -> some View {
        self.overlay(
            MacOSKeyboardShortcutsView(
                items: items,
                selectedItem: selectedItem,
                modelContext: modelContext
            )
            .frame(width: 0, height: 0)
            .hidden()
        )
    }
}

private struct MacOSKeyboardShortcutsView: View {
    let items: [FeedItem]
    @Binding var selectedItem: FeedItem?
    let modelContext: ModelContext

    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            // j — select next item
            Button("Next") { selectNext() }
                .keyboardShortcut("j", modifiers: [])

            // k — select previous item
            Button("Prev") { selectPrevious() }
                .keyboardShortcut("k", modifiers: [])

            // u — toggle read/unread on selected item
            Button("Toggle Read") { toggleRead() }
                .keyboardShortcut("u", modifiers: [])

            // r — refresh all feeds (emits event; TimelineContentView drives the fetch via refreshable)
            Button("Refresh") {
                Task { await EventBus.shared.emit(.userInitiatedRefresh) }
            }
            .keyboardShortcut("r", modifiers: [])

            // s — toggle offline save
            Button("Save") { toggleSave() }
                .keyboardShortcut("s", modifiers: [])

            // f — toggle star
            Button("Star") { toggleStar() }
                .keyboardShortcut("f", modifiers: [])

            // o — open in browser
            Button("Open") { openInBrowser() }
                .keyboardShortcut("o", modifiers: [])
        }
    }

    // MARK: - Helpers

    private var selectedIndex: Int? {
        guard let sel = selectedItem else { return nil }
        return items.firstIndex(where: { $0.id == sel.id })
    }

    private func selectNext() {
        guard !items.isEmpty else { return }
        if let idx = selectedIndex {
            selectedItem = items[min(idx + 1, items.count - 1)]
        } else {
            selectedItem = items.first
        }
    }

    private func selectPrevious() {
        guard !items.isEmpty else { return }
        if let idx = selectedIndex {
            selectedItem = items[max(idx - 1, 0)]
        } else {
            selectedItem = items.first
        }
    }

    private func toggleRead() {
        guard let item = selectedItem else { return }
        item.isRead.toggle()
        let event: LensEvent = item.isRead
            ? .itemMarkedRead(itemId: item.id)
            : .itemMarkedUnread(itemId: item.id)
        Task { await EventBus.shared.emit(event) }
    }

    private func toggleSave() {
        guard let item = selectedItem else { return }
        let wasAlreadySaved = item.savedOfflineState == .saved
        item.savedOfflineState = wasAlreadySaved ? .notSaved : .saving
        let event: LensEvent = wasAlreadySaved
            ? .itemOfflineSaveRemoved(itemId: item.id)
            : .itemSavedOffline(itemId: item.id)
        Task { await EventBus.shared.emit(event) }
    }

    private func toggleStar() {
        guard let item = selectedItem else { return }
        item.isStarred.toggle()
        let event: LensEvent = item.isStarred
            ? .itemStarred(itemId: item.id)
            : .itemUnstarred(itemId: item.id)
        Task { await EventBus.shared.emit(event) }
    }

    private func openInBrowser() {
        guard let url = selectedItem?.link else { return }
        openURL(url)
    }
}
#endif

// MARK: - Preview

#Preview("Timeline — empty") {
    NavigationStack {
        TimelineView(selectedItem: .constant(nil))
            .environment(TimelineState())
    }
    .modelContainer(for: [FeedItem.self, Feed.self, LensCore.Category.self], inMemory: true)
    .environment(\.lensAccentColor, Color(hex: "#4A90D9"))
    .environment(\.lensListDensity, 0.5)
}
