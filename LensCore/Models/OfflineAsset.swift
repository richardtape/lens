// OfflineAsset.swift — tracks a single file saved for offline reading.
//
// One FeedItem may have many OfflineAssets (its HTML body plus embedded images).
// itemId is a plain UUID foreign key to FeedItem — not a SwiftData relationship.
import SwiftData
import Foundation

@Model
public final class OfflineAsset {
    public var id: UUID
    /// UUID of the parent FeedItem.
    public var itemId: UUID
    /// Path in the app sandbox where the file is stored.
    public var localFileURL: URL
    /// Original remote URL (for cache validation / re-download).
    public var remoteURL: URL
    public var mimeType: String

    public init(
        id: UUID = UUID(),
        itemId: UUID,
        localFileURL: URL,
        remoteURL: URL,
        mimeType: String
    ) {
        self.id = id
        self.itemId = itemId
        self.localFileURL = localFileURL
        self.remoteURL = remoteURL
        self.mimeType = mimeType
    }
}
