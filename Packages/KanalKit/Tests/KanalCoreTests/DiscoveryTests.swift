import Foundation
import Testing
@testable import KanalCore

@Suite("Matching recommendations to a library")
struct LibraryMatchingTests {

    static func movie(_ title: String, year: Int? = nil) -> MediaItem {
        MediaItem(
            id: title, kind: .movie, title: title, rawTitle: title,
            streamURL: URL(string: "http://p.tv/play/\(abs(title.hashValue))")!,
            year: year
        )
    }

    static func episode(_ show: String, season: Int, episode: Int) -> MediaItem {
        MediaItem(
            id: "\(show)-\(season)-\(episode)", kind: .series,
            title: "\(show) S0\(season)E0\(episode)", rawTitle: "\(show) S0\(season)E0\(episode)",
            streamURL: URL(string: "http://p.tv/play/\(abs(show.hashValue))\(season)\(episode)")!,
            seriesName: show, season: season, episode: episode
        )
    }

    let library = Library(items: [
        movie("The Lion King", year: 1994),
        movie("Making The Lion King", year: 1994),
        movie("The Lion King", year: 2019),
        movie("Interstellar", year: 2014),
        movie("Blade Runner 2049", year: 2017),
        episode("Breaking Bad", season: 1, episode: 1),
    ])

    @Test("Finds a film the provider carries")
    func findsCarried() throws {
        let wanted = DiscoveryTitle(id: 1, names: ["Interstellar"], year: 2014)
        #expect(library.item(matching: wanted)?.title == "Interstellar")
    }

    @Test("Matches through a localised name")
    func matchesLocalised() throws {
        // TMDB gives both the Norwegian and the original name; the provider
        // used the original.
        let wanted = DiscoveryTitle(id: 2, names: ["Løvenes konge", "The Lion King"], year: 1994)
        let match = try #require(library.item(matching: wanted))
        #expect(match.title == "The Lion King")
        #expect(match.year == 1994)
    }

    /// The failure that would embarrass us: a shelf that opens the wrong film.
    @Test("Refuses a title that merely contains the words")
    func refusesSubstring() {
        let wanted = DiscoveryTitle(id: 3, names: ["Lion King"], year: 1994)
        // "Making The Lion King" contains the words but is a different film.
        #expect(library.item(matching: wanted)?.title != "Making The Lion King")
    }

    @Test("Picks the right edition when the year distinguishes them")
    func picksByYear() throws {
        let remake = DiscoveryTitle(id: 4, names: ["The Lion King"], year: 2019)
        #expect(library.item(matching: remake)?.year == 2019)

        let original = DiscoveryTitle(id: 5, names: ["The Lion King"], year: 1994)
        #expect(library.item(matching: original)?.year == 1994)
    }

    @Test("A disagreeing year blocks the match")
    func wrongYearBlocks() {
        #expect(library.item(matching: DiscoveryTitle(id: 6, names: ["Interstellar"], year: 1975)) == nil)
    }

    @Test("Says nothing when the provider doesn't carry it")
    func absent() {
        #expect(library.item(matching: DiscoveryTitle(id: 7, names: ["Some Unavailable Film"])) == nil)
    }

    @Test("Matches a series through its show name, not an episode title")
    func matchesSeries() throws {
        let wanted = DiscoveryTitle(id: 8, names: ["Breaking Bad"], isSeries: true)
        #expect(library.item(matching: wanted)?.seriesName == "Breaking Bad")
    }

    @Test("A film recommendation never matches a series, or the reverse")
    func kindsDoNotCross() {
        #expect(library.item(matching: DiscoveryTitle(id: 9, names: ["Breaking Bad"], isSeries: false)) == nil)
        #expect(library.item(matching: DiscoveryTitle(id: 10, names: ["Interstellar"], isSeries: true)) == nil)
    }

    @Test("Keeps the order the recommendations arrived in")
    func preservesOrder() {
        let wanted = [
            DiscoveryTitle(id: 11, names: ["Blade Runner 2049"], year: 2017),
            DiscoveryTitle(id: 12, names: ["Not Carried"]),
            DiscoveryTitle(id: 13, names: ["Interstellar"], year: 2014),
        ]
        #expect(library.items(matching: wanted).map(\.title) == ["Blade Runner 2049", "Interstellar"])
    }

