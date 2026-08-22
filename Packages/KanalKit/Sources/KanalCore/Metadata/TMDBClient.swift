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

    private let apiKey: String
    private let session: URLSession
    /// The language localised titles and plots come back in.
    private let language: String

    public init(
        apiKey: String,
        language: String = PreferredLanguages.primaryTag(),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
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
        return title
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
        guard !apiKey.isEmpty else { throw Failure.noAPIKey }

        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        components.queryItems = query + [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = components.url else { throw Failure.transport("Could not build the request.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
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
