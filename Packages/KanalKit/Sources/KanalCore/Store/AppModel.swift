import Foundation
import Observation

/// The app's single source of truth.
///
/// Every screen reads from here; nothing else owns state. Loading happens on a
/// background actor and lands back here in one assignment, which keeps the
/// scroll views from ever seeing a half-built library.
@MainActor
@Observable
public final class AppModel {

    public enum Phase: Equatable {
        case welcome
        case loading(String)
        case ready
        case failed(String)
    }

    // MARK: State

    public private(set) var phase: Phase = .welcome
    public private(set) var sources: [PlaylistSource] = []
    public private(set) var activeSourceID: UUID?
    public private(set) var library: Library = .empty
    public private(set) var guide: XMLTVParser.Guide?
    public private(set) var isRefreshingGuide = false
    /// A refresh running behind an already-visible catalogue.
    public private(set) var isRefreshingLibrary = false
    /// What was wrong with the data this source sent, if anything.
    public private(set) var diagnostics = SourceDiagnostics()
    /// Whether an artwork provider is configured — drives required attribution.
    public private(set) var usesArtworkProvider = false
    /// Whether the intro has been seen. Kept in its own file rather than in
    /// `WatchState`, so adding it cannot fail to decode anyone's favourites.
    public private(set) var hasCompletedIntro = false
    /// Episodes fetched on demand, keyed by the provider's series id.
    public private(set) var loadedEpisodes: [Int: [MediaItem]] = [:]
    public private(set) var episodeLoadFailures: [Int: String] = [:]
    private var episodeLoadsInFlight: Set<Int> = []
    public var watchState = WatchState() {
        didSet { scheduleWatchStateSave() }
    }

    public let metadata: MetadataService
    public let discovery: DiscoveryService
    /// Recommendation rows, already filtered to what this library carries.
    public private(set) var discoveryShelves: [DiscoveryShelf] = []
    private let loader: LibraryLoader
    private let storage: KanalStorage
    private var watchStateSaveTask: Task<Void, Never>?

    private static let sourcesFile = "sources.json"
    private static let introFile = "intro-completed.json"

    public init(
        loader: LibraryLoader = LibraryLoader(),
        storage: KanalStorage = .shared,
        metadata: MetadataService? = nil
    ) {
        self.loader = loader
        self.storage = storage
        // Wikidata is always available and needs no key. A TMDB key, if the
        // app was built with one, only adds artwork on top.
        let tmdbKey = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String
        self.metadata = metadata ?? MetadataService(tmdbAPIKey: tmdbKey, storage: storage)
        self.discovery = DiscoveryService(apiKey: tmdbKey, storage: storage)
    }

    public var activeSource: PlaylistSource? {
        sources.first { $0.id == activeSourceID } ?? sources.first
    }

    // MARK: Lifecycle

    /// Restores persisted state and refreshes the active source.
    public func start() async {
        await metadata.loadCaches()
        usesArtworkProvider = await metadata.hasArtworkProvider
        hasCompletedIntro = await storage.load(Bool.self, from: Self.introFile) ?? false

        await discovery.loadCache()
        discoveryShelves = await discovery.cached
        let stored = await storage.load([PlaylistSource].self, from: Self.sourcesFile) ?? []
        watchState = await storage.load(WatchState.self, from: WatchState.fileName) ?? WatchState()
        sources = stored
        activeSourceID = stored.first?.id

        guard let source = activeSource else {
            phase = .welcome
            return
        }

        // Show the catalogue we already have before going anywhere near the
        // network. A real provider is 135 MB and takes the better part of a
        // minute to fetch and parse; making someone watch that on every launch
        // is the difference between an app that feels instant and one that
        // does not.
        if let cached = await loader.loadCache(for: source.id, storage: storage) {
            library = cached
            phase = .ready
            if let epgURL = source.epgURL { loadGuide(from: epgURL) }
            refreshDiscovery()
            await refresh(source, inBackground: true)
        } else {
            await refresh(source)
        }
    }

    /// The whole of setup: one string in, a loaded library out.
    @discardableResult
    public func addSource(from input: String) async -> SourceDetector.Detection {
        let detection = SourceDetector.detect(input)
        switch detection {
        case .complete(let source):
            await add(source)
        case .pastedText(let text):
            await addPastedPlaylist(text)
        case .needsCredentials, .unrecognized:
            break
        }
        return detection
    }

    public func addXtreamSource(portal: URL, username: String, password: String) async {
        await add(SourceDetector.xtreamSource(portal: portal, username: username, password: password))
    }

    public func add(_ source: PlaylistSource) async {
        sources.append(source)
        activeSourceID = source.id
        await persistSources()
        await refresh(source)
    }

    public func completeIntro() async {
        hasCompletedIntro = true
        await storage.save(true, to: Self.introFile)
    }

