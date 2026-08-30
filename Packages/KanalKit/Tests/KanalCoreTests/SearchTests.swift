import Foundation
import Testing
@testable import KanalCore

@Suite("Search normalisation")
struct SearchNormalizerTests {

    @Test("Folds Nordic letters that Foundation leaves alone", arguments: [
        ("Skjønnheten", "skjonnheten"),
        ("Løvenes konge", "lovenes konge"),
        ("Kjærlighet", "kjaerlighet"),
        ("Brødrene Blues", "brodrene blues"),
        ("Måneskinn", "maneskinn"),
    ])
    func nordic(input: String, expected: String) {
        #expect(SearchNormalizer.normalize(input) == expected)
    }

    @Test("Folds ordinary accents too")
    func accents() {
        #expect(SearchNormalizer.normalize("Amélie") == "amelie")
        #expect(SearchNormalizer.normalize("Hämnden") == "hamnden")
    }

    @Test("Punctuation becomes word breaks")
    func punctuation() {
        #expect(SearchNormalizer.normalize("Marvel's Agents of S.H.I.E.L.D.") == "marvel s agents of s h i e l d")
        #expect(SearchNormalizer.normalize("NO| TV 2 - Sport") == "no tv 2 sport")
    }
}

@Suite("Search index")
struct SearchIndexTests {

    let library = Library(items: [
        Self.item("The Lion King", raw: "EN| The Lion King 1080p", alternates: ["Løvenes konge"]),
        Self.item("Frost", raw: "NO| Frost"),
        Self.item("Frost Fishing Championship", raw: "NO| Frost Fishing Championship"),
        Self.item("Skjønnheten og udyret", raw: "NO| Skjønnheten og udyret"),
        Self.item("Viaplay Sport 1", raw: "NO| VIAPLAY SPORT 1 FHD", kind: .liveTV),
    ])

    static func item(
        _ title: String,
        raw: String,
        alternates: [String] = [],
        kind: MediaKind = .movie
    ) -> MediaItem {
        MediaItem(
            id: title,
            kind: kind,
            title: title,
            rawTitle: raw,
            alternateTitles: alternates,
            streamURL: URL(string: "http://a/\(title.hashValue)")!
        )
    }

    @Test("Finds a title typed without Norwegian letters")
    func foldedQuery() {
        let titles = library.search("skjonnheten").map(\.title)
        #expect(titles.first == "Skjønnheten og udyret")
    }

    @Test("Finds a film by its Norwegian name when we know it")
    func alternateTitle() {
        let titles = library.search("løvenes konge").map(\.title)
        #expect(titles.first == "The Lion King")
    }

    @Test("Ranks the exact title above a longer one containing it")
    func ranking() {
        let titles = library.search("frost").map(\.title)
        #expect(titles.first == "Frost")
        #expect(titles.contains("Frost Fishing Championship"))
    }

    @Test("Matches words in any order")
    func wordOrder() {
        #expect(library.search("king lion").map(\.title).first == "The Lion King")
    }

    @Test("Matches partial words as you type")
    func prefixes() {
        #expect(library.search("lio ki").map(\.title).first == "The Lion King")
    }

    @Test("Still finds the provider's own spelling")
    func rawTitle() {
        #expect(library.search("viaplay fhd").map(\.title).first == "Viaplay Sport 1")
    }

    @Test("Returns nothing for a query that matches nothing")
    func noMatch() {
        #expect(library.search("zzzzz").isEmpty)
    }
}

@Suite("Search results match what the viewer can open")
struct GroupedLibrarySearchTests {

    static func item(
        id: String,
        kind: MediaKind,
        title: String,
        url: String,
        category: String? = nil,
        alternateTitles: [String] = [],
        seriesName: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        year: Int? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            kind: kind,
            title: title,
            rawTitle: title,
            alternateTitles: alternateTitles,
            streamURL: URL(string: url)!,
            category: category,
            seriesName: seriesName,
            season: season,
            episode: episode,
            year: year
        )
    }

    @Test("Hundreds of episode rows become one show")
    func oneResultPerShow() throws {
        let episodes = (1...250).map { number in
            Self.item(
                id: "reacher-\(number)",
                kind: .series,
                title: "Reacher",
                url: "https://example.com/reacher/\(number).mkv",
                category: "Drama",
                seriesName: "Reacher",
                season: (number - 1) / 25 + 1,
                episode: (number - 1) % 25 + 1
            )
        }
        let film = Self.item(
            id: "reacher-film",
            kind: .movie,
            title: "Reacher",
            url: "https://example.com/reacher.mp4",
            year: 2024
        )
        let library = Library(items: episodes + [film])

        let hits = library.search("reacher")
        let results = library.groupedSearchResults(from: hits)

        #expect(hits.count == 2)
        #expect(results.series.count == 1)
        #expect(results.series.first?.episodes.count == 250)
        #expect(results.movies.map(\.id) == ["reacher-film"])
    }

    @Test("A channel result retains every fallback stream")
    func channelResultRetainsFallbacks() throws {
        let library = Library(items: [
            Self.item(
                id: "nrk-hd",
                kind: .liveTV,
                title: "NRK 1 HD",
                url: "https://example.com/nrk-hd.m3u8",
                category: "Nyheter"
            ),
            Self.item(
                id: "nrk-plain",
                kind: .liveTV,
                title: "NRK 1",
                url: "https://example.com/nrk.m3u8",
                category: "Norge"
            ),
        ])

        // A category carried by a non-primary variant is searchable too.
        let hits = library.search("nyheter")
        let results = library.groupedSearchResults(from: hits)
        let channel = try #require(results.channels.first)

        #expect(hits.count == 1)
        #expect(results.channels.count == 1)
        #expect(channel.variants.count == 2)
        #expect(channel.categories == ["Norge", "Nyheter"])
    }

    @Test("Duplicate film listings collapse while remakes stay separate")
    func duplicateFilms() {
        let library = Library(items: [
            Self.item(
                id: "dune-a", kind: .movie, title: "Dune",
                url: "https://example.com/dune-a.mkv", category: "Sci-Fi", year: 2021
            ),
            Self.item(
                id: "dune-b", kind: .movie, title: "Dune",
                url: "https://example.com/dune-b.mkv", category: "New",
                alternateTitles: ["Ørkenplaneten"], year: 2021
            ),
            Self.item(
                id: "dune-1984", kind: .movie, title: "Dune",
                url: "https://example.com/dune-1984.mkv", category: "Classics", year: 1984
            ),
        ])

        let hits = library.search("dune")
        let results = library.groupedSearchResults(from: hits)

        #expect(hits.count == 2)
        #expect(results.movies.count == 2)
        #expect(Set(results.movies.compactMap(\.year)) == [1984, 2021])
        #expect(library.search("orkenplaneten").count == 1)
    }

    @Test("Same-named films without a year fold into one card, keeping both streams")
    func unknownYearFoldsButKeepsStreams() {
        let library = Library(items: [
            Self.item(
                id: "crash-1996", kind: .movie, title: "Crash",
                url: "https://example.com/crash-a.mkv"
            ),
            Self.item(
                id: "crash-2004", kind: .movie, title: "Crash",
                url: "https://example.com/crash-b.mkv"
            ),
        ])

        let results = library.groupedSearchResults(from: library.search("crash"))

        // One result, because seven identical posters in a row is what a real
        // provider's duplicates look like and nobody can read that. Both
        // streams stay reachable behind it: if these really are two films,
        // the second is still there to fall through to.
        #expect(results.movies.count == 1)
        #expect(library.movieGroup(containing: results.movies[0])?.variants.count == 2)
    }
}
