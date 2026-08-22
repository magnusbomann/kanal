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
