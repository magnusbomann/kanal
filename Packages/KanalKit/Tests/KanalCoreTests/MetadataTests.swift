import Foundation
import Testing
@testable import KanalCore

/// A provider with fixed answers, so the service's own rules can be tested
/// without a network or an API key.
struct StubProvider: MetadataProvider {
    var providerName: String
    var providesArtwork: Bool
    var results: [ResolvedTitle]
    var shouldThrow = false

    func lookup(name: String, year: Int?, isSeries: Bool?) async throws -> [ResolvedTitle] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return results
    }
}

private func scratchStorage() -> KanalStorage {
    KanalStorage(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
}

private let lionKing = ResolvedTitle(
    id: "wikidata:Q36479",
    canonicalName: "The Lion King",
    localizedName: "Løvenes konge",
    allNames: ["The Lion King", "Løvenes konge", "Lejonkungen", "Løvernes Konge", "Lion King"],
    year: 1994,
    isSeries: false
)

@Suite("Query translation")
struct TranslationTests {

    @Test("Translates a Norwegian title to the name a provider would list")
    func translates() async {
        let service = MetadataService(
            storage: scratchStorage(),
            providers: [StubProvider(providerName: "Stub", providesArtwork: false, results: [lionKing])]
        )
        let result = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(result.spellings.contains("The Lion King"))
        #expect(result.matched == "The Lion King")
    }

    @Test("Works when the accented letters are typed as plain ones")
    func folded() async {
        let service = MetadataService(
            storage: scratchStorage(),
            providers: [StubProvider(providerName: "Stub", providesArtwork: false, results: [lionKing])]
        )
        let result = await service.alternativeSpellings(for: "lovenes konge")
        #expect(result.spellings.contains("The Lion King"))
    }

    @Test("Refuses a candidate that is not what was typed")
    func refusesUnrelated() async {
        let unrelated = ResolvedTitle(
            id: "stub:1",
            canonicalName: "Something Else",
            allNames: ["Something Else"]
        )
        let service = MetadataService(
            storage: scratchStorage(),
            providers: [StubProvider(providerName: "Stub", providesArtwork: false, results: [unrelated])]
        )
        let result = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(result.spellings.isEmpty)
        #expect(result.matched == nil)
    }

    @Test("Falls through to the next provider when the first has nothing")
    func fallsThrough() async {
        let service = MetadataService(
            storage: scratchStorage(),
            providers: [
                StubProvider(providerName: "Empty", providesArtwork: false, results: []),
                StubProvider(providerName: "Stub", providesArtwork: false, results: [lionKing]),
            ]
        )
        let result = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(result.matched == "The Lion King")
    }

    @Test("A provider that throws does not break the chain")
    func survivesFailure() async {
        let service = MetadataService(
            storage: scratchStorage(),
            providers: [
                StubProvider(providerName: "Broken", providesArtwork: false, results: [], shouldThrow: true),
                StubProvider(providerName: "Stub", providesArtwork: false, results: [lionKing]),
            ]
        )
        let result = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(result.matched == "The Lion King")
    }

    @Test("Very short queries never reach a provider")
    func tooShort() async {
        let service = MetadataService(
            storage: scratchStorage(),
            providers: [StubProvider(providerName: "Stub", providesArtwork: false, results: [lionKing])]
        )
        #expect(await service.alternativeSpellings(for: "lo").spellings.isEmpty)
    }

    @Test("Wikidata is on by default and needs no key")
    func defaultProvider() async {
        let service = MetadataService(storage: scratchStorage())
        #expect(await service.providerNames == ["Wikidata"])
        #expect(await service.hasArtworkProvider == false)
    }

    @Test("A TMDB key adds an artwork provider on top")
    func withKey() async {
        let service = MetadataService(tmdbAPIKey: "abc", storage: scratchStorage())
        #expect(await service.providerNames == ["Wikidata", "TMDB"])
        #expect(await service.hasArtworkProvider == true)
    }
}

@Suite("Failure handling")
struct MetadataFailureTests {

    /// The bug this guards: a rate limit or a dropped connection is not an
    /// answer. Remembering one as "no such film" makes a title permanently
    /// invisible after a single bad moment.
    @Test("A provider failure is never cached as a missing title")
    func failureIsNotAMiss() async {
        let broken = StubProvider(
            providerName: "Broken", providesArtwork: false, results: [], shouldThrow: true
        )
        let service = MetadataService(storage: scratchStorage(), providers: [broken])

        // First attempt fails.
        #expect(await service.alternativeSpellings(for: "Løvenes konge").spellings.isEmpty)

        // The provider recovers; the answer must now come through rather than
        // being served from a cached miss.
        await service.replaceProviders([
            StubProvider(providerName: "Working", providesArtwork: false, results: [lionKing])
        ])
        let second = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(second.matched == "The Lion King")
    }

    @Test("A genuine no-match is cached and not asked again")
    func genuineMissIsCached() async {
        let empty = CountingProvider()
        let service = MetadataService(storage: scratchStorage(), providers: [empty])

        _ = await service.alternativeSpellings(for: "Zzzq Flurb")
        _ = await service.alternativeSpellings(for: "Zzzq Flurb")
        #expect(await empty.calls == 1)
    }
}

/// Counts how many times it was asked, to prove negative caching works.
final class CountingProvider: MetadataProvider, @unchecked Sendable {
    var providerName: String { "Counting" }
    var providesArtwork: Bool { false }
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }

    func lookup(name: String, year: Int?, isSeries: Bool?) async throws -> [ResolvedTitle] {
        lock.withLock { _calls += 1 }
        return []
    }
}

