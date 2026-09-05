import Foundation
import Testing
@testable import KanalCore

@Suite("Remembering Home")
struct HomeWatchStateTests {

    @Test("An older saved state gains empty Home fields")
    func olderStateStillDecodes() throws {
        let data = Data(#"{"favoriteIDs":["one"],"recentIDs":[]}"#.utf8)
        let state = try JSONDecoder().decode(WatchState.self, from: data)

        #expect(state.favoriteIDs == ["one"])
        #expect(state.recentItems.isEmpty)
        #expect(state.recentChannelGroupIDs.isEmpty)
    }

    @Test("Recent channels are ordered, de-duplicated and bounded")
    func channelHistoryIsAnMRU() {
        var state = WatchState()
        for number in 0..<55 { state.recordChannel(groupID: "channel-\(number)") }
        state.recordChannel(groupID: "channel-10")

        #expect(state.recentChannelGroupIDs.count == 50)
        #expect(state.recentChannelGroupIDs.first == "channel-10")
        #expect(Set(state.recentChannelGroupIDs).count == 50)
    }

    @Test("An on-demand snapshot uses the same scoped key as its progress")
    func snapshotFollowsProgressKey() {
        let episode = HomeFixtures.episode(show: "Show", season: 1, number: 1)
        let scopedKey = "source-id|\(episode.id)"
        var state = WatchState()
        state.record(
            WatchProgress(itemID: scopedKey, position: 100, duration: 1_000),
            item: episode
        )

        #expect(state.recentIDs == [scopedKey])
        #expect(state.recentItems[scopedKey] == episode)
        #expect(state.recentItems[episode.id] == nil)
    }
}

@Suite("New on Home")
struct LibraryUpdatesTests {

    @Test("A first import does not call the whole service new")
    func firstImportIsEmpty() {
        let current = Library(items: [HomeFixtures.movie(id: "one", title: "One")])
        #expect(LibraryUpdates.detect(previous: .empty, current: current).isEmpty)
    }

    @Test("Films and shows added by a later refresh are detected")
    func detectsBothKinds() {
        let old = Library(items: [
            HomeFixtures.movie(id: "old", title: "Old", year: 2020),
            HomeFixtures.episode(show: "Old Show", season: 1, number: 1),
        ])
        let current = Library(items: old.items + [
            HomeFixtures.movie(id: "new", title: "New", year: 2025),
            HomeFixtures.episode(show: "New Show", season: 1, number: 1),
        ])

        let updates = LibraryUpdates.detect(previous: old, current: current)
        #expect(updates.movieKeys.count == 1)
        #expect(updates.seriesKeys.count == 1)
    }

    @Test("A rotated stream token does not make an old film new")
    func ignoresURLRotation() {
        let old = Library(items: [
            HomeFixtures.movie(
                id: "old-id", title: "Same Film", year: 2024,
                url: "https://provider.test/movie.mkv?token=old"
            ),
        ])
        let current = Library(items: [
            HomeFixtures.movie(
                id: "new-id", title: "Same Film", year: 2024,
                url: "https://provider.test/movie.mkv?token=new"
            ),
        ])

        #expect(LibraryUpdates.detect(previous: old, current: current).isEmpty)
    }

    @Test("A remake with another year is a new film")
    func yearDistinguishesRemake() {
        let old = Library(items: [HomeFixtures.movie(id: "a", title: "Dune", year: 1984)])
        let current = Library(items: old.items + [
            HomeFixtures.movie(id: "b", title: "Dune", year: 2021),
        ])

        #expect(LibraryUpdates.detect(previous: old, current: current).movieKeys.count == 1)
    }

    @Test("Detection is not capped before a profile filters it")
    func retainsTheWholeBatch() {
        let old = Library(items: [HomeFixtures.movie(id: "old", title: "Old")])
        let additions = (0..<40).map {
            HomeFixtures.movie(id: "new-\($0)", title: "New \($0)", year: 2025)
        }
        let updates = LibraryUpdates.detect(
            previous: old,
            current: Library(items: old.items + additions)
        )

        #expect(updates.movieKeys.count == 40)
    }

