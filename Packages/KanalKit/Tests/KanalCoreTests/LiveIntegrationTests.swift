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
        let result = try await loader.loadLibrary(for: source)
        #expect(result.library.channels.count > 50)
        // Genre folders called "Series" must not turn live channels into shows.
        #expect(result.library.series.isEmpty)
    }
}

/// TMDB tests, run only when a key is present.
///
/// Reads the key from the environment rather than the app bundle so the suite
/// never depends on a build setting, and skips silently when there is none.
@Suite(
    "Live TMDB",
    .enabled(if: ProcessInfo.processInfo.environment["KANAL_LIVE_TESTS"] == "1"
             && ProcessInfo.processInfo.environment["TMDB_API_KEY"]?.isEmpty == false)
)
struct LiveTMDBTests {

    var key: String {
        ProcessInfo.processInfo.environment["TMDB_API_KEY"] ?? ""
    }

    @Test("The credential's shape is detected, not configured")
    func detectsCredentialKind() throws {
        let credential = try #require(TMDBClient.Credential(key))
        // A v4 read access token is a JWT; a v3 key is 32 hex characters.
        if key.hasPrefix("ey") {
            #expect(credential == .bearerToken(key))
        } else {
            #expect(credential == .apiKey(key))
        }
    }

    @Test("Whitespace from a pasted, line-wrapped token is stripped")
    func stripsWrapping() throws {
        let wrapped = key.isEmpty ? "" : String(key.prefix(20)) + "\n" + String(key.dropFirst(20))
        let credential = try #require(TMDBClient.Credential(wrapped))
        if case .bearerToken(let token) = credential {
            #expect(!token.contains("\n"))
            #expect(token == key)
        }
    }

    @Test("Authenticates and returns artwork for a real film")
    func fetchesArtwork() async throws {
        let provider = try #require(TMDBProvider(apiKey: key))
        let results = try await provider.lookup(name: "The Lion King", year: 1994, isSeries: false)
        let match = try #require(
            results.first { $0.year == 1994 },
            "TMDB returned \(results.count) candidates but none from 1994"
        )
        #expect(match.posterURL != nil, "no poster path came back")
        #expect(match.overview?.isEmpty == false, "no plot came back")
    }

    @Test("Localised titles come back in the device language")
    func localisedTitle() async throws {
        let client = try #require(TMDBClient(apiKey: key, language: "nb-NO"))
        let candidates = try await client.search("The Lion King", year: 1994, isSeries: false)
        let match = try #require(candidates.first { $0.year == 1994 })
        let detailed = try #require(try await client.details(id: match.id, isSeries: false))
        #expect(detailed.allTitles.contains { $0.localizedCaseInsensitiveContains("Løvenes") })
    }

    /// The gap this closes: TMDB searches its own titles, not the viewer's, so
    /// "Biler" finds nothing however hard it looks. The bundled pack knows it
    /// means "Cars", and passing that on is what gets a poster on screen.
    @Test("A Norwegian film title still gets artwork")
    func norwegianTitleGetsArtwork() async throws {
        let storage = KanalStorage(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        let service = MetadataService(
            storage: storage,
            providers: [
                BundledTitleProvider(packs: ["nb": ["Biler": "Cars"]]),
                try #require(TMDBProvider(apiKey: key)),
            ]
        )
        let item = MediaItem(
            id: "1", kind: .movie, title: "Biler", rawTitle: "Biler (2006)",
            streamURL: URL(string: "http://p.tv/movie/u/p/1.mp4")!, year: 2006
        )
        let resolved = try #require(await service.metadata(for: item))
        #expect(resolved.canonicalName == "Cars")
        #expect(resolved.posterURL != nil)
    }
}

/// Points the real loader at a real guide file.
///
/// Set `KANAL_TEST_EPG_URL` to your provider's own EPG to see exactly what
/// Kanal makes of it — how much it recovered, what it had to repair, and how
/// much of your channel list it actually covers.
@Suite(
    "Live EPG file",
    .enabled(if: ProcessInfo.processInfo.environment["KANAL_TEST_EPG_URL"]?.isEmpty == false)
)
struct LiveEPGTests {

    @Test("Reports what it recovered and what it had to repair")
    func inspectGuide() async throws {
        let url = try #require(URL(string: ProcessInfo.processInfo.environment["KANAL_TEST_EPG_URL"] ?? ""))
        let result = try await LibraryLoader().loadGuide(from: url)

        print("""

        EPG: \(url.absoluteString)
          channels   \(result.guide.schedules.count)
          programmes \(result.programmeCount)
          repairs    \(result.repairs.map(\.rawValue).joined(separator: ", ").ifEmpty("none"))
          partial    \(result.isPartial)

        """)
        #expect(result.programmeCount > 0, "nothing was recovered from this guide")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
