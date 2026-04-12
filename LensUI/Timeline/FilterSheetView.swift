// FilterSheetView.swift — Category + feed filter picker.
//
// Presented as a modal sheet on iOS and a popover on macOS (caller decides).
// Category and feed filters are mutually exclusive; selecting one clears the other.
// The unreadOnly toggle lives in the toolbar, not here.
import SwiftUI
import SwiftData
import LensCore

// Category conflicts with an ObjC runtime type when Foundation is in scope.
// fileprivate (not private) so @Query's generated storage can reference the type.
fileprivate typealias Category = LensCore.Category

struct FilterSheetView: View {
    @Binding var filterMode: TimelineFilter
    @Binding var unreadOnly: Bool

    @Query(sort: \Category.sortOrder) fileprivate var categories: [Category]
    @Query(sort: \Feed.displayName)   private var feeds: [Feed]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                categoriesSection
                feedsSection
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear All") {
                        filterMode = .all
                        unreadOnly = false
                        dismiss()
                    }
                    .disabled(filterMode == .all && !unreadOnly)
                }
            }
        }
    }

    // MARK: - Sections

    private var categoriesSection: some View {
        Section("Category") {
            // "All categories" clears any category filter
            Button {
                if case .category = filterMode { filterMode = .all }
            } label: {
                HStack {
                    Text("All Categories")
                    Spacer()
                    if case .all = filterMode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    if case .feed = filterMode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .foregroundStyle(.primary)

            ForEach(categories) { category in
                Button {
                    filterMode = .category(category.id)
                } label: {
                    HStack {
                        Text(category.name)
                        Spacer()
                        if case .category(let id) = filterMode, id == category.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var feedsSection: some View {
        Section("Feed") {
            Button {
                if case .feed = filterMode { filterMode = .all }
            } label: {
                HStack {
                    Text("All Feeds")
                    Spacer()
                    if case .all = filterMode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    if case .category = filterMode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .foregroundStyle(.primary)

            ForEach(feeds) { feed in
                Button {
                    filterMode = .feed(feed.id)
                } label: {
                    HStack {
                        Text(feed.displayName)
                        Spacer()
                        if case .feed(let id) = filterMode, id == feed.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

#Preview {
    @Previewable @State var filter: TimelineFilter = .all
    @Previewable @State var unreadOnly = false
    FilterSheetView(filterMode: $filter, unreadOnly: $unreadOnly)
        .modelContainer(for: [Category.self, Feed.self], inMemory: true)
}
