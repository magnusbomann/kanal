import Foundation

/// A discovery row after its outside recommendations have been resolved to
/// titles the viewer's own TV service actually carries.
public struct MatchedDiscoveryShelf: Identifiable, Sendable, Hashable {
    public var shelf: DiscoveryShelf
    public var items: [MediaItem]

    public var id: String { shelf.id }

    public init(shelf: DiscoveryShelf, items: [MediaItem]) {
        self.shelf = shelf
        self.items = items
    }
}

/// A small, already-ranked preview of one film category.
public struct MovieCategoryPreview: Identifiable, Sendable, Hashable {
    public var name: String
    public var movies: [MediaItem]

    public var id: String { name }

    public init(name: String, movies: [MediaItem]) {
        self.name = name
        self.movies = movies
    }
}

/// A small, already-ranked preview of one series category.
public struct SeriesCategoryPreview: Identifiable, Sendable, Hashable {
    public var name: String
    public var series: [SeriesGroup]

    public var id: String { name }

    public init(name: String, series: [SeriesGroup]) {
        self.name = name
        self.series = series
    }
}

/// Films and shows carried locally that are associated with one recognisable
/// streaming service. The two kinds are deliberately mixed for a compact Home
/// row; their dedicated browse screens retain separate shelves.
public struct DiscoveryServiceSpotlight: Identifiable, Sendable, Hashable {
    public var serviceID: Int
    public var serviceName: String
    public var items: [MediaItem]

    public var id: Int { serviceID }

    public init(serviceID: Int, serviceName: String, items: [MediaItem]) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.items = items
    }
}

/// Everything a film or series landing screen needs, resolved once instead of
/// filtering and sorting a provider-sized catalogue during every SwiftUI pass.
public struct BrowsePresentation: Sendable, Hashable {
    public var topMovies: [MediaItem]
    public var topMoviesAreTrending: Bool
    public var newMovies: [MediaItem]
    public var newMoviesAreDiscoveryBased: Bool

    public var topSeries: [SeriesGroup]
    public var topSeriesAreTrending: Bool
    public var newSeries: [SeriesGroup]
    public var newSeriesAreDiscoveryBased: Bool

    public var movieServiceShelves: [MatchedDiscoveryShelf]
    public var seriesServiceShelves: [MatchedDiscoveryShelf]
    public var homeServiceSpotlights: [DiscoveryServiceSpotlight]

    public var movieCategories: [MovieCategoryPreview]
    public var seriesCategories: [SeriesCategoryPreview]

    public var movieFilterCategories: [String]
    public var movieFilterCountries: [String]
    public var movieFilterDecades: [Int]
    public var seriesFilterCategories: [String]
    public var seriesFilterCountries: [String]
    public var seriesFilterDecades: [Int]

    public init(
        topMovies: [MediaItem] = [],
        topMoviesAreTrending: Bool = false,
        newMovies: [MediaItem] = [],
        newMoviesAreDiscoveryBased: Bool = false,
        topSeries: [SeriesGroup] = [],
        topSeriesAreTrending: Bool = false,
        newSeries: [SeriesGroup] = [],
        newSeriesAreDiscoveryBased: Bool = false,
        movieServiceShelves: [MatchedDiscoveryShelf] = [],
        seriesServiceShelves: [MatchedDiscoveryShelf] = [],
        homeServiceSpotlights: [DiscoveryServiceSpotlight] = [],
        movieCategories: [MovieCategoryPreview] = [],
        seriesCategories: [SeriesCategoryPreview] = [],
        movieFilterCategories: [String] = [],
        movieFilterCountries: [String] = [],
        movieFilterDecades: [Int] = [],
        seriesFilterCategories: [String] = [],
        seriesFilterCountries: [String] = [],
        seriesFilterDecades: [Int] = []
    ) {
        self.topMovies = topMovies
        self.topMoviesAreTrending = topMoviesAreTrending
        self.newMovies = newMovies
        self.newMoviesAreDiscoveryBased = newMoviesAreDiscoveryBased
        self.topSeries = topSeries
        self.topSeriesAreTrending = topSeriesAreTrending
        self.newSeries = newSeries
        self.newSeriesAreDiscoveryBased = newSeriesAreDiscoveryBased
        self.movieServiceShelves = movieServiceShelves
        self.seriesServiceShelves = seriesServiceShelves
        self.homeServiceSpotlights = homeServiceSpotlights
        self.movieCategories = movieCategories
        self.seriesCategories = seriesCategories
        self.movieFilterCategories = movieFilterCategories
        self.movieFilterCountries = movieFilterCountries
        self.movieFilterDecades = movieFilterDecades
        self.seriesFilterCategories = seriesFilterCategories
        self.seriesFilterCountries = seriesFilterCountries
        self.seriesFilterDecades = seriesFilterDecades
    }
}

