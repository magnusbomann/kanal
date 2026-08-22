import Foundation

/// Wikidata as Kanal's default metadata source.
///
/// Chosen over the commercial databases for one reason: it needs no API key, no
/// signup and no registered application URL, and its data is CC0 — so Kanal
/// works out of the box for everyone, on day one, at no cost, commercial or
/// not. It also happens to be excellent at the exact question Kanal asks, since
/// every entity carries a label in every language.
///
/// What it cannot do is posters — film artwork is copyrighted and mostly absent
/// from Commons. That is what a paid provider would add later.
public struct WikidataProvider: MetadataProvider {

    public var providerName: String { "Wikidata" }
    public var providesArtwork: Bool { false }

    /// Follows the device, not the developer. Hardcoding Norwegian here was a
    /// real bug: it made the whole translation feature useless to anyone else.
    private let languages: [String]

    /// `instance of` values that mean "this is something you watch".
    private static let audiovisualTypes: Set<String> = [
        "Q11424",    // film
        "Q202866",   // animated film
        "Q24856",    // film series
        "Q5398426",  // television series
        "Q506240",   // television film
        "Q1259759",  // miniseries
        "Q29168811", // animated feature film
        "Q93204",    // documentary film
        "Q580850",   // adult animation
        "Q1366112",  // animated series
        "Q117467246",// animated television series
        "Q15416",    // television programme
    ]

    private let session: URLSession
    private let userAgent: String

    public init(
        session: URLSession = .shared,
        userAgent: String = "Kanal/1.0 (IPTV player for Apple platforms)",
        languages: [String] = PreferredLanguages.codes()
    ) {
        self.session = session
        self.userAgent = userAgent
        self.languages = languages
    }

    public func lookup(name: String, year: Int?, isSeries: Bool?) async throws -> [ResolvedTitle] {
        // Searched once per preferred language: the Norwegian index answers
        // "Løvenes konge", the German one "Der König der Löwen", and the
        // English one answers for the provider's own listing.
        // Sequential on purpose. Firing one request per language in parallel
        // is what earns a 429 from Wikimedia, and the second language is only
        // needed when the first came up short anyway.
        var ids: [String] = []
        var seen = Set<String>()
        for language in languages.prefix(2) {
            for id in try await searchIDs(name, language: language) where seen.insert(id).inserted {
                ids.append(id)
            }
            if ids.count >= 6 { break }
        }
        guard !ids.isEmpty else { return [] }

        return try await entities(ids: Array(ids.prefix(10)))
    }

    // MARK: - Requests

    private func searchIDs(_ name: String, language: String) async throws -> [String] {
        let data = try await get(query: [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: name),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "uselang", value: language),
            URLQueryItem(name: "type", value: "item"),
            URLQueryItem(name: "limit", value: "7"),
            URLQueryItem(name: "format", value: "json"),
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["search"] as? [[String: Any]]
        else { return [] }
        return results.compactMap { $0["id"] as? String }
    }

