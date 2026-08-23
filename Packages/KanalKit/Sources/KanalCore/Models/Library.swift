import Foundation

/// A show, with its episodes folded together.
public struct SeriesGroup: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var artworkURL: URL?
    public var category: String?
    public var year: Int?
    public var episodes: [MediaItem]

    /// Set when the show came from a panel that lists episodes on request.
    public var providerSeriesID: Int? { episodes.first?.providerSeriesID }

    /// A panel listing gives us one placeholder entry per show, not real
    /// episodes. Those have to be fetched before the detail screen means
    /// anything.
    public var needsEpisodeLoad: Bool {
        providerSeriesID != nil && episodes.allSatisfy { $0.episode == nil }
    }

    public var seasonNumbers: [Int] {
        Array(Set(episodes.compactMap(\.season))).sorted()
    }

    public func episodes(inSeason season: Int) -> [MediaItem] {
        episodes.filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }
}

/// The organised view of everything a source returned.
///
/// Built once per refresh so the UI never sorts or filters a 50k-item array on
/// the main thread while scrolling.
public struct Library: Sendable {
    public var items: [MediaItem]
    public var channels: [MediaItem]
    /// Channels with duplicates folded together, alternatives kept.
    public var channelGroups: [ChannelGroup]
    public var movies: [MediaItem]
    public var series: [SeriesGroup]

    /// Category name → items, per kind. Order is by size, biggest first, so the
    /// categories a person actually uses float to the top on their own.
    public var channelCategories: [(name: String, items: [MediaItem])]
    public var movieCategories: [(name: String, items: [MediaItem])]
    public var seriesCategories: [(name: String, items: [SeriesGroup])]

    /// Built on first use rather than at load.
    ///
    /// Indexing a real catalogue takes seconds, and the first screen does not
    /// search — making launch wait for it is paying up front for something
    /// that may never be needed.
    private let indexBox: SearchIndexBox

    public var searchIndex: SearchIndex { indexBox.index }

    public static let empty = Library(items: [])

    public init(items: [MediaItem]) {
        self.items = items

        // One pass instead of three. A real catalogue is four hundred thousand
        // entries, and each `filter` is a full traversal and a fresh array.
        var channels: [MediaItem] = []
        var movies: [MediaItem] = []
        var episodes: [MediaItem] = []
        channels.reserveCapacity(items.count / 8)
        movies.reserveCapacity(items.count / 4)
        episodes.reserveCapacity(items.count / 2)
        for item in items {
            switch item.kind {
            case .liveTV: channels.append(item)
            case .movie: movies.append(item)
            case .series: episodes.append(item)
            }
        }

        self.channels = channels.sorted { lhs, rhs in
            switch (lhs.channelNumber, rhs.channelNumber) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }

        // Only two thousand channels even in a huge catalogue, so this is
        // cheap enough to do at load rather than defer.
        self.channelGroups = Library.makeChannelGroups(self.channels)
        self.movies = Library.sortedByTitle(movies)
        self.series = Library.groupSeries(episodes)

        self.indexBox = SearchIndexBox(items: items)
        self.channelCategories = Library.bucket(self.channels, key: \.category)
        self.movieCategories = Library.bucket(self.movies, key: \.category)
        self.seriesCategories = Library.bucket(self.series, key: \.category)
    }

    public var isEmpty: Bool { items.isEmpty }

    public func item(id: String) -> MediaItem? {
        items.first { $0.id == id }
    }

    /// The group a channel belongs to, for reaching its alternatives.
    public func channelGroup(containing item: MediaItem) -> ChannelGroup? {
        let key = ChannelNaming.groupKey(for: item)
        return channelGroups.first { $0.id == key }
    }

    /// Best matches for a query, already ranked.
    public func search(_ query: String, limit: Int = 200) -> [MediaItem] {
        searchIndex.search(query, limit: limit).map { items[$0] }
    }

    // MARK: - Building

    /// Sorts on precomputed keys rather than comparing locale-aware on every
    /// comparison, which is the expensive half of an ordinary sort.
    static func sortedByTitle(_ items: [MediaItem]) -> [MediaItem] {
        items
            .map { (key: $0.title.lowercased(), item: $0) }
            .sorted { $0.key < $1.key }
            .map(\.item)
    }

    static func groupSeries(_ episodes: [MediaItem]) -> [SeriesGroup] {
        // Episodes are accumulated into a dictionary of arrays first.
        //
        // Reading a whole `SeriesGroup` out, appending to its episode array and
        // writing it back copies that array every time — quadratic over a show
        // with hundreds of episodes, and this runs over hundreds of thousands
        // of them. Subscripting with a default appends in place instead.
        var buckets: [String: [MediaItem]] = [:]
        var names: [String: String] = [:]
        buckets.reserveCapacity(episodes.count / 16)

        for episode in episodes {
            let name = episode.seriesName ?? episode.title
            let key = name.lowercased()
            buckets[key, default: []].append(episode)
            if names[key] == nil { names[key] = name }
        }

        var groups: [SeriesGroup] = []
        groups.reserveCapacity(buckets.count)
        for (key, var found) in buckets {
            found.sort { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
            groups.append(
                SeriesGroup(
                    id: key,
                    name: names[key] ?? key,
                    artworkURL: found.first { $0.logoURL != nil }?.logoURL,
                    category: found.first { $0.category != nil }?.category,
                    year: found.first { $0.year != nil }?.year,
                    episodes: found
                )
            )
        }
        return groups
            .map { (key: $0.name.lowercased(), group: $0) }
            .sorted { $0.key < $1.key }
            .map(\.group)
    }

    static func bucket<Element>(
        _ elements: [Element],
        key: KeyPath<Element, String?>
    ) -> [(name: String, items: [Element])] {
        var buckets: [String: [Element]] = [:]
        for element in elements {
            // Category names themselves come from the provider and stay in
            // whatever language they were written in; only our fallback is ours
            // to translate.
            let name = element[keyPath: key] ?? String(localized: CoreStrings.otherCategory)
            buckets[name, default: []].append(element)
        }
        return buckets
            .map { (name: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                if lhs.items.count != rhs.items.count { return lhs.items.count > rhs.items.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}


/// Holds the search index so a `Library` value can build it lazily.
///
/// A struct cannot mutate itself on first access, and the index is expensive
/// enough that building it eagerly is what made launch slow.
final class SearchIndexBox: @unchecked Sendable {
    private let items: [MediaItem]
    private let lock = NSLock()
    private var built: SearchIndex?

    init(items: [MediaItem]) {
        self.items = items
    }

    var index: SearchIndex {
        lock.lock()
        defer { lock.unlock() }
        if let built { return built }
        let index = SearchIndex(items: items)
        built = index
        return index
    }
}
