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
    public var movies: [MediaItem]
    public var series: [SeriesGroup]

    /// Category name → items, per kind. Order is by size, biggest first, so the
    /// categories a person actually uses float to the top on their own.
    public var channelCategories: [(name: String, items: [MediaItem])]
    public var movieCategories: [(name: String, items: [MediaItem])]
    public var seriesCategories: [(name: String, items: [SeriesGroup])]

    /// Built here, on whatever background actor loaded the library, so the
    /// search field never pays for normalisation while someone is typing.
    public let searchIndex: SearchIndex

    public static let empty = Library(items: [])

    public init(items: [MediaItem]) {
        self.items = items

        let channels = items.filter { $0.kind == .liveTV }
        self.channels = channels.sorted { lhs, rhs in
            switch (lhs.channelNumber, rhs.channelNumber) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }

        self.movies = items.filter { $0.kind == .movie }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        self.series = Library.groupSeries(items.filter { $0.kind == .series })

        self.searchIndex = SearchIndex(items: items)
        self.channelCategories = Library.bucket(self.channels, key: \.category)
        self.movieCategories = Library.bucket(self.movies, key: \.category)
        self.seriesCategories = Library.bucket(self.series, key: \.category)
    }

    public var isEmpty: Bool { items.isEmpty }

    public func item(id: String) -> MediaItem? {
        items.first { $0.id == id }
    }

    /// Best matches for a query, already ranked.
    public func search(_ query: String, limit: Int = 200) -> [MediaItem] {
        searchIndex.search(query, limit: limit).map { items[$0] }
    }

    // MARK: - Building

    static func groupSeries(_ episodes: [MediaItem]) -> [SeriesGroup] {
        var groups: [String: SeriesGroup] = [:]
        for episode in episodes {
            let name = episode.seriesName ?? episode.title
            let key = name.lowercased()
            if var existing = groups[key] {
                existing.episodes.append(episode)
                existing.artworkURL = existing.artworkURL ?? episode.logoURL
                existing.category = existing.category ?? episode.category
                existing.year = existing.year ?? episode.year
                groups[key] = existing
            } else {
                groups[key] = SeriesGroup(
                    id: key,
                    name: name,
                    artworkURL: episode.logoURL,
                    category: episode.category,
                    year: episode.year,
                    episodes: [episode]
                )
            }
        }
        return groups.values
            .map { group in
                var group = group
                group.episodes.sort { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
                return group
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