    @Test("Never returns the same entry twice")
    func deduplicates() {
        let twice = [
            DiscoveryTitle(id: 14, names: ["Interstellar"], year: 2014),
            DiscoveryTitle(id: 15, names: ["Interstellar"], year: 2014),
        ]
        #expect(library.items(matching: twice).count == 1)
    }
}

@Suite("Choosing recognisable streaming services")
struct DiscoveryServiceSelectionTests {

    @Test("Netflix, Max and Apple TV+ survive a short regional list")
    func keepsRecognisableServices() {
        let ranked = [
            DiscoveryService.Service(id: 1, name: "Local One"),
            DiscoveryService.Service(id: 2, name: "Local Two"),
            DiscoveryService.Service(id: 3, name: "Netflix"),
            DiscoveryService.Service(id: 4, name: "Max"),
            // TMDB currently localises the Apple TV+ provider (id 350) as
            // plain "Apple TV" in some regions.
            DiscoveryService.Service(id: 350, name: "Apple TV"),
            DiscoveryService.Service(id: 6, name: "Local Three"),
        ]

        let chosen = DiscoveryService.curatedServices(ranked, limit: 4)
        #expect(chosen.map(\.name) == ["Netflix", "Max", "Apple TV", "Local One"])
    }

    @Test("The Apple rental store is not mistaken for Apple TV+")
    func leavesTheRentalStoreInRegionalOrder() {
        let ranked = [
            DiscoveryService.Service(id: 1, name: "Local One"),
            DiscoveryService.Service(id: 2, name: "Apple TV"),
            DiscoveryService.Service(id: 3, name: "Netflix"),
        ]

        let chosen = DiscoveryService.curatedServices(ranked, limit: 2)
        #expect(chosen.map(\.name) == ["Netflix", "Local One"])
    }

    /// Measured against the real catalogue: Disney carried seventeen films a
    /// nine-year-old could watch, Netflix twelve — and Disney is the one a
    /// parent goes looking for.
    @Test("A child's rows lead with Disney")
    func childrenLeadWithDisney() {
        let ranked = [
            DiscoveryService.Service(id: 1, name: "Local One"),
            DiscoveryService.Service(id: 8, name: "Netflix"),
            DiscoveryService.Service(id: 337, name: "Disney Plus"),
            DiscoveryService.Service(id: 4, name: "Max"),
        ]

        let chosen = DiscoveryService.curatedServices(
            ranked, limit: 3, leadingWith: DiscoveryAudience.children(.nine).preferredServices
        )
        #expect(chosen.map(\.name) == ["Disney Plus", "Netflix", "Max"])
    }

    @Test("A grown-up's ordering is left exactly as it was")
    func grownUpsUnchanged() {
        let ranked = [
            DiscoveryService.Service(id: 337, name: "Disney Plus"),
            DiscoveryService.Service(id: 8, name: "Netflix"),
        ]

        #expect(
            DiscoveryService.curatedServices(
                ranked, limit: 2, leadingWith: DiscoveryAudience.everyone.preferredServices
            ) == DiscoveryService.curatedServices(ranked, limit: 2)
        )
    }
}

/// The rows a child gets are a different question put to TMDB, not the
/// grown-up answer with the unsuitable parts taken out.
@Suite("Who the recommendations are for")
struct DiscoveryAudienceTests {

    @Test("A grown-up's profile asks for nothing extra")
    func grownUp() {
        let audience = DiscoveryAudience(profile: Profile(name: "A", maturity: .adult))
        #expect(audience == .everyone)
        #expect(audience.movieGenres == nil)
        #expect(audience.seriesGenres == nil)
        #expect(audience.movieCertification == nil)
    }

    /// Failing safe: before anyone has chosen, the audience is a child's.
    @Test("No profile is treated as a child's")
    func noProfile() {
        #expect(DiscoveryAudience(profile: nil) == .everyone)
    }

