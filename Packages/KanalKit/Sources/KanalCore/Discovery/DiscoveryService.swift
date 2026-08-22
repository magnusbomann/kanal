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
            serviceLimit: Int = 5
        ) {
            self.region = region
            self.language = language
            self.serviceLimit = serviceLimit
        }
    }

    private let apiKey: String?
    private let session: URLSession
    private let configuration: Configuration
    private let storage: KanalStorage

    private var shelves: [DiscoveryShelf] = []
    private static let cacheFile = "discovery.json"
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
        shelves = await storage.load([DiscoveryShelf].self, from: Self.cacheFile) ?? []
    }

    /// Refreshes if the cache is old. Returns whatever is current either way.
    @discardableResult
    public func refreshIfStale() async -> [DiscoveryShelf] {
        let newest = shelves.map(\.fetchedAt).max()
        if let newest, Date.now.timeIntervalSince(newest) < Self.maximumAge {
            return shelves
        }
        return await refresh()
    }

    @discardableResult
    public func refresh() async -> [DiscoveryShelf] {
        guard isAvailable else { return shelves }

        var built: [DiscoveryShelf] = []
        for kind in [MediaKind.movie, .series] {
            if let trending = await fetchTrending(kind: kind) { built.append(trending) }
            if let fresh = await fetchNewReleases(kind: kind) { built.append(fresh) }
        }

        // Streaming services, most prominent in this country first.
        for service in await fetchServices().prefix(configuration.serviceLimit) {
            for kind in [MediaKind.movie, .series] {
                if let shelf = await fetchService(service, kind: kind) { built.append(shelf) }
            }
        }

        guard !built.isEmpty else { return shelves }
        shelves = built
        await storage.save(built, to: Self.cacheFile)
        return built
    }

    // MARK: - Requests

    struct Service: Sendable, Hashable {
        let id: Int
        let name: String
    }

    private func fetchTrending(kind: MediaKind) async -> DiscoveryShelf? {
        let path = kind == .series ? "trending/tv/week" : "trending/movie/week"
        guard let titles = await fetchTitles(path: path, query: [], isSeries: kind == .series),
              !titles.isEmpty
        else { return nil }
        return DiscoveryShelf(
            id: "trending.\(kind.rawValue)", source: .trending, kind: kind, titles: titles
        )
    }

    /// Released in the last few months, ordered by how much attention they got.
    private func fetchNewReleases(kind: MediaKind) async -> DiscoveryShelf? {
        let isSeries = kind == .series
        let path = isSeries ? "discover/tv" : "discover/movie"
        let since = Date.now.addingTimeInterval(-120 * 24 * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .gmt

        let dateKey = isSeries ? "first_air_date.gte" : "primary_release_date.gte"
        guard let titles = await fetchTitles(
            path: path,
            query: [
                URLQueryItem(name: dateKey, value: formatter.string(from: since)),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "vote_count.gte", value: "20"),
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
        return rows
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
    }

    private func fetchService(_ service: Service, kind: MediaKind) async -> DiscoveryShelf? {
        let isSeries = kind == .series
        guard let titles = await fetchTitles(
            path: isSeries ? "discover/tv" : "discover/movie",
            query: [
                URLQueryItem(name: "watch_region", value: configuration.region),
                URLQueryItem(name: "with_watch_providers", value: String(service.id)),
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