    @Test("An old batch expires instead of pretending it just arrived")
    func expires() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let updates = LibraryUpdates(movieKeys: ["film"], detectedAt: now)
        #expect(updates.isRecent(at: now.addingTimeInterval(13 * 24 * 60 * 60)))
        #expect(!updates.isRecent(at: now.addingTimeInterval(15 * 24 * 60 * 60)))
    }
}

@MainActor
@Suite("Home rows")
struct HomeContentTests {

    @Test("A finished episode offers its successor, while partial playback resumes")
    func nextAndContinueDoNotCompete() async throws {
        let episodes = [
            HomeFixtures.episode(show: "The Show", season: 1, number: 1),
            HomeFixtures.episode(show: "The Show", season: 1, number: 2),
            HomeFixtures.episode(show: "The Show", season: 1, number: 3),
        ]
        let (model, _, _) = try await makeModel(items: episodes)

        model.record(item: episodes[0], position: 1_000, duration: 1_000)
        #expect(model.nextEpisodes.map(\.id) == [episodes[1].id])
        #expect(model.continueWatching.isEmpty)

        model.record(item: episodes[1], position: 200, duration: 1_000)
        #expect(model.continueWatching.map(\.id) == [episodes[1].id])
        #expect(model.nextEpisodes.isEmpty)
    }

    @Test("Stopping in the first minute is not labelled as the next episode")
    func shortAttemptIsNeitherRow() async throws {
        let episodes = [
            HomeFixtures.episode(show: "The Show", season: 1, number: 1),
            HomeFixtures.episode(show: "The Show", season: 1, number: 2),
        ]
        let (model, _, _) = try await makeModel(items: episodes)

        model.record(item: episodes[0], position: 30, duration: 1_000)
        #expect(model.continueWatching.isEmpty)
        #expect(model.nextEpisodes.isEmpty)
    }

    @Test("Continue watching keeps only the newest episode of a show")
    func oneResumePerShow() async throws {
        let episodes = [
            HomeFixtures.episode(show: "The Show", season: 1, number: 1),
            HomeFixtures.episode(show: "The Show", season: 1, number: 2),
        ]
        let (model, _, _) = try await makeModel(items: episodes)

        model.record(item: episodes[0], position: 200, duration: 1_000)
        model.record(item: episodes[1], position: 300, duration: 1_000)

        #expect(model.continueWatching.map(\.id) == [episodes[1].id])
    }

    @Test("On-demand episodes find their show by provider id even when its name differs")
    func providerIDReconnectsEpisodes() async throws {
        let placeholder = HomeFixtures.seriesPlaceholder(
            id: "series-42", name: "Provider Listing", providerID: 42
        )
        let fetched = [
            HomeFixtures.episode(
                show: "Official Name", season: 1, number: 1, providerID: 42
            ),
            HomeFixtures.episode(
                show: "Official Name", season: 1, number: 2, providerID: 42
            ),
        ]
        let (model, loader, _) = try await makeModel(
            items: [placeholder], episodes: [42: fetched]
        )
        _ = loader

        model.record(item: fetched[0], position: 1_000, duration: 1_000)
        #expect(model.nextEpisodes.isEmpty)
        await model.prepareHome()
        #expect(model.nextEpisodes.map(\.id) == [fetched[1].id])
        #expect(model.nextEpisode(after: fetched[0])?.id == fetched[1].id)
    }

    @Test("Episode caches are cleared when two services reuse a series id")
    func episodeCacheIsSourceScoped() async throws {
        let firstSource = PlaylistSource(kind: .m3u, name: "One")
        let secondSource = PlaylistSource(kind: .m3u, name: "Two")
        let firstPlaceholder = HomeFixtures.seriesPlaceholder(
            id: "first-series", name: "First listing", providerID: 42
        )
        let secondPlaceholder = HomeFixtures.seriesPlaceholder(
            id: "second-series", name: "Second listing", providerID: 42
        )
        let firstEpisodes = [
            HomeFixtures.episode(show: "First show", season: 1, number: 1, providerID: 42),
        ]
        let secondEpisodes = [
            HomeFixtures.episode(show: "Second show", season: 1, number: 1, providerID: 42),
        ]
        let loader = HomeLibraryLoader(
            libraries: [
                firstSource.id: Library(items: [firstPlaceholder]),
                secondSource.id: Library(items: [secondPlaceholder]),
            ],
            episodesBySource: [
                firstSource.id: [42: firstEpisodes],
                secondSource.id: [42: secondEpisodes],
            ]
        )
        let model = AppModel(loader: loader, storage: Self.scratchStorage())

        try await model.add(firstSource)
        try await model.add(secondSource)
        let secondGroup = try #require(model.library.series.first)
        await model.loadEpisodesIfNeeded(for: secondGroup)
        #expect(model.episodes(for: secondGroup).first?.seriesName == "Second show")

        await model.switchTo(firstSource)
        let firstGroup = try #require(model.library.series.first)
        await model.loadEpisodesIfNeeded(for: firstGroup)
        #expect(model.episodes(for: firstGroup).first?.seriesName == "First show")
    }

