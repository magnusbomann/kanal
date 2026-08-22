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
