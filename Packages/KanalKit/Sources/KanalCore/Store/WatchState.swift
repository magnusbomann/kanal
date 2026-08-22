import Foundation

/// How far into something the viewer got.
public struct WatchProgress: Codable, Sendable, Hashable, Identifiable {
    public var id: String { itemID }
    public let itemID: String
    public var position: TimeInterval
    public var duration: TimeInterval
    public var updatedAt: Date

    public init(itemID: String, position: TimeInterval, duration: TimeInterval, updatedAt: Date = .now) {
        self.itemID = itemID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Past this point we treat it as watched and stop offering to resume.
    public var isFinished: Bool { fraction >= 0.92 }
    /// Below this it isn't worth a "Continue watching" row.
    public var isWorthResuming: Bool { position > 60 && !isFinished }

    public var remaining: TimeInterval { max(duration - position, 0) }
}

/// Favourites and watch history, persisted together.
public struct WatchState: Codable, Sendable {
    public var favoriteIDs: Set<String> = []
    public var hiddenCategoryNames: Set<String> = []
    public var progress: [String: WatchProgress] = [:]
    /// Most recent first.
    public var recentIDs: [String] = []

    public init() {}

    public static let fileName = "watch-state.json"

    public mutating func record(_ update: WatchProgress) {
        progress[update.itemID] = update
        recentIDs.removeAll { $0 == update.itemID }
        recentIDs.insert(update.itemID, at: 0)
        if recentIDs.count > 200 { recentIDs.removeLast(recentIDs.count - 200) }
    }

    public mutating func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) { favoriteIDs.remove(id) } else { favoriteIDs.insert(id) }
    }

    public func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }
}