    @Test("History with colliding provider ids stays with its own TV service")
    func historyIsSourceScoped() async throws {
        let firstSource = PlaylistSource(kind: .m3u, name: "One")
        let secondSource = PlaylistSource(kind: .m3u, name: "Two")
        let firstMovie = HomeFixtures.movie(id: "movie-7", title: "First service")
        let secondMovie = HomeFixtures.movie(id: "movie-7", title: "Second service")
        let loader = HomeLibraryLoader(libraries: [
            firstSource.id: Library(items: [firstMovie]),
            secondSource.id: Library(items: [secondMovie]),
        ])
        let model = AppModel(loader: loader, storage: Self.scratchStorage())

        try await model.add(firstSource)
        model.record(item: firstMovie, position: 111, duration: 1_000)
        try await model.add(secondSource)
        #expect(model.progress(for: secondMovie) == nil)
        model.record(item: secondMovie, position: 222, duration: 1_000)

        await model.switchTo(firstSource)
        #expect(model.progress(for: firstMovie)?.position == 111)
    }

    @Test("A refresh exposes newly added titles using their stable keys")
    func refreshBuildsRecentlyAdded() async throws {
        let oldMovie = HomeFixtures.movie(id: "old", title: "Old Film", year: 2020)
        let newMovie = HomeFixtures.movie(id: "new", title: "New Film", year: 2025)
        let newShow = HomeFixtures.episode(show: "New Show", season: 1, number: 1)
        let (model, loader, source) = try await makeModel(items: [oldMovie])

        await loader.setLibrary(
            Library(items: [oldMovie, newMovie, newShow]), for: source.id
        )
        await model.refreshActiveSource()

        #expect(model.newlyAddedMovies.map(\.title) == ["New Film"])
        #expect(model.newlyAddedSeries.map(\.name) == ["New Show"])
    }

    @Test("A rotated movie URL keeps its Continue watching position")
    func movieHistorySurvivesURLRotation() async throws {
        let oldMovie = HomeFixtures.movie(
            id: "old-signed-id", title: "Same Film", year: 2025,
            url: "https://provider.test/movie.mkv?token=old"
        )
        let currentMovie = HomeFixtures.movie(
            id: "new-signed-id", title: "Same Film", year: 2025,
            url: "https://provider.test/movie.mkv?token=new"
        )
        let (model, loader, source) = try await makeModel(items: [oldMovie])
        model.record(item: oldMovie, position: 321, duration: 1_000)

        await loader.setLibrary(Library(items: [currentMovie]), for: source.id)
        await model.refreshActiveSource()

        #expect(model.continueWatching.map(\.id) == [currentMovie.id])
        #expect(model.progress(for: currentMovie)?.position == 321)
    }

    @Test("A recently played channel is source-scoped and appears once")
    func recentChannelAppears() async throws {
        let channel = HomeFixtures.channel(id: "live-1", title: "NRK 1")
        let (model, _, _) = try await makeModel(items: [channel])
        let group = try #require(model.library.channelGroups.first)

        model.recordChannel(groupID: group.id)
        model.recordChannel(groupID: group.id)

        #expect(model.recentChannelGroups.map(\.id) == [group.id])
    }

    private func makeModel(
        items: [MediaItem],
        episodes: [Int: [MediaItem]] = [:]
    ) async throws -> (AppModel, HomeLibraryLoader, PlaylistSource) {
        let source = PlaylistSource(kind: .m3u, name: "Test")
        let loader = HomeLibraryLoader(
            libraries: [source.id: Library(items: items)], episodes: episodes
        )
        let model = AppModel(loader: loader, storage: Self.scratchStorage())
        try await model.add(source)
        return (model, loader, source)
    }

