import Foundation

/// Outside knowledge about films and shows, cached and rate-aware.
///
/// Two jobs, and the first one is the point of the whole layer:
///
/// 1. **Translating a search.** Someone types "Løvenes konge"; the provider
///    listed "The Lion King". Rather than pre-translating a 50,000-entry
///    library — a hundred thousand requests nobody will wait for and nobody
///    should pay for — Kanal translates the *query*, once, and searches the
///    local index again. One request, and it covers the whole catalogue from
///    the first launch.
///
/// 2. **Artwork and plots**, resolved only for what is actually on screen, so
///    the cost is bounded by what a person looks at rather than by how large
///    their subscription is.
///
/// Providers are tried in order and the first confident answer wins, so the
/// free source carries the common case and a paid one is never on the critical
/// path.
public actor MetadataService {

    private var providers: [MetadataProvider]
    private let storage: KanalStorage

    /// Query → the other names that query goes by.
    private var resolutions: [String: Resolution] = [:]
    /// Library entry → what we identified it as.
    private var identified: [String: ResolvedTitle] = [:]
    /// Things no provider knew, so we stop asking.
    private var misses: Set<String> = []

    private var saveTask: Task<Void, Never>?
    /// Guards against a scrolling grid firing dozens of parallel lookups.
    private var inFlight: Set<String> = []

    struct Resolution: Codable, Sendable {
        var spellings: [String]
        var displayTitle: String?
        var resolvedAt: Date
    }

    private static let resolutionsFile = "title-resolutions.json"
    private static let identifiedFile = "title-identified.json"

    /// - Parameter tmdbAPIKey: optional. Present only adds artwork; Kanal's
    ///   search works identically without it.
    public init(
        tmdbAPIKey: String? = nil,
        storage: KanalStorage = .shared,
        providers: [MetadataProvider]? = nil
    ) {
        self.storage = storage
        if let providers {
            self.providers = providers
        } else {
            // Ordered cheapest-first: the bundled pack answers offline and
            // instantly, and only what it does not know reaches the network.
            var built: [MetadataProvider] = []
            let bundled = BundledTitleProvider()
            if bundled.isLoaded { built.append(bundled) }
            built.append(WikidataProvider())
            if let tmdbAPIKey, !tmdbAPIKey.isEmpty {
                built.append(TMDBProvider(apiKey: tmdbAPIKey))
            }
            self.providers = built
        }
    }

    public var providerNames: [String] { providers.map(\.providerName) }

    /// Replaces the provider chain — used by tests, and by anything that turns
    /// an optional provider on or off at runtime.
    public func replaceProviders(_ providers: [MetadataProvider]) {
        self.providers = providers
    }
    public var hasArtworkProvider: Bool { providers.contains { $0.providesArtwork } }

    public func loadCaches() async {
        resolutions = await storage.load([String: Resolution].self, from: Self.resolutionsFile) ?? [:]
        identified = await storage.load([String: ResolvedTitle].self, from: Self.identifiedFile) ?? [:]
    }

    // MARK: - Translating a query

    /// Other names the thing someone typed might be listed under.
    ///
    /// An empty result is the normal, quiet failure mode: no network, nothing
    /// matched, or nothing confident enough. Callers fall back to local results.
    public func alternativeSpellings(for query: String) async -> (spellings: [String], matched: String?) {
        let key = SearchNormalizer.normalize(query)
        guard key.count >= 3 else { return ([], nil) }

        if let cached = resolutions[key] { return (cached.spellings, cached.displayTitle) }
        guard !misses.contains(key), !inFlight.contains(key) else { return ([], nil) }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        // A provider that failed has not told us the title is unknown, so a
        // failure must never be remembered as one.
        var anyProviderFailed = false

        for provider in providers {
            let candidates: [ResolvedTitle]
            do {
                candidates = try await provider.lookup(name: query, year: nil, isSeries: nil)
            } catch {
                anyProviderFailed = true
                continue
            }
            guard !candidates.isEmpty else { continue }

            // Only trust a candidate whose own name is what was typed. A wrong
            // translation is worse than none — it sends someone to the wrong
            // film with no clue why.
            guard let best = candidates.first(where: { $0.matches(normalizedQuery: key) })
                ?? candidates.first(where: { $0.loosonMatches(normalizedQuery: key) })
            else { continue }

            let spellings = best.allNames.filter { SearchNormalizer.normalize($0) != key }
            guard !spellings.isEmpty else { continue }

            resolutions[key] = Resolution(
                spellings: spellings,
                displayTitle: best.canonicalName,
                resolvedAt: .now
            )
            scheduleSave()
            return (spellings, best.canonicalName)
        }

        if !anyProviderFailed { misses.insert(key) }
        return ([], nil)
    }

    // MARK: - Artwork and plots

    /// What we believe a library entry is, or nil when no provider could say
    /// confidently. Only providers that carry artwork are asked.
    public func metadata(for item: MediaItem) async -> ResolvedTitle? {
        guard item.kind != .liveTV else { return nil }
        let name = item.seriesName ?? item.title
        let key = identityKey(title: name, year: item.year)

        if let cached = identified[key] { return cached }
        guard !misses.contains(key), !inFlight.contains(key) else { return nil }

        let artworkProviders = providers.filter(\.providesArtwork)
        guard !artworkProviders.isEmpty else { return nil }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var anyProviderFailed = false
        for provider in artworkProviders {
            let candidates: [ResolvedTitle]
            do {
                candidates = try await provider.lookup(
                    name: name, year: item.year, isSeries: item.kind == .series
                )
            } catch {
                anyProviderFailed = true
                continue
            }
            guard let best = bestMatch(for: name, year: item.year, among: candidates) else {
                continue
            }
            identified[key] = best
            scheduleSave()
            return best
        }

        if !anyProviderFailed { misses.insert(key) }
        return nil
    }

    /// Requires the names to agree, and lets the year confirm or veto.
    /// Anything weaker is left unmatched on purpose.
    func bestMatch(for name: String, year: Int?, among candidates: [ResolvedTitle]) -> ResolvedTitle? {
        let needle = SearchNormalizer.normalize(name)
        guard !needle.isEmpty else { return nil }

        var best: (title: ResolvedTitle, score: Int)?
        for candidate in candidates {
            var score = 0
            for title in candidate.allNames {
                let normalized = SearchNormalizer.normalize(title)
                if normalized == needle {
                    score = max(score, 100)
                } else if normalized.hasPrefix(needle) || needle.hasPrefix(normalized) {
                    score = max(score, 60)
                }
            }
            guard score > 0 else { continue }
            if let year, let candidateYear = candidate.year {
                // A year that disagrees outweighs a name that matches: "Frost"
                // from 1950 is not the "Frost" from 2013, and the wrong poster
                // is worse than the provider's own thumbnail.
                score += abs(candidateYear - year) <= 1 ? 25 : -60
            }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        guard let best, best.score >= 60 else { return nil }
        return best.title
    }

    private func identityKey(title: String, year: Int?) -> String {
        let normalized = SearchNormalizer.normalize(title)
        return year.map { "\(normalized)|\($0)" } ?? normalized
    }

    /// Lookups arrive in bursts as a grid scrolls; write once when it settles.
    private func scheduleSave() {
        saveTask?.cancel()
        let resolutions = resolutions
        let identified = identified
        saveTask = Task { [storage] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await storage.save(resolutions, to: Self.resolutionsFile)
            await storage.save(identified, to: Self.identifiedFile)
        }
    }
}