/// The pure presentation snapshot shared by Home and both on-demand browse
/// screens. Building it has no side effects and is safe to run away from the
/// main actor.
public struct DiscoveryPresentation: Sendable, Hashable {
    public var matchedShelves: [MatchedDiscoveryShelf]
    /// Concrete movie/episode id to its first position in the canonical
    /// discovery order.
    public var itemRanking: [String: Int]
    /// SeriesGroup.id to its first position. Provider series ids are used while
    /// resolving the recommendation, never exposed as the UI's identity.
    public var seriesRanking: [String: Int]
    public var browse: BrowsePresentation

    public init(
        matchedShelves: [MatchedDiscoveryShelf] = [],
        itemRanking: [String: Int] = [:],
        seriesRanking: [String: Int] = [:],
        browse: BrowsePresentation = BrowsePresentation()
    ) {
        self.matchedShelves = matchedShelves
        self.itemRanking = itemRanking
        self.seriesRanking = seriesRanking
        self.browse = browse
    }

    /// Resolves and ranks all discovery and browse rows in one pass-oriented
    /// snapshot. Every outward-facing row is capped; filter values intentionally
    /// remain complete so "See all" never loses a valid category.
    /// - Parameter audience: only decides which services lead. The rows
    ///   themselves were already fetched for this audience; ordering them by
    ///   the grown-up list here would put Netflix above Disney on a child's
    ///   Home no matter what the request asked for.
    public static func build(
        library: Library,
        shelves: [DiscoveryShelf],
        audience: DiscoveryAudience = .everyone,
        minimumShelfSize: Int = 4,
        limit: Int = 24,
        categoryLimit: Int = 4,
        serviceLimit: Int = 3
    ) -> DiscoveryPresentation {
        guard !Task.isCancelled else { return DiscoveryPresentation() }
        let itemLimit = max(limit, 0)
        let previewLimit = max(categoryLimit, 0)
        let serviceCountLimit = max(serviceLimit, 0)
        let requiredMatches = max(minimumShelfSize, 1)

        // The same TMDB title commonly appears in trending, new and one or more
        // service rows. Resolve it once, while keeping the overlap between rows
        // because that membership is meaningful to the presentation.
        var matchedTitleCache: [DiscoveryTitleIdentity: MediaItem] = [:]
        var unmatchedTitles = Set<DiscoveryTitleIdentity>()
        var rawShelves: [RawMatchedShelf] = []
        if itemLimit > 0 {
            rawShelves.reserveCapacity(shelves.count)
            for (order, shelf) in shelves.enumerated() {
                guard !Task.isCancelled else { return DiscoveryPresentation() }
                guard shelf.kind == .movie || shelf.kind == .series else { continue }
                var items: [MediaItem] = []
                var seen = Set<String>()
                for (titleIndex, title) in shelf.titles.enumerated() {
                    if titleIndex.isMultiple(of: 16), Task.isCancelled {
                        return DiscoveryPresentation()
                    }
                    let identity = DiscoveryTitleIdentity(title)
                    let item: MediaItem?
                    if let cached = matchedTitleCache[identity] {
                        item = cached
                    } else if unmatchedTitles.contains(identity) {
                        item = nil
                    } else if let matched = library.item(matching: title) {
                        matchedTitleCache[identity] = matched
                        item = matched
                    } else {
                        unmatchedTitles.insert(identity)
                        item = nil
                    }
                    guard let item, item.kind == shelf.kind,
                          seen.insert(item.id).inserted
                    else { continue }
                    items.append(item)
                }
                rawShelves.append(RawMatchedShelf(shelf: shelf, items: items, order: order))
            }
        }

        let matchedShelves = rawShelves.compactMap {
            $0.presentation(minimum: requiredMatches, limit: itemLimit)
        }

        let resolver = SeriesResolver(library.series)
        let serviceBundles = ServiceBundle.make(from: rawShelves)
        let leadingServices = audience.preferredServices
        let orderedServices = serviceBundles.sorted {
            ServiceBundle.precedes($0, $1, leadingWith: leadingServices)
        }

        let trendingMoviesShelf = bestShelf(
            in: matchedShelves, kind: .movie, source: .trending
        )
        let newMoviesShelf = bestShelf(
            in: matchedShelves, kind: .movie, source: .newReleases
        )
        let trendingSeriesShelf = bestShelf(
            in: matchedShelves, kind: .series, source: .trending
        )
        let newSeriesShelf = bestShelf(
            in: matchedShelves, kind: .series, source: .newReleases
        )

        let movieServiceShelves = Array(orderedServices.lazy.compactMap {
            $0.movieShelf?.presentation(minimum: requiredMatches, limit: itemLimit)
        }.prefix(serviceCountLimit))
        let seriesServiceShelves = Array(orderedServices.lazy.compactMap {
            $0.seriesShelf?.presentation(minimum: requiredMatches, limit: itemLimit)
        }.prefix(serviceCountLimit))

        // A deterministic order makes recommendations stable even if network
        // completion changes the incoming shelf order.
        let canonicalMovieShelves = [trendingMoviesShelf, newMoviesShelf].compactMap { $0 }
            + movieServiceShelves
        let canonicalSeriesShelves = [trendingSeriesShelf, newSeriesShelf].compactMap { $0 }
            + seriesServiceShelves

        var itemRanking: [String: Int] = [:]
        var itemPosition = 0
        for matched in canonicalMovieShelves {
            for item in matched.items where itemRanking[item.id] == nil {
                itemRanking[item.id] = itemPosition
                itemPosition += 1
            }
        }

        var seriesRanking: [String: Int] = [:]
        var seriesPosition = 0
        for matched in canonicalSeriesShelves {
            for item in matched.items {
                guard let group = resolver.group(for: item),
                      seriesRanking[group.id] == nil
                else { continue }
                seriesRanking[group.id] = seriesPosition
                seriesPosition += 1
            }
        }

        // Landing pages need at most `itemLimit` entries. Selecting that small
        // top set avoids four complete O(n log n) sorts of a provider catalogue
        // that can contain hundreds of thousands of rows.
        let newestMovies = limited(
            library.movies, ranking: [:], limit: itemLimit,
            key: \MediaItem.id, year: \MediaItem.year, name: \MediaItem.title
        )
        let newestSeries = limited(
            library.series, ranking: [:], limit: itemLimit,
            key: \SeriesGroup.id, year: \SeriesGroup.year, name: \SeriesGroup.name
        )

        let matchedTopSeries = trendingSeriesShelf.map {
            resolver.groups(for: $0.items, limit: itemLimit)
        } ?? []
        let matchedNewSeries = newSeriesShelf.map {
            resolver.groups(for: $0.items, limit: itemLimit)
        } ?? []

        let hasTrendingSeries = trendingSeriesShelf != nil && !matchedTopSeries.isEmpty
        let hasDiscoveryNewSeries = newSeriesShelf != nil && !matchedNewSeries.isEmpty

        let orderedMovieBuckets = movieBucketsWithOtherLast(library.movieCategories)
        let orderedSeriesBuckets = seriesBucketsWithOtherLast(library.seriesCategories)

        let movieCategories = movieCategoryPreviews(
            buckets: Array(orderedMovieBuckets.prefix(previewLimit)),
            ranking: itemRanking,
            itemLimit: itemLimit
        )
        let seriesCategories = seriesCategoryPreviews(
            buckets: Array(orderedSeriesBuckets.prefix(previewLimit)),
            ranking: seriesRanking,
            itemLimit: itemLimit
        )

        let homeServiceSpotlights: [DiscoveryServiceSpotlight] = orderedServices.lazy.filter {
            $0.matchCount >= requiredMatches
        }.prefix(serviceCountLimit).compactMap { bundle -> DiscoveryServiceSpotlight? in
            let items = interleave(
                bundle.movieShelf?.items ?? [],
                bundle.seriesShelf?.items ?? [],
                limit: itemLimit
            )
            guard !items.isEmpty else { return nil }
            return DiscoveryServiceSpotlight(
                serviceID: bundle.id,
                serviceName: bundle.name,
                items: items
            )
        }

        let browse = BrowsePresentation(
            topMovies: trendingMoviesShelf?.items ?? Array(newestMovies.prefix(itemLimit)),
            topMoviesAreTrending: trendingMoviesShelf != nil,
            newMovies: newMoviesShelf?.items ?? Array(newestMovies.prefix(itemLimit)),
            newMoviesAreDiscoveryBased: newMoviesShelf != nil,
            topSeries: hasTrendingSeries
                ? matchedTopSeries
                : Array(newestSeries.prefix(itemLimit)),
            topSeriesAreTrending: hasTrendingSeries,
            newSeries: hasDiscoveryNewSeries
                ? matchedNewSeries
                : Array(newestSeries.prefix(itemLimit)),
            newSeriesAreDiscoveryBased: hasDiscoveryNewSeries,
            movieServiceShelves: movieServiceShelves,
            seriesServiceShelves: seriesServiceShelves,
            homeServiceSpotlights: homeServiceSpotlights,
            movieCategories: movieCategories,
            seriesCategories: seriesCategories,
            movieFilterCategories: orderedMovieBuckets.map(\.name),
            movieFilterCountries: countries(in: library.movies),
            movieFilterDecades: decades(in: library.movies.compactMap(\.year)),
            seriesFilterCategories: orderedSeriesBuckets.map(\.name),
            // SeriesGroup currently has no country field and Library.series(...)
            // cannot apply one. Advertising a dead filter would be worse than
            // omitting it until that model supports it end to end.
            seriesFilterCountries: [],
            seriesFilterDecades: decades(in: library.series.compactMap(\.year))
        )

        return DiscoveryPresentation(
            matchedShelves: matchedShelves,
            itemRanking: itemRanking,
            seriesRanking: seriesRanking,
            browse: browse
        )
    }
}