@Suite("Identifying a library entry")
struct IdentificationTests {

    let service = MetadataService(
        storage: scratchStorage(),
        providers: [StubProvider(providerName: "Stub", providesArtwork: true, results: [])]
    )

    static func candidate(_ name: String, year: Int?, id: Int = 1) -> ResolvedTitle {
        ResolvedTitle(id: "stub:\(id)", canonicalName: name, allNames: [name], year: year)
    }

    @Test("Matches on the exact name")
    func exact() async {
        let match = await service.bestMatch(for: "The Lion King", year: nil, among: [
            Self.candidate("The Lion King II", year: nil, id: 1),
            Self.candidate("The Lion King", year: nil, id: 2),
        ])
        #expect(match?.id == "stub:2")
    }

    @Test("A matching year breaks a tie")
    func yearTieBreak() async {
        let match = await service.bestMatch(for: "Frost", year: 1997, among: [
            Self.candidate("Frost", year: 2013, id: 1),
            Self.candidate("Frost", year: 1997, id: 2),
        ])
        #expect(match?.id == "stub:2")
    }

    @Test("A year that disagrees outweighs a name that matches")
    func wrongYear() async {
        let match = await service.bestMatch(for: "Frost", year: 2013, among: [
            Self.candidate("Frost", year: 1950),
        ])
        #expect(match == nil)
    }

    @Test("Refuses a weak match rather than guessing")
    func refusesWeak() async {
        let match = await service.bestMatch(for: "The Lion King", year: nil, among: [
            Self.candidate("Something Else", year: nil),
        ])
        #expect(match == nil)
    }

    @Test("Live channels are never looked up")
    func skipsLive() async {
        let channel = MediaItem(
            id: "c1", kind: .liveTV, title: "TV 2", rawTitle: "TV 2",
            streamURL: URL(string: "http://a/1.m3u8")!
        )
        #expect(await service.metadata(for: channel) == nil)
    }
}

@Suite("Wikidata parsing")
struct WikidataParsingTests {

    /// Trimmed to the shape wbgetentities actually returns for Q36479.
    let lionKingEntity: [String: Any] = [
        "labels": [
            "en": ["language": "en", "value": "The Lion King"],
            "nb": ["language": "nb", "value": "Løvenes konge"],
            "sv": ["language": "sv", "value": "Lejonkungen"],
            "da": ["language": "da", "value": "Løvernes Konge"],
        ],
        "aliases": [
            "en": [["language": "en", "value": "Lion King"]],
        ],
        "descriptions": [
            "nb": ["language": "nb", "value": "amerikansk animert Disney-film fra 1994"],
        ],
        "claims": [
            "P31": [["mainsnak": ["datavalue": ["value": ["id": "Q202866"]]]]],
            "P577": [["mainsnak": ["datavalue": ["value": ["time": "+1994-11-18T00:00:00Z"]]]]],
        ],
    ]

    @Test("Reads every name, with English as the canonical one")
    func names() throws {
        let title = try #require(WikidataProvider.title(id: "Q36479", entity: lionKingEntity))
        #expect(title.canonicalName == "The Lion King")
        #expect(title.localizedName == "Løvenes konge")
        #expect(title.allNames.contains("Lejonkungen"))
        #expect(title.allNames.contains("Lion King"))
        #expect(title.year == 1994)
        #expect(title.isSeries == false)
    }

    @Test("Answers to the Norwegian name")
    func matchesNorwegian() throws {
        let title = try #require(WikidataProvider.title(id: "Q36479", entity: lionKingEntity))
        #expect(title.matches(normalizedQuery: SearchNormalizer.normalize("Løvenes konge")))
        #expect(title.matches(normalizedQuery: "lovenes konge"))
    }

    @Test("Rejects entities that are not something you watch")
    func rejectsNonFilm() {
        let person: [String: Any] = [
            "labels": ["en": ["value": "Elton John"]],
            "claims": ["P31": [["mainsnak": ["datavalue": ["value": ["id": "Q5"]]]]]],
        ]
        #expect(WikidataProvider.title(id: "Q2808", entity: person) == nil)
    }

    @Test("Accepts a film subtype it has never seen, via its director")
    func acceptsViaDirector() {
        let obscure: [String: Any] = [
            "labels": ["en": ["value": "An Obscure Film"]],
            "claims": [
                "P31": [["mainsnak": ["datavalue": ["value": ["id": "Q99999999"]]]]],
                "P57": [["mainsnak": ["datavalue": ["value": ["id": "Q123"]]]]],
            ],
        ]
        #expect(WikidataProvider.title(id: "Q1", entity: obscure)?.canonicalName == "An Obscure Film")
    }

    @Test("Recognises a television series")
    func series() {
        let show: [String: Any] = [
            "labels": ["en": ["value": "Breaking Bad"]],
            "claims": ["P31": [["mainsnak": ["datavalue": ["value": ["id": "Q5398426"]]]]]],
        ]
        #expect(WikidataProvider.title(id: "Q1079", entity: show)?.isSeries == true)
    }

    @Test("Takes the earliest release year when there are several")
    func earliestYear() {
        let claims: [String: Any] = [
            "P577": [
                ["mainsnak": ["datavalue": ["value": ["time": "+1995-03-01T00:00:00Z"]]]],
                ["mainsnak": ["datavalue": ["value": ["time": "+1994-11-18T00:00:00Z"]]]],
            ],
        ]
        #expect(WikidataProvider.year(claims: claims) == 1994)
    }
}
