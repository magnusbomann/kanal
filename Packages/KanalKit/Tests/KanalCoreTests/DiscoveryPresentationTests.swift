import Foundation
import Testing
@testable import KanalCore

@Suite("Discovery presentation")
struct DiscoveryPresentationTests {

    @Test("Top and new rows are selected by source and kind, not response order")
    func selectsRowsExplicitly() throws {
        let trendingMovie = Fixtures.movie("Trending Film", year: 2021)
        let newMovie = Fixtures.movie("New Film", year: 2026)
        let trendingShow = Fixtures.show("Trending Show", year: 2020, providerID: 10)
        let newShow = Fixtures.show("New Show", year: 2025, providerID: 11)
        let serviceMovie = Fixtures.movie("Service Film", year: 2022)
        let serviceShow = Fixtures.show("Service Show", year: 2023, providerID: 12)
        let library = Library(items: [
            trendingMovie, newMovie, trendingShow, newShow, serviceMovie, serviceShow,
        ])

        // Deliberately the reverse of the presentation order, with a service
        // row first: this is the cache-order regression the builder closes.
        let shelves = [
            Fixtures.shelf("netflix.series", source: .service(id: 8, name: "Netflix"), items: [serviceShow]),
            Fixtures.shelf("new.series", source: .newReleases, items: [newShow]),
            Fixtures.shelf("netflix.movie", source: .service(id: 8, name: "Netflix"), items: [serviceMovie]),
            Fixtures.shelf("trending.series", source: .trending, items: [trendingShow]),
            Fixtures.shelf("new.movie", source: .newReleases, items: [newMovie]),
            Fixtures.shelf("trending.movie", source: .trending, items: [trendingMovie]),
        ]

        let result = DiscoveryPresentation.build(
            library: library, shelves: shelves, minimumShelfSize: 1, limit: 8
        )

        #expect(result.browse.topMovies.map(\.title) == ["Trending Film"])
        #expect(result.browse.newMovies.map(\.title) == ["New Film"])
        #expect(result.browse.topSeries.map(\.name) == ["Trending Show"])
        #expect(result.browse.newSeries.map(\.name) == ["New Show"])
        #expect(result.browse.topMoviesAreTrending)
        #expect(result.browse.newMoviesAreDiscoveryBased)
        #expect(result.browse.topSeriesAreTrending)
        #expect(result.browse.newSeriesAreDiscoveryBased)
        #expect(result.browse.movieServiceShelves.flatMap(\.items).allSatisfy { $0.kind == .movie })
        #expect(result.browse.seriesServiceShelves.flatMap(\.items).allSatisfy { $0.kind == .series })
    }

    @Test("Series recommendations rank SeriesGroup ids rather than episode ids")
    func ranksSeriesGroups() {
        let alpha = Fixtures.show("Alpha", year: 2025, providerID: 101)
        let zulu = Fixtures.show("Zulu", year: 2020, providerID: 202)
        let library = Library(items: [alpha, zulu])
        let shelf = Fixtures.shelf(
            "trending.series", source: .trending, items: [zulu, alpha]
        )

        let result = DiscoveryPresentation.build(
            library: library, shelves: [shelf], minimumShelfSize: 1
        )
        let ordered = library.series(
            LibraryFilter(sort: .recommended), ranking: result.seriesRanking
        )

        #expect(result.seriesRanking["zulu"] == 0)
        #expect(result.seriesRanking["alpha"] == 1)
        #expect(result.seriesRanking[zulu.id] == nil)
        #expect(result.itemRanking[zulu.id] == nil)
        #expect(ordered.map(\.name) == ["Zulu", "Alpha"])
    }

