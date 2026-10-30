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
        /// Before anything has been read from disk. Distinct from `welcome`,
        /// which is a real state meaning "this person has no playlist" — a
        /// returning user must never be shown the setup screen in the moment
        /// before their own library appears.
        case starting
        case welcome
        case loading(String)
        case ready
        case failed(String)
    }

    // MARK: State

    public private(set) var phase: Phase = .starting
    /// Plain-language progress for a first connection or repair attempt.
    public private(set) var connectionProgress: ConnectionProgress?
    public private(set) var syncState: HouseholdSyncState = .waiting
    public private(set) var sources: [PlaylistSource] = [] {
        didSet { if !isApplyingHousehold { householdRevision &+= 1 } }
    }
    public private(set) var activeSourceID: UUID?
    /// Everything the source returned, before any profile is considered.
    ///
    /// Only the profile machinery reads this. Every screen reads `library`, so
    /// a screen that forgets about age limits cannot exist.
    public internal(set) var catalogue: Library = .empty {
        didSet { catalogueRevision &+= 1 }
    }
    /// Bumped on every catalogue change, so a narrowing computed off the main
    /// actor can tell whether it still describes the catalogue it was cut from.
    @ObservationIgnored var catalogueRevision: UInt64 = 0
    /// What the person watching right now is allowed to see.
    public internal(set) var library: Library = .empty
    public internal(set) var profiles: [Profile] = [] {
        didSet { if !isApplyingHousehold { householdRevision &+= 1 } }
    }
    public internal(set) var activeProfileID: UUID?
    var profileSelectionGeneration: UInt64 = 0
    /// Whether the "who is watching?" screen is up.
    ///
    /// Kept apart from `phase` on purpose: the picker is shown *over* whatever
    /// the app is doing, which is what turns choosing a profile into the moment
    /// the catalogue loads instead of an extra wait bolted in front of it.
    public internal(set) var isChoosingProfile = false
    public internal(set) var ratings = RatingIndex()
    /// Set when a restricted profile is active and something was withheld —
    /// the count behind "some things are hidden here".
    public internal(set) var withheldCount = 0
    /// Titles in this profile's approved sections still waiting on an age
    /// rating. Drives "checking 340 of 1,200" rather than a library that looks
    /// mysteriously thin while the lookups run.
    public internal(set) var ratingsPending = 0
    public private(set) var guide: XMLTVParser.Guide?
    public private(set) var isRefreshingGuide = false
    /// A refresh running behind an already-visible catalogue.
    public private(set) var isRefreshingLibrary = false
    /// What was wrong with the data this source sent, if anything.
    public private(set) var diagnostics = SourceDiagnostics()
    /// Films and shows detected when this service last changed its catalogue.
    /// Stored per service so switching away and back does not mix libraries.
    public private(set) var libraryUpdates = LibraryUpdates()
    /// Whether an artwork provider is configured — drives required attribution.
    public private(set) var usesArtworkProvider = false
    /// Whether national board ratings can be fetched at all. Without a key the
    /// app still works — a grown-up's approvals carry the load — but the
    /// profile editor says so rather than leaving a parent wondering why
    /// nothing fills in on its own.
    public internal(set) var canVerifyRatings = false
    /// Whether the intro has been seen. Kept in its own file rather than in
    /// `WatchState`, so adding it cannot fail to decode anyone's favourites.
    public private(set) var hasCompletedIntro = false
    /// Episodes fetched on demand, keyed by the provider's series id.
    public private(set) var loadedEpisodes: [Int: [MediaItem]] = [:]
    public private(set) var episodeLoadFailures: [Int: String] = [:]
    private var episodeLoadsInFlight: Set<Int> = []
    public private(set) var homeContent = HomeContent()
    private var cachedFavoriteChannels: [MediaItem] = []
    private var cachedFavoriteChannelGroups: [ChannelGroup] = []
    private var cachedFavoriteMovies: [MediaItem] = []
    private var cachedFavoriteSeries: [SeriesGroup] = []
    @ObservationIgnored private var homeIndex = HomeLibraryIndex()
    /// Current scoped item key → older scoped key carrying its progress. M3U
    /// services often put expiring URLs into ids, so the same film can receive
    /// a new technical id while its semantic title/year identity stays put.
    @ObservationIgnored private var progressHistoryAliases: [String: String] = [:]
    @ObservationIgnored private var libraryUpdatesExpiryTask: Task<Void, Never>?
    public var watchState = WatchState() {
        didSet {
            if !isApplyingHousehold { householdRevision &+= 1 }
            scheduleWatchStateSave()
            if oldValue.favoriteIDs != watchState.favoriteIDs {
                rebuildFavoriteContent()
            }
            // Progress arrives repeatedly during playback. Re-resolve only the
            // history rows; the catalogue-dependent "new" rows stay cached.
            rebuildHomeContent(resolveLibraryUpdates: false)
        }
    }

    public let metadata: MetadataService
    public let discovery: DiscoveryService
    public let ratingService: RatingService
    public let parentalCode = ParentalCode()
    /// Recommendation rows, already filtered to what this library carries.
    public private(set) var discoveryShelves: [DiscoveryShelf] = []
    /// A compact, pre-ranked snapshot shared by Home, Films and Series.
    /// Building it also resolves the outside recommendations against this
    /// person's visible library, so no SwiftUI body walks a provider-sized
    /// catalogue while someone scrolls.
    public private(set) var discoveryPresentation = DiscoveryPresentation()
    /// Kept as a small compatibility surface for full movie-library sorting.
    /// Series deliberately has its own group-id ranking in the presentation.
    public private(set) var discoveryRanking: [String: Int] = [:]
    /// Changes only when a complete browse snapshot lands. Screens can use it
    /// to invalidate an off-main full-library sort without hashing the arrays.
    public private(set) var browseRevision: UInt64 = 0
    private let loader: any LibraryLoading
    let storage: KanalStorage
    private let credentialStore: any SourceCredentialStoring
    private let householdSync: any HouseholdSyncing
    private var watchStateSaveTask: Task<Void, Never>?
    private var householdSyncTask: Task<Void, Never>?
    private var householdReplica = HouseholdReplica()
    private var householdRevision: UInt64 = 0
    private var isApplyingHousehold = false
    private var isSyncInFlight = false
    private var isReceivingPairing = false
    private var syncRequestedAgain = false
    private var credentialMigrationFailure: String?
    private static let replicaFile = "household-replica.json"
    private var householdChangeTask: Task<Void, Never>?
    private var matchingTask: Task<Void, Never>?
    private var discoveryMatchGeneration: UInt64 = 0
    /// Who the cached `discoveryShelves` were fetched for.
    var discoveryAudience: DiscoveryAudience = .everyone
    var verificationTask: Task<Void, Never>?
    /// Every library load supersedes the one before it. The generation is
    /// checked after each suspension point before any result reaches state.
    private var libraryLoadGeneration: UInt64 = 0
    @ObservationIgnored private var deferredLibraryTask: Task<Void, Never>?
    /// Guide downloads have their own generation because they outlive the
    /// library load that discovered their URL.
    private var guideLoadGeneration: UInt64 = 0

    private static let sourcesFile = "sources.json"
    private static let introFile = "intro-completed.json"
    static let profilesFile = "profiles.json"
    private static let syncStampFile = "household-sync-stamp.json"

    public init(
        loader: any LibraryLoading = LibraryLoader(),
        storage: KanalStorage = .shared,
        metadata: MetadataService? = nil,
        credentialStore: (any SourceCredentialStoring)? = nil,
        householdSync: (any HouseholdSyncing)? = nil
    ) {
        self.loader = loader
        self.storage = storage
        #if os(macOS)
        self.credentialStore = credentialStore ?? MemorySourceCredentialStore()
        self.householdSync = householdSync ?? NoopHouseholdSync()
        #else
        self.credentialStore = credentialStore ?? KeychainSourceCredentialStore()
        self.householdSync = householdSync ?? ICloudHouseholdSync()
        #endif
        // Wikidata is always available and needs no key. A TMDB key, if the
        // app was built with one, only adds artwork on top.
        let tmdbKey = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String
        self.metadata = metadata ?? MetadataService(tmdbAPIKey: tmdbKey, storage: storage)
        self.discovery = DiscoveryService(apiKey: tmdbKey, storage: storage)
        self.ratingService = RatingService(tmdbAPIKey: tmdbKey, storage: storage)
    }

    public var activeSource: PlaylistSource? {
        sources.first { $0.id == activeSourceID } ?? sources.first
    }

    public var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// The rules in force right now.
    ///
    /// Falls back to a restricted profile with nothing approved when no profile
    /// has been chosen. That is the safe end of the failure: a moment of an
    /// empty library, rather than a moment of the whole catalogue.
    public var policy: ContentPolicy {
        ContentPolicy(
            profile: activeProfile ?? Profile(name: "", maturity: .allAges),
            ratings: ratings
        )
    }

    public var isRestricted: Bool { activeProfile?.isRestricted ?? true }

    // MARK: Lifecycle

    /// Restores persisted state and refreshes the active source.
    public func start() async {
        observeHouseholdChanges()
        await metadata.loadCaches()
        usesArtworkProvider = await metadata.hasArtworkProvider
        hasCompletedIntro = await storage.load(Bool.self, from: Self.introFile) ?? false

        await ratingService.load()
        ratings = await ratingService.current
        canVerifyRatings = await ratingService.canVerifyAutomatically

        await discovery.loadCache()
        discoveryShelves = await discovery.cached
        let stored = await storage.load([PlaylistSource].self, from: Self.sourcesFile) ?? []
        sources = await migrateAndHydrate(stored)
        profiles = await storage.load([Profile].self, from: Self.profilesFile) ?? []
        householdReplica = await storage.load(HouseholdReplica.self, from: Self.replicaFile)
            ?? HouseholdReplica()
        await syncNow()
        activeSourceID = sources.first(where: Self.hasConnection)?.id ?? sources.first?.id

        guard let source = activeSource, Self.hasConnection(source) else {
            phase = .welcome
            scheduleHouseholdSync()
            return
        }
        installLibraryUpdates(await storage.load(
            LibraryUpdates.self, from: Self.libraryUpdatesFile(for: source.id)
        ))

        // Someone who has been using Kanal since before profiles existed keeps
        // everything they had, as a grown-up.
        if profiles.isEmpty { await adoptExistingHousehold() }

        // Ask who is watching before anything is drawn, and load the catalogue
        // behind the question. A real provider is 135 MB; the seconds a person
        // spends picking their own face are seconds nobody spends waiting.
        if shouldAskWhoIsWatching {
            isChoosingProfile = true
        } else if let only = profiles.first {
            await activate(only)
        }
        scheduleHouseholdSync()

        // Show the catalogue we already have before going anywhere near the
        // network. A real provider is 135 MB and takes the better part of a
        // minute to fetch and parse; making someone watch that on every launch
        // is the difference between an app that feels instant and one that
        // does not.
        if let cached = await loader.loadCache(for: source.id, storage: storage) {
            await setCatalogue(cached)
            // Draw first. Matching recommendations builds the search index,
            // which on a real catalogue is seconds of work nobody should wait
            // through to see their own channels.
            phase = .ready
            scheduleDiscoveryMatching()
            if let epgURL = source.epgURL { loadGuide(from: epgURL, for: source.id) }
            refreshDiscovery()
            await refresh(source, inBackground: true)
        } else {
            await refresh(source)
        }
    }

    /// The whole of setup: one string in, a loaded library out.
    @discardableResult
    public func addSource(from input: String) async throws -> SourceDetector.Detection {
        let detection = SourceDetector.detect(input)
        switch detection {
        case .complete(let source):
            try await add(source)
        case .pastedText(let text):
            do {
                try await addPastedPlaylist(text)
            } catch {
                if sources.isEmpty { phase = .welcome }
                throw error
            }
        case .needsCredentials, .unrecognized:
            break
        }
        return detection
    }

    public func addXtreamSource(portal: URL, username: String, password: String) async throws {
        try await add(SourceDetector.xtreamSource(
            portal: portal, username: username, password: password
        ))
    }

    /// Replaces a broken saved service without changing its identity. Keeping
    /// the id means favourites, history and cached catalogue ownership remain
    /// attached to the service the person is repairing.
    @discardableResult
    public func repairSource(
        _ existing: PlaylistSource, from input: String
    ) async throws -> SourceDetector.Detection {
        let detection = SourceDetector.detect(input)
        switch detection {
        case .complete(var replacement):
            replacement.id = existing.id
            replacement.name = existing.name
            replacement.createdAt = existing.createdAt
            try await replaceSource(existing, with: replacement)
        case .pastedText(let text):
            try await replacePastedSource(existing, with: text)
        case .needsCredentials, .unrecognized:
            break
        }
        return detection
    }

    public func repairXtreamSource(
        _ existing: PlaylistSource,
        portal: URL,
        username: String,
        password: String
    ) async throws {
        var replacement = SourceDetector.xtreamSource(
            portal: portal,
            username: username,
            password: password,
            name: existing.name
        )
        replacement.id = existing.id
        replacement.createdAt = existing.createdAt
        try await replaceSource(existing, with: replacement)
    }

    /// Validates a source before it becomes part of the household.
    ///
    /// Loading first is deliberate. A typo must not replace a library that is
    /// already working, and a broken first attempt must not be persisted into
    /// a retry loop on the next launch.
    public func add(_ source: PlaylistSource) async throws {
        try await add([source])
    }

    /// Adds a handoff payload as one transaction.
    ///
    /// Every source proves it can load before any of them appears on disk or
    /// in memory. The final source becomes active, matching the order the
    /// sending device presented.
    public func add(_ incomingSources: [PlaylistSource], household: HouseholdSnapshot? = nil) async throws {
        guard let firstSource = incomingSources.first,
              let lastSource = incomingSources.last
        else { return }

        let previousPhase = phase
        let preservesVisibleLibrary = activeSource != nil && previousPhase == .ready
        let load = beginLibraryLoad(for: lastSource, showsRefreshActivity: preservesVisibleLibrary)
        connectionProgress = progressForContacting(firstSource)

        if !preservesVisibleLibrary, previousPhase != .welcome {
            phase = .loading(String(localized: CoreStrings.loadingSource(firstSource.name)))
        }
        defer { finishLibraryLoad(load) }

        var validated: [ValidatedSource] = []
        validated.reserveCapacity(incomingSources.count)
        var stagedFirstImport = false
        do {
            for source in incomingSources {
                connectionProgress = progressForContacting(source)
                let staged: LibraryLoader.LibraryResult?
                if incomingSources.count == 1 && sources.isEmpty {
                    staged = try await loader.loadPlayableChannels(for: source)
                } else {
                    staged = nil
                }
                let result: LibraryLoader.LibraryResult
                if let staged {
                    result = staged
                } else {
                    result = try await loader.loadLibrary(for: source)
                }
                guard isCurrent(load) else { throw CancellationError() }
                connectionProgress = .organising
                validated.append(ValidatedSource(source: source, result: result))
                stagedFirstImport = staged != nil
            }
            try await commit(validated, load: load, household: household)
        } catch {
            guard isCurrent(load) else { throw CancellationError() }
            // An existing library remains usable, including its phase and
            // active-source identity. With no working source, return to setup
            // so the caller can explain and repair the input inline.
            phase = preservesVisibleLibrary
                ? previousPhase
                : (sources.isEmpty ? .welcome : previousPhase)
            connectionProgress = nil
            throw error
        }

        if stagedFirstImport, let active = validated.last {
            scheduleDeferredLibrary(
                for: active.source, including: active.result, load: load
            )
        }
    }

    /// Transfers a complete household over the QR-authenticated LAN channel.
    /// No profile or credential is expected to arrive later through iCloud.
    public func makePairingPayload() async throws -> Pairing.Payload {
        await flushPendingWatchState()
        let hydrated = await hydrate(sources)
        guard !hydrated.isEmpty else { throw LibraryLoader.LoadError.emptyPlaylist }
        guard hydrated.allSatisfy(Self.hasConnection) else { throw LibraryLoader.LoadError.noPlaylistURL }
        var files: [String: String] = [:]
        var outgoing = hydrated
        for index in outgoing.indices where outgoing[index].kind == .localFile {
            guard let url = outgoing[index].playlistURL, url.isFileURL else {
                throw LibraryLoader.LoadError.emptyPlaylist
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 3_500_000, let text = String(data: data, encoding: .utf8) else {
                throw SyncError.payloadTooLarge
            }
            files[outgoing[index].id.uuidString] = text
            outgoing[index].playlistURL = nil
        }
        let local = await makeHouseholdSnapshot()
        householdReplica.observe(local: local)
        return Pairing.Payload(sources: outgoing,
                               household: householdReplica.snapshot().sanitizedForSync(),
                               activeSourceID: activeSourceID, localPlaylists: files)
    }

    public func receivePairing(_ payload: Pairing.Payload) async throws {
        guard !isReceivingPairing, !payload.sources.isEmpty,
              Set(payload.sources.map(\.id)).count == payload.sources.count else {
            throw LibraryLoader.LoadError.emptyPlaylist
        }
        isReceivingPairing = true
        householdSyncTask?.cancel()
        defer { isReceivingPairing = false; scheduleHouseholdSync() }
        // Let any already-running merge finish before staging the handoff.
        while isSyncInFlight { try await Task.sleep(for: .milliseconds(20)) }
        var incoming = payload.sources
        for index in incoming.indices where incoming[index].kind == .localFile {
            guard let text = payload.localPlaylists?[incoming[index].id.uuidString],
                  !M3UParser().parse(text).items.isEmpty else {
                throw LibraryLoader.LoadError.emptyPlaylist
            }
            incoming[index].playlistURL = try await storage.saveImportedPlaylist(text, for: incoming[index].id)
        }
        // add() activates its last entry. Preserve the phone's selected service.
        if let id = payload.activeSourceID, let index = incoming.firstIndex(where: { $0.id == id }) {
            incoming.append(incoming.remove(at: index))
        }
        try await add(incoming, household: payload.household)
        await completeIntro()
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
        invalidateLibraryLoads()
        await storage.removeCache(LibraryCache.fileName(for: source.id))
        await storage.removeImportedPlaylist(for: source.id)
        await storage.remove(Self.libraryUpdatesFile(for: source.id))
        try? await credentialStore.remove(for: source.id)
        sources.removeAll { $0.id == source.id }
        if activeSourceID == source.id {
            invalidateGuideLoads()
            clearLoadedEpisodes()
            activeSourceID = sources.first?.id
            await setCatalogue(.empty)
            guide = nil
            if let nextID = activeSourceID {
                installLibraryUpdates(await storage.load(
                    LibraryUpdates.self, from: Self.libraryUpdatesFile(for: nextID)
                ))
            } else {
                installLibraryUpdates(nil)
            }
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
        invalidateLibraryLoads()
        invalidateGuideLoads()
        clearLoadedEpisodes()
        activeSourceID = source.id
        await setCatalogue(.empty)
        guide = nil
        installLibraryUpdates(await storage.load(
            LibraryUpdates.self, from: Self.libraryUpdatesFile(for: source.id)
        ))
        await refresh(source)
    }

    public func refreshActiveSource() async {
        guard let source = activeSource else { return }
        await refresh(source)
    }

    // MARK: Loading

    private func refresh(_ source: PlaylistSource, inBackground: Bool = false) async {
        let load = beginLibraryLoad(for: source, showsRefreshActivity: inBackground)
        if !inBackground { connectionProgress = progressForContacting(source) }
        if !inBackground {
            phase = .loading(String(localized: CoreStrings.loadingSource(source.name)))
        }
        defer { finishLibraryLoad(load) }

        do {
            let staged: LibraryLoader.LibraryResult?
            if !inBackground && catalogue.isEmpty {
                staged = try await loader.loadPlayableChannels(for: source)
            } else {
                staged = nil
            }
            let result: LibraryLoader.LibraryResult
            if let staged {
                result = staged
            } else {
                result = try await loader.loadLibrary(for: source)
            }
            if !inBackground { connectionProgress = .organising }
            let updates = LibraryUpdates.detect(previous: catalogue, current: result.library)
            let preparedRatings = await ratingsForInstallation(of: result.library)
            guard isCurrent(load), activeSourceID == source.id else { return }

            if !updates.isEmpty {
                installLibraryUpdates(updates)
            } else {
                refreshLibraryUpdatesLifetime()
            }
            installCatalogue(result.library, ratings: preparedRatings)
            scheduleDiscoveryMatching()
            let epgURL = result.epgURL

            var diagnostics = SourceDiagnostics()
            diagnostics.skippedPlaylistLines = result.skippedLines
            diagnostics.channelsWithID = result.library.channels.count {
                $0.channelID?.isEmpty == false
            }
            self.diagnostics = diagnostics
            phase = .ready
            self.diagnostics.timeToFirstPlayableChannel = elapsedSeconds(since: load.startedAt)
            if !inBackground { connectionProgress = .ready }

            if var updated = sources.first(where: { $0.id == source.id }) {
                updated.lastRefreshedAt = .now
                updated.epgURL = epgURL
                replace(updated)
            }

            let mergedRatings = await ratingService.merge(preparedRatings)
            guard isCurrent(load), activeSourceID == source.id else { return }
            ratings = mergedRatings
            applyPolicy()
            scheduleVerification()

            // State above is one synchronous commit. These writes may suspend,
            // so every UI-affecting action below checks the generation again.
            await persistSources()
            if !updates.isEmpty {
                await storage.save(updates, to: Self.libraryUpdatesFile(for: source.id))
            }
            await loader.saveCache(result.library, for: source.id, storage: storage)
            guard isCurrent(load), activeSourceID == source.id else { return }

            if let epgURL {
                loadGuide(from: epgURL, for: source.id)
            }
            if !inBackground { refreshDiscovery() }
            if staged != nil {
                scheduleDeferredLibrary(for: source, including: result, load: load)
            }
        } catch {
            guard isCurrent(load), activeSourceID == source.id else { return }
            // A refresh behind a visible catalogue must not replace it with an
            // error screen — what is on screen still works.
            guard !inBackground else { return }
            phase = .failed(error.localizedDescription)
            connectionProgress = nil
        }
    }

    /// Lets a successful channel stage end the blocking setup flow. The rest
    /// of a large Xtream catalogue lands as a second, generation-checked
    /// snapshot and cannot overwrite a later source switch or repair.
    private func scheduleDeferredLibrary(
        for source: PlaylistSource,
        including initial: LibraryLoader.LibraryResult,
        load: LibraryLoad
    ) {
        deferredLibraryTask?.cancel()
        deferredLibraryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            guard self.isCurrent(load) else { return }
            self.isRefreshingLibrary = true
            defer {
                if self.isCurrent(load) { self.isRefreshingLibrary = false }
            }
            do {
                guard let result = try await self.loader.loadDeferredLibrary(
                    for: source, including: initial
                ) else { return }
                let preparedRatings = await self.ratingsForInstallation(of: result.library)
                guard !Task.isCancelled,
                      self.isCurrent(load),
                      self.activeSourceID == source.id
                else { return }

                self.installCatalogue(result.library, ratings: preparedRatings)
                self.scheduleDiscoveryMatching()
                let mergedRatings = await self.ratingService.merge(preparedRatings)
                guard !Task.isCancelled,
                      self.isCurrent(load),
                      self.activeSourceID == source.id
                else { return }
                self.ratings = mergedRatings
                self.applyPolicy()
                self.scheduleVerification()
                await self.loader.saveCache(result.library, for: source.id, storage: self.storage)
            } catch is CancellationError {
                return
            } catch {
                // Channels remain playable. A later manual refresh retries the
                // optional catalogues without turning success into an error.
                return
            }
        }
    }

    /// Runs the matching after the current screen has had a chance to draw.
    func scheduleDiscoveryMatching(reset: Bool = false) {
        matchingTask?.cancel()
        discoveryMatchGeneration &+= 1
        let generation = discoveryMatchGeneration
        let library = library
        let shelves = discoveryShelves
        let audience = discoveryAudience

        // A profile change must never leave the previous profile's discovery
        // cards on screen while its replacement is being calculated.
        if reset {
            discoveryPresentation = DiscoveryPresentation()
            discoveryRanking = [:]
            browseRevision &+= 1
        }

        matchingTask = Task { @MainActor in
            // One turn of the run loop is enough for the first frame.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let presentation = await DiscoveryPresentationQueue.shared.build(
                library: library, shelves: shelves, audience: audience
            )
            guard !Task.isCancelled, generation == discoveryMatchGeneration else { return }
            discoveryPresentation = presentation
            discoveryRanking = presentation.itemRanking
            browseRevision &+= 1
        }
    }

    /// Recommendations are a nicety on top of a working library, so nothing
    /// ever waits on them and a failure is silent.
    private func refreshDiscovery() {
        let audience = DiscoveryAudience(profile: activeProfile)
        discoveryAudience = audience
        Task { [discovery] in
            // Whatever was cached for this audience goes up first, so a child
            // switching profiles sees their own rows rather than the previous
            // person's while the network catches up.
            let cached = await discovery.use(audience)
            if !cached.isEmpty {
                await MainActor.run {
                    self.discoveryShelves = cached
                    self.scheduleDiscoveryMatching()
                }
            }
            let shelves = await discovery.refreshIfStale()
            await MainActor.run {
                guard self.discoveryAudience == audience else { return }
                let hadNothing = self.discoveryShelves.isEmpty
                self.discoveryShelves = shelves
                self.scheduleDiscoveryMatching()
                // A restricted profile's rows are gated on ratings, and the
                // queue that produces them is ordered by these shelves. When
                // they arrive after the queue was built — which is exactly
                // what a profile switch does — it is worth rebuilding so the
                // first lookups go to the titles the rows are waiting for.
                if hadNothing, !shelves.isEmpty, self.isRestricted {
                    self.scheduleVerification()
                }
            }
        }
    }

    /// Re-asks TMDB when the person watching changes what a good suggestion is.
    ///
    /// A child's rows are a different request, not a filtered version of the
    /// grown-up's — see `DiscoveryAudience`. Cheap when nothing changed, which
    /// matters because `applyPolicy` runs on every rating that lands.
    func refreshDiscoveryForAudience() {
        let audience = DiscoveryAudience(profile: activeProfile)
        guard audience != discoveryAudience else { return }
        // The outgoing audience's rows must not survive the switch even for a
        // frame: they were chosen for somebody else.
        discoveryShelves = []
        refreshDiscovery()
    }

    /// Fire-and-forget: the guide enriches the UI but nothing waits on it.
    private func loadGuide(from url: URL, for sourceID: UUID) {
        guideLoadGeneration &+= 1
        let generation = guideLoadGeneration
        isRefreshingGuide = true
        Task { [loader] in
            let result = try? await loader.loadGuide(from: url)
            await MainActor.run {
                guard generation == self.guideLoadGeneration,
                      sourceID == self.activeSourceID
                else { return }
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

    private func addPastedPlaylist(_ text: String) async throws {
        let playlist = M3UParser().parse(text)
        guard !playlist.items.isEmpty else {
            if sources.isEmpty { phase = .welcome }
            throw LibraryLoader.LoadError.emptyPlaylist
        }

        let sourceID = UUID()
        let source = PlaylistSource(
            id: sourceID,
            kind: .localFile,
            name: "Pasted playlist",
            epgURL: playlist.epgURL
        )
        let previousPhase = phase
        let preservesVisibleLibrary = activeSource != nil && previousPhase == .ready
        let load = beginLibraryLoad(for: source, showsRefreshActivity: preservesVisibleLibrary)
        connectionProgress = .organising
        defer { finishLibraryLoad(load) }

        let fileURL: URL
        do {
            fileURL = try await storage.saveImportedPlaylist(text, for: sourceID)
        } catch {
            guard isCurrent(load) else { throw CancellationError() }
            throw error
        }
        var storedSource = source
        storedSource.playlistURL = fileURL
        let result = LibraryLoader.LibraryResult(
            library: Library(items: playlist.items),
            epgURL: playlist.epgURL,
            skippedLines: playlist.skippedLineCount
        )
        do {
            try await commit([ValidatedSource(source: storedSource, result: result)], load: load)
        } catch {
            await storage.removeImportedPlaylist(for: sourceID)
            throw error
        }
    }

    /// Installs a source whose data has already loaded successfully.
    /// Nothing above this line mutates the current household, which is what
    /// makes adding a source transactional from the viewer's perspective.
    private struct ValidatedSource {
        var source: PlaylistSource
        var result: LibraryLoader.LibraryResult
    }

    private func commit(
        _ validated: [ValidatedSource],
        load: LibraryLoad,
        replacing sourceID: UUID? = nil,
        household: HouseholdSnapshot? = nil
    ) async throws {
        guard let active = validated.last else { return }
        let preparedRatings = await ratingsForInstallation(of: active.result.library)
        try Task.checkCancellation()
        guard isCurrent(load) else { throw CancellationError() }

        let refreshedAt = Date.now
        let committed = validated.map { validatedSource in
            var source = validatedSource.source
            source.lastRefreshedAt = refreshedAt
            source.epgURL = validatedSource.result.epgURL
            return source
        }
        guard let activeSource = committed.last else { return }

        // Persist credentials before installing/redacting anything. Previously
        // persistSources swallowed Keychain failures after phase became ready.
        for source in committed {
            let credentials = SourceCredentials(source: source)
            if !credentials.isEmpty { try await credentialStore.save(credentials, for: source.id) }
        }
        try Task.checkCancellation()
        guard isCurrent(load) else { throw CancellationError() }
        var nextSources = sources
        for source in committed {
            if let index = nextSources.firstIndex(where: { $0.id == source.id }) {
                nextSources[index] = source
            } else { nextSources.append(source) }
        }
        var nextProfiles = profiles
        var importedStates: [String: WatchState] = [:]
        var replica = householdReplica
        if let household {
            replica.observe(local: await makeHouseholdSnapshot())
            replica.merge(remote: household)
            let merged = replica.snapshot()
            nextProfiles = merged.profiles
            importedStates = merged.watchStates
        }
        let createdOwner = nextProfiles.isEmpty
        if createdOwner {
            nextProfiles = [Profile.makeOwner(named: String(localized: CoreStrings.profileDefaultOwnerName))]
        }
        try await storage.saveVerified(nextSources.map(\.redactedForPersistence), to: Self.sourcesFile)
        try await storage.saveVerified(nextProfiles, to: Self.profilesFile)
        for profile in nextProfiles {
            if let state = importedStates[profile.id.uuidString] {
                try await storage.saveVerified(state, to: profile.watchStateFileName)
            }
        }
        if household != nil {
            try await storage.saveVerified(replica, to: Self.replicaFile)
        }
        try Task.checkCancellation()
        guard isCurrent(load) else { throw CancellationError() }
        credentialMigrationFailure = nil
        sources = nextSources
        profiles = nextProfiles
        if household != nil { householdReplica = replica }
        if activeProfile == nil || household != nil {
            // Restore the transferred people, never silently invent/activate a
            // replacement owner or leave a nil policy hiding the whole library.
            if shouldAskWhoIsWatching {
                activeProfileID = nil
                isChoosingProfile = true
                watchState = WatchState()
            } else if let only = profiles.first {
                activeProfileID = only.id
                let restored = await storage.load(WatchState.self, from: only.watchStateFileName)
                watchState = importedStates[only.id.uuidString] ?? restored ?? WatchState()
                isChoosingProfile = false
            }
        }
        activeSourceID = activeSource.id
        invalidateGuideLoads()
        guide = nil
        installLibraryUpdates(nil)
        clearLoadedEpisodes()

        installCatalogue(active.result.library, ratings: preparedRatings)
        scheduleDiscoveryMatching()

        var diagnostics = SourceDiagnostics()
        diagnostics.skippedPlaylistLines = active.result.skippedLines
        diagnostics.channelsWithID = active.result.library.channels.count {
            $0.channelID?.isEmpty == false
        }
        self.diagnostics = diagnostics

        phase = .ready
        diagnostics.timeToFirstPlayableChannel = elapsedSeconds(since: load.startedAt)
        self.diagnostics = diagnostics
        connectionProgress = .ready
        let mergedRatings = await ratingService.merge(preparedRatings)
        guard isCurrent(load), activeSourceID == activeSource.id else { return }
        ratings = mergedRatings
        applyPolicy()
        scheduleVerification()

        if createdOwner { await persistProfiles() }
        await persistSources()
        await storage.save(
            LibraryUpdates(), to: Self.libraryUpdatesFile(for: activeSource.id)
        )
        for (source, validatedSource) in zip(committed, validated) {
            await loader.saveCache(
                validatedSource.result.library,
                for: source.id,
                storage: storage
            )
        }
        guard isCurrent(load), activeSourceID == activeSource.id else { return }
        if let epgURL = active.result.epgURL {
            loadGuide(from: epgURL, for: activeSource.id)
        }
        refreshDiscovery()
    }

    private func replaceSource(
        _ existing: PlaylistSource,
        with replacement: PlaylistSource
    ) async throws {
        let previousPhase = phase
        let preservesVisibleLibrary = previousPhase == .ready && !catalogue.isEmpty
        let load = beginLibraryLoad(for: replacement, showsRefreshActivity: preservesVisibleLibrary)
        connectionProgress = progressForContacting(replacement)
        if !preservesVisibleLibrary {
            phase = .loading(String(localized: CoreStrings.loadingSource(existing.name)))
        }
        defer { finishLibraryLoad(load) }

        do {
            let result = try await loader.loadLibrary(for: replacement)
            guard isCurrent(load) else { throw CancellationError() }
            connectionProgress = .organising
            try await commit(
                [ValidatedSource(source: replacement, result: result)],
                load: load,
                replacing: existing.id
            )
        } catch {
            guard isCurrent(load) else { throw CancellationError() }
            phase = preservesVisibleLibrary ? previousPhase : .failed(error.localizedDescription)
            connectionProgress = nil
            throw error
        }
    }

    private func replacePastedSource(
        _ existing: PlaylistSource,
        with text: String
    ) async throws {
        let playlist = M3UParser().parse(text)
        guard !playlist.items.isEmpty else { throw LibraryLoader.LoadError.emptyPlaylist }
        let fileURL = try await storage.saveImportedPlaylist(text, for: existing.id)
        var replacement = PlaylistSource(
            id: existing.id,
            kind: .localFile,
            name: existing.name,
            playlistURL: fileURL,
            epgURL: playlist.epgURL,
            createdAt: existing.createdAt
        )
        replacement.lastRefreshedAt = existing.lastRefreshedAt

        let previousPhase = phase
        let load = beginLibraryLoad(for: replacement, showsRefreshActivity: previousPhase == .ready)
        connectionProgress = .organising
        defer { finishLibraryLoad(load) }
        let result = LibraryLoader.LibraryResult(
            library: Library(items: playlist.items),
            epgURL: playlist.epgURL,
            skippedLines: playlist.skippedLineCount
        )
        try await commit(
            [ValidatedSource(source: replacement, result: result)],
            load: load,
            replacing: existing.id
        )
    }

    private func progressForContacting(_ source: PlaylistSource) -> ConnectionProgress {
        source.kind == .xtream ? .signingIn : .loadingContent
    }

    /// A token identifying the only library load allowed to reach state.
    private struct LibraryLoad: Equatable {
        let generation: UInt64
        let sourceID: UUID
        let startedAt: ContinuousClock.Instant
    }

    private func beginLibraryLoad(
        for source: PlaylistSource,
        showsRefreshActivity: Bool
    ) -> LibraryLoad {
        libraryLoadGeneration &+= 1
        // Requests from the previous catalogue may use the same numeric
        // series id as this one. Their defer blocks are generation-guarded, so
        // clearing here cannot let an old request clear a newer marker later.
        episodeLoadsInFlight.removeAll()
        isRefreshingLibrary = showsRefreshActivity
        deferredLibraryTask?.cancel()
        return LibraryLoad(
            generation: libraryLoadGeneration,
            sourceID: source.id,
            startedAt: .now
        )
    }

    private func finishLibraryLoad(_ load: LibraryLoad) {
        guard isCurrent(load) else { return }
        isRefreshingLibrary = false
    }

    private func isCurrent(_ load: LibraryLoad) -> Bool {
        load.generation == libraryLoadGeneration
    }

    private func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let parts = start.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }

    private func invalidateLibraryLoads() {
        libraryLoadGeneration &+= 1
        deferredLibraryTask?.cancel()
        episodeLoadsInFlight.removeAll()
        isRefreshingLibrary = false
    }

    private func invalidateGuideLoads() {
        guideLoadGeneration &+= 1
        isRefreshingGuide = false
    }

    /// Provider markers are prepared off the main actor and without touching
    /// RatingService. Only a source that actually commits merges them into the
    /// shared rating cache.
    private func ratingsForInstallation(of library: Library) async -> RatingIndex {
        guard !library.isEmpty else { return ratings }
        let base = ratings
        let items = library.items
        return await Task.detached(priority: .utility) {
            var seeded = base
            for item in items {
                guard let found = RatingParser.rating(inText: item.rawTitle)
                    ?? item.rawGroup.flatMap(RatingParser.rating(inText:))
                else { continue }
                seeded.record(
                    ContentRating(rating: found, source: .provider),
                    for: RatingKey.of(item)
                )
            }
            return seeded
        }.value
    }

    /// The state part of a load commit is deliberately synchronous. A newer
    /// operation can start before or after it, never halfway through it.
    private func installCatalogue(_ library: Library, ratings: RatingIndex) {
        catalogue = library
        self.ratings = ratings
        applyPolicy(resetDiscovery: true)
        scheduleVerification()
    }

    private func replace(_ source: PlaylistSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
    }

    private func persistSources() async {
        for source in sources {
            let credentials = SourceCredentials(source: source)
            if !credentials.isEmpty {
                do {
                    try await credentialStore.save(credentials, for: source.id)
                } catch {
                    // Keep the last recoverable descriptor on disk. In
                    // particular, never erase a legacy plaintext credential
                    // before its replacement has reached Keychain.
                    return
                }
            }
        }
        await storage.save(sources.map(\.redactedForPersistence), to: Self.sourcesFile)
        scheduleHouseholdSync()
    }

    private static func libraryUpdatesFile(for sourceID: UUID) -> String {
        "library-updates-\(sourceID.uuidString).json"
    }

    private static func recentUpdates(_ updates: LibraryUpdates?) -> LibraryUpdates {
        guard let updates, updates.isRecent() else { return LibraryUpdates() }
        return updates
    }

    private func installLibraryUpdates(_ updates: LibraryUpdates?) {
        libraryUpdates = Self.recentUpdates(updates)
        scheduleLibraryUpdatesExpiry()
    }

    /// Removes a "recently added" batch at the same moment it stops being
    /// recent, even if the app has stayed open for days without a refresh.
    private func scheduleLibraryUpdatesExpiry() {
        libraryUpdatesExpiryTask?.cancel()
        guard !libraryUpdates.isEmpty,
              let expirationDate = libraryUpdates.expirationDate
        else { return }

        let remaining = expirationDate.timeIntervalSinceNow
        guard remaining > 0 else {
            libraryUpdates = LibraryUpdates()
            rebuildHomeContent()
            return
        }

        let expected = libraryUpdates
        libraryUpdatesExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled,
                  let self,
                  self.libraryUpdates == expected,
                  !self.libraryUpdates.isRecent()
            else { return }
            self.libraryUpdates = LibraryUpdates()
            self.rebuildHomeContent()
        }
    }

    private func refreshLibraryUpdatesLifetime() {
        if !libraryUpdates.isRecent() {
            installLibraryUpdates(nil)
            rebuildHomeContent()
        } else {
            scheduleLibraryUpdatesExpiry()
        }
    }

    private func clearLoadedEpisodes() {
        loadedEpisodes.removeAll(keepingCapacity: false)
        episodeLoadFailures.removeAll(keepingCapacity: false)
        episodeLoadsInFlight.removeAll(keepingCapacity: false)
    }

    /// Progress updates arrive every few seconds during playback; coalesce them.
    ///
    /// Written to the active profile's own file. Favourites and history belong
    /// to a person, not to a device — and a child's cartoons turning up in a
    /// parent's Continue watching would be the harmless half of getting that
    /// wrong.
    private func scheduleWatchStateSave() {
        guard !isApplyingHousehold else { return }
        watchStateSaveTask?.cancel()
        let snapshot = watchState
        let file = activeProfile?.watchStateFileName ?? WatchState.fileName
        scheduleHouseholdSync()
        watchStateSaveTask = Task { [storage] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await storage.save(snapshot, to: file)
        }
    }

    // MARK: - Secure household sync

    /// Capture the owner and value together before suspending. Used when a
    /// playback checkpoint or background transition cannot wait for debounce.
    ///
    /// Also publishes to iCloud at once. The debounced sync is a sleeping task,
    /// and a suspended app never wakes it: closing the player and pocketing the
    /// phone would otherwise leave the TV resuming from the last 15-second
    /// checkpoint, or from nothing.
    public func flushPendingWatchState() async {
        watchStateSaveTask?.cancel()
        let snapshot = watchState
        let file = activeProfile?.watchStateFileName ?? WatchState.fileName
        await storage.save(snapshot, to: file)
        guard !isApplyingHousehold, !isReceivingPairing, phase != .starting else { return }
        householdSyncTask?.cancel()
        await syncNow()
    }

    /// Pulls the newest private iCloud household and then publishes this
    /// device's merged snapshot. Called at launch, foreground and from the
    /// explicit Settings action.
    public func syncNow() async {
        guard !isReceivingPairing else { return }
        if let credentialMigrationFailure {
            syncState = .failed(credentialMigrationFailure)
            return
        }
        guard !isSyncInFlight else { syncRequestedAgain = true; return }
        isSyncInFlight = true
        defer { isSyncInFlight = false }
        repeat {
            syncRequestedAgain = false
            syncState = .syncing
            do {
                let remote = try await householdSync.pull()
                if let remote { _ = await hydrate(remote.sources) }
                if credentialMigrationFailure != nil { throw SyncError.keyNotAvailable }
                // Retry preparation if a user changes state during disk or
                // Keychain reads. No partially prepared merge reaches the UI.
                while true {
                    let revision = householdRevision
                    let local = Self.withoutUnusedOwner(await makeHouseholdSnapshot(), joining: remote)
                    guard revision == householdRevision else { continue }
                    var candidate = householdReplica
                    candidate.observe(local: local)
                    if let remote { candidate.merge(remote: remote) }
                    let merged = candidate.snapshot().sanitizedForSync()
                    let hydrated = await hydrate(merged.sources)
                    if credentialMigrationFailure != nil { throw SyncError.keyNotAvailable }
                    guard revision == householdRevision else { continue }
                    householdReplica = candidate
                    await installHousehold(merged, hydrated: hydrated, local: local)
                    // Persist merge metadata before publishing, so a restart
                    // cannot forget deletions or reinterpret remote edits.
                    await storage.save(candidate, to: Self.replicaFile)
                    if remote?.sanitizedForSync() != merged,
                       !merged.sources.isEmpty || !merged.profiles.isEmpty || merged.syncRecords?.isEmpty == false {
                        try await householdSync.push(merged)
                    }
                    syncState = .current(merged.modifiedAt)
                    if householdRevision != revision { syncRequestedAgain = true }
                    break
                }
            } catch let error as SyncError {
                syncState = if case .unavailable = error { .unavailable }
                    else { .failed(error.localizedDescription) }
                break
            } catch {
                syncState = .failed(error.localizedDescription)
                break
            }
        } while syncRequestedAgain
    }

    /// A reinstall, or a second device set up by hand, creates a fresh "Me"
    /// before it has heard from iCloud. Merged by id, that left two profiles
    /// called "Me" — seen on Apple TV. When the household already has a grown
    /// up and this device's only profile is that untouched default, it steps
    /// aside and the household's own owner is kept.
    nonisolated static func withoutUnusedOwner(
        _ local: HouseholdSnapshot, joining remote: HouseholdSnapshot?
    ) -> HouseholdSnapshot {
        guard let remote, local.profiles.count == 1, let owner = local.profiles.first,
              owner.name == String(localized: CoreStrings.profileDefaultOwnerName),
              owner.maturity == .adult,
              !remote.profiles.contains(where: { $0.id == owner.id }),
              remote.profiles.contains(where: { $0.maturity == .adult })
        else { return local }
        let state = local.watchStates[owner.id.uuidString] ?? WatchState()
        guard state.favoriteIDs.isEmpty, state.progress.isEmpty, state.recentIDs.isEmpty else { return local }
        var trimmed = local
        trimmed.profiles = []
        trimmed.watchStates[owner.id.uuidString] = nil
        return trimmed
    }

    func scheduleHouseholdSync() {
        guard !isApplyingHousehold, !isReceivingPairing else { return }
        if isSyncInFlight { syncRequestedAgain = true; return }
        householdSyncTask?.cancel()
        householdSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            await self.syncNow()
        }
    }

    private func observeHouseholdChanges() {
        guard householdChangeTask == nil else { return }
        householdChangeTask = Task { @MainActor [weak self, householdSync] in
            let changes = await householdSync.externalChanges()
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }
                await self.syncNow()
            }
        }
    }

    private func makeHouseholdSnapshot() async -> HouseholdSnapshot {
        let selectedID = activeProfileID
        let selectedState = watchState
        let profileSnapshot = profiles
        let sourceSnapshot = sources
        var states: [String: WatchState] = [:]
        for profile in profileSnapshot {
            if profile.id == selectedID {
                states[profile.id.uuidString] = selectedState
            } else if let saved = await storage.load(WatchState.self, from: profile.watchStateFileName) {
                states[profile.id.uuidString] = saved
            }
        }
        return HouseholdSnapshot(
            sources: sourceSnapshot.filter { $0.kind != .localFile }.map(\.redactedForPersistence),
            profiles: profileSnapshot, watchStates: states
        )
    }

    private func installHousehold(
        _ merged: HouseholdSnapshot, hydrated: [PlaylistSource], local: HouseholdSnapshot
    ) async {
        let previousSource = activeSource
        let previousProfile = activeProfile
        let localFiles = sources.filter { $0.kind == .localFile }
        var states = merged.watchStates
        for (profileID, var state) in states {
            // A local stream remains local. New devices receive only stubs and
            // fetch the current episode URLs from their own provider account.
            for (key, item) in state.recentItems {
                if let existing = local.watchStates[profileID]?.recentItems[key],
                   existing.id == item.id, existing.streamURL.scheme != "kanal-history" {
                    state.recentItems[key] = existing
                }
            }
            states[profileID] = state
        }

        isApplyingHousehold = true
        watchStateSaveTask?.cancel()
        sources = hydrated.map { source in
            var updated = source
            updated.lastRefreshedAt = sources.first { $0.id == source.id }?.lastRefreshedAt
            return updated
        } + localFiles
        profiles = merged.profiles
        if let previousProfile {
            let replacement = profiles.first { $0.id == previousProfile.id }
            // A remote policy edit must never silently grant a child more
            // access. Re-enter the chooser even if only an allowlist changed.
            if replacement == nil || (previousProfile.isRestricted &&
                replacement.map { previousProfile.narrows(differentlyThan: $0) } == true) {
                activeProfileID = nil
                profileSelectionGeneration &+= 1
                isChoosingProfile = !profiles.isEmpty
                watchState = WatchState()
            }
        }
        if activeProfileID == nil, previousProfile == nil, !isChoosingProfile, phase != .starting, !profiles.isEmpty {
            if shouldAskWhoIsWatching { isChoosingProfile = true }
            else { activeProfileID = profiles.first?.id; isChoosingProfile = false }
        }
        if let id = activeProfileID { watchState = states[id.uuidString] ?? WatchState() }
        if activeSourceID == nil || !sources.contains(where: { $0.id == activeSourceID }) {
            activeSourceID = sources.first?.id
        }
        let sourceChanged = previousSource != activeSource
        if sourceChanged {
            invalidateLibraryLoads()
            invalidateGuideLoads()
            clearLoadedEpisodes()
            catalogue = .empty
            guide = nil
        }
        if sourceChanged || previousProfile != activeProfile {
            applyPolicy(resetDiscovery: true)
            scheduleVerification()
        } else {
            rebuildHomeIndex()
            rebuildHomeContent()
        }
        isApplyingHousehold = false

        let savedSources = sources.map(\.redactedForPersistence)
        let savedProfiles = profiles
        await storage.save(savedSources, to: Self.sourcesFile)
        await storage.save(savedProfiles, to: Self.profilesFile)
        for profile in savedProfiles {
            if let state = states[profile.id.uuidString] {
                await storage.save(state, to: profile.watchStateFileName)
            }
        }
        if phase != .starting {
            if activeSource == nil || activeSource.map(Self.hasConnection) == false {
                // Cloud descriptors may arrive without credentials on TV.
                // Keep the real profiles but offer QR setup instead of an
                // empty library or fabricating a replacement household.
                isChoosingProfile = false
                phase = .welcome
            } else if sourceChanged, let active = activeSource {
                await refresh(active)
            } else {
                await prepareHome()
            }
        }
    }

    private static func hasConnection(_ source: PlaylistSource) -> Bool {
        switch source.kind {
        case .m3u, .localFile: source.playlistURL != nil
        case .xtream: source.portalURL != nil && source.username != nil && source.password != nil
        }
    }

    private func migrateAndHydrate(_ stored: [PlaylistSource]) async -> [PlaylistSource] {
        var migrationFailed = false
        var result: [PlaylistSource] = []
        for source in stored {
            let saved: SourceCredentials?
            do { saved = try await credentialStore.load(for: source.id) }
            catch {
                migrationFailed = true
                credentialMigrationFailure = error.localizedDescription
                result.append(source)
                continue
            }
            let combined = mergeCredentials(source: source, saved: saved)
            if !combined.isEmpty {
                do { try await credentialStore.save(combined, for: source.id) }
                catch {
                    migrationFailed = true
                    credentialMigrationFailure = error.localizedDescription
                }
            }
            result.append(source.applying(combined))
        }
        if !migrationFailed {
            await storage.save(result.map(\.redactedForPersistence), to: Self.sourcesFile)
        }
        return result
    }

    private func mergeCredentials(source: PlaylistSource, saved: SourceCredentials?) -> SourceCredentials {
        let inline = SourceCredentials(source: source)
        guard var result = saved else { return inline }
        if let value = inline.portalURL { result.portalURL = value }
        if let value = inline.playlistURL { result.playlistURL = value }
        if let value = inline.epgURL { result.epgURL = value }
        if let value = inline.username { result.username = value }
        if let value = inline.password { result.password = value }
        return result
    }

    private func hydrate(_ descriptors: [PlaylistSource]) async -> [PlaylistSource] {
        var result: [PlaylistSource] = []
        for source in descriptors {
            let saved: SourceCredentials?
            do { saved = try await credentialStore.load(for: source.id) }
            catch {
                credentialMigrationFailure = error.localizedDescription
                result.append(sources.first { $0.id == source.id } ?? source)
                continue
            }
            let credentials = mergeCredentials(source: source, saved: saved)
            // Older cloud descriptors carried the portal root. Move it into
            // the same Keychain record without replacing existing passwords.
            if source.portalURL != nil, credentials != saved {
                do { try await credentialStore.save(credentials, for: source.id) }
                catch { credentialMigrationFailure = error.localizedDescription }
            }
            result.append(source.applying(credentials))
        }
        return result
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
        let episodes: [MediaItem]
        if let id = group.providerSeriesID, let fetched = loadedEpisodes[id], !fetched.isEmpty {
            episodes = fetched
        } else {
            episodes = group.episodes
        }
        // The on-demand cache is shared across profiles and sits outside the
        // filtered library. Reapply the current policy at this read boundary.
        return isRestricted ? episodes.filter { policy.allows($0) } : episodes
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

        let sourceID = source.id
        let generation = libraryLoadGeneration
        episodeLoadsInFlight.insert(seriesID)
        episodeLoadFailures[seriesID] = nil
        defer {
            if generation == libraryLoadGeneration, sourceID == activeSourceID {
                episodeLoadsInFlight.remove(seriesID)
            }
        }

        do {
            let episodes = try await loader.loadEpisodes(for: source, seriesID: seriesID)
            guard generation == libraryLoadGeneration,
                  sourceID == activeSourceID
            else { return }
            loadedEpisodes[seriesID] = episodes
            rebuildHomeContent()
        } catch {
            guard generation == libraryLoadGeneration,
                  sourceID == activeSourceID
            else { return }
            episodeLoadFailures[seriesID] = error.localizedDescription
        }
    }
}

