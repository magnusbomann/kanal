import Foundation
import Testing
@testable import KanalCore

@Suite("Folding duplicate films")
struct MovieGroupTests {

    static func movie(
        _ title: String, url: String, category: String? = nil, year: Int? = nil
    ) -> MediaItem {
        let cleaned = TitleCleaner.clean(title)
        return MediaItem(
            id: "\(title)|\(url)", kind: .movie, title: cleaned.title,
            rawTitle: title, streamURL: URL(string: url)!, category: category,
            year: year ?? cleaned.year, qualityTag: cleaned.qualityTag
        )
    }

    /// What the real provider does: one film filed under four folders, so the
    /// shelf showed the same poster four times in a row.
    @Test("The same film in several categories becomes one card")
    func sameFilmManyCategories() throws {
        let library = Library(items: [
            Self.movie("Interstellar", url: "http://p.tv/1.mkv", category: "Sci-fi"),
            Self.movie("Interstellar", url: "http://p.tv/1.mkv", category: "Drama"),
            Self.movie("Interstellar", url: "http://p.tv/1.mkv", category: "Eventyr"),
        ])

        #expect(library.movies.count == 1)
        let group = try #require(library.movieGroups.first)
        #expect(group.variants.count == 1)
        #expect(group.categories == ["Drama", "Eventyr", "Sci-fi"])
    }

    @Test("Different streams of one film survive as alternatives")
    func distinctStreamsKept() throws {
        let library = Library(items: [
            Self.movie("Interstellar SD", url: "http://p.tv/sd.mkv"),
            Self.movie("Interstellar 4K", url: "http://p.tv/4k.mkv"),
            Self.movie("Interstellar HD", url: "http://p.tv/hd.mkv"),
        ])

        #expect(library.movies.count == 1)
        let group = try #require(library.movieGroups.first)
        #expect(group.variants.count == 3)
        // Best first, worst last — but never dropped.
        #expect(group.primary.streamURL.absoluteString == "http://p.tv/4k.mkv")
        #expect(group.variants.last?.streamURL.absoluteString == "http://p.tv/sd.mkv")
    }

    @Test("Two films sharing a name stay apart when the years say so")
    func differentYearsStayApart() {
        let library = Library(items: [
            Self.movie("The Lion King", url: "http://p.tv/1994.mkv", year: 1994),
            Self.movie("The Lion King", url: "http://p.tv/2019.mkv", year: 2019),
        ])

        #expect(library.movies.count == 2)
        #expect(Set(library.movies.compactMap(\.year)) == [1994, 2019])
    }

    @Test("An undated listing joins the only year there is")
    func undatedJoinsSoleYear() throws {
        let library = Library(items: [
            Self.movie("Interstellar", url: "http://p.tv/a.mkv", year: 2014),
            Self.movie("Interstellar", url: "http://p.tv/b.mkv"),
        ])

        #expect(library.movies.count == 1)
        let group = try #require(library.movieGroups.first)
        #expect(group.year == 2014)
        #expect(group.variants.count == 2)
    }

    /// The one case where folding would be guessing: the name covers two
    /// films and this listing says nothing about which.
    @Test("An undated listing stays its own card when the name covers two films")
    func undatedStaysApartWhenAmbiguous() {
        let library = Library(items: [
            Self.movie("The Lion King", url: "http://p.tv/1994.mkv", year: 1994),
            Self.movie("The Lion King", url: "http://p.tv/2019.mkv", year: 2019),
            Self.movie("The Lion King", url: "http://p.tv/x.mkv"),
        ])

        #expect(library.movies.count == 3)
    }

    @Test("A film keeps its place in every folder it was filed in")
    func categoriesKeepTheFilm() throws {
        let library = Library(items: [
            Self.movie("Interstellar", url: "http://p.tv/1.mkv", category: "Sci-fi"),
            Self.movie("Interstellar", url: "http://p.tv/2.mkv", category: "4k"),
        ])

        let folders = Dictionary(
            uniqueKeysWithValues: library.movieCategories.map { ($0.name, $0.items.count) }
        )
        #expect(folders["Sci-fi"] == 1)
        #expect(folders["4k"] == 1)
    }

    @Test("Playing a folded film tries every listing of it")
    func playbackFallsThroughListings() throws {
        let library = Library(items: [
            Self.movie("Interstellar 4K", url: "http://p.tv/4k.mkv"),
            Self.movie("Interstellar HD", url: "http://p.tv/hd.mkv"),
        ])
        let group = try #require(library.movieGroups.first)

        let plan = PlaybackPlan(movie: group)
        #expect(plan.variantCount == 2)
        #expect(plan.item.title == group.title)
        #expect(plan.candidates.contains(URL(string: "http://p.tv/hd.mkv")!))
    }

    @Test("The listing that last worked leads next time")
    func rememberedListingLeads() throws {
        let library = Library(items: [
            Self.movie("Interstellar 4K", url: "http://p.tv/4k.mkv"),
            Self.movie("Interstellar HD", url: "http://p.tv/hd.mkv"),
        ])
        let group = try #require(library.movieGroups.first)
        let worked = try #require(group.variants.last)

        let plan = PlaybackPlan(movie: group, remembered: worked.id)
        #expect(plan.owner(at: 0) == worked.id)
        // Still titled after the film, not after the listing that plays.
        #expect(plan.item.title == group.title)
    }

    @Test("A film reaches its own group from the card that stands for it")
    func lookupFromRepresentative() throws {
        let library = Library(items: [
            Self.movie("Blade Runner 2049", url: "http://p.tv/a.mkv", category: "Sci-fi"),
            Self.movie("Blade Runner 2049", url: "http://p.tv/b.mkv", category: "4k"),
            Self.movie("The Lion King", url: "http://p.tv/lk.mkv", year: 1994),
        ])
        let card = try #require(library.movies.first { $0.title == "Blade Runner 2049" })

        // The number is part of the name, so this is one film with two
        // listings rather than a 2049 release with none.
        #expect(card.year == nil)
        #expect(library.movieGroup(containing: card)?.variants.count == 2)
    }
}
