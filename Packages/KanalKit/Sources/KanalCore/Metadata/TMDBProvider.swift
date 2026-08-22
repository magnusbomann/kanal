import Foundation

/// TMDB, behind the common provider interface.
///
/// Optional on purpose. Kanal works fully without it — Wikidata answers the
/// question that matters — and TMDB is only worth its licence cost for what
/// Wikidata cannot give: real poster and backdrop artwork.
public struct TMDBProvider: MetadataProvider {

    public var providerName: String { "TMDB" }
    public var providesArtwork: Bool { true }

    private let client: TMDBClient

    public init?(apiKey: String, session: URLSession = .shared) {
        guard let client = TMDBClient(apiKey: apiKey, session: session) else { return nil }
        self.client = client
    }

    public func lookup(name: String, year: Int?, isSeries: Bool?) async throws -> [ResolvedTitle] {
        // When the caller does not know, ask both — a provider's "series"
        // folder routinely contains films and the other way round.
        let kinds: [Bool] = isSeries.map { [$0] } ?? [false, true]

        var results: [ResolvedTitle] = []
        for kind in kinds {
            let candidates = (try? await client.search(name, year: year, isSeries: kind)) ?? []
            for candidate in candidates.prefix(5) {
                let detailed = (try? await client.details(id: candidate.id, isSeries: kind)) ?? candidate
                results.append(Self.resolved(detailed))
            }
        }
        return results
    }

    static func resolved(_ title: TMDBTitle) -> ResolvedTitle {
        ResolvedTitle(
            id: "tmdb:\(title.id)",
            canonicalName: title.originalTitle,
            localizedName: title.localizedTitle == title.originalTitle ? nil : title.localizedTitle,
            allNames: title.allTitles,
            year: title.year,
            isSeries: title.isSeries,
            posterURL: title.posterURL(),
            overview: title.overview
        )
    }
}