// MARK: - Watching a series through

public extension AppModel {

    /// The episode that follows the one just finished, if there is one.
    ///
    /// Nil for films, for the last episode of a show, and for anything that is
    /// not part of a series — in every case meaning "nothing follows this".
    func nextEpisode(after item: MediaItem) -> MediaItem? {
        guard item.kind == .series,
              let group = seriesGroup(for: item)
        else { return nil }
        return Library.nextEpisode(after: item, among: episodes(for: group))
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

    /// Local search always runs away from the UI actor. Discovery may be
    /// building the same lazy index; waiting for its lock must never freeze the
    /// search field or scrolling animation.
    func localSearch(_ query: String, limit: Int = 200) async -> [MediaItem] {
        let library = library
        return await LibrarySearchQueue.shared.search(query, limit: limit, in: library)
    }

    /// Everything worth trying for one entry the viewer chose.
    ///
    /// A film the provider listed several times gets those other listings as
    /// fallbacks, led by whichever one last worked. Anything else — an
    /// episode, a one-off stream — is just itself.
    func playbackPlan(for item: MediaItem) -> PlaybackPlan? {
        guard item.kind == .movie, let group = library.movieGroup(containing: item),
              group.hasAlternatives
        else { return nil }
        return PlaybackPlan(movie: group, remembered: watchState.workingVariants[group.id])
    }

    /// Which of a person's credits this household can actually watch.
    ///
    /// Keyed by the credit's TMDB id. Runs off the UI actor for the same
    /// reason search does: a dozen lookups across a provider-sized catalogue
    /// is not work a sheet's first frame should wait on.
    func availableCredits(among roles: [KnownRole]) async -> [Int: MediaItem] {
        guard !roles.isEmpty else { return [:] }
        let library = library
        return await LibrarySearchQueue.shared.match(roles, in: library)
    }

    /// Searches the library, then — only if that came up short — asks what the
    /// query means and searches again under every other name the title has.
    ///
    /// The order matters: a local hit is instant and offline, so the network is
    /// never on the path for the common case.
    func search(
        _ query: String, localResults: [MediaItem]? = nil
    ) async -> SearchOutcome {
        let local = if let localResults { localResults } else { await localSearch(query) }
        // Three solid local hits is enough; no reason to go to the network.
        if local.count >= 3 { return SearchOutcome(items: local) }

        let (spellings, _) = await metadata.alternativeSpellings(for: query)
        guard !spellings.isEmpty else { return SearchOutcome(items: local) }

        var merged = local
        var seen = Set(local.map(\.id))
        var matchedVia: String?
        for spelling in spellings {
            let hits = await localSearch(spelling, limit: 50)
            for item in hits where seen.insert(item.id).inserted {
                merged.append(item)
                matchedVia = matchedVia ?? spelling
            }
        }
        return SearchOutcome(items: merged, matchedVia: matchedVia)
    }
}

// MARK: - Derived shelves

public extension AppModel {