    @Test("Every preview is capped, ranked and keeps Other behind named categories")
    func capsAndDistributesCategories() throws {
        let action = (0..<4).map {
            Fixtures.movie("Action \($0)", year: 2020 + $0, category: "Action", country: "NO")
        }
        let drama = (0..<3).map {
            Fixtures.movie("Drama \($0)", year: 2010 + $0, category: "Drama", country: "NO")
        }
        let uncategorized = (0..<6).map {
            Fixtures.movie("Loose \($0)", year: 2000 + $0, country: $0 < 2 ? "US" : "NO")
        }
        let kidsShows = (0..<3).map {
            Fixtures.show("Kids \($0)", year: 2020 + $0, category: "Kids", providerID: 300 + $0)
        }
        let dramaShows = (0..<2).map {
            Fixtures.show("Drama Show \($0)", year: 2010 + $0, category: "Drama", providerID: 400 + $0)
        }
        let looseShows = (0..<4).map {
            Fixtures.show("Loose Show \($0)", year: 2000 + $0, providerID: 500 + $0)
        }
        let all = action + drama + uncategorized + kidsShows + dramaShows + looseShows
        let library = Library(items: all)
        let shelves = [
            Fixtures.shelf(
                "trending.movie", source: .trending,
                items: [action[3], action[1], action[0], action[2]]
            ),
            Fixtures.shelf(
                "service.movie", source: .service(id: 50, name: "Local"),
                items: action + drama
            ),
            Fixtures.shelf(
                "service.series", source: .service(id: 50, name: "Local"),
                items: kidsShows + dramaShows
            ),
        ]

        let result = DiscoveryPresentation.build(
            library: library,
            shelves: shelves,
            minimumShelfSize: 1,
            limit: 2,
            categoryLimit: 3,
            serviceLimit: 1
        )
        let otherMovieName = try #require(
            library.movieCategories.first { $0.items.contains { $0.category == nil } }?.name
        )
        let otherSeriesName = try #require(
            library.seriesCategories.first { $0.items.contains { $0.category == nil } }?.name
        )

        #expect(result.matchedShelves.allSatisfy { $0.items.count <= 2 })
        #expect(result.browse.topMovies.count <= 2)
        #expect(result.browse.newMovies.count <= 2)
        #expect(result.browse.topSeries.count <= 2)
        #expect(result.browse.newSeries.count <= 2)
        #expect(result.browse.movieServiceShelves.count == 1)
        #expect(result.browse.seriesServiceShelves.count == 1)
        #expect(result.browse.homeServiceSpotlights.count == 1)
        #expect(result.browse.homeServiceSpotlights[0].items.count <= 2)
        #expect(result.browse.movieCategories.count == 3)
        #expect(result.browse.seriesCategories.count == 3)
        #expect(result.browse.movieCategories.allSatisfy { $0.movies.count <= 2 })
        #expect(result.browse.seriesCategories.allSatisfy { $0.series.count <= 2 })
        #expect(result.browse.movieCategories.last?.name == otherMovieName)
        #expect(result.browse.seriesCategories.last?.name == otherSeriesName)
        #expect(result.browse.movieFilterCategories.last == otherMovieName)
        #expect(result.browse.seriesFilterCategories.last == otherSeriesName)
        #expect(result.browse.movieCategories.first { $0.name == "Action" }?.movies.map(\.title)
            == ["Action 3", "Action 1"])
        #expect(result.browse.movieFilterCountries == ["NO"])
        #expect(result.browse.movieFilterDecades.first == 2020)
        #expect(result.browse.seriesFilterCountries.isEmpty)
        #expect(result.browse.seriesFilterDecades.first == 2020)
    }

    @Test("Home combines small film and series service rows before applying the minimum")
    func combinesServiceKindsForHome() {
        let movies = [Fixtures.movie("Film A"), Fixtures.movie("Film B")]
        let shows = [
            Fixtures.show("Show A", providerID: 1),
            Fixtures.show("Show B", providerID: 2),
        ]
        let malformed = DiscoveryShelf(
            id: "malformed.movie",
            source: .trending,
            kind: .movie,
            titles: [Fixtures.title(for: shows[0])]
        )
        let live = DiscoveryShelf(
            id: "not.discovery.live",
            source: .trending,
            kind: .liveTV,
            titles: [Fixtures.title(for: movies[0])]
        )
        let shelves = [
            Fixtures.shelf("netflix.movie", source: .service(id: 8, name: "Netflix"), items: movies),
            Fixtures.shelf("netflix.series", source: .service(id: 8, name: "Netflix"), items: shows),
            malformed,
            live,
        ]

        let result = DiscoveryPresentation.build(
            library: Library(items: movies + shows),
            shelves: shelves,
            minimumShelfSize: 4,
            limit: 4
        )

        #expect(result.browse.movieServiceShelves.isEmpty)
        #expect(result.browse.seriesServiceShelves.isEmpty)
        #expect(result.browse.homeServiceSpotlights.count == 1)
        #expect(result.browse.homeServiceSpotlights[0].items.map(\.kind)
            == [.movie, .series, .movie, .series])
        #expect(!result.matchedShelves.contains { $0.id == malformed.id || $0.id == live.id })
    }

    @Test("Netflix, Max and Apple TV+ lead; other services follow local match count and order")
    func prioritizesRecognisableServices() {
        let movies = (0..<24).map { Fixtures.movie("Catalog \($0)") }
        let shelves = [
            Fixtures.shelf("local-b", source: .service(id: 1, name: "Local B"), items: Array(movies[0..<2])),
            Fixtures.shelf("apple-store", source: .service(id: 2, name: "Apple TV"), items: Array(movies[2..<6])),
            Fixtures.shelf("cinemax", source: .service(id: 3, name: "Cinemax"), items: Array(movies[6..<11])),
            Fixtures.shelf("local-strong", source: .service(id: 4, name: "Local Strong"), items: Array(movies[11..<14])),
            Fixtures.shelf("apple-plus", source: .service(id: 350, name: "Apple TV"), items: [movies[14]]),
            Fixtures.shelf("max", source: .service(id: 6, name: "Max"), items: [movies[15]]),
            Fixtures.shelf("netflix", source: .service(id: 7, name: "Netflix"), items: [movies[16]]),
            Fixtures.shelf("local-a", source: .service(id: 8, name: "Local A"), items: Array(movies[17..<19])),
        ]

        let result = DiscoveryPresentation.build(
            library: Library(items: movies), shelves: shelves,
            minimumShelfSize: 1, limit: 10, serviceLimit: 8
        )

        #expect(result.browse.homeServiceSpotlights.map(\.serviceID) == [
            7, 6, 350, 3, 2, 4, 1, 8,
        ])
    }

    @Test("Missing and undersized discovery rows fall back to newest without false labels")
    func fallsBackToNewest() {
        let oldMovie = Fixtures.movie("Old Film", year: 1990)
        let newMovie = Fixtures.movie("New Film", year: 2025)
        let oldShow = Fixtures.show("Old Show", year: 1980, providerID: 10)
        let newShow = Fixtures.show("New Show", year: 2024, providerID: 11)
        let shelves = [
            Fixtures.shelf("too-small.movie", source: .trending, items: [oldMovie]),
            Fixtures.shelf("too-small.series", source: .newReleases, items: [oldShow]),
            DiscoveryShelf(
                id: "unmatched.new.movie", source: .newReleases, kind: .movie,
                titles: [DiscoveryTitle(id: 999, names: ["Not Carried"])]
            ),
        ]

        let result = DiscoveryPresentation.build(
            library: Library(items: [oldMovie, newMovie, oldShow, newShow]),
            shelves: shelves,
            minimumShelfSize: 2,
            limit: 4
        )

        #expect(result.matchedShelves.isEmpty)
        #expect(result.browse.topMovies.first?.title == "New Film")
        #expect(result.browse.newMovies.first?.title == "New Film")
        #expect(result.browse.topSeries.first?.name == "New Show")
        #expect(result.browse.newSeries.first?.name == "New Show")
        #expect(!result.browse.topMoviesAreTrending)
        #expect(!result.browse.newMoviesAreDiscoveryBased)
        #expect(!result.browse.topSeriesAreTrending)
        #expect(!result.browse.newSeriesAreDiscoveryBased)
    }

    @Test("Zero and negative limits expose no display rows")
    func emptyLimitsAreSafe() {
        let movie = Fixtures.movie("Only Film", year: 2025, category: "Drama")
        let shelf = Fixtures.shelf("trending.movie", source: .trending, items: [movie])

        for limit in [0, -4] {
            let result = DiscoveryPresentation.build(
                library: Library(items: [movie]), shelves: [shelf],
                minimumShelfSize: 1, limit: limit,
                categoryLimit: limit, serviceLimit: limit
            )
            #expect(result.matchedShelves.isEmpty)
            #expect(result.browse.topMovies.isEmpty)
            #expect(result.browse.newMovies.isEmpty)
            #expect(result.browse.movieCategories.isEmpty)
            #expect(result.browse.movieServiceShelves.isEmpty)
            #expect(result.browse.homeServiceSpotlights.isEmpty)
        }
    }
}

