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
public struct WatchState: Codable, Sendable, Equatable {
    public var favoriteIDs: Set<String> = []
    public var hiddenCategoryNames: Set<String> = []
    public var progress: [String: WatchProgress] = [:]
    /// Most recent first.
    public var recentIDs: [String] = []
    /// Small snapshots for on-demand episodes that are not part of the initial
    /// catalogue, keyed by source + item. Without these, an episode disappears
    /// from Continue watching after relaunch even though its progress survived.
    public var recentItems: [String: MediaItem] = [:]
    /// Source-scoped channel group ids, most recent first. Kept separate from
    /// video progress: a live channel has no finite duration to record.
    public var recentChannelGroupIDs: [String] = []
    /// Channel group id → the variant that last played successfully.
    ///
    /// A provider carries the same channel on several streams and some of them
    /// are dead. Remembering which one worked means the second viewing does
    /// not repeat yesterday's failures.
    public var workingVariants: [String: String] = [:]

    /// Explicit user choice; independent of the last successful stream.
    public var lockedVariants: [String: String] = [:]

    public init() {}

    /// Decoded field by field so that adding one cannot make an existing
    /// file unreadable — losing someone's favourites to a new feature would
    /// be an unforced error.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteIDs = try container.decodeIfPresent(Set<String>.self, forKey: .favoriteIDs) ?? []
        hiddenCategoryNames = try container.decodeIfPresent(
            Set<String>.self, forKey: .hiddenCategoryNames
        ) ?? []
        // Entry by entry. A merge between devices can leave one entry
        // half-written, and one unreadable entry used to make the whole state
        // undecodable — which emptied that profile's favourites and history.
        progress = Self.decodeEntries(WatchProgress.self, in: container, forKey: .progress)
        recentIDs = try container.decodeIfPresent([String].self, forKey: .recentIDs) ?? []
        recentItems = Self.decodeEntries(MediaItem.self, in: container, forKey: .recentItems)
        recentChannelGroupIDs = try container.decodeIfPresent(
            [String].self, forKey: .recentChannelGroupIDs
        ) ?? []
        lockedVariants = try container.decodeIfPresent(
            [String: String].self, forKey: .lockedVariants
        ) ?? [:]
        workingVariants = try container.decodeIfPresent(
            [String: String].self, forKey: .workingVariants
        ) ?? [:]
        scrubAddresses()
    }

    /// Rewrites ids from builds that put the stream address in them.
    ///
    /// Done on reading, so a file on disk and a snapshot from another device
    /// are both brought to today's ids, and the address — often the login —
    /// stops being written anywhere by the next save.
    private mutating func scrubAddresses() {
        func hasAddress(_ id: String) -> Bool { id.contains("://") }
        let scrub = MediaItem.scrubbedID
        if favoriteIDs.contains(where: hasAddress) { favoriteIDs = Set(favoriteIDs.map(scrub)) }
        if recentIDs.contains(where: hasAddress) { recentIDs = recentIDs.map(scrub) }
        if progress.keys.contains(where: hasAddress) {
            progress = Dictionary(progress.map { key, value in
                (scrub(key), WatchProgress(
                    itemID: scrub(value.itemID), position: value.position,
                    duration: value.duration, updatedAt: value.updatedAt
                ))
            }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        }
        if recentItems.keys.contains(where: hasAddress) {
            recentItems = Dictionary(
                recentItems.map { (scrub($0.key), $0.value) }, uniquingKeysWith: { first, _ in first }
            )
        }
        for (group, variant) in workingVariants where hasAddress(variant) {
            workingVariants[group] = scrub(variant)
        }
        for (group, variant) in lockedVariants where hasAddress(variant) {
            lockedVariants[group] = scrub(variant)
        }
    }

    /// A dictionary whose unreadable entries are dropped rather than fatal.
    private static func decodeEntries<Value: Decodable, Key: CodingKey>(
        _ type: Value.Type,
        in container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> [String: Value] {
        guard let entries = try? container.decodeIfPresent([String: Tolerant<Value>].self, forKey: key) else {
            return [:]
        }
        return entries.compactMapValues(\.value)
    }

    private struct Tolerant<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    public static let fileName = "watch-state.json"

    public mutating func record(_ update: WatchProgress, item: MediaItem? = nil) {
        progress[update.itemID] = update
        if let item { recentItems[update.itemID] = item }
        recentIDs.removeAll { $0 == update.itemID }
        recentIDs.insert(update.itemID, at: 0)
        if recentIDs.count > 200 {
            let removed = Array(recentIDs.suffix(from: 200))
            recentIDs.removeLast(recentIDs.count - 200)
            for id in removed {
                recentItems[id] = nil
                // Positions go with the history they belong to. Kept forever,
                // they grew without limit and were carried to every device.
                progress[id] = nil
            }
        }
    }

    public mutating func recordChannel(groupID: String) {
        recentChannelGroupIDs.removeAll { $0 == groupID }
        recentChannelGroupIDs.insert(groupID, at: 0)
        if recentChannelGroupIDs.count > 50 {
            recentChannelGroupIDs.removeLast(recentChannelGroupIDs.count - 50)
        }
    }

    /// Forgets one thing entirely: its position, its snapshot and its place in
    /// the history.
    ///
    /// Deliberately not "mark as finished". Someone removing a title from
    /// Continue watching is saying they are done with it, and a finished
    /// position would quietly bring the next episode forward instead.
    public mutating func forget(_ itemID: String) {
        progress[itemID] = nil
        recentItems[itemID] = nil
        recentIDs.removeAll { $0 == itemID }
    }

    public mutating func forgetChannel(_ groupID: String) {
        recentChannelGroupIDs.removeAll { $0 == groupID }
    }

    /// Clears watch history. Favourites are untouched: they are a list someone
    /// built on purpose, and history is a list the app built for them.
    public mutating func clearHistory() {
        progress = [:]
        recentIDs = []
        recentItems = [:]
        recentChannelGroupIDs = []
    }

    public mutating func clearFavorites() {
        favoriteIDs = []
    }

    public mutating func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) { favoriteIDs.remove(id) } else { favoriteIDs.insert(id) }
    }

    public func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    public mutating func rememberWorkingVariant(_ variantID: String, forGroup groupID: String) {
        workingVariants[groupID] = variantID
    }
}