    var continueWatching: [MediaItem] { homeContent.continueWatching }
    var nextEpisodes: [MediaItem] { homeContent.nextEpisodes }
    var recentChannelGroups: [ChannelGroup] { homeContent.recentChannels }
    var newlyAddedMovies: [MediaItem] { homeContent.newMovies }
    var newlyAddedSeries: [SeriesGroup] { homeContent.newSeries }

    var favoriteChannels: [MediaItem] { cachedFavoriteChannels }

    /// Favourites, folded so one channel is one card.
    var favoriteChannelGroups: [ChannelGroup] { cachedFavoriteChannelGroups }

    var favoriteSeries: [SeriesGroup] { cachedFavoriteSeries }

    var favoriteMovies: [MediaItem] { cachedFavoriteMovies }

    /// Produces a deliberately redacted report a person can inspect before
    /// sharing. The report contains counts and failure shape, never content or
    /// provider secrets.
    func makeSupportReport() -> SupportReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let appVersion = build.map { "\(version) (\($0))" } ?? version
        let phaseName: String = switch phase {
        case .starting: "starting"
        case .welcome: "welcome"
        case .loading: "loading"
        case .ready: "ready"
        case .failed: "failed"
        }
        return SupportReport(
            appVersion: appVersion,
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            phase: phaseName,
            sourceCount: sources.count,
            activeSource: activeSource.map(SupportReport.sourceSummary),
            channelCount: catalogue.channels.count,
            movieCount: catalogue.movies.count,
            seriesCount: catalogue.series.count,
            guideProgrammeCount: diagnostics.guideProgrammes,
            guideCoveragePercent: Int(diagnostics.guideCoverage * 100),
            guideWasRepaired: !diagnostics.guideRepairs.isEmpty,
            guideIsPartial: diagnostics.guideIsPartial,
            skippedPlaylistLines: diagnostics.skippedPlaylistLines,
            timeToFirstPlayableChannel: diagnostics.timeToFirstPlayableChannel
        )
    }

