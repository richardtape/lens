// ArticleRowView.swift — Single article row for the timeline list.
//
// Layout: a 3pt accent bar on the leading edge spans the full row height,
// followed by the row content (source, title, optional excerpt/timestamp).
// The bar is a plain Rectangle in an HStack — not a separator — so it
// tracks dynamic row height correctly.
//
// Density variants (from lensListDensity environment):
//   0.0–0.33  Title only   source + title
//   0.33–0.67 Compact      source + title + timestamp
//   0.67–1.0  Standard     full layout (default at 0.5)
import SwiftUI
import SwiftData
import LensCore

struct ArticleRowView: View {
    let item: FeedItem
    let feed: Feed?

    @Environment(\.lensAccentColor) private var accentColor
    @Environment(\.lensListDensity) private var listDensity
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    // Drives the system share sheet (iOS) / NSSharingServicePicker (macOS).
    @State private var showShareSheet = false

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar — full row height, transparent when read.
            Rectangle()
                .fill(item.isRead ? Color.clear : accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: densitySpacing) {
                // Source row: favicon/monogram + feed name
                HStack(spacing: 6) {
                    MonogramView(feed: feed, accentColor: accentColor)
                        .frame(width: 17, height: 17)
                        .opacity(item.isRead ? 0.3 : 1.0)

                    Text(feed?.displayName ?? "Unknown Feed")
                        .font(.caption)
                        .foregroundStyle(item.isRead ? .tertiary : .secondary)
                        .lineLimit(1)

                    Spacer()
                }

                // Title — bold + .headline unread; regular + .subheadline read
                Text(item.title)
                    .font(item.isRead ? .subheadline : .headline)
                    .foregroundStyle(item.isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(titleLineLimit)

                // Excerpt — standard density only
                if showsExcerpt, let raw = item.summaryHTML, !raw.isEmpty {
                    Text(raw.strippingHTML)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .opacity(item.isRead ? 0.45 : 1.0)
                        .lineLimit(2)
                }

                // Timestamp — compact + standard density
                if showsTimestamp {
                    Text(item.publishedAt.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, densityPadding)
        }
        // contentShape ensures the tap area covers the full row including the
        // accent bar, which would otherwise not be hit-testable.
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggleRead) {
                Label(
                    item.isRead ? "Mark Unread" : "Mark Read",
                    systemImage: item.isRead ? "circle" : "checkmark.circle.fill"
                )
            }
            .tint(item.isRead ? .orange : .green)
        }
        .swipeActions(edge: .trailing) {
            Button(action: toggleStar) {
                Label(
                    item.isStarred ? "Unstar" : "Star",
                    systemImage: item.isStarred ? "star.slash.fill" : "star.fill"
                )
            }
            .tint(.yellow)

            Button(action: saveOffline) {
                Label("Save", systemImage: "arrow.down.circle.fill")
            }
            .tint(.blue)

            Button { showShareSheet = true } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.indigo)
        }
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showShareSheet) {
            if let url = item.link {
                #if os(iOS)
                ShareActivityView(url: url)
                    .presentationDetents([.medium, .large])
                #else
                ShareLink(item: url)
                    .padding()
                    .presentationDetents([.medium])
                #endif
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(item.isRead ? "Mark Unread" : "Mark Read", action: toggleRead)
        Button(item.isStarred ? "Unstar" : "Star", action: toggleStar)
        Button(
            item.savedOfflineState == .saved ? "Remove Save" : "Save for Offline",
            action: saveOffline
        )
        Divider()
        if let url = item.link {
            ShareLink(item: url)
            Button("Open in Browser") { openURL(url) }
            Button("Copy Link") { copyLink(url) }
        }
    }

    // MARK: - Actions

    private func toggleRead() {
        item.isRead.toggle()
        let event: LensEvent = item.isRead
            ? .itemMarkedRead(itemId: item.id)
            : .itemMarkedUnread(itemId: item.id)
        Task { await EventBus.shared.emit(event) }
    }

    private func toggleStar() {
        item.isStarred.toggle()
        let event: LensEvent = item.isStarred
            ? .itemStarred(itemId: item.id)
            : .itemUnstarred(itemId: item.id)
        Task { await EventBus.shared.emit(event) }
    }

    private func saveOffline() {
        // Phase 6 wires the actual download pipeline. For now we toggle the
        // saved state optimistically and emit the event for future consumers.
        let wasAlreadySaved = item.savedOfflineState == .saved
        item.savedOfflineState = wasAlreadySaved ? .notSaved : .saving
        let event: LensEvent = wasAlreadySaved
            ? .itemOfflineSaveRemoved(itemId: item.id)
            : .itemSavedOffline(itemId: item.id)
        Task { await EventBus.shared.emit(event) }
    }

    private func copyLink(_ url: URL) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
        UIPasteboard.general.string = url.absoluteString
        #endif
    }

    // MARK: - Density helpers

    private var densityLevel: Int {
        switch listDensity {
        case ..<0.33: return 0  // Title only
        case ..<0.67: return 1  // Compact
        default:      return 2  // Standard
        }
    }

    private var showsExcerpt:   Bool    { densityLevel >= 2 }
    private var showsTimestamp: Bool    { densityLevel >= 1 }
    private var titleLineLimit: Int     { densityLevel == 0 ? 2 : 3 }
    private var densitySpacing: CGFloat { CGFloat(densityLevel == 0 ? 4 : 6) }
    private var densityPadding: CGFloat {
        switch densityLevel {
        case 0:  return 8
        case 1:  return 10
        default: return 12
        }
    }
}

// MARK: - String stripping helper

private extension String {
    /// Removes HTML tags to produce plain excerpt text.
    /// Not a full HTML parser — sufficient for short feed summary strings.
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Date formatting helper

private extension Optional where Wrapped == Date {
    /// Relative display under 6 days old; locale-formatted absolute date for older items.
    var relativeFormatted: String {
        guard let date = self else { return "Date unknown" }
        let sixDays: TimeInterval = 6 * 24 * 3600
        if abs(date.timeIntervalSinceNow) < sixDays {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .full
            return fmt.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - iOS share sheet bridge

#if os(iOS)
/// Wraps UIActivityViewController for the system share sheet on iOS.
private struct ShareActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Preview

#Preview {
    let feedId = UUID()
    let item = FeedItem(
        feedId: feedId,
        stableId: "preview-1",
        title: "Understanding Swift Actors: A Practical Guide",
        link: URL(string: "https://example.com/swift-actors"),
        publishedAt: Date().addingTimeInterval(-3600 * 2),
        summaryHTML: "<p>Swift actors are a new concurrency primitive introduced in Swift 5.5 to help you write safe concurrent code.</p>"
    )
    let feed = Feed(id: feedId, url: URL(string: "https://example.com/feed")!, displayName: "Swift Weekly")

    List {
        ArticleRowView(item: item, feed: feed)
        ArticleRowView(item: {
            let r = FeedItem(feedId: feedId, stableId: "preview-2", title: "Read article — no excerpt", publishedAt: Date().addingTimeInterval(-86400 * 3))
            r.isRead = true
            return r
        }(), feed: feed)
    }
    .listStyle(.plain)
    .environment(\.lensAccentColor, Color(hex: "#4A90D9"))
    .environment(\.lensListDensity, 0.5)
}