    @Test("Every child ceiling carries a board limit TMDB can filter on")
    func ceilings() {
        let expected: [MaturityRating: String] = [
            .allAges: "G", .six: "G", .nine: "PG", .twelve: "PG-13", .fifteen: "R",
        ]
        for (ceiling, code) in expected {
            let audience = DiscoveryAudience.children(ceiling)
            let certification = audience.movieCertification
            #expect(certification?.country == "US")
            #expect(certification?.code == code, "ceiling \(ceiling.rawValue)")
        }
    }

    /// The mistake this app has already made once, in the profile suggestions:
    /// Animation is a technique, not an audience. Filtering shows by it
    /// returns Family Guy next to Paw Patrol — measured, two usable shows
    /// against seven for the audience genres.
    @Test("Shows are chosen by audience, never by Animation alone")
    func showsUseAudienceGenres() {
        let genres = DiscoveryAudience.children(.nine).seriesGenres
        #expect(genres == "10762|10751")
        #expect(genres != "16")
    }

    @Test("Films may use Animation, because a board rating gates them too")
    func filmsMayUseAnimation() {
        #expect(DiscoveryAudience.children(.nine).movieGenres == "16|10751")
        #expect(DiscoveryAudience.children(.nine).movieCertification != nil)
    }

    /// Two profiles that ask different questions must not share an answer.
    @Test("Each audience caches under its own name")
    func cacheScopes() {
        let scopes = [
            DiscoveryAudience.everyone,
            .children(.allAges), .children(.six), .children(.nine),
            .children(.twelve), .children(.fifteen),
        ].map(\.cacheScope)
        #expect(Set(scopes).count == scopes.count)
    }
}

@Suite("An actor's other work")
struct CreditMatchingTests {

    let library = Library(items: [
        LibraryMatchingTests.movie("Løvenes konge", year: 1994),
        LibraryMatchingTests.movie("Interstellar", year: 2014),
        LibraryMatchingTests.episode("Breaking Bad", season: 1, episode: 1),
    ])

    static func role(
        _ id: Int, _ title: String, original: String? = nil,
        isSeries: Bool = false, year: Int? = nil
    ) -> KnownRole {
        KnownRole(
            id: id, title: title, originalTitle: original, isSeries: isSeries,
            posterPath: nil, popularity: 1, year: year
        )
    }

    @Test("A credit the provider carries resolves to something playable")
    func resolvesCarried() throws {
        let match = try #require(library.item(matching: Self.role(1, "Interstellar", year: 2014)))
        #expect(match.title == "Interstellar")
    }

    @Test("Matches on the original name when the provider used that one")
    func matchesOriginalName() throws {
        // TMDB answers in the viewer's language; a provider may not.
        let role = Self.role(2, "The Lion King", original: "Løvenes konge", year: 1994)
        #expect(library.item(matching: role)?.title == "Løvenes konge")
    }

    @Test("A show resolves to one of its episodes, not to nothing")
    func resolvesSeries() throws {
        let role = Self.role(3, "Breaking Bad", isSeries: true, year: 2008)
        #expect(library.item(matching: role)?.seriesName == "Breaking Bad")
    }

    @Test("A credit the provider lacks stays unmatched rather than guessing")
    func leavesUncarriedAlone() {
        #expect(library.item(matching: Self.role(4, "Dune", year: 2021)) == nil)
    }

    @Test("A wrong year rules a match out")
    func yearMustAgree() {
        #expect(library.item(matching: Self.role(5, "Interstellar", year: 1979)) == nil)
    }

    @Test("Resolving a whole credit list keys results by their TMDB id")
    func resolvesInBulk() {
        let roles = [
            Self.role(10, "Interstellar", year: 2014),
            Self.role(11, "Dune", year: 2021),
            Self.role(12, "Breaking Bad", isSeries: true),
        ]
        let found = library.items(matching: roles)
        #expect(found.count == 2)
        #expect(found[10]?.title == "Interstellar")
        #expect(found[11] == nil)
        #expect(found[12]?.seriesName == "Breaking Bad")
    }