// MARK: - Selection and ordering

private extension DiscoveryPresentation {
    struct DiscoveryTitleIdentity: Hashable {
        var id: Int
        var isSeries: Bool

        init(_ title: DiscoveryTitle) {
            self.id = title.id
            self.isSeries = title.isSeries
        }
    }

    struct RawMatchedShelf {
        var shelf: DiscoveryShelf
        var items: [MediaItem]
        var order: Int

        func presentation(minimum: Int, limit: Int) -> MatchedDiscoveryShelf? {
            guard limit > 0, items.count >= minimum else { return nil }
            return MatchedDiscoveryShelf(shelf: shelf, items: Array(items.prefix(limit)))
        }
    }

    enum BasicSource {
        case trending
        case newReleases
    }

    static func bestShelf(
        in shelves: [MatchedDiscoveryShelf],
        kind: MediaKind,
        source: BasicSource
    ) -> MatchedDiscoveryShelf? {
        shelves.filter { matched in
            guard matched.shelf.kind == kind else { return false }
            switch (source, matched.shelf.source) {
            case (.trending, .trending), (.newReleases, .newReleases): return true
            default: return false
            }
        }.max { lhs, rhs in
            if lhs.items.count != rhs.items.count { return lhs.items.count < rhs.items.count }
            return lhs.id > rhs.id
        }
    }

