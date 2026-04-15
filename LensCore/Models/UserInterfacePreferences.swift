// UserInterfacePreferences.swift — singleton SwiftData record for UI/behaviour settings.
import SwiftData
import Foundation

/// Controls the sort order of feeds in the sidebar.
public enum FeedSortOrder: String, Codable, Sendable, CaseIterable {
    case alphabetical
    case unreadCount
    case lastUpdated
    case byCategory

    /// Human-readable label used in sort pickers and the macOS Sort Feeds menu.
    public var localizedName: String {
        switch self {
        case .alphabetical:  return "Alphabetical"
        case .unreadCount:   return "Unread Count"
        case .lastUpdated:   return "Last Updated"
        case .byCategory:    return "By Category"
        }
    }
}

/// How long feed items are kept before background eviction.
/// Items that are starred, saved offline, or unread are never evicted.
public enum RetentionPolicy: Codable, Sendable {
    case days(Int)
    case keepAll

    // Manual Codable implementation required for enum with associated value.
    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "days":
            self = .days(try c.decode(Int.self, forKey: .value))
        case "keepAll":
            self = .keepAll
        default:
            self = .days(90) // safe fallback; unknown types treated as default
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .days(let n):
            try c.encode("days", forKey: .type)
            try c.encode(n, forKey: .value)
        case .keepAll:
            try c.encode("keepAll", forKey: .type)
        }
    }
}

@Model
public final class UserInterfacePreferences {
    public var feedSortOrder: FeedSortOrder
    // SwiftData cannot reliably store a Codable enum with an associated value as a
    // @Model property — mutations to sibling properties corrupt the serialised blob.
    // Store as a plain Int? instead: nil means .keepAll, any Int means .days(n).
    var _retentionPolicyDays: Int?
    /// When false, background refresh and badge updates are both disabled.
    public var backgroundRefreshEnabled: Bool

    /// The retention policy derived from the underlying primitive storage.
    public var retentionPolicy: RetentionPolicy {
        get { _retentionPolicyDays.map { .days($0) } ?? .keepAll }
        set {
            switch newValue {
            case .days(let n): _retentionPolicyDays = n
            case .keepAll:     _retentionPolicyDays = nil
            }
        }
    }

    public init() {
        feedSortOrder = .alphabetical
        _retentionPolicyDays = 90  // default: .days(90)
        backgroundRefreshEnabled = true
    }
}
