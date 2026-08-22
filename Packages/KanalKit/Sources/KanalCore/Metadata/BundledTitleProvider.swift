import Foundation

/// Answers the common case instantly, from a file that ships with the app.
///
/// The observation this rests on: **only titles that differ from English are
/// worth storing.** "Ratatouille" and "Django Unchained" are spelled the same
/// everywhere, and the local search index already finds those. The pairs that
/// need shipping are only the ones where the viewer's name for a film is not
/// the name their provider used — and that is a small, static set per language.
///
/// The consequence is the one that matters on a TV in a living room: the
/// common case costs no request, no key, no rate limit and no waiting, and it
/// works with the network down. Live Wikidata stays behind this for the long
/// tail.
public struct BundledTitleProvider: MetadataProvider {

    public var providerName: String { "Bundled titles" }
    public var providesArtwork: Bool { false }

    private let packs: [Pack]

    struct Pack: Sendable {
        let language: String
        /// Normalised localised title → the title a provider is likely to use.
        let titles: [String: String]
    }

    public init(languages: [String] = PreferredLanguages.codes()) {
        self.packs = languages.compactMap(Self.loadPack)
    }

    /// For tests, and for anything that wants to supply its own data.
    public init(packs: [String: [String: String]]) {
        self.packs = packs.map { language, titles in
            Pack(
                language: language,
                titles: Dictionary(
                    titles.map { (SearchNormalizer.normalize($0.key), $0.value) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }
    }

    /// Whether any pack was found. False simply means the live provider does
    /// all the work — never an error.
    public var isLoaded: Bool { !packs.isEmpty }

    public var pairCount: Int { packs.reduce(0) { $0 + $1.titles.count } }

    public func lookup(name: String, year: Int?, isSeries: Bool?) async throws -> [ResolvedTitle] {
        let key = SearchNormalizer.normalize(name)
        guard !key.isEmpty else { return [] }

        var results: [ResolvedTitle] = []
        for pack in packs {
            guard let english = pack.titles[key] else { continue }
            results.append(
                ResolvedTitle(
                    id: "bundled:\(pack.language):\(key)",
                    canonicalName: english,
                    localizedName: name,
                    allNames: [english, name],
                    year: nil,
                    isSeries: isSeries ?? false
                )
            )
        }
        return results
    }

    // MARK: - Loading

    private static func loadPack(for language: String) -> Pack? {
        guard let url = Bundle.module.url(
            forResource: language,
            withExtension: "json",
            subdirectory: "titles"
        ),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }

        // Normalised once at load, so a lookup is a single dictionary hit even
        // while someone is typing.
        var titles: [String: String] = [:]
        titles.reserveCapacity(raw.count)
        for (localized, english) in raw {
            titles[SearchNormalizer.normalize(localized)] = english
        }
        return Pack(language: language, titles: titles)
    }
}