    /// Favourites change rarely, while SwiftUI bodies and playback progress
    /// change constantly. Resolve the ids once per library/profile/favourite
    /// mutation instead of scanning a provider-sized catalogue every redraw.
    func rebuildFavoriteContent() {
        let ids = watchState.favoriteIDs
        guard !ids.isEmpty else {
            cachedFavoriteChannels = []
            cachedFavoriteChannelGroups = []
            cachedFavoriteMovies = []
            cachedFavoriteSeries = []
            return
        }
        cachedFavoriteChannels = library.channels.filter { ids.contains($0.id) }
        cachedFavoriteChannelGroups = library.channelGroups.filter { group in
            group.variants.contains { ids.contains($0.id) }
        }
        cachedFavoriteMovies = library.movies.filter { ids.contains($0.id) }
        cachedFavoriteSeries = library.series.filter { ids.contains($0.id) }
    }

    func progress(for item: MediaItem) -> WatchProgress? {
        let key = historyKey(for: item.id)
        if let progress = watchState.progress[key] { return progress }
        if let previousKey = progressHistoryAliases[key],
           let progress = watchState.progress[previousKey] {
            return progress
        }
        // History written before source scoping is safe to adopt only when
        // there is no second service whose ids could mean something else.
        guard sources.count <= 1 else { return nil }
        return watchState.progress[item.id]
    }

