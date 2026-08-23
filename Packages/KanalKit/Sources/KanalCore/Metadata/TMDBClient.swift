import Foundation

/// A film or show as TMDB knows it.
public struct TMDBTitle: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var isSeries: Bool
    /// Title in the language we asked for — Norwegian, when TMDB has one.
    public var localizedTitle: String
    /// The title it was released under originally.
    public var originalTitle: String
    /// Every other name it goes by, across the countries TMDB tracks.
    public var alternateTitles: [String]
    public var overview: String?
    public var year: Int?
    public var posterPath: String?
    public var backdropPath: String?
    public var voteAverage: Double?

    /// Everything this title can be called, deduplicated.
    public var allTitles: [String] {
        var seen = Set<String>()
        return ([localizedTitle, originalTitle] + alternateTitles).filter { title in
            let key = SearchNormalizer.normalize(title)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    public func posterURL(width: Int = 500) -> URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w\(width)\($0)") }
    }

    public func backdropURL(width: Int = 780) -> URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w\(width)\($0)") }
    }
}

/// Reads film and series metadata from TMDB.
///
/// Used two ways. Forwards, to give a library entry a real poster and plot.
/// Backwards — the more important one — to answer "what is 'Løvenes konge'?"
/// so a search in Norwegian can be matched against a provider list written in
/// English.
public struct TMDBClient: Sendable {

