import Foundation

/// Talks to an Xtream Codes panel.
///
/// Worth preferring over the raw M3U whenever credentials are available: the
/// panel hands us real categories, series structure and an EPG endpoint, which
/// is most of what "auto-organised" needs and none of which the M3U carries.
public struct XtreamClient: Sendable {

    public struct AccountInfo: Sendable, Equatable {
        public var username: String
        public var status: String?
        public var expiresAt: Date?
        public var isTrial: Bool
        public var activeConnections: Int?
        public var maxConnections: Int?
        public var serverName: String?
    }

    public enum Failure: LocalizedError, Equatable {
        case badResponse
        case unauthorized
        case expired(Date?)
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse:
                String(localized: CoreStrings.badResponse)
            case .unauthorized:
                String(localized: CoreStrings.unauthorized)
            case .expired(let date):
                if let date {
                    String(localized: CoreStrings.subscriptionExpired(
                        on: date.formatted(date: .abbreviated, time: .omitted)
                    ))
                } else {
                    String(localized: CoreStrings.subscriptionExpired)
                }
            case .transport(let message):
                message
            }
        }
    }

    public let portal: URL
    public let username: String
    public let password: String
    private let session: URLSession

    public init(portal: URL, username: String, password: String, session: URLSession = .shared) {
        self.portal = portal
        self.username = username
        self.password = password
        self.session = session
    }

    public init?(source: PlaylistSource, session: URLSession = .shared) {
        guard source.kind == .xtream,
              let portal = source.portalURL,
              let username = source.username,
              let password = source.password
        else { return nil }
        self.init(portal: portal, username: username, password: password, session: session)
    }

    // MARK: - Endpoints

    public var epgURL: URL {
        apiURL(path: "xmltv.php", query: [])
    }

    public var m3uURL: URL {
        apiURL(path: "get.php", query: [
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "ts"),
        ])
    }

    func apiURL(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: portal, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        components.path = "/" + path
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
        ] + query
        return components.url ?? portal
    }

    func actionURL(_ action: String, extra: [URLQueryItem] = []) -> URL {
        apiURL(path: "player_api.php", query: [URLQueryItem(name: "action", value: action)] + extra)
    }

    // MARK: - Requests

    /// Verifies credentials and reports what the panel says about the account.
    public func authenticate() async throws -> AccountInfo {
        let data = try await fetch(apiURL(path: "player_api.php", query: []))
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.badResponse
        }
        guard let userInfo = root["user_info"] as? [String: Any] else { throw Failure.badResponse }

        let auth = (userInfo["auth"] as? Int) ?? Int(userInfo["auth"] as? String ?? "0") ?? 0
        let status = userInfo["status"] as? String
        guard auth == 1 else { throw Failure.unauthorized }

        let expiresAt = (userInfo["exp_date"] as? String).flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) }
            ?? (userInfo["exp_date"] as? Double).map { Date(timeIntervalSince1970: $0) }

        if status?.caseInsensitiveCompare("Expired") == .orderedSame {
            throw Failure.expired(expiresAt)
        }

        let serverInfo = root["server_info"] as? [String: Any]
        return AccountInfo(
            username: (userInfo["username"] as? String) ?? username,
            status: status,
            expiresAt: expiresAt,
            isTrial: intValue(userInfo["is_trial"]) == 1,
            activeConnections: intValue(userInfo["active_cons"]),
            maxConnections: intValue(userInfo["max_connections"]),
            serverName: serverInfo?["url"] as? String
        )
    }

    /// Full library, assembled from the live/VOD/series endpoints.
    public func loadLibrary() async throws -> [MediaItem] {
        async let live = liveItems()
        async let movies = movieItems()
        async let series = seriesItems()
        return try await live + movies + series
    }

    func liveItems() async throws -> [MediaItem] {
        let categories = try await categoryNames(action: "get_live_categories")
        let entries = try await jsonArray(actionURL("get_live_streams"))
        return entries.compactMap { entry in
            guard let streamID = intValue(entry["stream_id"]) else { return nil }
            let rawTitle = (entry["name"] as? String) ?? "Channel \(streamID)"
            let cleaned = TitleCleaner.clean(rawTitle)
            let category = categories[stringValue(entry["category_id"]) ?? ""]
            return MediaItem(
                id: "live-\(streamID)",
                kind: .liveTV,
                title: cleaned.title,
                rawTitle: rawTitle,
                streamURL: streamURL(section: "live", id: streamID, extension: "m3u8"),
                logoURL: (entry["stream_icon"] as? String).flatMap { URL(string: $0) },
                rawGroup: category,
                category: CategoryNormalizer.normalize(category),
                channelID: entry["epg_channel_id"] as? String,
                channelNumber: intValue(entry["num"]),
                countryCode: cleaned.countryCode,
                qualityTag: cleaned.qualityTag
            )
        }
    }

    func movieItems() async throws -> [MediaItem] {
        let categories = try await categoryNames(action: "get_vod_categories")
        let entries = try await jsonArray(actionURL("get_vod_streams"))
        return entries.compactMap { entry in
            guard let streamID = intValue(entry["stream_id"]) else { return nil }
            let rawTitle = (entry["name"] as? String) ?? "Movie \(streamID)"
            let cleaned = TitleCleaner.clean(rawTitle)
            let container = (entry["container_extension"] as? String) ?? "mp4"
            let category = categories[stringValue(entry["category_id"]) ?? ""]
            return MediaItem(
                id: "movie-\(streamID)",
                kind: .movie,
                title: cleaned.title,
                rawTitle: rawTitle,
                streamURL: streamURL(section: "movie", id: streamID, extension: container),
                logoURL: (entry["stream_icon"] as? String).flatMap { URL(string: $0) },
                rawGroup: category,
                category: CategoryNormalizer.normalize(category),
                year: cleaned.year ?? (entry["year"] as? String).flatMap(Int.init),
                qualityTag: cleaned.qualityTag
            )
        }
    }

    /// Series listings, one item per show. Episodes load on demand — a large
    /// panel has tens of thousands of them and nobody needs them up front.
    func seriesItems() async throws -> [MediaItem] {
        let categories = try await categoryNames(action: "get_series_categories")
        let entries = try await jsonArray(actionURL("get_series"))
        return entries.compactMap { entry in
            guard let seriesID = intValue(entry["series_id"]) else { return nil }
            let rawTitle = (entry["name"] as? String) ?? "Series \(seriesID)"
            let cleaned = TitleCleaner.clean(rawTitle)
            let category = categories[stringValue(entry["category_id"]) ?? ""]
            // Placeholder URL: replaced by a real episode URL once expanded.
            let placeholder = streamURL(section: "series", id: seriesID, extension: "mp4")
            return MediaItem(
                id: "series-\(seriesID)",
                kind: .series,
                title: cleaned.title,
                rawTitle: rawTitle,
                streamURL: placeholder,
                logoURL: (entry["cover"] as? String).flatMap { URL(string: $0) },
                rawGroup: category,
                category: CategoryNormalizer.normalize(category),
                seriesName: cleaned.title,
                providerSeriesID: seriesID,
                year: cleaned.year ?? (entry["year"] as? String).flatMap(Int.init)
            )
        }
    }

    /// Every episode of one show.
    public func episodes(seriesID: Int) async throws -> [MediaItem] {
        let url = actionURL("get_series_info", extra: [
            URLQueryItem(name: "series_id", value: String(seriesID)),
        ])
        let data = try await fetch(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.badResponse
        }
        let showName = ((root["info"] as? [String: Any])?["name"] as? String) ?? ""
        guard let seasons = root["episodes"] as? [String: Any] else { return [] }

        var result: [MediaItem] = []
        for (seasonKey, value) in seasons {
            guard let episodes = value as? [[String: Any]] else { continue }
            let season = Int(seasonKey) ?? 0
            for episode in episodes {
                guard let episodeID = stringValue(episode["id"]), let id = Int(episodeID) else {
                    continue
                }
                let number = intValue(episode["episode_num"]) ?? 0
                let container = (episode["container_extension"] as? String) ?? "mp4"
                let rawTitle = (episode["title"] as? String) ?? "Episode \(number)"
                result.append(
                    MediaItem(
                        id: "episode-\(id)",
                        kind: .series,
                        title: TitleCleaner.clean(rawTitle).title,
                        rawTitle: rawTitle,
                        streamURL: streamURL(section: "series", id: id, extension: container),
                        logoURL: ((episode["info"] as? [String: Any])?["movie_image"] as? String)
                            .flatMap { URL(string: $0) },
                        seriesName: showName,
                        season: season,
                        episode: number,
                        providerSeriesID: seriesID
                    )
                )
            }
        }
        return result.sorted {
            ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0)
        }
    }

    // MARK: - Plumbing

    func streamURL(section: String, id: Int, extension ext: String) -> URL {
        portal
            .appending(path: section)
            .appending(path: username)
            .appending(path: password)
            .appending(path: "\(id).\(ext)")
    }

    private func categoryNames(action: String) async throws -> [String: String] {
        let entries = try await jsonArray(actionURL(action))
        return Dictionary(
            entries.compactMap { entry -> (String, String)? in
                guard let id = stringValue(entry["category_id"]),
                      let name = entry["category_name"] as? String
                else { return nil }
                return (id, name)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func jsonArray(_ url: URL) async throws -> [[String: Any]] {
        let data = try await fetch(url)
        // Panels answer with `[]`, `{}` or an error object when a section is empty.
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    private func fetch(_ url: URL) async throws -> Data {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            // Some panels reject the default URLSession agent outright.
            request.setValue("Kanal/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 || http.statusCode == 403 { throw Failure.unauthorized }
                guard (200..<300).contains(http.statusCode) else { throw Failure.badResponse }
            }
            return data
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
    }
}

// Panels are inconsistent about whether numbers arrive as numbers or strings.
private func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String { return Int(value) }
    return nil
}

private func stringValue(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? Int { return String(value) }
    if let value = value as? Double { return String(Int(value)) }
    return nil
}
