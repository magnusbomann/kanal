import Foundation
import Testing
@testable import KanalCore

@MainActor
@Suite("Progressive first import")
struct ProgressiveImportTests {

    @Test("Channels are playable before films finish loading")
    func channelsArriveFirst() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KanalProgressiveImportTests")
            .appending(path: UUID().uuidString)
        let loader = StagedLibraryLoader()
        let model = AppModel(loader: loader, storage: KanalStorage(directory: directory))
        let source = PlaylistSource(
            kind: .xtream,
            name: "Large service",
            portalURL: URL(string: "https://provider.test")!,
            username: "viewer",
            password: "secret"
        )

        try await model.add(source)
        await waitUntil { await loader.deferredDidStart }

        #expect(model.phase == .ready)
        #expect(model.library.channels.map(\.id) == ["live-1"])
        #expect(model.library.movies.isEmpty)
        #expect(model.isRefreshingLibrary)
        #expect(model.diagnostics.timeToFirstPlayableChannel != nil)

        await loader.releaseDeferredLibrary()
        await waitUntil { !model.library.movies.isEmpty }

        #expect(model.library.channels.map(\.id) == ["live-1"])
        #expect(model.library.movies.map(\.id) == ["movie-1"])
        await waitUntil { !model.isRefreshingLibrary }
    }

    private func waitUntil(
        _ condition: @escaping @MainActor @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("Condition did not become true")
    }
}

private actor StagedLibraryLoader: LibraryLoading {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var deferredDidStart = false

    func loadPlayableChannels(
        for source: PlaylistSource
    ) async throws -> LibraryLoader.LibraryResult? {
        LibraryLoader.LibraryResult(
            library: Library(items: [Self.channel]), epgURL: nil, skippedLines: 0
        )
    }

    func loadDeferredLibrary(
        for source: PlaylistSource,
        including initial: LibraryLoader.LibraryResult
    ) async throws -> LibraryLoader.LibraryResult? {
        deferredDidStart = true
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        return LibraryLoader.LibraryResult(
            library: Library(items: initial.library.items + [Self.movie]),
            epgURL: nil,
            skippedLines: 0
        )
    }

    func releaseDeferredLibrary() {
        released = true
        continuation?.resume()
        continuation = nil
    }

    func loadLibrary(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult {
        throw LibraryLoader.LoadError.emptyPlaylist
    }

    func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async {}
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem] { [] }
    func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult {
        XMLTVParser().parseDetailed(Data("<tv></tv>".utf8))
    }

    private static let channel = MediaItem(
        id: "live-1",
        kind: .liveTV,
        title: "Channel",
        rawTitle: "Channel",
        streamURL: URL(string: "https://provider.test/live/1.m3u8")!
    )

    private static let movie = MediaItem(
        id: "movie-1",
        kind: .movie,
        title: "Film",
        rawTitle: "Film",
        streamURL: URL(string: "https://provider.test/movie/1.mp4")!
    )
}
