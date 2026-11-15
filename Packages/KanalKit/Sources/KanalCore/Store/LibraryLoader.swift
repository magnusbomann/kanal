import Foundation

/// The loading boundary AppModel depends on.
///
/// Keeping it as a protocol makes ordering and cancellation behaviour
/// testable with controlled continuations rather than timing or real servers.
public protocol LibraryLoading: Sendable {
    func loadLibrary(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult
    /// The smallest useful first screen. `nil` means this source cannot be
    /// split and should use `loadLibrary` as one atomic operation.
    func loadPlayableChannels(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult?
    /// Finishes a split load without downloading the first stage again.
    func loadDeferredLibrary(
        for source: PlaylistSource,
        including initial: LibraryLoader.LibraryResult
    ) async throws -> LibraryLoader.LibraryResult?
    func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library?
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem]
    func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult
}

public extension LibraryLoading {
    func loadPlayableChannels(
        for source: PlaylistSource
    ) async throws -> LibraryLoader.LibraryResult? { nil }

    func loadDeferredLibrary(
        for source: PlaylistSource,
        including initial: LibraryLoader.LibraryResult
    ) async throws -> LibraryLoader.LibraryResult? { nil }
}

/// Fetches and parses a source, off the main actor.
///
/// Both halves of a refresh — the library and the guide — are reported
/// separately so channels appear immediately and the guide fills in behind
/// them. A slow EPG should never hold up the first screen.
public actor LibraryLoader: LibraryLoading {

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

    /// Xtream exposes live TV independently from its much larger VOD
    /// catalogues. Prove the account and fetch only that endpoint so the app
    /// can offer a playable channel while films and series continue behind it.
    public func loadPlayableChannels(for source: PlaylistSource) async throws -> LibraryResult? {
        guard source.kind == .xtream else { return nil }
        guard let client = XtreamClient(source: source, session: session) else {
            throw LoadError.noPlaylistURL
        }
        async let account = client.authenticate()
        async let channels = client.liveItems()
        _ = try await account
        let items = try await channels
        // Some valid Xtream accounts contain only movies or series. Keep the
        // staged import alive so the deferred catalogue can still be loaded.
        guard !items.isEmpty else { return nil }
        return LibraryResult(
            library: Library(items: items),
            epgURL: source.epgURL ?? client.epgURL,
            skippedLines: 0
        )
    }

    /// Completes the Xtream catalogue using the already-loaded live stage.
    /// Movies and series are independent panel endpoints and remain parallel.
    public func loadDeferredLibrary(
        for source: PlaylistSource,
        including initial: LibraryResult
    ) async throws -> LibraryResult? {
        guard source.kind == .xtream else { return nil }
        guard let client = XtreamClient(source: source, session: session) else {
            throw LoadError.noPlaylistURL
        }
        async let movies = client.movieItems()
        async let series = client.seriesItems()
        let items = try await initial.library.items + movies + series
        return LibraryResult(
            library: Library(items: items),
            epgURL: initial.epgURL ?? source.epgURL ?? client.epgURL,
            skippedLines: initial.skippedLines
        )
    }

    /// Reads a cached catalogue, off the main actor.
    ///
    /// Decoding four hundred thousand entries takes about half a second, which
    /// is nothing next to a refresh but far too much to do while the first
    /// frame is waiting.
    public func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library? {
        let name = LibraryCache.fileName(for: sourceID)
        guard let data = await storage.loadCache(name),
              let snapshot = LibraryCache.decode(data),
              !snapshot.items.isEmpty
        else { return nil }
        return Library(items: snapshot.items)
    }

    public func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async {
        let snapshot = LibraryCache.Snapshot(
            items: library.items, savedAt: .now, sourceID: sourceID
        )
        await storage.saveCache(LibraryCache.encode(snapshot), to: LibraryCache.fileName(for: sourceID))
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
    nonisolated func decodeText(_ data: Data) -> String { Self.decodeText(data) }

    static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        // Strict UTF-8 is all or nothing: one stray byte in a 135 MB playlist
        // — common where a panel stitches feeds together — used to send the
        // whole file to Latin-1 and turn every æ, ø and å into "Ã¦". So decode
        // leniently, and only believe Latin-1 when the bytes that failed
        // outnumber the accented letters that did decode — Latin-1 text
        // almost never forms a valid UTF-8 sequence by accident.
        let lenient = String(decoding: data, as: UTF8.self)
        var damaged = 0
        var accented = 0
        for scalar in lenient.unicodeScalars where scalar.value > 0x7F {
            if scalar == "\u{FFFD}" { damaged += 1 } else { accented += 1 }
        }
        if damaged > accented,
           let text = String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1) {
            return text
        }
        return lenient
    }
}
