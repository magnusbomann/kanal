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
    /// Kept alongside the providers because detail requests are a different
    /// shape: one title at a time, only once someone has shown interest.
    private var detailClient: TMDBClient?
    private let storage: KanalStorage

    /// Query → the other names that query goes by.
    private var resolutions: [String: Resolution] = [:]
    /// Library entry → what we identified it as.
    private var identified: [String: ResolvedTitle] = [:]
    /// Things no provider knew, so we stop asking.
    private var misses: Set<String> = []

    private var saveTask: Task<Void, Never>?
    private var details: [Int: TitleDetails] = [:]
    private var people: [Int: PersonProfile] = [:]
    private var detailsInFlight: Set<Int> = []
    /// Guards against a scrolling grid firing dozens of parallel lookups.
    private var inFlight: Set<String> = []

    struct Resolution: Codable, Sendable {
        var spellings: [String]
        var displayTitle: String?
        var resolvedAt: Date
    }

    private static let resolutionsFile = "title-resolutions.json"
    private static let identifiedFile = "title-identified.json"
    private static let detailsFile = "title-details.json"
    private static let peopleFile = "people.json"

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
            if let tmdbAPIKey, let tmdb = TMDBProvider(apiKey: tmdbAPIKey) {
                built.append(tmdb)
            }
            if let tmdbAPIKey {
                detailClient = TMDBClient(apiKey: tmdbAPIKey)
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
        details = await storage.load([Int: TitleDetails].self, from: Self.detailsFile) ?? [:]
        people = await storage.load([Int: PersonProfile].self, from: Self.peopleFile) ?? [:]
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

    // MARK: - Detail screen

    /// Whether a detail screen has anything to show at all.
    public var canShowDetails: Bool { detailClient != nil }

    /// Everything about one library entry, for the screen shown before playing.
    ///
    /// Two steps: work out which film or show this is, then fetch its record.
    /// Both halves are cached, so opening the same title twice costs nothing.
    public func details(for item: MediaItem) async -> TitleDetails? {
        guard let client = detailClient, item.kind != .liveTV else { return nil }
        guard let identified = await metadata(for: item),
              let tmdbID = Self.tmdbID(from: identified.id)
        else { return nil }

        if let cached = details[tmdbID] { return cached }
        guard !detailsInFlight.contains(tmdbID) else { return nil }
        detailsInFlight.insert(tmdbID)
        defer { detailsInFlight.remove(tmdbID) }

        guard let fetched = try? await client.fullDetails(
            id: tmdbID, isSeries: item.kind == .series
        ) else { return nil }

        details[tmdbID] = fetched
        scheduleSave()
        return fetched
    }

    /// One of the people in it.
    public func person(id: Int) async -> PersonProfile? {
        if let cached = people[id] { return cached }
        guard let client = detailClient,
              let fetched = try? await client.person(id: id)
        else { return nil }
        people[id] = fetched
        scheduleSave()
        return fetched
    }

    /// Provider ids look like "tmdb:8587"; anything else is not one.
    static func tmdbID(from identifier: String) -> Int? {
        guard identifier.hasPrefix("tmdb:") else { return nil }
        return Int(identifier.dropFirst("tmdb:".count))
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

        // Artwork databases search their own titles, not the viewer's. TMDB
        // will not find "Biler" however hard it looks, but it knows "Cars" —
        // so the free tier canonicalises the name before the paid one is asked.
        // Both spellings are then tried, because a Norwegian film really is
        // filed under its Norwegian name.
        let canonical = await alternativeSpellings(for: name).matched
        let attempts = [canonical, name].compactMap { $0 }.reduce(into: [String]()) { unique, value in
            if !unique.contains(value) { unique.append(value) }
        }

        var anyProviderFailed = false
        for provider in artworkProviders {
            for attempt in attempts {
                let candidates: [ResolvedTitle]
                do {
                    candidates = try await provider.lookup(
                        name: attempt, year: item.year, isSeries: item.kind == .series
                    )
                } catch {
                    anyProviderFailed = true
                    continue
                }
                guard let best = bestMatch(for: attempt, year: item.year, among: candidates) else {
                    continue
                }
                identified[key] = best
                scheduleSave()
                return best
            }
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
        let details = details
        let people = people
        saveTask = Task { [storage] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await storage.save(resolutions, to: Self.resolutionsFile)
            await storage.save(identified, to: Self.identifiedFile)
            await storage.save(details, to: Self.detailsFile)
            await storage.save(people, to: Self.peopleFile)
        }
    }
}
