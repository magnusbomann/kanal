import Foundation
import Testing
@testable import KanalCore

@Suite("Launch readiness regressions")
struct LaunchReadinessTests {
    @MainActor
    @Test("On-demand episode lists respect the current profile even after an adult loaded them")
    func cachedEpisodesRespectProfile() async throws {
        let model = AppModel(
            loader: MigrationLoader(),
            storage: KanalStorage(directory: FileManager.default.temporaryDirectory
                .appending(path: "KanalEpisodeRegression-\(UUID().uuidString)")),
            credentialStore: MemorySourceCredentialStore(), householdSync: NoopHouseholdSync()
        )
        try await model.add(PlaylistSource(
            kind: .xtream, name: "Test TV", portalURL: URL(string: "https://tv.example"),
            username: "test-user", password: "test-password"
        ))
        var placeholder = MigrationLoader.safeEpisode
        placeholder.episode = nil
        let group = try #require(Library(items: [placeholder]).series.first)
        await model.loadEpisodesIfNeeded(for: group)
        #expect(model.episodes(for: group).count == 2)

        let child = Profile(name: "Child", maturity: .six,
                            allowedTitleKeys: [RatingKey.of(placeholder)])
        await model.addProfile(child)
        await model.activate(child)
        #expect(model.episodes(for: group).map(\.id) == [MigrationLoader.safeEpisode.id])
    }

    @Test("Restarting must not make the adult profile an unlocked escape route")
    func adultSelection() {
        let owner = Profile.makeOwner(named: "Parent")
        #expect(owner.requiresCodeForSelection(parentalCodeIsSet: true))
        #expect(!owner.requiresCodeForSelection(parentalCodeIsSet: false))
        let child = Profile.makeChild(named: "Child", maturity: .six)
        #expect(!child.requiresCodeForSelection(parentalCodeIsSet: true))
    }

    @MainActor
    @Test("A failed credential migration stays recoverable after refresh and relaunch")
    func failedCredentialMigration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KanalMigrationRegression-\(UUID().uuidString)")
        let storage = KanalStorage(directory: directory)
        let source = PlaylistSource(
            kind: .xtream, name: "Test TV",
            portalURL: URL(string: "https://tv.example"),
            username: "test-user", password: "test-password"
        )
        await storage.save([source], to: "sources.json")
        let failingVault = UnavailableCredentialStore()
        let first = AppModel(
            loader: MigrationLoader(), storage: storage,
            credentialStore: failingVault, householdSync: NoopHouseholdSync()
        )
        await first.start()
        #expect(first.phase == .ready)
        let retained = try #require(await storage.load([PlaylistSource].self, from: "sources.json"))
        #expect(retained.first?.password == "test-password")

        let recoveredVault = MemorySourceCredentialStore()
        let second = AppModel(
            loader: MigrationLoader(), storage: storage,
            credentialStore: recoveredVault, householdSync: NoopHouseholdSync()
        )
        await second.start()
        #expect(second.phase == .ready)
        #expect(second.sources.first?.password == "test-password")
        #expect(try await recoveredVault.load(for: source.id)?.password == "test-password")
        let redacted = try #require(await storage.load([PlaylistSource].self, from: "sources.json"))
        #expect(redacted.first?.password == nil)
    }
}

private actor UnavailableCredentialStore: SourceCredentialStoring {
    struct Unavailable: Error {}
    func load(for sourceID: UUID) -> SourceCredentials? { nil }
    func save(_ credentials: SourceCredentials, for sourceID: UUID) throws { throw Unavailable() }
    func remove(for sourceID: UUID) {}
}

private actor MigrationLoader: LibraryLoading {
    static let safeEpisode = MediaItem(
        id: "episode-1", kind: .series, title: "Test Show", rawTitle: "Test Show S01E01",
        streamURL: URL(string: "https://tv.example/episode-1.mp4")!,
        seriesName: "Test Show", season: 1, episode: 1, providerSeriesID: 123
    )
    func loadLibrary(for source: PlaylistSource) throws -> LibraryLoader.LibraryResult {
        guard source.username == "test-user", source.password == "test-password" else {
            throw LibraryLoader.LoadError.noPlaylistURL
        }
        return .init(library: Library(items: [MediaItem(
            id: "test-channel", kind: .liveTV, title: "Test", rawTitle: "Test",
            streamURL: URL(string: "https://tv.example/test.m3u8")!
        )]), epgURL: nil, skippedLines: 0)
    }
    func loadCache(for sourceID: UUID, storage: KanalStorage) -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) {}
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) -> [MediaItem] {
        let adult = MediaItem(
            id: "episode-2", kind: .series, title: "XXX", rawTitle: "XXX",
            streamURL: URL(string: "https://tv.example/episode-2.mp4")!,
            rawGroup: "XXX", seriesName: "Test Show", season: 1, episode: 2, providerSeriesID: 123
        )
        return [Self.safeEpisode, adult]
    }
    func loadGuide(from url: URL) -> XMLTVParser.ParseResult {
        .init(guide: .init(channelNames: [:], channelIcons: [:], schedules: [:]), repairs: [], isPartial: false)
    }
}