private enum Fixtures {
    static func movie(
        _ title: String,
        year: Int? = nil,
        category: String? = nil,
        country: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: "movie|\(title)",
            kind: .movie,
            title: title,
            rawTitle: title,
            streamURL: URL(string: "https://provider.test/movie/\(urlPart(title)).mp4")!,
            category: category,
            countryCode: country,
            year: year
        )
    }

    static func show(
        _ name: String,
        year: Int? = nil,
        category: String? = nil,
        providerID: Int
    ) -> MediaItem {
        MediaItem(
            id: "series-\(providerID)",
            kind: .series,
            title: name,
            rawTitle: name,
            streamURL: URL(string: "https://provider.test/series/\(providerID).mp4")!,
            category: category,
            seriesName: name,
            providerSeriesID: providerID,
            year: year
        )
    }

    static func shelf(
        _ id: String,
        source: DiscoveryShelf.Source,
        items: [MediaItem]
    ) -> DiscoveryShelf {
        DiscoveryShelf(
            id: id,
            source: source,
            kind: items.first?.kind ?? .movie,
            titles: items.enumerated().map { offset, item in
                title(for: item, id: stableID(id, offset))
            }
        )
    }

    static func title(for item: MediaItem, id: Int = 10_000) -> DiscoveryTitle {
        DiscoveryTitle(
            id: id,
            names: [item.seriesName ?? item.title],
            year: item.year,
            isSeries: item.kind == .series
        )
    }

    private static func stableID(_ text: String, _ offset: Int) -> Int {
        var value = 17
        for byte in text.utf8 { value = (value &* 31 &+ Int(byte)) & 0x3fff_ffff }
        return value &+ offset
    }

    private static func urlPart(_ title: String) -> String {
        title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "item"
    }
}

