import Foundation
import Testing
@testable import KanalCore

/// Tests that talk to the real internet.
///
/// Off by default so the suite stays fast and deterministic. Run them when
/// changing a provider, to confirm the remote API still answers the way the
/// parsing expects:
///
///     KANAL_LIVE_TESTS=1 swift test --filter Live
@Suite("Live services", .enabled(if: ProcessInfo.processInfo.environment["KANAL_LIVE_TESTS"] == "1"))
struct LiveIntegrationTests {

    /// Languages are passed explicitly rather than read from the machine: a
    /// test that only passes on a Norwegian Mac proves nothing about the
    /// feature, only about the Mac.
    @Test(
        "A localised title resolves to the name a provider would list",
        arguments: [
            (["nb", "en"], "Løvenes konge", "lovenes konge"),
            (["de", "en"], "Der König der Löwen", "der konig der lowen"),
            (["sv", "en"], "Lejonkungen", "lejonkungen"),
        ]
    )
    func localisedTitleResolves(
        languages: [String], query: String, normalized: String
    ) async throws {
        let provider = WikidataProvider(languages: languages)
        let results = try await provider.lookup(name: query, year: nil, isSeries: nil)
        let match = try #require(
            results.first { $0.matches(normalizedQuery: normalized) },
            "no candidate answered to \(query) in \(languages)"
        )
        #expect(match.allNames.contains("The Lion King"))
    }

    @Test("Wikidata answers for a series")
    func wikidataSeries() async throws {
        let provider = WikidataProvider(languages: ["en"])
        let results = try await provider.lookup(name: "Breaking Bad", year: nil, isSeries: true)
        #expect(results.contains { $0.canonicalName == "Breaking Bad" })
    }

    @Test("The whole translation path works end to end")
    func serviceTranslation() async throws {
        let storage = KanalStorage(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        let service = MetadataService(
            storage: storage,
            providers: [WikidataProvider(languages: ["nb", "en"])]
        )
        let result = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(result.spellings.contains { $0.localizedCaseInsensitiveContains("Lion King") })
    }

    /// The scenario the whole metadata layer exists for: a Norwegian viewer
    /// types the name they know, against a provider list written in English.
    @Test("A Norwegian title finds an English listing")
    func norwegianTitleFindsEnglishListing() async {
        let library = Library(items: [
            MediaItem(
                id: "1", kind: .movie,
                title: "The Lion King", rawTitle: "EN| The Lion King 1080p",
                streamURL: URL(string: "http://p.tv/movie/u/p/1.mp4")!,
                year: 1994
            ),
            MediaItem(
                id: "2", kind: .movie,
                title: "Blade Runner", rawTitle: "EN| Blade Runner",
                streamURL: URL(string: "http://p.tv/movie/u/p/2.mp4")!
            ),
        ])

        // Nothing local can match — the strings share no words.
        #expect(library.search("Løvenes konge").isEmpty)

        let storage = KanalStorage(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        let service = MetadataService(
            storage: storage,
            providers: [WikidataProvider(languages: ["nb", "en"])]
        )
        let (spellings, _) = await service.alternativeSpellings(for: "Løvenes konge")

        let hits = spellings.flatMap { library.search($0) }
        #expect(hits.contains { $0.title == "The Lion King" })
    }

    @Test("A free public playlist still parses")
    func iptvOrgPlaylist() async throws {
        let loader = LibraryLoader()
        let source = PlaylistSource(
            kind: .m3u,
            name: "iptv-org",
            playlistURL: URL(string: "https://iptv-org.github.io/iptv/countries/no.m3u")
        )
        let (library, _) = try await loader.loadLibrary(for: source)
        #expect(library.channels.count > 50)
        // Genre folders called "Series" must not turn live channels into shows.
        #expect(library.series.isEmpty)
    }
}