    /// What is on this channel right now, when we have a guide for it.
    func nowPlaying(on channel: MediaItem) -> Programme? {
        guard let channelID = channel.channelID, let guide else { return nil }
        return guide.schedules[channelID]?.programme()
    }

    /// A duplicate channel can have a logo on one stream and a guide id on
    /// another. Home shows the group, so its schedule must try every variant.
    func nowPlaying(on group: ChannelGroup) -> Programme? {
        guard let guide else { return nil }
        return group.programme(in: guide)
    }

    func upcoming(on channel: MediaItem, limit: Int = 3) -> [Programme] {
        guard let channelID = channel.channelID, let guide else { return [] }
        return guide.schedules[channelID]?.upcoming(limit: limit) ?? []
    }

    func upcoming(on group: ChannelGroup, limit: Int = 3) -> [Programme] {
        guard let guide else { return [] }
        return group.upcoming(in: guide, limit: limit)
    }

    /// Fetches only the handful of on-demand episode lists needed to rebuild
    /// Continue watching and Next episode after a relaunch.
    func prepareHome() async {
        refreshLibraryUpdatesLifetime()
        var seen = Set<String>()
        let groups = watchState.recentIDs.compactMap { id -> SeriesGroup? in
            guard let item = watchState.recentItems[id],
                  currentItemID(from: id) != nil,
                  let group = seriesGroup(for: item),
                  seen.insert(seriesIdentity(for: group)).inserted,
                  group.needsEpisodeLoad
            else { return nil }
            return group
        }
        for group in groups.prefix(6) {
            await loadEpisodesIfNeeded(for: group)
        }
    }