    private static func scratchStorage() -> KanalStorage {
        KanalStorage(directory: FileManager.default.temporaryDirectory
            .appending(path: "KanalHomeContentTests")
            .appending(path: UUID().uuidString))
    }
}

@Suite("Guide on Home")
struct HomeGuideTests {

    @Test("A channel group finds guide data carried only by a fallback feed")
    func fallbackVariantSuppliesGuideID() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let primary = HomeFixtures.channel(id: "primary", title: "NRK 1")
        let fallback = HomeFixtures.channel(id: "fallback", title: "NRK 1", channelID: "nrk1.no")
        let current = Programme(
            channelID: "nrk1.no", title: "Dagsrevyen",
            start: now.addingTimeInterval(-600), stop: now.addingTimeInterval(600)
        )
        let next = Programme(
            channelID: "nrk1.no", title: "Sporten",
            start: now.addingTimeInterval(600), stop: now.addingTimeInterval(1_200)
        )
        let guide = XMLTVParser.Guide(
            channelNames: [:], channelIcons: [:],
            schedules: ["nrk1.no": Schedule(channelID: "nrk1.no", programmes: [current, next])]
        )
        let group = ChannelGroup(
            id: "nrk-1", name: "NRK 1", variants: [primary, fallback], categories: []
        )

        #expect(group.programme(in: guide, at: now)?.title == "Dagsrevyen")
        #expect(group.upcoming(in: guide, after: now, limit: 1).first?.title == "Sporten")
    }
}

private actor HomeLibraryLoader: LibraryLoading {
    private var libraries: [UUID: Library]
    private let episodes: [Int: [MediaItem]]
    private let episodesBySource: [UUID: [Int: [MediaItem]]]

    init(
        libraries: [UUID: Library],
        episodes: [Int: [MediaItem]] = [:],
        episodesBySource: [UUID: [Int: [MediaItem]]] = [:]
    ) {
        self.libraries = libraries
        self.episodes = episodes
        self.episodesBySource = episodesBySource
    }

    func setLibrary(_ library: Library, for sourceID: UUID) {
        libraries[sourceID] = library
    }

    func loadLibrary(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult {
        guard let library = libraries[source.id] else { throw LibraryLoader.LoadError.emptyPlaylist }
        return LibraryLoader.LibraryResult(library: library, epgURL: nil, skippedLines: 0)
    }

    func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async {}

    func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem] {
        episodesBySource[source.id]?[seriesID] ?? episodes[seriesID] ?? []
    }

    func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult {
        XMLTVParser().parseDetailed(Data("<tv></tv>".utf8))
    }
}

private enum HomeFixtures {
    static func movie(
        id: String,
        title: String,
        year: Int? = nil,
        url: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id, kind: .movie, title: title, rawTitle: title,
            streamURL: URL(string: url ?? "https://provider.test/movie/\(id).mp4")!,
            year: year
        )
    }

    static func episode(
        show: String,
        season: Int,
        number: Int,
        providerID: Int? = nil
    ) -> MediaItem {
        MediaItem(
            id: "episode-\(providerID.map(String.init) ?? show)-\(season)-\(number)",
            kind: .series,
            title: "\(show) S\(season)E\(number)",
            rawTitle: "\(show) S\(season)E\(number)",
            streamURL: URL(string: "https://provider.test/series/\(season)-\(number).mp4")!,
            seriesName: show,
            season: season,
            episode: number,
            providerSeriesID: providerID
        )
    }

    static func seriesPlaceholder(id: String, name: String, providerID: Int) -> MediaItem {
        MediaItem(
            id: id, kind: .series, title: name, rawTitle: name,
            streamURL: URL(string: "https://provider.test/series/\(providerID).mp4")!,
            seriesName: name, providerSeriesID: providerID
        )
    }

    static func channel(id: String, title: String, channelID: String? = nil) -> MediaItem {
        MediaItem(
            id: id, kind: .liveTV, title: title, rawTitle: title,
            streamURL: URL(string: "https://provider.test/live/\(id).m3u8")!,
            channelID: channelID
        )
    }
}