/// The fetch order and the presentation order have to agree about who leads,
/// or a child's Home opens on Netflix however the request was made.
@Suite("Whose services lead")
struct ServiceOrderingTests {

    static func shelves() -> [DiscoveryShelf] {
        [
            Fixtures.shelf(
                "service.8.movie", source: .service(id: 8, name: "Netflix"),
                items: [Fixtures.movie("Netflix Film", year: 2021)]
            ),
            Fixtures.shelf(
                "service.1899.movie", source: .service(id: 1899, name: "HBO Max"),
                items: [Fixtures.movie("Max Film", year: 2022)]
            ),
            Fixtures.shelf(
                "service.337.movie", source: .service(id: 337, name: "Disney Plus"),
                items: [Fixtures.movie("Disney Film", year: 2023)]
            ),
        ]
    }

    static func library() -> Library {
        Library(items: [
            Fixtures.movie("Netflix Film", year: 2021),
            Fixtures.movie("Max Film", year: 2022),
            Fixtures.movie("Disney Film", year: 2023),
        ])
    }

    static func services(for audience: DiscoveryAudience) -> [String] {
        DiscoveryPresentation.build(
            library: library(), shelves: shelves(), audience: audience,
            minimumShelfSize: 1, limit: 8
        ).browse.homeServiceSpotlights.map(\.serviceName)
    }

    /// Measured on a real catalogue, Disney carried seventeen films a
    /// nine-year-old could watch against Netflix's twelve — and it is the row
    /// a parent goes looking for.
    @Test("A child's rows open on Disney")
    func childLeadsWithDisney() {
        #expect(Self.services(for: .children(.nine)) == ["Disney Plus", "Netflix", "HBO Max"])
    }

    @Test("A grown-up's order is untouched")
    func grownUpKeepsTheOldOrder() {
        #expect(Self.services(for: .everyone) == ["Netflix", "HBO Max", "Disney Plus"])
    }
}