    /// Pins an explicit source independently of successful playback history.
    func lockVariant(_ variantID: String?, forGroup groupID: String) {
        watchState.lockedVariants[groupID] = variantID
    }

    /// Remembers which of a channel's stream variants actually played, so the
    /// next attempt starts with the one that worked rather than the first one
    /// the provider happened to list.
    func rememberWorkingVariant(_ variantID: String, forGroup groupID: String) {
        watchState.rememberWorkingVariant(variantID, forGroup: groupID)
    }

    func toggleFavorite(_ id: String) {
        watchState.toggleFavorite(id)
    }

    // MARK: - Taking things off the screen
    //
    // Everything the app puts on Home, it must also be possible to take off.
    // Continue watching in particular: a film someone abandoned ten minutes in
    // sits at the top of the first screen for months, and "I don't want to see
    // this any more" is not a request the app can answer with a refresh.

    func removeFavorite(_ id: String) {
        watchState.favoriteIDs.remove(id)
    }

    func clearFavorites() {
        watchState.clearFavorites()
    }

    /// Removes one title from Continue watching, whichever key its progress was
    /// written under — an id that changed between playlist refreshes has both.
    func forgetProgress(for item: MediaItem) {
        let key = historyKey(for: item.id)
        if let previous = progressHistoryAliases[key] {
            watchState.forget(previous)
        }
        watchState.forget(key)
        watchState.forget(item.id)
    }

