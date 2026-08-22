import Foundation
import Testing
@testable import KanalCore

@Suite("Bundled title packs")
struct BundledTitleTests {

    let provider = BundledTitleProvider(packs: [
        "nb": [
            "Løvenes konge": "The Lion King",
            "Gudfaren": "The Godfather",
            "Oppdrag Nemo": "Finding Nemo",
        ],
        "de": ["Der König der Löwen": "The Lion King"],
    ])

    @Test("Answers from the pack with no network")
    func answersOffline() async throws {
        let results = try await provider.lookup(name: "Løvenes konge", year: nil, isSeries: nil)
        let match = try #require(results.first)
        #expect(match.canonicalName == "The Lion King")
        #expect(match.allNames.contains("Løvenes konge"))
    }

    @Test("Folds the letters people type without", arguments: [
        "lovenes konge", "LØVENES KONGE", "Løvenes  Konge",
    ])
    func folded(query: String) async throws {
        let results = try await provider.lookup(name: query, year: nil, isSeries: nil)
        #expect(results.first?.canonicalName == "The Lion King")
    }

    @Test("Searches every pack the device asked for")
    func multipleLanguages() async throws {
        let german = try await provider.lookup(name: "Der König der Löwen", year: nil, isSeries: nil)
        #expect(german.first?.canonicalName == "The Lion King")
    }

    @Test("Says nothing rather than guessing")
    func unknown() async throws {
        #expect(try await provider.lookup(name: "Zzzq Flurb", year: nil, isSeries: nil).isEmpty)
        #expect(try await provider.lookup(name: "", year: nil, isSeries: nil).isEmpty)
    }

    @Test("A missing pack is not an error, only a quieter provider")
    func missingPack() async throws {
        let empty = BundledTitleProvider(packs: [:])
        #expect(empty.isLoaded == false)
        #expect(try await empty.lookup(name: "Løvenes konge", year: nil, isSeries: nil).isEmpty)
    }

    /// The point of the pack: the network provider is never reached for a
    /// title the app already ships an answer for.
    @Test("A bundled hit never reaches the network")
    func shortCircuitsNetwork() async {
        let counting = CountingProvider()
        let service = MetadataService(
            storage: KanalStorage(
                directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            providers: [provider, counting]
        )
        let result = await service.alternativeSpellings(for: "Løvenes konge")
        #expect(result.matched == "The Lion King")
        #expect(await counting.calls == 0)
    }
}

@Suite("The shipped title pack")
struct ShippedPackTests {

    let provider = BundledTitleProvider(languages: ["nb"])

    @Test("The pack is actually in the bundle")
    func packIsBundled() {
        #expect(provider.isLoaded, "no title pack found in KanalCore's resources")
        #expect(provider.pairCount > 1000, "pack looks truncated: \(provider.pairCount) pairs")
    }

    @Test("Real Norwegian titles resolve with no network", arguments: [
        ("Løvenes konge", "The Lion King"),
        ("Gudfaren", "The Godfather"),
        ("Askepott", "Cinderella"),
        ("Oppdrag Nemo", "Finding Nemo"),
        ("Gjøkeredet", "One Flew Over the Cuckoo's Nest"),
        ("lovenes konge", "The Lion King"),
    ])
    func resolvesOffline(query: String, expected: String) async throws {
        let results = try await provider.lookup(name: query, year: nil, isSeries: nil)
        #expect(results.first?.canonicalName == expected)
    }

    /// Titles spelled the same in both languages are deliberately absent — the
    /// local index already finds those, and storing them would only bloat the
    /// pack.
    @Test("Identical titles are left out on purpose", arguments: [
        "Ratatouille", "Django Unchained",
    ])
    func identicalTitlesAbsent(query: String) async throws {
        #expect(try await provider.lookup(name: query, year: nil, isSeries: nil).isEmpty)
    }
}