    @Test("A credit cached before years were recorded still matches")
    func decodesOlderCache() throws {
        // Shipped caches predate `originalTitle` and `year`; a missing field
        // must not throw away the whole person.
        let legacy = """
        {"id":7,"title":"Interstellar","isSeries":false,"popularity":9.5}
        """
        let role = try JSONDecoder().decode(KnownRole.self, from: Data(legacy.utf8))
        #expect(role.year == nil)
        #expect(library.item(matching: role)?.title == "Interstellar")
    }
}

/// A child sees a film only once a board has been consulted about it, and the
/// queue that consults them is tens of thousands long. Which end it starts at
/// decides whether their Home fills in minutes or in days.
@Suite("Which titles get checked first")
struct DiscoveryVerificationOrderTests {

    static func movie(_ title: String) -> MediaItem {
        MediaItem(
            id: title, kind: .movie, title: title, rawTitle: title,
            streamURL: URL(string: "http://p.tv/play/\(abs(title.hashValue))")!
        )
    }

    static func shelf(_ names: [String]) -> DiscoveryShelf {
        DiscoveryShelf(
            id: "trending.movie", source: .trending, kind: .movie,
            titles: names.enumerated().map { DiscoveryTitle(id: $0.offset, names: [$0.element]) }
        )
    }

    @Test("The recommendations go to the front, in their own order")
    func recommendationsLead() {
        let pool = [
            Self.movie("Some Panel Filler"),
            Self.movie("Toy Story"),
            Self.movie("Another Filler"),
            Self.movie("Coco"),
        ]
        let ranking = DiscoveryVerificationOrder.ranking(for: [Self.shelf(["Coco", "Toy Story"])])
        let ordered = DiscoveryVerificationOrder.prioritised(pool, by: ranking)

        #expect(ordered.map(\.title) == [
            "Coco", "Toy Story", "Some Panel Filler", "Another Filler",
        ])
    }

    /// Nothing may be dropped: the queue exists to reach the end of the
    /// catalogue, and a title nobody recommended still needs an answer.
    @Test("Everything in the pool survives the reordering")
    func nothingIsLost() {
        let pool = (1...50).map { Self.movie("Film \($0)") }
        let ranking = DiscoveryVerificationOrder.ranking(for: [Self.shelf(["Film 40", "Film 3"])])
        let ordered = DiscoveryVerificationOrder.prioritised(pool, by: ranking)

        #expect(ordered.count == pool.count)
        #expect(Set(ordered.map(\.id)) == Set(pool.map(\.id)))
        #expect(ordered.prefix(2).map(\.title) == ["Film 40", "Film 3"])
    }

    @Test("With no recommendations the pool is left exactly as it was")
    func noRecommendations() {
        let pool = [Self.movie("A"), Self.movie("B")]
        #expect(DiscoveryVerificationOrder.prioritised(pool, by: [:]).map(\.id) == ["A", "B"])
        #expect(
            DiscoveryVerificationOrder.prioritised(pool, by: ["nothing here": 0]).map(\.id)
                == ["A", "B"]
        )
    }

    /// A localised name is how a Norwegian provider files a Disney film, and
    /// the recommendation carries both.
    @Test("A title is recognised by any name it goes by")
    func matchesLocalisedName() {
        let pool = [Self.movie("Filler"), Self.movie("Løvenes konge")]
        let shelf = DiscoveryShelf(
            id: "trending.movie", source: .trending, kind: .movie,
            titles: [DiscoveryTitle(id: 1, names: ["Løvenes konge", "The Lion King"])]
        )
        let ordered = DiscoveryVerificationOrder.prioritised(
            pool, by: DiscoveryVerificationOrder.ranking(for: [shelf])
        )
        #expect(ordered.first?.title == "Løvenes konge")
    }

    /// Shows are filed per episode; the queue is about the show.
    @Test("An episode is recognised by its show's name")
    func matchesSeriesName() {
        var episode = Self.movie("Bluey S01E01")
        episode.kind = .series
        episode.seriesName = "Bluey"
        let pool = [Self.movie("Filler"), episode]
        let ordered = DiscoveryVerificationOrder.prioritised(
            pool, by: DiscoveryVerificationOrder.ranking(for: [Self.shelf(["Bluey"])])
        )
        #expect(ordered.first?.seriesName == "Bluey")
    }
}
