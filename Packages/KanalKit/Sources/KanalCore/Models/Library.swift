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

/// Search results expressed the way people browse them, rather than the flat
/// rows a provider sent us.
///
/// A channel can be listed in several folders and a show can contribute
/// hundreds of episode rows. Neither should turn into hundreds of search
/// results. Keeping the grouped types here also makes it impossible for the UI
/// to accidentally throw away a channel's fallback streams or a show's other
/// episodes.
public struct LibrarySearchResults: Sendable {
    public var channels: [ChannelGroup]
    public var movies: [MediaItem]
    public var series: [SeriesGroup]

    public init(
        channels: [ChannelGroup] = [],
        movies: [MediaItem] = [],
        series: [SeriesGroup] = []
    ) {
        self.channels = channels
        self.movies = movies
        self.series = series
    }

    public var isEmpty: Bool {
        channels.isEmpty && movies.isEmpty && series.isEmpty
    }

    public var count: Int {
        channels.count + movies.count + series.count
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
    /// One entry per film, duplicates folded away. What every screen shows.
    public var movies: [MediaItem]
    /// Those same films with every listing kept behind them, for playback.
    public var movieGroups: [MovieGroup]
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

    /// One representative per thing someone can open from search.
    ///
    /// These are all real library entries (never synthetic ids), so an item
    /// can still be handed to details or playback. The title and aliases of
    /// the representatives are widened to cover the group they stand for.
    private let searchableItems: [MediaItem]

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
        let movieGroups = Library.makeMovieGroups(movies)
        self.movieGroups = movieGroups
        self.movies = Library.sortedByTitle(movieGroups.map(\.representative))
        self.series = Library.groupSeries(episodes)

        self.searchableItems = Library.makeSearchableItems(
            channels: self.channelGroups,
            movies: movieGroups,
            series: self.series
        )
        self.indexBox = SearchIndexBox(items: self.searchableItems)
        self.channelCategories = Library.bucket(self.channels, key: \.category)
        self.movieCategories = Library.bucketMovies(movieGroups)
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

    /// The group a film belongs to, for reaching its other listings.
    public func movieGroup(containing item: MediaItem) -> MovieGroup? {
        let key = TitleKey.groupKey(for: item)
        if let year = item.year, let dated = movieGroups.first(where: { $0.id == "\(key)|\(year)" }) {
            return dated
        }
        return movieGroups.first { $0.id == key }
    }

    /// Best matches for a query, already ranked.
    public func search(_ query: String, limit: Int = 200) -> [MediaItem] {
        searchIndex.search(query, limit: limit).map { searchableItems[$0] }
    }

    /// Best matches split into the three things the interface can open.
    ///
    /// `items` is accepted separately because translated search merges hits
    /// from more than one spelling before presenting them.
    public func groupedSearchResults(from items: [MediaItem]) -> LibrarySearchResults {
        let channelsByID = Dictionary(uniqueKeysWithValues: channelGroups.map { ($0.id, $0) })
        let seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })

        var channels: [ChannelGroup] = []
        var movies: [MediaItem] = []
        var shows: [SeriesGroup] = []
        var seenChannels = Set<String>()
        var seenMovies = Set<String>()
        var seenSeries = Set<String>()

        for item in items {
            switch item.kind {
            case .liveTV:
                let key = ChannelNaming.groupKey(for: item)
                guard seenChannels.insert(key).inserted,
                      let group = channelsByID[key]
                else { continue }
                channels.append(group)

            case .movie:
                let key = Library.movieSearchKey(item)
                guard seenMovies.insert(key).inserted else { continue }
                movies.append(item)

            case .series:
                let key = (item.seriesName ?? item.title).lowercased()
                guard seenSeries.insert(key).inserted,
                      let group = seriesByID[key]
                else { continue }
                shows.append(group)
            }
        }

        return LibrarySearchResults(channels: channels, movies: movies, series: shows)
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

    /// Builds the smaller, human-shaped catalogue search actually needs.
    ///
    /// Indexing the provider's flat rows made a query for a long-running show
    /// spend its first 200 hits on episodes of that one show. One
    /// representative per channel, film and show is both faster and correct.
    private static func makeSearchableItems(
        channels: [ChannelGroup], movies: [MovieGroup], series: [SeriesGroup]
    ) -> [MediaItem] {
        var result: [MediaItem] = []
        result.reserveCapacity(channels.count + movies.count + series.count)

        for group in channels {
            var representative = group.primary
            representative.title = group.name
            representative.alternateTitles = uniqueSearchTerms(
                representative.alternateTitles
                    + group.variants.flatMap { [$0.title, $0.rawTitle] }
                    + group.categories
            )
            result.append(representative)
        }

        for group in movies {
            var representative = group.representative
            // Every name and folder any listing of this film used, so a search
            // for the provider's spelling still reaches the folded card.
            representative.alternateTitles = uniqueSearchTerms(
                representative.alternateTitles
                    + group.variants.flatMap { $0.alternateTitles + [$0.title, $0.rawTitle] }
                    + group.categories
            )
            result.append(representative)
        }

        for group in series {
            guard var representative = group.episodes.first else { continue }
            representative.title = group.name
            representative.seriesName = group.name
            representative.logoURL = group.artworkURL ?? representative.logoURL
            representative.category = group.category ?? representative.category
            result.append(representative)
        }

        return result
    }

    private static func movieSearchKey(_ item: MediaItem) -> String {
        let title = SearchNormalizer.normalize(item.title)
        // A year is the evidence that two same-named listings are the same
        // film. Without it, collapsing them can silently hide a different
        // film — or the only stream that works.
        guard let year = item.year else { return "\(title)|unknown|\(item.id)" }
        return "\(title)|\(year)"
    }

    private static func uniqueSearchTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.filter { term in
            let normalized = SearchNormalizer.normalize(term)
            return !normalized.isEmpty && seen.insert(normalized).inserted
        }
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

    /// Films bucketed by folder, appearing under every folder they were filed
    /// in — the same way a channel listed in four places shows up in all four.
    static func bucketMovies(_ groups: [MovieGroup]) -> [(name: String, items: [MediaItem])] {
        var buckets: [String: [MediaItem]] = [:]
        for group in groups {
            let representative = group.representative
            let names = group.categories.isEmpty
                ? [String(localized: CoreStrings.otherCategory)]
                : group.categories
            for name in names { buckets[name, default: []].append(representative) }
        }
        return buckets
            .map { (name: $0.key, items: sortedByTitle($0.value)) }
            .sorted { lhs, rhs in
                if lhs.items.count != rhs.items.count { return lhs.items.count > rhs.items.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
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