    func forgetChannel(_ group: ChannelGroup) {
        watchState.forgetChannel(historyKey(for: group.id))
        watchState.forgetChannel(group.id)
    }

    /// Clears Continue watching, Next episode and the recent channels together:
    /// they are three views of one history, and clearing only the visible one
    /// would bring the rest back on the next launch.
    func clearWatchHistory() {
        watchState.clearHistory()
    }

    func record(item: MediaItem, position: TimeInterval, duration: TimeInterval) {
        guard duration > 0 else { return }
        let key = historyKey(for: item.id)
        // The item is already known playable and current. Keep this one sparse
        // lookup hot without indexing every title in a provider-sized library.
        homeIndex.rememberPlayable(item)
        watchState.record(
            WatchProgress(itemID: key, position: position, duration: duration),
            item: item
        )
    }

    /// Compatibility for callers that only have an id. New playback code uses
    /// the item overload so on-demand episodes survive a relaunch.
    func record(itemID: String, position: TimeInterval, duration: TimeInterval) {
        guard duration > 0 else { return }
        watchState.record(
            WatchProgress(
                itemID: historyKey(for: itemID),
                position: position,
                duration: duration
            )
        )
    }

    func recordChannel(groupID: String) {
        homeIndex.rememberChannel(groupID, in: library)
        watchState.recordChannel(groupID: historyKey(for: groupID))
    }

    /// Resolves all Home rows once when their inputs change. Doing this work in
    /// computed properties would rescan a 400k-title catalogue on every scroll
    /// frame.
    func rebuildHomeIndex() {
        let recentItemIDs = Set(watchState.recentIDs.prefix(200).compactMap(currentItemID))
        let recentChannelIDs = Set(
            watchState.recentChannelGroupIDs.prefix(50).compactMap(currentItemID)
        )
        let recentSnapshots = watchState.recentIDs.prefix(200).compactMap { key in
            currentItemID(from: key) == nil ? nil : watchState.recentItems[key]
        }
        homeIndex = HomeLibraryIndex(
            library: library,
            recentItemIDs: recentItemIDs,
            recentChannelGroupIDs: recentChannelIDs,
            recentSnapshots: recentSnapshots,
            libraryUpdates: libraryUpdates
        )
    }

