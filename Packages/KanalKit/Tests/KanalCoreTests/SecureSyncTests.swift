import Foundation
import Testing
@testable import KanalCore

@Suite("Secure TV service storage")
struct SecureSourceStorageTests {
    @Test("The JSON descriptor contains no private link or credentials")
    func redaction() {
        let source = PlaylistSource(
            kind: .m3u,
            name: "Home",
            playlistURL: URL(string: "https://tv.example/list.m3u?username=alice&password=hunter2"),
            username: "alice",
            password: "hunter2",
            epgURL: URL(string: "https://tv.example/xmltv.php?token=secret")
        )
        let redacted = source.redactedForPersistence
        #expect(redacted.playlistURL == nil)
        #expect(redacted.epgURL == nil)
        #expect(redacted.username == nil)
        #expect(redacted.password == nil)
        #expect(redacted.id == source.id)
        #expect(redacted.name == "Home")
    }

    @Test("Secrets round-trip through the credential vault")
    func vaultRoundTrip() async throws {
        let vault = MemorySourceCredentialStore()
        let source = PlaylistSource(
            kind: .xtream,
            name: "Home",
            portalURL: URL(string: "https://tv.example"),
            username: "alice",
            password: "hunter2",
            epgURL: URL(string: "https://tv.example/xmltv.php?token=secret")
        )
        let secret = SourceCredentials(source: source)
        try await vault.save(secret, for: source.id)
        let restored = source.redactedForPersistence.applying(try await vault.load(for: source.id))
        #expect(restored.username == "alice")
        #expect(restored.password == "hunter2")
        #expect(restored.epgURL?.query == "token=secret")
    }

    @MainActor
    @Test("AppModel migrates plaintext source JSON into the vault")
    func migration() async throws {
        let directory = scratchDirectory("migration")
        let storage = KanalStorage(directory: directory)
        let vault = MemorySourceCredentialStore()
        let source = PlaylistSource(
            kind: .xtream,
            name: "Home",
            portalURL: URL(string: "https://tv.example"),
            username: "alice",
            password: "hunter2"
        )
        await storage.save([source], to: "sources.json")

        let model = AppModel(
            loader: SyncTestLoader(),
            storage: storage,
            credentialStore: vault,
            householdSync: NoopHouseholdSync()
        )
        await model.start()

        let disk = try #require(await storage.load([PlaylistSource].self, from: "sources.json"))
        #expect(disk.first?.username == nil)
        #expect(disk.first?.password == nil)
        #expect(model.sources.first?.username == "alice")
        #expect(model.sources.first?.password == "hunter2")
        #expect(try await vault.load(for: source.id)?.password == "hunter2")
    }

    private func scratchDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "KanalSecureStorageTests")
            .appending(path: name)
            .appending(path: UUID().uuidString)
    }
}

@MainActor
@Suite("Private Apple device sync")
struct HouseholdSyncTests {
    @Test("A second device receives services, profiles, favourites and progress")
    func secondDevice() async throws {
        let sync = MemoryHouseholdSync()
        let vault = MemorySourceCredentialStore()
        let firstStorage = KanalStorage(directory: scratchDirectory("first"))
        let secondStorage = KanalStorage(directory: scratchDirectory("second"))
        let source = PlaylistSource(
            kind: .xtream,
            name: "Family TV",
            portalURL: URL(string: "https://tv.example"),
            username: "alice",
            password: "hunter2"
        )

        let first = AppModel(
            loader: SyncTestLoader(),
            storage: firstStorage,
            credentialStore: vault,
            householdSync: sync
        )
        try await first.add(source)
        let item = try #require(first.library.items.first)
        first.toggleFavorite(item.id)
        first.record(item: item, position: 180, duration: 900)
        await first.syncNow()

        let second = AppModel(
            loader: SyncTestLoader(),
            storage: secondStorage,
            credentialStore: vault,
            householdSync: sync
        )
        await second.start()

        #expect(second.phase == .ready)
        #expect(second.sources.map(\.id) == [source.id])
        #expect(second.sources.first?.username == "alice")
        #expect(second.sources.first?.password == "hunter2")
        #expect(second.profiles.map(\.id) == first.profiles.map(\.id))
        #expect(second.watchState.favoriteIDs.contains(item.id))
        #expect(second.watchState.progress.values.contains { $0.position == 180 })
    }

    @Test("Local imported files stay on their own device")
    func localFilesStayLocal() async throws {
        let sync = MemoryHouseholdSync()
        let firstStorage = KanalStorage(directory: scratchDirectory("local-first"))
        let model = AppModel(
            loader: SyncTestLoader(),
            storage: firstStorage,
            credentialStore: MemorySourceCredentialStore(),
            householdSync: sync
        )
        let file = scratchDirectory("playlist").appending(path: "local.m3u")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("#EXTM3U\n#EXTINF:-1,Local\nhttps://example.com/1.m3u8".utf8)
            .write(to: file)
        try await model.add(PlaylistSource(kind: .localFile, name: "Local", playlistURL: file))
        await model.syncNow()

        let snapshot = try #require(await sync.snapshot)
        #expect(snapshot.sources.isEmpty)
    }

    private func scratchDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "KanalHouseholdSyncTests")
            .appending(path: name)
            .appending(path: UUID().uuidString)
    }
}

private actor SyncTestLoader: LibraryLoading {
    private let item = MediaItem(
        id: "channel-1",
        kind: .liveTV,
        title: "Channel One",
        rawTitle: "Channel One",
        streamURL: URL(string: "https://stream.example/1.m3u8")!
    )

    func loadLibrary(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult {
        if source.kind == .xtream {
            guard source.username == "alice", source.password == "hunter2" else {
                throw LibraryLoader.LoadError.noPlaylistURL
            }
        }
        return LibraryLoader.LibraryResult(
            library: Library(items: [item]), epgURL: nil, skippedLines: 0
        )
    }

    func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async {}
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem] { [] }
    func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult {
        XMLTVParser.ParseResult(
            guide: .init(channelNames: [:], channelIcons: [:], schedules: [:]),
            repairs: [],
            isPartial: false
        )
    }
}
