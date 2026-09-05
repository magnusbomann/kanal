// Regression coverage for the original launch-audit sync failures.
import Foundation
import Testing
@testable import KanalCore

@MainActor
@Suite("SyncAuditProbes")
struct SyncAuditProbes {
    @Test("A remote update must preserve an unsynced local favourite")
    func localFavouriteSurvives() async throws {
        let (model, sync) = try await fixture()
        await model.syncNow()
        var remote = try #require(await sync.snapshot)
        let profile = try #require(model.activeProfileID).uuidString
        remote.watchStates[profile]?.favoriteIDs.insert("remote-favourite")
        remote.modifiedAt = .now.addingTimeInterval(10)
        await sync.push(remote)
        model.toggleFavorite("local-favourite")
        await model.syncNow()
        #expect(model.watchState.favoriteIDs.contains("remote-favourite"))
        #expect(model.watchState.favoriteIDs.contains("local-favourite"))
    }

    @Test("The cloud descriptor must not contain stream credentials from watch history")
    func cloudHistoryHasNoCredentials() async throws {
        let (model, sync) = try await fixture()
        let episode = MediaItem(
            id: "episode", kind: .series, title: "Test", rawTitle: "Test",
            streamURL: URL(string: "https://tv.example/series/test-user/PRIVATE_TEST_PASSWORD/1.mkv")!,
            seriesName: "Test", season: 1, episode: 1
        )
        model.record(item: episode, position: 120, duration: 1200)
        await model.syncNow()
        let snapshot = try #require(await sync.snapshot)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!json.contains("PRIVATE_TEST_PASSWORD"))
    }

    @Test("Deleting the active child remotely returns to profile selection")
    func remoteChildDeletion() async throws {
        let (model, sync) = try await fixture()
        let child = Profile.makeChild(named: "Child", maturity: .six)
        await model.addProfile(child)
        await model.activate(child)
        await model.syncNow()
        let base = try #require(await sync.snapshot)
        var remote = HouseholdReplica(deviceID: "remote")
        remote.merge(remote: base)
        var changed = base
        changed.profiles.removeAll { $0.id == child.id }
        changed.watchStates.removeValue(forKey: child.id.uuidString)
        remote.observe(local: changed)
        await sync.push(remote.snapshot())
        await model.syncNow()
        #expect(model.activeProfileID == nil)
        #expect(model.isChoosingProfile)
        #expect(!model.profiles.contains { $0.id == child.id })
    }

    @Test("Expanding a child profile remotely requires a new profile selection")
    func remoteChildExpansion() async throws {
        let (model, sync) = try await fixture()
        let child = Profile.makeChild(named: "Child", maturity: .six)
        await model.addProfile(child)
        await model.activate(child)
        await model.syncNow()
        let base = try #require(await sync.snapshot)
        var remote = HouseholdReplica(deviceID: "remote")
        remote.merge(remote: base)
        var changed = base
        let index = try #require(changed.profiles.firstIndex { $0.id == child.id })
        changed.profiles[index].maturity = Profile.makeOwner(named: "Adult").maturity
        remote.observe(local: changed)
        await sync.push(remote.snapshot())
        await model.syncNow()
        #expect(model.activeProfileID == nil)
        #expect(model.isChoosingProfile)
    }

    private func fixture() async throws -> (AppModel, MemoryHouseholdSync) {
        let sync = MemoryHouseholdSync()
        let model = AppModel(
            loader: ProbeLoader(),
            storage: KanalStorage(directory: FileManager.default.temporaryDirectory
                .appending(path: "KanalSyncAudit-\(UUID().uuidString)")),
            credentialStore: MemorySourceCredentialStore(), householdSync: sync
        )
        try await model.add(PlaylistSource(kind: .m3u, name: "Test",
            playlistURL: URL(string: "https://tv.example/list.m3u")))
        return (model, sync)
    }
}

private actor ProbeLoader: LibraryLoading {
    func loadLibrary(for source: PlaylistSource) -> LibraryLoader.LibraryResult {
        .init(library: Library(items: [MediaItem(
            id: "channel", kind: .liveTV, title: "Test", rawTitle: "Test",
            streamURL: URL(string: "https://tv.example/1.m3u8")!
        )]), epgURL: nil, skippedLines: 0)
    }
    func loadCache(for sourceID: UUID, storage: KanalStorage) -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) {}
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) -> [MediaItem] { [] }
    func loadGuide(from url: URL) -> XMLTVParser.ParseResult {
        .init(guide: .init(channelNames: [:], channelIcons: [:], schedules: [:]), repairs: [], isPartial: false)
    }
}
