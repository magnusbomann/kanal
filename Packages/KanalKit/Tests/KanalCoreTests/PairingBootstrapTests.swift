import Foundation
import Testing
@testable import KanalCore

@MainActor
@Suite("Pairing bootstrap")
struct PairingBootstrapTests {

    @Test("A pairing payload bootstraps sources, profiles and viewing state")
    func bootstrapsHousehold() async throws {
        let phoneStorage = storage("phone")
        let phoneVault = MemorySourceCredentialStore()
        let phone = AppModel(
            loader: BootstrapLoader(), storage: phoneStorage,
            credentialStore: phoneVault, householdSync: NoopHouseholdSync()
        )
        _ = try await phone.addSource(from: playlist)
        // Adding the first source creates the household owner automatically.
        let owner = try #require(phone.profiles.first)
        let child = Profile.makeChild(named: "Child", maturity: .allAges)
        await phone.addProfile(child)
        await phone.activate(owner)
        let favoriteID = try #require(phone.library.items.first?.id)
        phone.toggleFavorite(favoriteID)

        let payload = try await phone.makePairingPayload()
        let (_, pairingKey) = Pairing.Invitation.generate()
        let sealedPayload = try Pairing.seal(payload, with: pairingKey)
        let openedPayload = try Pairing.open(sealedPayload, with: pairingKey)
        let tvStorage = storage("tv")
        let tvVault = MemorySourceCredentialStore()
        let tv = AppModel(
            loader: BootstrapLoader(), storage: tvStorage,
            credentialStore: tvVault, householdSync: NoopHouseholdSync()
        )
        try await tv.receivePairing(openedPayload)

        #expect(tv.sources.map(\.id) == phone.sources.map(\.id))
        #expect(Set(tv.profiles.map(\.id)) == Set([owner.id, child.id]))
        #expect(tv.isChoosingProfile)
        await tv.activate(owner)
        #expect(tv.library.items.map(\.id) == phone.library.items.map(\.id))
        #expect(tv.watchState.favoriteIDs == phone.watchState.favoriteIDs)

        let restarted = AppModel(
            loader: BootstrapLoader(), storage: tvStorage,
            credentialStore: tvVault, householdSync: NoopHouseholdSync()
        )
        await restarted.start()
        let sourceID = try #require(phone.activeSourceID)
        #expect(restarted.sources.map(\.id) == [sourceID])
        #expect(Set(restarted.profiles.map(\.id)) == Set([owner.id, child.id]))
        #expect(restarted.isChoosingProfile)
    }

    @Test("Receiving the same payload is idempotent")
    func repeatedReceiveDoesNotDuplicateSources() async throws {
        let phone = AppModel(
            loader: BootstrapLoader(), storage: storage("repeat-phone"),
            credentialStore: MemorySourceCredentialStore(), householdSync: NoopHouseholdSync()
        )
        _ = try await phone.addSource(from: playlist)
        let payload = try await phone.makePairingPayload()
        let tv = AppModel(
            loader: BootstrapLoader(), storage: storage("repeat-tv"),
            credentialStore: MemorySourceCredentialStore(), householdSync: NoopHouseholdSync()
        )
        try await tv.receivePairing(payload)
        try await tv.receivePairing(payload)
        let sourceID = try #require(phone.activeSourceID)
        #expect(tv.sources.map(\.id) == [sourceID])
    }

