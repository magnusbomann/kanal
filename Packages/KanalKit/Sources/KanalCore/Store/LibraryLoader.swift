import Foundation

/// Fetches and parses a source, off the main actor.
///
/// Both halves of a refresh — the library and the guide — are reported
/// separately so channels appear immediately and the guide fills in behind
/// them. A slow EPG should never hold up the first screen.
public actor LibraryLoader {

    public enum LoadError: LocalizedError {
        case noPlaylistURL
        case emptyPlaylist
        case http(Int)
        case underlying(String)

        public var errorDescription: String? {
            switch self {
            case .noPlaylistURL: String(localized: CoreStrings.noPlaylistURL)
            case .emptyPlaylist: String(localized: CoreStrings.emptyPlaylist)
            case .http(let code): String(localized: CoreStrings.httpError(code))
            // Already localised by the system that produced it.
            case .underlying(let message): message
            }
        }
    }

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 300
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public struct LibraryResult: Sendable {
        public var library: Library
        public var epgURL: URL?
        /// Playlist lines that produced nothing playable.
        public var skippedLines: Int
    }

    /// Loads the library and, when we can find one, the EPG url to follow up with.
    public func loadLibrary(for source: PlaylistSource) async throws -> LibraryResult {
        switch source.kind {
        case .xtream:
            guard let client = XtreamClient(source: source, session: session) else {
                throw LoadError.noPlaylistURL
            }
            // Authenticating first turns "0 channels" into a real explanation.
            _ = try await client.authenticate()
            let items = try await client.loadLibrary()
            guard !items.isEmpty else { throw LoadError.emptyPlaylist }
            return LibraryResult(
                library: Library(items: items),
                epgURL: source.epgURL ?? client.epgURL,
                skippedLines: 0
            )

        case .m3u:
            guard let url = source.playlistURL else { throw LoadError.noPlaylistURL }
            let text = try await fetchText(url)
            let playlist = M3UParser().parse(text)
            guard !playlist.items.isEmpty else { throw LoadError.emptyPlaylist }
            return LibraryResult(
                library: Library(items: playlist.items),
                epgURL: source.epgURL ?? playlist.epgURL,
                skippedLines: playlist.skippedLineCount
            )

        case .localFile:
            guard let url = source.playlistURL else { throw LoadError.noPlaylistURL }
            let data = try Data(contentsOf: url)
            let playlist = M3UParser().parse(decodeText(Gunzip.decode(data)))
            guard !playlist.items.isEmpty else { throw LoadError.emptyPlaylist }
            return LibraryResult(
                library: Library(items: playlist.items),
                epgURL: source.epgURL ?? playlist.epgURL,
                skippedLines: playlist.skippedLineCount
            )
        }
    }

    /// Every episode of one show, from a panel that stores them separately.
    public func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem] {
        guard let client = XtreamClient(source: source, session: session) else {
            throw LoadError.noPlaylistURL
        }
        return try await client.episodes(seriesID: seriesID)
    }

    public func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult {
        let data = Gunzip.decode(try await fetchData(url))
        return XMLTVParser().parseDetailed(data)
    }

    // MARK: - Transport

    private func fetchText(_ url: URL) async throws -> String {
        decodeText(Gunzip.decode(try await fetchData(url)))
    }

    private func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // Panels routinely 403 the default agent and expect a player-ish one.
        request.setValue("Kanal/1.0 (AppleCoreMedia)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LoadError.http(http.statusCode)
            }
            return data
        } catch let error as LoadError {
            throw error
        } catch {
            throw LoadError.underlying(error.localizedDescription)
        }
    }

    /// Playlists are usually UTF-8 but Latin-1 shows up often enough to matter.
    private nonisolated func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