    struct RankedCandidate<Element> {
        var element: Element
        var rank: Int?
        var year: Int
        var name: String
        var id: String
    }

    static func limited<Element>(
        _ elements: [Element],
        ranking: [String: Int],
        limit: Int,
        key: KeyPath<Element, String>,
        year: KeyPath<Element, Int?>,
        name: KeyPath<Element, String>
    ) -> [Element] {
        guard limit > 0 else { return [] }
        var best: [RankedCandidate<Element>] = []
        best.reserveCapacity(min(limit, elements.count))

        for (index, element) in elements.enumerated() {
            if index.isMultiple(of: 1_024), Task.isCancelled { return [] }
            let id = element[keyPath: key]
            let candidate = RankedCandidate(
                element: element,
                rank: ranking[id],
                year: element[keyPath: year] ?? .min,
                name: SearchNormalizer.normalize(element[keyPath: name]),
                id: id
            )

            var low = 0
            var high = best.count
            while low < high {
                let middle = (low + high) / 2
                if precedes(candidate, best[middle]) {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            guard low < limit else { continue }
            best.insert(candidate, at: low)
            if best.count > limit { best.removeLast() }
        }
        return best.map(\.element)
    }

    static func precedes<Element>(
        _ lhs: RankedCandidate<Element>, _ rhs: RankedCandidate<Element>
    ) -> Bool {
        switch (lhs.rank, rhs.rank) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - Services

private extension DiscoveryPresentation {
    struct ServiceBundle {
        var id: Int
        var name: String
        var movieShelf: RawMatchedShelf?
        var seriesShelf: RawMatchedShelf?
        var firstOrder: Int

        var matchCount: Int {
            var identities = Set<String>()
            for item in movieShelf?.items ?? [] { identities.insert("movie|\(item.id)") }
            for item in seriesShelf?.items ?? [] { identities.insert("series|\(item.id)") }
            return identities.count
        }

        /// Lower leads. `leading` comes from the audience and sits in front of
        /// the general list, so a child's Home opens on Disney while everyone
        /// else keeps the order that was chosen for them.
        func preference(leadingWith leading: [String]) -> Int {
            let normalized = SearchNormalizer.normalize(name)
            for (index, wanted) in leading.enumerated()
            where name.localizedCaseInsensitiveContains(wanted) {
                return index - leading.count
            }
            let words = Set(normalized.split(separator: " ").map(String.init))
            if words.contains("netflix") { return 0 }
            if words.contains("hbo") || normalized == "max" || normalized.hasPrefix("max ") {
                return 1
            }
            let lowered = name.lowercased()
            if id == 350
                || lowered.contains("apple tv+")
                || normalized.contains("apple tv plus") {
                return 2
            }
            return 3
        }

        static func precedes(
            _ lhs: ServiceBundle, _ rhs: ServiceBundle, leadingWith leading: [String] = []
        ) -> Bool {
            let left = lhs.preference(leadingWith: leading)
            let right = rhs.preference(leadingWith: leading)
            if left != right { return left < right }
            if left == 3, lhs.matchCount != rhs.matchCount {
                return lhs.matchCount > rhs.matchCount
            }
            if lhs.firstOrder != rhs.firstOrder { return lhs.firstOrder < rhs.firstOrder }
            return lhs.id < rhs.id
        }

        static func make(from shelves: [RawMatchedShelf]) -> [ServiceBundle] {
            var result: [Int: ServiceBundle] = [:]
            for matched in shelves {
                guard case .service(let id, let name) = matched.shelf.source else { continue }
                var bundle = result[id] ?? ServiceBundle(
                    id: id, name: name, movieShelf: nil, seriesShelf: nil,
                    firstOrder: matched.order
                )
                bundle.firstOrder = min(bundle.firstOrder, matched.order)
                if bundle.name.isEmpty { bundle.name = name }
                switch matched.shelf.kind {
                case .movie:
                    bundle.movieShelf = better(bundle.movieShelf, matched)
                case .series:
                    bundle.seriesShelf = better(bundle.seriesShelf, matched)
                case .liveTV:
                    break
                }
                result[id] = bundle
            }
            return Array(result.values)
        }

        private static func better(
            _ current: RawMatchedShelf?, _ candidate: RawMatchedShelf
        ) -> RawMatchedShelf {
            guard let current else { return candidate }
            if candidate.items.count != current.items.count {
                return candidate.items.count > current.items.count ? candidate : current
            }
            return candidate.shelf.id < current.shelf.id ? candidate : current
        }
    }

    static func interleave(
        _ first: [MediaItem], _ second: [MediaItem], limit: Int
    ) -> [MediaItem] {
        guard limit > 0 else { return [] }
        var result: [MediaItem] = []
        result.reserveCapacity(min(limit, first.count + second.count))
        var seen = Set<String>()
        var firstIndex = 0
        var secondIndex = 0

        while result.count < limit, firstIndex < first.count || secondIndex < second.count {
            if firstIndex < first.count {
                let item = first[firstIndex]
                firstIndex += 1
                if seen.insert("\(item.kind.rawValue)|\(item.id)").inserted {
                    result.append(item)
                }
            }
            guard result.count < limit else { break }
            if secondIndex < second.count {
                let item = second[secondIndex]
                secondIndex += 1
                if seen.insert("\(item.kind.rawValue)|\(item.id)").inserted {
                    result.append(item)
                }
            }
        }
        return result
    }
}

// MARK: - Categories and filters

private extension DiscoveryPresentation {
    typealias MovieBucket = (name: String, items: [MediaItem])
    typealias SeriesBucket = (name: String, items: [SeriesGroup])

    static func movieBucketsWithOtherLast(_ buckets: [MovieBucket]) -> [MovieBucket] {
        buckets.filter { !isOther($0) } + buckets.filter(isOther)
    }

    static func seriesBucketsWithOtherLast(_ buckets: [SeriesBucket]) -> [SeriesBucket] {
        buckets.filter { !isOther($0) } + buckets.filter(isOther)
    }

    static func isOther(_ bucket: MovieBucket) -> Bool {
        bucket.items.contains { $0.category == nil }
    }

    static func isOther(_ bucket: SeriesBucket) -> Bool {
        bucket.items.contains { $0.category == nil }
    }

    static func movieCategoryPreviews(
        buckets: [MovieBucket], ranking: [String: Int], itemLimit: Int
    ) -> [MovieCategoryPreview] {
        guard itemLimit > 0, !buckets.isEmpty else { return [] }
        return buckets.compactMap { bucket in
            let movies = limited(
                bucket.items, ranking: ranking, limit: itemLimit,
                key: \MediaItem.id, year: \MediaItem.year, name: \MediaItem.title
            )
            guard !movies.isEmpty else { return nil }
            return MovieCategoryPreview(name: bucket.name, movies: movies)
        }
    }

    static func seriesCategoryPreviews(
        buckets: [SeriesBucket], ranking: [String: Int], itemLimit: Int
    ) -> [SeriesCategoryPreview] {
        guard itemLimit > 0, !buckets.isEmpty else { return [] }
        return buckets.compactMap { bucket in
            let series = limited(
                bucket.items, ranking: ranking, limit: itemLimit,
                key: \SeriesGroup.id, year: \SeriesGroup.year, name: \SeriesGroup.name
            )
            guard !series.isEmpty else { return nil }
            return SeriesCategoryPreview(name: bucket.name, series: series)
        }
    }

    static func countries(in items: [MediaItem], minimum: Int = 3) -> [String] {
        var counts: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 1_024), Task.isCancelled { return [] }
            guard let code = normalizedCountry(item.countryCode) else { continue }
            counts[code, default: 0] += 1
        }
        return orderedCountries(counts, minimum: minimum)
    }

    static func countries(in groups: [SeriesGroup], minimum: Int = 3) -> [String] {
        var counts: [String: Int] = [:]
        for (index, group) in groups.enumerated() {
            if index.isMultiple(of: 1_024), Task.isCancelled { return [] }
            guard let code = group.episodes.lazy.compactMap(\.countryCode)
                .compactMap(normalizedCountry).first
            else { continue }
            counts[code, default: 0] += 1
        }
        return orderedCountries(counts, minimum: minimum)
    }

    static func normalizedCountry(_ value: String?) -> String? {
        guard let code = value?.uppercased(), code.count == 2 else { return nil }
        return code
    }

    static func orderedCountries(_ counts: [String: Int], minimum: Int) -> [String] {
        counts.filter { $0.value >= minimum }.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map(\.key)
    }

    static func decades(in years: [Int]) -> [Int] {
        Set(years.map { ($0 / 10) * 10 }).filter { $0 >= 1900 }.sorted(by: >)
    }
}

// MARK: - Series identity

private struct SeriesResolver {
    private var byID: [String: SeriesGroup] = [:]
    private var byNormalizedName: [String: SeriesGroup] = [:]
    private var byProviderID: [Int: SeriesGroup] = [:]

    init(_ groups: [SeriesGroup]) {
        byID.reserveCapacity(groups.count)
        byNormalizedName.reserveCapacity(groups.count)
        byProviderID.reserveCapacity(groups.count)
        for group in groups {
            if byID[group.id] == nil { byID[group.id] = group }
            let name = SearchNormalizer.normalize(group.name)
            if byNormalizedName[name] == nil { byNormalizedName[name] = group }
            if let providerID = group.providerSeriesID, byProviderID[providerID] == nil {
                byProviderID[providerID] = group
            }
        }
    }

    func group(for item: MediaItem) -> SeriesGroup? {
        if let providerID = item.providerSeriesID, let group = byProviderID[providerID] {
            return group
        }
        if let key = item.seriesKey, let group = byID[key] { return group }
        return byNormalizedName[SearchNormalizer.normalize(item.seriesName ?? item.title)]
    }

    func groups(for items: [MediaItem], limit: Int) -> [SeriesGroup] {
        guard limit > 0 else { return [] }
        var result: [SeriesGroup] = []
        var seen = Set<String>()
        for item in items {
            guard let group = group(for: item), seen.insert(group.id).inserted else { continue }
            result.append(group)
            if result.count >= limit { break }
        }
        return result
    }
}