    @Test("An empty pairing payload is rejected without changing the TV")
    func emptyPayloadRejected() async throws {
        let tv = AppModel(
            loader: BootstrapLoader(), storage: storage("empty-tv"),
            credentialStore: MemorySourceCredentialStore(), householdSync: NoopHouseholdSync()
        )
        let before = (tv.sources, tv.profiles)
        await #expect(throws: (any Error).self) {
            try await tv.receivePairing(Pairing.Payload(sources: []))
        }
        #expect(tv.sources == before.0)
        #expect(tv.profiles == before.1)
    }

    @Test("A failed network source leaves the TV household untouched")
    func failedSourceIsAtomic() async throws {
        let source = PlaylistSource(
            kind: .xtream, name: "Provider", portalURL: URL(string: "https://tv.example"),
            username: "user", password: "secret"
        )
        let tv = AppModel(
            loader: RejectingLoader(), storage: storage("failed-tv"),
            credentialStore: MemorySourceCredentialStore(), householdSync: NoopHouseholdSync()
        )
        let before = (tv.sources, tv.profiles)
        let payload = Pairing.Payload(
            sources: [source],
            household: HouseholdSnapshot(sources: [source], profiles: [Profile(name: "Owner")], watchStates: [:]),
            activeSourceID: source.id
        )
        await #expect(throws: (any Error).self) {
            try await tv.receivePairing(payload)
        }
        #expect(tv.sources == before.0)
        #expect(tv.profiles == before.1)
    }

    @Test("Credential persistence failure leaves the TV household untouched")
    func failedCredentialPersistenceIsAtomic() async throws {
        let source = PlaylistSource(
            kind: .xtream, name: "Provider", portalURL: URL(string: "https://tv.example"),
            username: "user", password: "secret"
        )
        let tv = AppModel(
            loader: BootstrapLoader(), storage: storage("failed-credentials-tv"),
            credentialStore: ThrowingCredentialStore(), householdSync: NoopHouseholdSync()
        )
        let before = (tv.sources, tv.profiles)
        let payload = Pairing.Payload(
            sources: [source],
            household: HouseholdSnapshot(sources: [source], profiles: [Profile(name: "Owner")], watchStates: [:]),
            activeSourceID: source.id
        )
        await #expect(throws: (any Error).self) {
            try await tv.receivePairing(payload)
        }
        #expect(tv.sources == before.0)
        #expect(tv.profiles == before.1)
    }

    @Test("Redacted cloud recovery keeps profiles until QR restores credentials")
    func cloudRecoveryPreservesProfiles() async throws {
        let source = PlaylistSource(
            kind: .xtream, name: "Provider", portalURL: URL(string: "https://tv.example"),
            username: "user", password: "secret"
        )
        let owner = Profile(name: "Owner")
        let child = Profile.makeChild(named: "Child", maturity: .allAges)
        let tvStorage = storage("cloud-recovery-tv")
        await tvStorage.save([source.redactedForPersistence], to: "sources.json")
        await tvStorage.save([owner, child], to: "profiles.json")

        let tv = AppModel(
            loader: BootstrapLoader(), storage: tvStorage,
            credentialStore: MemorySourceCredentialStore(), householdSync: NoopHouseholdSync()
        )
        await tv.start()
        #expect(tv.phase == .welcome)
        #expect(Set(tv.profiles.map(\.id)) == Set([owner.id, child.id]))

        let payload = Pairing.Payload(
            sources: [source],
            household: HouseholdSnapshot(sources: [source], profiles: [owner, child], watchStates: [:]),
            activeSourceID: source.id
        )
        try await tv.receivePairing(payload)
        await tv.activate(owner)
        #expect(tv.sources.map(\.id) == [source.id])
        #expect(tv.library.items.map(\.id) == ["one"])
        #expect(tv.profiles.map(\.id).contains(owner.id))
    }

    private let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-id="one",Channel One
    https://example.com/channel.m3u8
    """

    private func storage(_ name: String) -> KanalStorage {
        KanalStorage(directory: FileManager.default.temporaryDirectory
            .appending(path: "KanalPairingBootstrapTests")
            .appending(path: name)
            .appending(path: UUID().uuidString))
    }
}

private actor BootstrapLoader: LibraryLoading {
    private let item = MediaItem(
        id: "one", kind: .liveTV, title: "Channel One", rawTitle: "Channel One",
        streamURL: URL(string: "https://example.com/channel.m3u8")!
    )

    func loadLibrary(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult {
        LibraryLoader.LibraryResult(library: Library(items: [item]), epgURL: nil, skippedLines: 0)
    }
    func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async {}
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem] { [] }
    func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult {
        XMLTVParser.ParseResult(guide: .init(channelNames: [:], channelIcons: [:], schedules: [:]), repairs: [], isPartial: false)
    }
}

private actor RejectingLoader: LibraryLoading {
    enum Failure: Error { case unavailable }
    func loadLibrary(for source: PlaylistSource) async throws -> LibraryLoader.LibraryResult { throw Failure.unavailable }
    func loadCache(for sourceID: UUID, storage: KanalStorage) async -> Library? { nil }
    func saveCache(_ library: Library, for sourceID: UUID, storage: KanalStorage) async {}
    func loadEpisodes(for source: PlaylistSource, seriesID: Int) async throws -> [MediaItem] { [] }
    func loadGuide(from url: URL) async throws -> XMLTVParser.ParseResult {
        XMLTVParser.ParseResult(guide: .init(channelNames: [:], channelIcons: [:], schedules: [:]), repairs: [], isPartial: false)
    }
}

private actor ThrowingCredentialStore: SourceCredentialStoring {
    enum Failure: Error { case unavailable }
    func load(for sourceID: UUID) async throws -> SourceCredentials? { nil }
    func save(_ credentials: SourceCredentials, for sourceID: UUID) async throws {
        throw Failure.unavailable
    }
    func remove(for sourceID: UUID) async throws {}
}