    private func entities(ids: [String]) async throws -> [ResolvedTitle] {
        let data = try await get(query: [
            URLQueryItem(name: "action", value: "wbgetentities"),
            URLQueryItem(name: "ids", value: ids.joined(separator: "|")),
            URLQueryItem(name: "props", value: "labels|aliases|claims|descriptions"),
            URLQueryItem(name: "languages", value: languages.joined(separator: "|")),
            URLQueryItem(name: "format", value: "json"),
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = root["entities"] as? [String: Any]
        else { return [] }

        // Preserve the order the search returned them in — Wikidata ranks by
        // relevance and we would only be guessing if we resorted.
        return ids.compactMap { id in
            guard let entity = entities[id] as? [String: Any] else { return nil }
            return Self.title(id: id, entity: entity, preferred: languages)
        }
    }

    // MARK: - Parsing

    static func title(
        id: String,
        entity: [String: Any],
        preferred: [String] = PreferredLanguages.codes()
    ) -> ResolvedTitle? {
        let claims = entity["claims"] as? [String: Any] ?? [:]
        guard isAudiovisual(claims: claims) else { return nil }

        let labels = (entity["labels"] as? [String: Any] ?? [:]).compactMapValues { value in
            (value as? [String: Any])?["value"] as? String
        }
        let aliases = (entity["aliases"] as? [String: Any] ?? [:]).mapValues { value -> [String] in
            (value as? [[String: Any]])?.compactMap { $0["value"] as? String } ?? []
        }

        // English is the name an IPTV provider is most likely to have used, so
        // it is the one we search the library with.
        let canonical = labels["en"]
            ?? preferred.compactMap { labels[$0] }.first
            ?? labels.values.first
        guard let canonical, !canonical.isEmpty else { return nil }

        // The name the viewer would actually call it, in their own language.
        let localized = preferred.compactMap { labels[$0] }.first
        let names = [canonical] + labels.values + aliases.values.flatMap { $0 }

        return ResolvedTitle(
            id: "wikidata:\(id)",
            canonicalName: canonical,
            localizedName: localized,
            allNames: names,
            year: year(claims: claims),
            isSeries: isSeries(claims: claims),
            posterURL: nil,
            overview: (entity["descriptions"] as? [String: Any]).flatMap { descriptions in
                ((descriptions["nb"] ?? descriptions["en"]) as? [String: Any])?["value"] as? String
            }
        )
    }

    /// Something you watch, rather than a person, place or disambiguation page.
    ///
    /// `instance of` alone is not enough — Wikidata has hundreds of film
    /// subtypes — so a director or a cast list counts as proof too.
    static func isAudiovisual(claims: [String: Any]) -> Bool {
        let types = entityIDs(claims: claims, property: "P31")
        if !types.isDisjoint(with: audiovisualTypes) { return true }
        // P57 director, P161 cast member, P58 screenwriter.
        return ["P57", "P161", "P58"].contains { claims[$0] != nil }
    }

    static func isSeries(claims: [String: Any]) -> Bool {
        let types = entityIDs(claims: claims, property: "P31")
        let seriesTypes: Set<String> = [
            "Q5398426", "Q1259759", "Q1366112", "Q117467246", "Q15416",
        ]
        return !types.isDisjoint(with: seriesTypes)
    }

    /// `P577` publication date, as `+1994-11-18T00:00:00Z`.
    static func year(claims: [String: Any]) -> Int? {
        guard let statements = claims["P577"] as? [[String: Any]] else { return nil }
        let years = statements.compactMap { statement -> Int? in
            guard let snak = statement["mainsnak"] as? [String: Any],
                  let value = snak["datavalue"] as? [String: Any],
                  let time = (value["value"] as? [String: Any])?["time"] as? String
            else { return nil }
            return Int(time.dropFirst().prefix(4))
        }
        return years.min()
    }

    static func entityIDs(claims: [String: Any], property: String) -> Set<String> {
        guard let statements = claims[property] as? [[String: Any]] else { return [] }
        return Set(statements.compactMap { statement in
            guard let snak = statement["mainsnak"] as? [String: Any],
                  let value = snak["datavalue"] as? [String: Any]
            else { return nil }
            return (value["value"] as? [String: Any])?["id"] as? String
        })
    }

    /// Wikimedia rate-limits, and a rate limit is not an answer.
    ///
    /// Returning empty on a 429 would be indistinguishable from "no such film",
    /// which the caller then caches — one slow moment and a title is
    /// permanently invisible. So transient failures are retried and then
    /// thrown, never quietly turned into a negative result.
    private func get(query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Wikimedia's policy requires a user agent that identifies the client.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var lastError: any Error = URLError(.unknown)
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(400 << attempt))
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return data }
                switch http.statusCode {
                case 200..<300:
                    return data
                case 429, 500..<600:
                    lastError = LookupFailure.temporary(http.statusCode)
                default:
                    throw LookupFailure.permanent(http.statusCode)
                }
            } catch let failure as LookupFailure {
                if case .permanent = failure { throw failure }
                lastError = failure
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Distinguishes "ask again later" from "this will never work".
    public enum LookupFailure: LocalizedError, Equatable {
        case temporary(Int)
        case permanent(Int)

        public var errorDescription: String? {
            switch self {
            case .temporary(let code): "Wikidata is busy (\(code)). Try again shortly."
            case .permanent(let code): "Wikidata replied with error \(code)."
            }
        }
    }
}