    func rebuildHomeContent(resolveLibraryUpdates: Bool = true) {
        let recentIDs = Array(watchState.recentIDs.prefix(200))
        let itemIDByHistoryKey = recentIDs.reduce(into: [String: String]()) { result, key in
            result[key] = currentItemID(from: key)
        }
        var recentItems: [String: MediaItem] = [:]
        recentItems.reserveCapacity(itemIDByHistoryKey.count)
        for (historyKey, itemID) in itemIDByHistoryKey {
            recentItems[historyKey] = homeIndex.itemsByID[itemID]
        }

        for id in recentIDs where recentItems[id] == nil {
            guard let snapshot = watchState.recentItems[id],
                  currentItemID(from: id) != nil,
                  policy.allows(snapshot)
            else { continue }
            switch snapshot.kind {
            case .liveTV:
                continue
            case .movie:
                // Prefer the current catalogue entry: signed playlist URLs can
                // rotate while the film itself remains the same.
                guard let current = homeIndex.moviesByUpdateKey[
                    LibraryUpdates.movieKey(snapshot)
                ] else { continue }
                recentItems[id] = current
            case .series:
                guard let group = seriesGroup(for: snapshot) else { continue }
                let resolved = episodes(for: group).first {
                    $0.id == snapshot.id || ($0.season == snapshot.season &&
                        $0.episode == snapshot.episode && snapshot.episode != nil)
                }
                if let resolved, canPlay(resolved) {
                    recentItems[id] = resolved
                } else if snapshot.streamURL.scheme != "kanal-history" {
                    recentItems[id] = snapshot
                }
            }
        }

        // Resolve progress through a changed M3U id without rewriting history
        // from inside this rebuild (which would recursively trigger didSet).
        var aliases: [String: String] = [:]
        aliases.reserveCapacity(recentItems.count)
        for id in recentIDs {
            guard let item = recentItems[id] else { continue }
            let currentKey = historyKey(for: item.id)
            if currentKey != id,
               watchState.progress[currentKey] == nil,
               aliases[currentKey] == nil {
                aliases[currentKey] = id
            }
        }
        progressHistoryAliases = aliases

        var continueWatching: [MediaItem] = []
        var nextEpisodes: [MediaItem] = []
        var seenResumeTitles = Set<String>()
        var seenShows = Set<String>()
        for id in recentIDs {
            guard let item = recentItems[id], let watched = watchState.progress[id] else { continue }
            if watched.isWorthResuming {
                let resumeIdentity = item.kind == .series
                    ? "series|\(item.providerSeriesID.map(String.init) ?? item.seriesKey ?? item.id)"
                    : "item|\(item.id)"
                if seenResumeTitles.insert(resumeIdentity).inserted {
                    continueWatching.append(item)
                }
            }

            guard item.kind == .series,
                  let group = seriesGroup(for: item),
                  seenShows.insert(seriesIdentity(for: group)).inserted,
                  watched.isFinished
            else { continue }
            let candidate = Library.nextEpisode(after: item, among: episodes(for: group))
            if let candidate,
               progress(for: candidate)?.isFinished != true,
               progress(for: candidate)?.isWorthResuming != true,
               canPlay(candidate) {
                nextEpisodes.append(candidate)
            }
        }

        let recentChannels = watchState.recentChannelGroupIDs.prefix(20).compactMap { key in
            currentItemID(from: key).flatMap { id in
                homeIndex.channelGroupIndicesByID[id].map { library.channelGroups[$0] }
            }
        }

        let newMovies: [MediaItem]
        let newSeries: [SeriesGroup]
        if resolveLibraryUpdates {
            let recentUpdates = libraryUpdates.isRecent() ? libraryUpdates : LibraryUpdates()
            newMovies = Array(recentUpdates.movieKeys.lazy.compactMap {
                self.homeIndex.moviesByUpdateKey[$0]
            }.prefix(24))
            newSeries = Array(recentUpdates.seriesKeys.lazy.compactMap {
                self.homeIndex.seriesByUpdateKey[$0].map { self.library.series[$0] }
            }.prefix(24))
        } else {
            newMovies = homeContent.newMovies
            newSeries = homeContent.newSeries
        }

        homeContent = HomeContent(
            continueWatching: Array(continueWatching.prefix(24)),
            nextEpisodes: Array(nextEpisodes.prefix(24)),
            recentChannels: recentChannels,
            newMovies: newMovies,
            newSeries: newSeries
        )
    }

    private func historyKey(for itemID: String) -> String {
        guard let sourceID = activeSourceID else { return itemID }
        return "\(sourceID.uuidString)|\(itemID)"
    }

    private func currentItemID(from historyKey: String) -> String? {
        guard let sourceID = activeSourceID else { return historyKey }
        let prefix = "\(sourceID.uuidString)|"
        if historyKey.hasPrefix(prefix) {
            return String(historyKey.dropFirst(prefix.count))
        }
        // Legacy, unscoped history can only be trusted in a one-service home.
        return sources.count <= 1 ? historyKey : nil
    }

    /// Resolves a representative episode or provider placeholder to the show
    /// card used throughout Home, Search and Series.
    func seriesGroup(for item: MediaItem) -> SeriesGroup? {
        if let providerID = item.providerSeriesID,
           let index = homeIndex.seriesByProviderID[providerID] {
            return library.series[index]
        }
        guard let key = item.seriesKey else { return nil }
        return homeIndex.seriesByID[key].map { library.series[$0] }
    }

    private func seriesIdentity(for group: SeriesGroup) -> String {
        group.providerSeriesID.map { "provider|\($0)" } ?? "title|\(group.id)"
    }
}

/// Lookup tables rebuilt only when the visible library changes. A playback
/// progress tick can then update Home in proportion to the small history list,
/// rather than walking a provider catalogue with hundreds of thousands of rows.
private struct HomeLibraryIndex {
    var itemsByID: [String: MediaItem] = [:]
    var channelGroupIndicesByID: [String: Int] = [:]
    var seriesByID: [String: Int] = [:]
    var seriesByProviderID: [Int: Int] = [:]
    var moviesByUpdateKey: [String: MediaItem] = [:]
    var seriesByUpdateKey: [String: Int] = [:]

    init() {}

    init(
        library: Library,
        recentItemIDs: Set<String>,
        recentChannelGroupIDs: Set<String>,
        recentSnapshots: [MediaItem],
        libraryUpdates: LibraryUpdates
    ) {
        // At most the 200 history entries Home can show are retained. A full
        // item dictionary would duplicate the memory footprint of a 400k-item
        // catalogue just to look up this tiny set.
        itemsByID.reserveCapacity(recentItemIDs.count)
        if !recentItemIDs.isEmpty {
            for item in library.items where recentItemIDs.contains(item.id) {
                itemsByID[item.id] = item
            }
        }

        channelGroupIndicesByID.reserveCapacity(recentChannelGroupIDs.count)
        for (index, group) in library.channelGroups.enumerated()
        where recentChannelGroupIDs.contains(group.id) {
            channelGroupIndicesByID[group.id] = index
        }

        seriesByID.reserveCapacity(library.series.count)
        seriesByProviderID.reserveCapacity(library.series.count)
        seriesByUpdateKey.reserveCapacity(library.series.count)
        for (index, group) in library.series.enumerated() {
            seriesByID[group.id] = index
            if let providerID = group.providerSeriesID,
               seriesByProviderID[providerID] == nil {
                seriesByProviderID[providerID] = index
            }
            let updateKey = LibraryUpdates.seriesKey(group)
            if seriesByUpdateKey[updateKey] == nil { seriesByUpdateKey[updateKey] = index }
        }

        let historyMovieKeys = Set(recentSnapshots.lazy.filter {
            $0.kind == .movie
        }.map(LibraryUpdates.movieKey))
        let updateMovieKeys = Set(libraryUpdates.movieKeys)
        moviesByUpdateKey.reserveCapacity(min(historyMovieKeys.count + 24, library.movies.count))
        var capturedUpdateKeys = Set<String>()
        for movie in library.movies {
            let updateKey = LibraryUpdates.movieKey(movie)
            let isHistory = historyMovieKeys.contains(updateKey)
            let isVisibleUpdate = capturedUpdateKeys.count < 24
                && updateMovieKeys.contains(updateKey)
            guard isHistory || isVisibleUpdate else { continue }
            if moviesByUpdateKey[updateKey] == nil {
                moviesByUpdateKey[updateKey] = movie
                if isVisibleUpdate { capturedUpdateKeys.insert(updateKey) }
            }
        }
    }

    mutating func rememberPlayable(_ item: MediaItem) {
        itemsByID[item.id] = item
        if item.kind == .movie {
            moviesByUpdateKey[LibraryUpdates.movieKey(item)] = item
        }
    }

    mutating func rememberChannel(_ groupID: String, in library: Library) {
        guard let index = library.channelGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        channelGroupIndicesByID[groupID] = index
    }
}

/// Serialises the expensive presentation build off the main actor. Cancelled
/// policy/discovery requests keep their cancellation bit while executing here,
/// so the builder can stop at its bounded checkpoints and a newer request never
/// races a second full catalogue pass alongside it.
private actor DiscoveryPresentationQueue {
    static let shared = DiscoveryPresentationQueue()

    func build(
        library: Library, shelves: [DiscoveryShelf], audience: DiscoveryAudience
    ) -> DiscoveryPresentation {
        guard !Task.isCancelled else { return DiscoveryPresentation() }
        return DiscoveryPresentation.build(
            library: library, shelves: shelves, audience: audience
        )
    }
}

private actor LibrarySearchQueue {
    static let shared = LibrarySearchQueue()

    func search(_ query: String, limit: Int, in library: Library) -> [MediaItem] {
        guard !Task.isCancelled else { return [] }
        return library.search(query, limit: limit)
    }

    func match(_ roles: [KnownRole], in library: Library) -> [Int: MediaItem] {
        guard !Task.isCancelled else { return [:] }
        return library.items(matching: roles)
    }
}
