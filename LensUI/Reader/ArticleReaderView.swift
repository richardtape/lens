// ArticleReaderView.swift — WKWebView-powered article reader.
//
// Replaces ReaderStubView from Phase 3.
//
// Layout (non-nil item):
//   • Has contentHTML or summaryHTML → WebViewWrapper (reads offline from SwiftData)
//   • Neither field present → "No Content" fallback with "Open in Browser" button
// Layout (nil item):
//   • ContentUnavailableView — macOS detail column idle state
//
// Lifecycle:
//   .task(id: item.id) fires a new Task every time the selected item changes.
//   It marks the item read (once) and emits itemDisplayed on the EventBus.
//
// Keyboard shortcuts (macOS toolbar buttons, single key, no modifier):
//   o → open in browser  f → star  s → save  u → mark unread
//
// Offline: text content renders from SwiftData without a network connection.
// External images in the HTML may fail to load offline; that is Phase 6 scope.
import SwiftUI
import SwiftData
import LensCore
#if os(iOS)
import SafariServices
#endif

public struct ArticleReaderView: View {
    /// The article to display. Nil when nothing is selected (macOS detail column).
    public let item: FeedItem?

    public init(item: FeedItem?) {
        self.item = item
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    // Reads the singleton preferences row; falls back to defaults if not yet created.
    @Query private var prefsQuery: [UserReadingPreferences]
    private var prefs: UserReadingPreferences { prefsQuery.first ?? UserReadingPreferences() }

    #if os(iOS)
    @State private var showingSafari = false
    @State private var safariURL: URL?
    #endif

    public var body: some View {
        Group {
            if let item {
                readerContent(for: item)
            } else {
                ContentUnavailableView("Select an article to read", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Reader content

    @ViewBuilder
    private func readerContent(for item: FeedItem) -> some View {
        let hasContent = item.contentHTML != nil || item.summaryHTML != nil

        Group {
            if hasContent {
                WebViewWrapper(
                    html: ArticlePageBuilder.buildPage(for: item, preferences: prefs),
                    baseURL: item.link,
                    appearanceOverride: prefs.appearanceOverride,
                    onExternalLink: { url in handleExternalLink(url) }
                )
            } else {
                noContentFallback(for: item)
            }
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { readerToolbar(for: item) }
        #if os(iOS)
        .sheet(isPresented: $showingSafari) {
            if let url = safariURL {
                SafariView(url: url)
            }
        }
        #endif
        // A new Task is started whenever item.id changes — marks the new item
        // as read and emits itemDisplayed. The previous task is cancelled automatically.
        .task(id: item.id) { await onItemAppeared(item) }
    }

    // MARK: - No-content fallback

    @ViewBuilder
    private func noContentFallback(for item: FeedItem) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "No Content Available",
                systemImage: "doc.text.slash",
                description: Text("This feed provides article summaries only. Open in your browser to read the full text.")
            )
            if let url = item.link {
                Button("Open in Browser") {
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func readerToolbar(for item: FeedItem) -> some ToolbarContent {
        // Open in browser
        if let url = item.link {
            ToolbarItem(placement: trailingPlacement) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                #if os(macOS)
                .keyboardShortcut("o", modifiers: [])
                #endif
            }
        }

        // Share
        if let url = item.link {
            ToolbarItem(placement: trailingPlacement) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }

        // Star / Unstar
        ToolbarItem(placement: trailingPlacement) {
            Button { toggleStar(for: item) } label: {
                Label(
                    item.isStarred ? "Unstar" : "Star",
                    systemImage: item.isStarred ? "star.fill" : "star"
                )
            }
            .tint(item.isStarred ? Color.yellow : nil)
            #if os(macOS)
            .keyboardShortcut("f", modifiers: [])
            #endif
        }

        // Save for offline / Remove save
        ToolbarItem(placement: trailingPlacement) {
            Button { toggleSave(for: item) } label: {
                Label(
                    item.savedOfflineState == .saved ? "Remove Save" : "Save for Offline",
                    systemImage: item.savedOfflineState == .saved ? "bookmark.fill" : "bookmark"
                )
            }
            .tint(item.savedOfflineState == .saved ? Color.blue : nil)
            #if os(macOS)
            .keyboardShortcut("s", modifiers: [])
            #endif
        }

        // Mark as unread — macOS only (u key)
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button { markUnread(item) } label: {
                Label("Mark as Unread", systemImage: "envelope.badge")
            }
            .keyboardShortcut("u", modifiers: [])
        }
        #endif
    }

    /// Toolbar placement varies: trailing nav bar on iOS, automatic (toolbar strip) on Mac.
    private var trailingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .navigationBarTrailing
        #else
        .automatic
        #endif
    }

    // MARK: - Item lifecycle

    private func onItemAppeared(_ item: FeedItem) async {
        // Only emit itemMarkedRead if the item was actually unread when opened.
        if !item.isRead {
            item.isRead = true
            try? modelContext.save()
            await EventBus.shared.emit(.itemMarkedRead(itemId: item.id))
        }
        await EventBus.shared.emit(.itemDisplayed(itemId: item.id))
    }

    // MARK: - Actions

    private func toggleStar(for item: FeedItem) {
        item.isStarred.toggle()
        try? modelContext.save()
        let id = item.id
        let starred = item.isStarred
        Task {
            if starred {
                await EventBus.shared.emit(.itemStarred(itemId: id))
            } else {
                await EventBus.shared.emit(.itemUnstarred(itemId: id))
            }
        }
    }

    private func toggleSave(for item: FeedItem) {
        // Phase 4: toggling save sets the state enum and emits the event.
        // Actual HTML + image download pipeline is Phase 6 (OfflineAsset).
        let id = item.id
        if item.savedOfflineState == .saved {
            item.savedOfflineState = .notSaved
            try? modelContext.save()
            Task { await EventBus.shared.emit(.itemOfflineSaveRemoved(itemId: id)) }
        } else {
            item.savedOfflineState = .saved
            try? modelContext.save()
            Task { await EventBus.shared.emit(.itemSavedOffline(itemId: id)) }
        }
    }

    private func markUnread(_ item: FeedItem) {
        item.isRead = false
        try? modelContext.save()
        let id = item.id
        Task { await EventBus.shared.emit(.itemMarkedUnread(itemId: id)) }
    }

    private func handleExternalLink(_ url: URL) {
        switch prefs.externalLinkBehavior {
        case .systemBrowser:
            openURL(url)
        case .inAppBrowser:
            #if os(iOS)
            // SFSafariViewController is iOS-only. macOS falls back to system browser.
            safariURL = url
            showingSafari = true
            #else
            openURL(url)
            #endif
        @unknown default:
            openURL(url)
        }
    }
}

// MARK: - SFSafariViewController wrapper (iOS only)

#if os(iOS)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif

// MARK: - Previews

#Preview("Article with content") {
    let item = FeedItem(
        feedId: UUID(),
        stableId: "preview-1",
        title: "The Future of Swift Concurrency",
        link: URL(string: "https://example.com/swift-concurrency")
    )
    item.contentHTML = """
    <h1>The Future of Swift Concurrency</h1>
    <p>Swift's concurrency model is evolving rapidly. With actors, async/await,
    and structured concurrency, developers now have powerful tools for writing
    safe concurrent code.</p>
    <h2>What's New</h2>
    <p>In this article, we explore the latest improvements and what they mean
    for your apps.</p>
    <pre><code>actor BankAccount {
      private var balance: Double
      func deposit(_ amount: Double) { balance += amount }
    }</code></pre>
    <blockquote><p>Concurrency is hard. Swift makes it less hard.</p></blockquote>
    """
    return NavigationStack {
        ArticleReaderView(item: item)
    }
    .modelContainer(for: [FeedItem.self, UserReadingPreferences.self], inMemory: true)
}

#Preview("No selection") {
    ArticleReaderView(item: nil)
}

#Preview("No content available") {
    let item = FeedItem(
        feedId: UUID(),
        stableId: "preview-empty",
        title: "Summary Only Article",
        link: URL(string: "https://example.com/article")
    )
    return NavigationStack {
        ArticleReaderView(item: item)
    }
    .modelContainer(for: [FeedItem.self, UserReadingPreferences.self], inMemory: true)
}
