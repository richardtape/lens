// ReaderStubView.swift — Article reader placeholder; replaced by WKWebView reader in Phase 4.
//
// On macOS this occupies the NavigationSplitView detail column.
// On iOS it's pushed onto the NavigationStack when a row is tapped.
import SwiftUI
import LensCore

struct ReaderStubView: View {
    /// Nil when nothing is selected (macOS detail column idle state).
    let item: FeedItem?

    var body: some View {
        if let item {
            VStack(spacing: 16) {
                Text(item.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("Full reader arrives in Phase 4")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView(
                "Select an article to read",
                systemImage: "doc.text"
            )
        }
    }
}

#Preview("Item selected") {
    let item = FeedItem(
        feedId: UUID(),
        stableId: "preview",
        title: "The Future of Swift Concurrency",
        link: URL(string: "https://example.com")
    )
    ReaderStubView(item: item)
}

#Preview("No selection") {
    ReaderStubView(item: nil)
}
