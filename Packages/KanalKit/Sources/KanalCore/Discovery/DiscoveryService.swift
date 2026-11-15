import Foundation

/// What the wider world is watching, so the good things sit at the top.
///
/// A provider's catalogue arrives in whatever order the panel felt like, which
/// is why browsing one lands you in a random action film. TMDB knows what is
/// popular, what is new, and what each streaming service carries in a given
/// country. Kanal uses that only as an *ordering* over the library someone
/// already has — nothing is ever shown that their provider does not carry.
///
/// Fetched once a day and cached, because a "popular this week" list does not
/// change between launches and nobody should wait for it.
public actor DiscoveryService {

    public struct Configuration: Sendable {
        /// Two-letter region for availability, e.g. "NO".
        public var region: String
        /// Language for titles and plots.
        public var language: String
        /// How many streaming services to build shelves for.
        public var serviceLimit: Int

        public init(
            region: String = Locale.current.region?.identifier ?? "US",
            language: String = PreferredLanguages.primaryTag(),
            serviceLimit: Int = 6
        ) {
            self.region = region
            self.language = PreferredLanguages.tmdbTag(language)
            self.serviceLimit = serviceLimit
        }
    }

    private let apiKey: String?
    private let session: URLSession
    private let configuration: Configuration
    private let storage: KanalStorage

    private var shelves: [DiscoveryShelf] = []
    /// Who the current `shelves` were fetched for. Swapped by `use(_:)`.
    private var audience: DiscoveryAudience = .everyone
    // v2 guarantees subscription-only service rows and curated provider ids;
    // do not keep a pre-v2 rental-store cache alive for another 24 hours.
    /// Discovery titles are localized by TMDB. A single global cache would
    /// leave Norwegian titles on screen after switching the app to Spanish.
    private var cacheFile: String {
        let scope = "\(configuration.language)-\(configuration.region)-\(audience.cacheScope)"
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "discovery-v3-\(scope).json"
    }
    /// A weekly list does not need refreshing more than daily.
    private static let maximumAge: TimeInterval = 24 * 3600

    public init(
        apiKey: String?,
        configuration: Configuration = Configuration(),
        storage: KanalStorage = .shared,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.configuration = configuration
        self.storage = storage
        self.session = session
    }

    public var isAvailable: Bool { apiKey?.isEmpty == false }

    public var cached: [DiscoveryShelf] { shelves }

    public func loadCache() async {
        shelves = await storage.load([DiscoveryShelf].self, from: cacheFile) ?? []
    }

    /// Points the service at one audience and loads whatever was cached for
    /// them. Returns those rows so a caller can show something immediately
    /// rather than waiting on the network.
    ///
    /// Each audience keeps its own cache file. Sharing one would mean a
    /// household that switches from a grown-up to a child sees the grown-up's
    /// recommendations until the daily refresh comes round.
    @discardableResult
    public func use(_ audience: DiscoveryAudience) async -> [DiscoveryShelf] {
        guard audience != self.audience else { return shelves }
        self.audience = audience
        await loadCache()
        return shelves
    }

    /// Refreshes if the cache is old. Returns whatever is current either way.
    @discardableResult
    public func refreshIfStale() async -> [DiscoveryShelf] {
        // A partially refreshed row keeps its older timestamp so the next app
        // start retries it instead of treating one successful request as a
        // fresh cache for every service.
        let oldest = shelves.map(\.fetchedAt).min()
        if let oldest, Date.now.timeIntervalSince(oldest) < Self.maximumAge {
            return shelves
        }
        return await refresh()
    }

    @discardableResult
    public func refresh() async -> [DiscoveryShelf] {
        guard isAvailable else { return shelves }

        // Provider discovery and the four editorial rows can travel together.
        // Once the provider ids arrive, their film/show requests travel
        // together too. Stable order is restored from the request indices.
        async let servicesRequest = fetchServices()
        let baseRows = await fetchBaseShelves()
        let services = await servicesRequest
        let serviceRows = await fetchServiceShelves(services)
        let refreshed = baseRows + serviceRows
        guard !refreshed.isEmpty else { return shelves }

        let baseIDs = [
            "trending.\(MediaKind.movie.rawValue)",
            "new.\(MediaKind.movie.rawValue)",
            "trending.\(MediaKind.series.rawValue)",
            "new.\(MediaKind.series.rawValue)",
        ]
        var requestedIDs = baseIDs
        for service in services {
            requestedIDs.append("service.\(service.id).\(MediaKind.movie.rawValue)")
            requestedIDs.append("service.\(service.id).\(MediaKind.series.rawValue)")
        }
        // If the provider-list request itself failed, retain the previous
        // service rows rather than interpreting a network error as removal.
        if services.isEmpty {
            requestedIDs.append(contentsOf: shelves.compactMap { shelf in
                if case .service = shelf.source { shelf.id } else { nil }
            })
        }

        let old = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
        var seen = Set<String>()
        let merged = requestedIDs.compactMap { id -> DiscoveryShelf? in
            guard seen.insert(id).inserted else { return nil }
            return new[id] ?? old[id]
        }
        guard !merged.isEmpty else { return shelves }
        shelves = merged
        await storage.save(merged, to: cacheFile)
        return merged
    }

    // MARK: - Requests

    struct Service: Sendable, Hashable {
        let id: Int
        let name: String
    }

    private func fetchBaseShelves() async -> [DiscoveryShelf] {
        await withTaskGroup(of: (Int, DiscoveryShelf?).self) { group in
            group.addTask { [self] in (0, await fetchTrending(kind: .movie)) }
            group.addTask { [self] in (1, await fetchNewReleases(kind: .movie)) }
            group.addTask { [self] in (2, await fetchTrending(kind: .series)) }
            group.addTask { [self] in (3, await fetchNewReleases(kind: .series)) }

            var rows: [(Int, DiscoveryShelf)] = []
            for await (order, shelf) in group {
                if let shelf { rows.append((order, shelf)) }
            }
            return rows.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func fetchServiceShelves(_ services: [Service]) async -> [DiscoveryShelf] {
        await withTaskGroup(of: (Int, DiscoveryShelf?).self) { group in
            for (serviceIndex, service) in services.enumerated() {
                group.addTask { [self] in
                    (serviceIndex * 2, await fetchService(service, kind: .movie))
                }
                group.addTask { [self] in
                    (serviceIndex * 2 + 1, await fetchService(service, kind: .series))
                }
            }

            var rows: [(Int, DiscoveryShelf)] = []
            for await (order, shelf) in group {
                if let shelf { rows.append((order, shelf)) }
            }
            return rows.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// What the world is watching — or, for a child, what the world's children
    /// are watching.
    ///
    /// TMDB's `trending` endpoint takes no filters at all, so an audience with
    /// a ceiling cannot use it: the list comes back as whatever is popular
    /// this week, and on a real catalogue not one of those twenty films was
    /// rated for a nine-year-old. `discover` sorted by popularity is the same
    /// question with the audience attached, and it fills the row.
    private func fetchTrending(kind: MediaKind) async -> DiscoveryShelf? {
        let isSeries = kind == .series
        let titles: [DiscoveryTitle]?

        if audience.isChildren {
            titles = await fetchTitles(
                path: isSeries ? "discover/tv" : "discover/movie",
                query: audienceQuery(isSeries: isSeries) + [
                    URLQueryItem(name: "sort_by", value: "popularity.desc"),
                    URLQueryItem(name: "vote_count.gte", value: "20"),
                ],
                isSeries: isSeries
            )
        } else {
            titles = await fetchTitles(
                path: isSeries ? "trending/tv/week" : "trending/movie/week",
                query: [],
                isSeries: isSeries
            )
        }

        guard let titles, !titles.isEmpty else { return nil }
        return DiscoveryShelf(
            id: "trending.\(kind.rawValue)", source: .trending, kind: kind, titles: titles
        )
    }

    /// The genre and certification terms this audience adds to a `discover`
    /// request. Empty for a grown-up, so their rows are exactly as before.
    private func audienceQuery(isSeries: Bool) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if let genres = isSeries ? audience.seriesGenres : audience.movieGenres {
            query.append(URLQueryItem(name: "with_genres", value: genres))
        }
        // TMDB offers no certification filter for shows; theirs is carried by
        // the audience genre and enforced afterwards by `ContentPolicy`.
        if !isSeries, let ceiling = audience.movieCertification {
            query.append(URLQueryItem(name: "certification_country", value: ceiling.country))
            query.append(URLQueryItem(name: "certification.lte", value: ceiling.code))
        }
        return query
    }

    /// Released in the last few months, ordered by how much attention they got.
    private func fetchNewReleases(kind: MediaKind) async -> DiscoveryShelf? {
        let isSeries = kind == .series
        let path = isSeries ? "discover/tv" : "discover/movie"
        // A year for children, four months for everyone else. "New" means
        // something different to the two: blockbusters turn over every few
        // weeks, children's films do not, and there are far fewer of them.
        // Measured on a real catalogue, the four-month window left the
        // strictest profiles two matching films — half of what the row needs
        // to appear at all — while a year gave the row enough to live and
        // doubled it for a nine-year-old.
        let window: TimeInterval = audience.isChildren ? 365 : 120
        let since = Date.now.addingTimeInterval(-window * 24 * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .gmt

        let dateKey = isSeries ? "first_air_date.gte" : "primary_release_date.gte"
        guard let titles = await fetchTitles(
            path: path,
            query: audienceQuery(isSeries: isSeries) + [
                URLQueryItem(name: dateKey, value: formatter.string(from: since)),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                // Children's films clear a twenty-vote bar far less often than
                // the week's blockbusters, and a well-known cartoon with
                // fifteen votes is still a better suggestion than the panel's
                // own ordering.
                URLQueryItem(
                    name: "vote_count.gte", value: audience.isChildren ? "5" : "20"
                ),
            ],
            isSeries: isSeries
        ), !titles.isEmpty else { return nil }

        return DiscoveryShelf(
            id: "new.\(kind.rawValue)", source: .newReleases, kind: kind, titles: titles
        )
    }

    private func fetchServices() async -> [Service] {
        guard let data = await get(path: "watch/providers/movie", query: [
            URLQueryItem(name: "watch_region", value: configuration.region),
        ]),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["results"] as? [[String: Any]]
        else { return [] }

        // Display priority is TMDB's own ordering of what matters in a country.
        let ranked = rows
            .compactMap { row -> (Service, Int)? in
                guard let id = row["provider_id"] as? Int,
                      let name = row["provider_name"] as? String
                else { return nil }
                let priorities = row["display_priorities"] as? [String: Int]
                let priority = priorities?[configuration.region]
                    ?? (row["display_priority"] as? Int)
                    ?? 999
                return (Service(id: id, name: name), priority)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        return Self.curatedServices(
            ranked, limit: configuration.serviceLimit, leadingWith: audience.preferredServices
        )
    }

    /// Keeps the services people recognise without losing the local ordering
    /// TMDB supplies for the viewer's country. Apple TV+ is deliberately
    /// matched by TMDB's stable provider id as well as its subscription name:
    /// some regions now display id 350 simply as "Apple TV". Provider id 2 is
    /// the similarly named rental store and must remain in regional order.
    static func curatedServices(
        _ ranked: [Service],
        limit: Int,
        leadingWith leading: [String] = []
    ) -> [Service] {
        guard limit > 0 else { return [] }
        // Whoever the audience asked for comes before the general ordering —
        // for a child that is Disney, which a parent looks for by name and
        // which carried more of this catalogue than Netflix did.
        let audiencePreferences: [(Service) -> Bool] = leading.map { wanted in
            { $0.name.localizedCaseInsensitiveContains(wanted) }
        }
        let preferred: [(Service) -> Bool] = audiencePreferences + [
            { $0.name.localizedCaseInsensitiveContains("Netflix") },
            {
                let name = $0.name.lowercased()
                return name == "max" || name.contains("hbo max")
            },
            {
                let name = $0.name.lowercased()
                return $0.id == 350
                    || name.contains("apple tv+")
                    || name.contains("apple tv plus")
            },
        ]

        var result: [Service] = []
        var seen = Set<Int>()
        for matches in preferred {
            if let service = ranked.first(where: matches), seen.insert(service.id).inserted {
                result.append(service)
            }
        }
        for service in ranked where seen.insert(service.id).inserted {
            result.append(service)
        }
        return Array(result.prefix(limit))
    }

    private func fetchService(_ service: Service, kind: MediaKind) async -> DiscoveryShelf? {
        let isSeries = kind == .series
        guard let titles = await fetchTitles(
            path: isSeries ? "discover/tv" : "discover/movie",
            query: audienceQuery(isSeries: isSeries) + [
                URLQueryItem(name: "watch_region", value: configuration.region),
                URLQueryItem(name: "with_watch_providers", value: String(service.id)),
                URLQueryItem(name: "with_watch_monetization_types", value: "flatrate"),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
            ],
            isSeries: isSeries
        ), !titles.isEmpty else { return nil }

        return DiscoveryShelf(
            id: "service.\(service.id).\(kind.rawValue)",
            source: .service(id: service.id, name: service.name),
            kind: kind,
            titles: titles
        )
    }

    private func fetchTitles(
        path: String, query: [URLQueryItem], isSeries: Bool
    ) async -> [DiscoveryTitle]? {
        guard let data = await get(path: path, query: query),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["results"] as? [[String: Any]]
        else { return nil }
        return rows.compactMap { Self.title(from: $0, isSeries: isSeries) }
    }

    static func title(from row: [String: Any], isSeries: Bool) -> DiscoveryTitle? {
        guard let id = row["id"] as? Int else { return nil }
        let localized = row[isSeries ? "name" : "title"] as? String
        let original = row[isSeries ? "original_name" : "original_title"] as? String
        let names = [localized, original].compactMap { $0 }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }

        let dateKey = isSeries ? "first_air_date" : "release_date"
        return DiscoveryTitle(
            id: id,
            names: names,
            year: (row[dateKey] as? String).flatMap { Int($0.prefix(4)) },
            isSeries: isSeries,
            posterPath: row["poster_path"] as? String,
            overview: (row["overview"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            popularity: (row["popularity"] as? Double) ?? 0
        )
    }

    private func get(path: String, query: [URLQueryItem]) async -> Data? {
        guard let apiKey, !apiKey.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        components.queryItems = query + [
            URLQueryItem(name: "language", value: configuration.language),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "accept")
        // A v4 read token authenticates by header; a v3 key by query parameter.
        if apiKey.hasPrefix("ey"), apiKey.contains(".") {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            components.queryItems?.append(URLQueryItem(name: "api_key", value: apiKey))
            guard let keyed = components.url else { return nil }
            request.url = keyed
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }
}
