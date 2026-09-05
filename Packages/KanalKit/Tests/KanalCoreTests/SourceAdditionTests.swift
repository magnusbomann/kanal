import Foundation
import Testing
@testable import KanalCore

@MainActor
@Suite("Adding a source")
struct SourceAdditionTests {

    private let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-id="nrk1.no" group-title="Norway",NRK 1
    https://example.com/live/nrk1.m3u8
    """

    @Test("A broken first source is neither installed nor persisted")
    func brokenFirstSourceDoesNotStick() async throws {
        let directory = scratchDirectory()
        let storage = KanalStorage(directory: directory)
        let model = AppModel(storage: storage)
        let broken = PlaylistSource(
            kind: .localFile,
            name: "Broken",
            playlistURL: directory.appending(path: "missing.m3u")
        )

        do {
            try await model.add(broken)
            Issue.record("A missing playlist should not load")
        } catch {
            // The error belongs to the caller, which can explain it inline.
        }

        #expect(model.phase == .welcome)
        #expect(model.sources.isEmpty)
        #expect(model.activeSourceID == nil)
        #expect(model.profiles.isEmpty)
        let persisted = await storage.load([PlaylistSource].self, from: "sources.json")
        #expect(persisted == nil || persisted?.isEmpty == true)
    }

    @Test("A failed addition leaves the working source and library untouched")
    func failedSecondSourcePreservesWorkingLibrary() async throws {
        let directory = scratchDirectory()
        let storage = KanalStorage(directory: directory)
        let goodURL = directory.appending(path: "working.m3u")
        try Data(playlist.utf8).write(to: goodURL, options: .atomic)

        let model = AppModel(storage: storage)
        let good = PlaylistSource(kind: .localFile, name: "Working", playlistURL: goodURL)
        try await model.add(good)

        let originalSourceID = model.activeSourceID
        let originalItemIDs = model.catalogue.items.map(\.id)
        let originalVisibleItemIDs = model.library.items.map(\.id)
        let broken = PlaylistSource(
            kind: .localFile,
            name: "Broken",
            playlistURL: directory.appending(path: "missing.m3u")
        )

        do {
            try await model.add(broken)
            Issue.record("A missing playlist should not load")
        } catch {
            // Expected. The assertions below are the contract that matters.
        }

        #expect(model.phase == .ready)
        #expect(model.activeSourceID == originalSourceID)
        #expect(model.sources.map(\.id) == [good.id])
        #expect(model.catalogue.items.map(\.id) == originalItemIDs)
        #expect(model.library.items.map(\.id) == originalVisibleItemIDs)
        #expect(model.isRefreshingLibrary == false)
        let persisted = await storage.load([PlaylistSource].self, from: "sources.json")
        #expect(persisted?.map(\.id) == [good.id])
    }

    @Test("Pasted playlist text reopens after the cache is gone")
    func pastedPlaylistSurvivesRelaunch() async throws {
        let directory = scratchDirectory()
        let storage = KanalStorage(directory: directory)
        let firstLaunch = AppModel(storage: storage)

        let detection = try await firstLaunch.addSource(from: playlist)
        guard case .pastedText = detection else {
            Issue.record("Expected pasted playlist detection")
            return
        }
        let source = try #require(firstLaunch.activeSource)
        let fileURL = try #require(source.playlistURL)

        #expect(source.kind == .localFile)
        #expect(FileManager.default.fileExists(atPath: fileURL.path()))
        #expect(firstLaunch.catalogue.items.map(\.title) == ["NRK 1"])

        // Force the next model through LibraryLoader's local-file path. If the
        // pasted text itself was not saved, the otherwise-helpful cache would
        // hide that bug.
        await storage.removeCache(LibraryCache.fileName(for: source.id))

        let secondLaunch = AppModel(storage: storage)
        await secondLaunch.start()

        #expect(secondLaunch.phase == .ready)
        #expect(secondLaunch.activeSourceID == source.id)
        #expect(secondLaunch.catalogue.items.map(\.title) == ["NRK 1"])
    }

    @Test("An empty pasted playlist leaves no source behind")
    func emptyPasteDoesNotStick() async throws {
        let directory = scratchDirectory()
        let storage = KanalStorage(directory: directory)
        let model = AppModel(storage: storage)

        do {
            _ = try await model.addSource(from: "#EXTM3U\n# no playable entries")
            Issue.record("An empty playlist should fail")
        } catch {
            // Expected.
        }

        #expect(model.phase == .welcome)
        #expect(model.sources.isEmpty)
        let persisted = await storage.load([PlaylistSource].self, from: "sources.json")
        #expect(persisted == nil || persisted?.isEmpty == true)
    }

    @Test("Repair keeps the service identity, favourites and history")
    func repairKeepsHouseholdState() async throws {
        let directory = scratchDirectory()
        let storage = KanalStorage(directory: directory)
        let originalURL = directory.appending(path: "original.m3u")
        try Data(playlist.utf8).write(to: originalURL, options: .atomic)
        let model = AppModel(storage: storage)
        let original = PlaylistSource(kind: .localFile, name: "Living room", playlistURL: originalURL)
        try await model.add(original)
        let item = try #require(model.library.items.first)
        model.toggleFavorite(item.id)
        model.record(item: item, position: 120, duration: 600)

        let replacement = """
        #EXTM3U
        #EXTINF:-1 tvg-id="nrk2.no" group-title="Norway",NRK 2
        https://example.com/live/nrk2.m3u8
        """
        _ = try await model.repairSource(original, from: replacement)

        #expect(model.activeSourceID == original.id)
        #expect(model.sources.count == 1)
        #expect(model.sources.first?.id == original.id)
        #expect(model.sources.first?.name == "Living room")
        #expect(model.catalogue.items.map(\.title) == ["NRK 2"])
        #expect(model.watchState.favoriteIDs.contains(item.id))
        #expect(model.watchState.progress.isEmpty == false)
    }

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "KanalSourceAdditionTests")
            .appending(path: UUID().uuidString)
    }
}