    public enum Failure: LocalizedError {
        case noAPIKey
        case rateLimited
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .noAPIKey: String(localized: CoreStrings.noAPIKey)
            case .rateLimited: String(localized: CoreStrings.rateLimited)
            case .transport(let message): message
            }
        }
    }

    /// TMDB issues two kinds of credential and they authenticate differently.
    ///
    /// A v3 key is 32 hex characters passed as a query parameter; a v4 read
    /// access token is a JWT passed as a bearer header. Both work against the
    /// same `/3/` endpoints, so the only thing that changes is how the request
    /// is signed — and guessing wrong fails with a 401 that reads like a bad
    /// key rather than a bad scheme.
    enum Credential: Sendable, Equatable {
        case apiKey(String)
        case bearerToken(String)

        /// Detected from the shape, so callers never have to say which they
        /// pasted. Whitespace is stripped: tokens are long enough that people
        /// paste them wrapped across lines.
        init?(_ raw: String) {
            let value = raw.components(separatedBy: .whitespacesAndNewlines).joined()
            guard !value.isEmpty else { return nil }
            if value.hasPrefix("ey"), value.contains(".") {
                self = .bearerToken(value)
            } else {
                self = .apiKey(value)
            }
        }
    }

    private let credential: Credential
    private let session: URLSession
    /// The language localised titles and plots come back in.
    private let language: String

    public init?(
        apiKey: String,
        language: String = PreferredLanguages.primaryTag(),
        session: URLSession = .shared
    ) {
        guard let credential = Credential(apiKey) else { return nil }
        self.credential = credential
        self.session = session
        self.language = language
    }

    // MARK: - Search

    /// Finds titles matching a name, in the given language.
    ///
    /// Searched twice — once in the viewer's language, once with no language
    /// hint — because TMDB's index answers a localised title only when asked in
    /// that language, and answers obscure original titles better when not.
    public func search(_ name: String, year: Int? = nil, isSeries: Bool) async throws -> [TMDBTitle] {
        let path = isSeries ? "search/tv" : "search/movie"
        var query = [URLQueryItem(name: "query", value: name)]
        if let year {
            query.append(URLQueryItem(name: isSeries ? "first_air_date_year" : "year", value: String(year)))
        }

        async let localized = results(path: path, query: query + [.init(name: "language", value: language)], isSeries: isSeries)
        async let neutral = results(path: path, query: query, isSeries: isSeries)

        var merged: [TMDBTitle] = []
        var seen = Set<Int>()
        for title in try await localized + neutral where seen.insert(title.id).inserted {
            merged.append(title)
        }
        return merged
    }

    /// Full record for one title, including every alternate name.
    public func details(id: Int, isSeries: Bool) async throws -> TMDBTitle? {
        let path = isSeries ? "tv/\(id)" : "movie/\(id)"
        let data = try await get(path: path, query: [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "alternative_titles"),
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var title = Self.title(from: root, isSeries: isSeries)

        // Movies nest under "titles", series under "results". Same idea, and
        // TMDB has never unified them.
        let container = root["alternative_titles"] as? [String: Any]
        let rows = (container?["titles"] as? [[String: Any]])
            ?? (container?["results"] as? [[String: Any]])
            ?? []
        title?.alternateTitles = rows.compactMap { $0["title"] as? String }

        // Most films have no plot written in most languages, and TMDB answers
        // that with an empty string rather than falling back. An English plot
        // tells you what the film is; a blank space tells you nothing.
        if title?.overview == nil, !language.hasPrefix("en") {
            title?.overview = try? await englishOverview(path: path)
        }
        return title
    }

    private func englishOverview(path: String) async throws -> String? {
        let data = try await get(path: path, query: [
            URLQueryItem(name: "language", value: "en-US"),
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let overview = root["overview"] as? String,
              !overview.isEmpty
        else { return nil }
        return overview
    }

    // MARK: - Certifications

    /// The age limit a national film board gave this title.
    ///
    /// TMDB files these two different ways — films under release dates per
    /// country, series under content ratings — and neither endpoint accepts a
    /// country filter, so the whole set comes back and is picked from here.
    ///
    /// - Parameter countries: ISO countries in order of preference. The first
    ///   one that rated the title wins, so a Norwegian viewer gets
    ///   Medietilsynet's answer where there is one and a neighbouring board's
    ///   otherwise.
    public func certification(
        id: Int, isSeries: Bool, preferring countries: [String]
    ) async throws -> (code: String, country: String)? {
        let path = isSeries ? "tv/\(id)/content_ratings" : "movie/\(id)/release_dates"
        let data = try await get(path: path, query: [])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["results"] as? [[String: Any]]
        else { return nil }

        var byCountry: [String: String] = [:]
        for row in rows {
            guard let country = (row["iso_3166_1"] as? String)?.uppercased() else { continue }
            let code: String?
            if isSeries {
                code = row["rating"] as? String
            } else {
                let releases = row["release_dates"] as? [[String: Any]] ?? []
                code = releases
                    .compactMap { $0["certification"] as? String }
                    .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            guard let code, !code.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            byCountry[country] = code
        }

        for country in countries.map({ $0.uppercased() }) {
            if let code = byCountry[country] { return (code, country) }
        }
        return nil
    }

    // MARK: - Plumbing

    private func results(path: String, query: [URLQueryItem], isSeries: Bool) async throws -> [TMDBTitle] {
        let data = try await get(path: path, query: query)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["results"] as? [[String: Any]]
        else { return [] }
        return rows.prefix(10).compactMap { Self.title(from: $0, isSeries: isSeries) }
    }

    static func title(from row: [String: Any], isSeries: Bool) -> TMDBTitle? {
        guard let id = row["id"] as? Int else { return nil }
        let localized = (row[isSeries ? "name" : "title"] as? String) ?? ""
        let original = (row[isSeries ? "original_name" : "original_title"] as? String) ?? localized
        guard !localized.isEmpty || !original.isEmpty else { return nil }

        let dateKey = isSeries ? "first_air_date" : "release_date"
        let year = (row[dateKey] as? String).flatMap { Int($0.prefix(4)) }

        return TMDBTitle(
            id: id,
            isSeries: isSeries,
            localizedTitle: localized.isEmpty ? original : localized,
            originalTitle: original,
            alternateTitles: [],
            overview: (row["overview"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            year: year,
            posterPath: row["poster_path"] as? String,
            backdropPath: row["backdrop_path"] as? String,
            voteAverage: row["vote_average"] as? Double
        )
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        var items = query
        if case .apiKey(let key) = credential {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw Failure.transport(String(localized: CoreStrings.requestFailed))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if case .bearerToken(let token) = credential {
            // Kept out of the query string: URLs end up in logs and proxies.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 { throw Failure.rateLimited }
                guard (200..<300).contains(http.statusCode) else {
                    throw Failure.transport(String(localized: CoreStrings.httpError(http.statusCode)))
                }
            }
            return data
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
    }
}
