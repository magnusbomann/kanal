import Foundation
import Testing
@testable import KanalCore

@Suite("Filtering and ordering")
struct LibraryFilterTests {

    static func movie(_ title: String, year: Int?, category: String?, country: String? = nil) -> MediaItem {
        MediaItem(
            id: title, kind: .movie, title: title, rawTitle: title,
            streamURL: URL(string: "http://p.tv/play/\(abs(title.hashValue))")!,
            category: category, countryCode: country, year: year
        )
    }

    let library = Library(items: [
        movie("Aged Classic", year: 1975, category: "Drama", country: "US"),
        movie("Brand New", year: 2026, category: "Action", country: "NO"),
        movie("Middle Aged", year: 2001, category: "Drama", country: "NO"),
        movie("No Year", year: nil, category: "Drama"),
        movie("Zulu", year: 2019, category: "Action", country: "NO"),
    ])

    @Test("Newest first, and entries with no year sink rather than lead")
    func newest() {
        let titles = library.movies(LibraryFilter(sort: .newest)).map(\.title)
        #expect(titles.first == "Brand New")
        #expect(titles.last == "No Year")
    }

    @Test("Oldest first also sinks the unknown")
    func oldest() {
        let titles = library.movies(LibraryFilter(sort: .oldest)).map(\.title)
        #expect(titles.first == "Aged Classic")
        #expect(titles.last == "No Year")
    }

    @Test("Alphabetical is alphabetical")
    func alphabetical() {
        #expect(library.movies(LibraryFilter(sort: .alphabetical)).first?.title == "Aged Classic")
    }

    /// The point of the default: what the world ranked comes first, and the
    /// remainder still opens on something current rather than arbitrary.
    @Test("Recommended puts ranked entries first, then the newest")
    func recommended() {
        let ranking = ["Middle Aged": 0, "Aged Classic": 1]
        let titles = library.movies(LibraryFilter(sort: .recommended), ranking: ranking).map(\.title)
        #expect(Array(titles.prefix(2)) == ["Middle Aged", "Aged Classic"])
        #expect(titles[2] == "Brand New")
    }

    @Test("Without a ranking, recommended is simply newest first")
    func recommendedWithoutRanking() {
        #expect(library.movies(LibraryFilter(sort: .recommended)).first?.title == "Brand New")
    }

    @Test("Narrows by the provider's own category")
    func byCategory() {
        let titles = library.movies(LibraryFilter(category: "Drama")).map(\.title)
        #expect(Set(titles) == ["Aged Classic", "Middle Aged", "No Year"])
    }

    @Test("Narrows by country")
    func byCountry() {
        #expect(library.movies(LibraryFilter(country: "NO")).count == 3)
    }

    @Test("Narrows by decade")
    func byDecade() {
        #expect(library.movies(LibraryFilter(decade: 2020)).map(\.title) == ["Brand New"])
        #expect(library.movies(LibraryFilter(decade: 1970)).map(\.title) == ["Aged Classic"])
    }

    @Test("Narrowings combine")
    func combined() {
        let filter = LibraryFilter(sort: .newest, category: "Action", country: "NO")
        #expect(library.movies(filter).map(\.title) == ["Brand New", "Zulu"])
    }

    /// An empty control is worse than no control.
    @Test("A country is only offered when the library carries enough of it")
    func countriesNeedEvidence() {
        #expect(library.availableCountries(minimum: 3) == ["NO"])
        #expect(library.availableCountries(minimum: 10).isEmpty)
    }

    @Test("Decades come from what is actually there")
    func decades() {
        #expect(library.availableDecades(among: library.movies) == [2020, 2010, 2000, 1970])
    }

    @Test("Counts how many narrowings are active")
    func activeCount() {
        #expect(LibraryFilter().activeCount == 0)
        #expect(LibraryFilter().isNarrowed == false)
        #expect(LibraryFilter(category: "Drama", country: "NO").activeCount == 2)
    }
}