    /// Renames a playlist. The detected name is only ever a starting point —
    /// "fomo.re" is where a list came from, not what a person calls it.
    public func rename(_ source: PlaylistSource, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var updated = sources.first(where: { $0.id == source.id }) else {
            return
        }
        updated.name = trimmed
        replace(updated)
        await persistSources()
    }

    public func remove(_ source: PlaylistSource) async {
        await storage.removeCache(LibraryCache.fileName(for: source.id))
        sources.removeAll { $0.id == source.id }
        if activeSourceID == source.id {
            activeSourceID = sources.first?.id
            library = .empty
            guide = nil
        }
        await persistSources()
        if let next = activeSource {
            await refresh(next)
        } else {
            phase = .welcome
        }
    }

    public func switchTo(_ source: PlaylistSource) async {
        guard source.id != activeSourceID else { return }
        activeSourceID = source.id
        library = .empty
        guide = nil
        await refresh(source)
    }

    public func refreshActiveSource() async {
        guard let source = activeSource else { return }
        await refresh(source)
    }

    // MARK: Loading

    private func refresh(_ source: PlaylistSource, inBackground: Bool = false) async {
        if inBackground {
            isRefreshingLibrary = true
        } else {
            phase = .loading(String(localized: CoreStrings.loadingSource(source.name)))
        }
        defer { isRefreshingLibrary = false }

        do {
            let result = try await loader.loadLibrary(for: source)
            self.library = result.library
            let epgURL = result.epgURL

            var diagnostics = SourceDiagnostics()
            diagnostics.skippedPlaylistLines = result.skippedLines
            diagnostics.channelsWithID = result.library.channels.count {
                $0.channelID?.isEmpty == false
            }
            self.diagnostics = diagnostics
            phase = .ready
            await loader.saveCache(result.library, for: source.id, storage: storage)

            if var updated = sources.first(where: { $0.id == source.id }) {
                updated.lastRefreshedAt = .now
                updated.epgURL = epgURL
                replace(updated)
                await persistSources()
            }
            if let epgURL {
                loadGuide(from: epgURL)
            }
            if !inBackground { refreshDiscovery() }
        } catch {
            // A refresh behind a visible catalogue must not replace it with an
            // error screen — what is on screen still works.
            guard !inBackground else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Recommendations are a nicety on top of a working library, so nothing
    /// ever waits on them and a failure is silent.
    private func refreshDiscovery() {
        Task { [discovery] in
            let shelves = await discovery.refreshIfStale()
            await MainActor.run { self.discoveryShelves = shelves }
        }
    }

    /// Fire-and-forget: the guide enriches the UI but nothing waits on it.
    private func loadGuide(from url: URL) {
        isRefreshingGuide = true
        Task { [loader] in
            let result = try? await loader.loadGuide(from: url)
            await MainActor.run {
                if let result {
                    self.guide = result.guide
                    self.recordGuideDiagnostics(result)
                }
                self.isRefreshingGuide = false
            }
        }
    }

    /// Coverage is measured against the library, not the file: a guide with a
    /// million programmes for channels nobody has is still an empty guide.
    private func recordGuideDiagnostics(_ result: XMLTVParser.ParseResult) {
        diagnostics.guideProgrammes = result.programmeCount
        diagnostics.guideRepairs = result.repairs
        diagnostics.guideIsPartial = result.isPartial
        diagnostics.guideChannelsMatched = library.channels.count { channel in
            guard let id = channel.channelID else { return false }
            return result.guide.schedules[id]?.programmes.isEmpty == false
        }
    }

    private func addPastedPlaylist(_ text: String) async {
        let playlist = M3UParser().parse(text)
        guard !playlist.items.isEmpty else {
            phase = .failed(String(localized: CoreStrings.emptyPlaylist))
            return
        }
        let source = PlaylistSource(kind: .localFile, name: "Pasted playlist", epgURL: playlist.epgURL)
        sources.append(source)
        activeSourceID = source.id
        library = Library(items: playlist.items)
        phase = .ready
        await persistSources()
        if let epgURL = playlist.epgURL { loadGuide(from: epgURL) }
    }

    private func replace(_ source: PlaylistSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
    }

    private func persistSources() async {
        await storage.save(sources, to: Self.sourcesFile)
    }

    /// Progress updates arrive every few seconds during playback; coalesce them.
    private func scheduleWatchStateSave() {
        watchStateSaveTask?.cancel()
        let snapshot = watchState
        watchStateSaveTask = Task { [storage] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await storage.save(snapshot, to: WatchState.fileName)
        }
    }
}

// MARK: - Episodes

public extension AppModel {

    /// Whether a show's episodes are being fetched right now.
    func isLoadingEpisodes(_ group: SeriesGroup) -> Bool {
        guard let id = group.providerSeriesID else { return false }
        return episodeLoadsInFlight.contains(id)
    }

    /// The episodes to show for a group: the ones the playlist already had, or
    /// the ones we fetched from the panel.
    func episodes(for group: SeriesGroup) -> [MediaItem] {
        guard let id = group.providerSeriesID, let fetched = loadedEpisodes[id], !fetched.isEmpty else {
            return group.episodes
        }
        return fetched
    }

    func episodeLoadFailure(for group: SeriesGroup) -> String? {
        group.providerSeriesID.flatMap { episodeLoadFailures[$0] }
    }

    /// Fetches a show's episodes, once. Panels store tens of thousands of
    /// episodes, so they are never part of the initial library load.
    func loadEpisodesIfNeeded(for group: SeriesGroup) async {
        guard group.needsEpisodeLoad,
              let seriesID = group.providerSeriesID,
              let source = activeSource,
              loadedEpisodes[seriesID] == nil,
              !episodeLoadsInFlight.contains(seriesID)
        else { return }

        episodeLoadsInFlight.insert(seriesID)
        episodeLoadFailures[seriesID] = nil
        defer { episodeLoadsInFlight.remove(seriesID) }

        do {
            let episodes = try await loader.loadEpisodes(for: source, seriesID: seriesID)
            loadedEpisodes[seriesID] = episodes
        } catch {
            episodeLoadFailures[seriesID] = error.localizedDescription
        }
    }
}

// MARK: - Search

/// What a search turned up, and how.
public struct SearchOutcome: Sendable {
    public var items: [MediaItem]
    /// The title the query was translated through, when translation is what
    /// produced the results. Shown to the person so the jump is not magic.
    public var matchedVia: String?

    public init(items: [MediaItem], matchedVia: String? = nil) {
        self.items = items
        self.matchedVia = matchedVia
    }
}

public extension AppModel {

    /// Searches the library, then — only if that came up short — asks what the
    /// query means and searches again under every other name the title has.
    ///
    /// The order matters: a local hit is instant and offline, so the network is
    /// never on the path for the common case.
    func search(_ query: String) async -> SearchOutcome {
        let local = library.search(query)
        // Three solid local hits is enough; no reason to go to the network.
        if local.count >= 3 { return SearchOutcome(items: local) }

        let (spellings, _) = await metadata.alternativeSpellings(for: query)
        guard !spellings.isEmpty else { return SearchOutcome(items: local) }

        var merged = local
        var seen = Set(local.map(\.id))
        var matchedVia: String?
        for spelling in spellings {
            let hits = library.search(spelling, limit: 50)
            for item in hits where seen.insert(item.id).inserted {
                merged.append(item)
                matchedVia = matchedVia ?? spelling
            }
        }
        return SearchOutcome(items: merged, matchedVia: matchedVia)
    }
}

// MARK: - Recommendations

public extension AppModel {

    /// Entry id to its place in the recommendations, so a browse screen can
    /// open on what the world rates rather than on whatever the panel listed
    /// first.
    var discoveryRanking: [String: Int] {
        var ranking: [String: Int] = [:]
        var position = 0
        for shelf in discoveryShelves {
            for item in library.items(matching: shelf.titles, limit: 40)
            where ranking[item.id] == nil {
                ranking[item.id] = position
                position += 1
            }
        }
        return ranking
    }

    /// Rows worth drawing: those where the library carries enough of what was
    /// recommended to look deliberate rather than sparse.
    var visibleDiscoveryShelves: [(shelf: DiscoveryShelf, items: [MediaItem])] {
        discoveryShelves.compactMap { shelf in
            let items = library.items(matching: shelf.titles)
            guard items.count >= 4 else { return nil }
            return (shelf, items)
        }
    }
}

// MARK: - Derived shelves

public extension AppModel {

    /// The "Continue watching" shelf: recent, unfinished, still in the library.
    var continueWatching: [MediaItem] {
        watchState.recentIDs.compactMap { id -> MediaItem? in
            guard let progress = watchState.progress[id], progress.isWorthResuming else { return nil }
            return library.item(id: id)
        }
    }

    var favoriteChannels: [MediaItem] {
        library.channels.filter { watchState.isFavorite($0.id) }
    }

    var favoriteSeries: [SeriesGroup] {
        library.series.filter { watchState.isFavorite($0.id) }
    }

    var favoriteMovies: [MediaItem] {
        library.movies.filter { watchState.isFavorite($0.id) }
    }

    func progress(for item: MediaItem) -> WatchProgress? {
        watchState.progress[item.id]
    }

    /// What is on this channel right now, when we have a guide for it.
    func nowPlaying(on channel: MediaItem) -> Programme? {
        guard let channelID = channel.channelID, let guide else { return nil }
        return guide.schedules[channelID]?.programme()
    }

    func upcoming(on channel: MediaItem, limit: Int = 3) -> [Programme] {
        guard let channelID = channel.channelID, let guide else { return [] }
        return guide.schedules[channelID]?.upcoming(limit: limit) ?? []
    }

    func toggleFavorite(_ id: String) {
        watchState.toggleFavorite(id)
    }

    func record(itemID: String, position: TimeInterval, duration: TimeInterval) {
        guard duration > 0 else { return }
        watchState.record(
            WatchProgress(itemID: itemID, position: position, duration: duration)
        )
    }
}
