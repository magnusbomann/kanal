import Foundation
import Testing
@testable import KanalCore

@Suite("Downloads")
struct DownloadTests {

    @Test("A provider url without an extension is saved as Matroska")
    func extensionlessUrlBecomesMatroska() {
        // The measured panel serves MKV whatever is asked of it, and its urls
        // are bare tokens. Guessing anything else files a film under a
        // container the system player would then refuse to open.
        #expect(DownloadFixtures.fileExtension(for: "https://panel.test/play/9f3a1b") == "mkv")
        #expect(DownloadFixtures.fileExtension(for: "https://panel.test/film.mkv") == "mkv")
        #expect(DownloadFixtures.fileExtension(for: "https://panel.test/film.mp4") == "mp4")
        // A path that ends in something that is not a container at all.
        #expect(DownloadFixtures.fileExtension(for: "https://panel.test/play/token/m3u8") == "mkv")
    }

    @Test("Downloads are scoped to the service they came from")
    func keysAreSourceScoped() {
        let first = UUID()
        let second = UUID()
        #expect(Download.key(itemID: "1234", sourceID: first)
            != Download.key(itemID: "1234", sourceID: second))
        #expect(Download.key(itemID: "1234", sourceID: nil) == "1234")
    }

    @Test("Progress is unknown until the server says how big the file is")
    func fractionNeedsAnExpectedSize() {
        var record = DownloadFixtures.record()
        record.byteCount = 500
        #expect(record.fraction == nil)
        record.expectedByteCount = 1_000
        #expect(record.fraction == 0.5)
    }

    @MainActor
    @Test("Queueing a title once leaves one record, and live TV is refused")
    func addingIsIdempotentAndRefusesLiveTV() async {
        let store = DownloadStore(storage: KanalStorage(directory: DownloadFixtures.scratch()))
        let film = DownloadFixtures.film()
        let source = UUID()

        store.add(film, sourceID: source)
        store.add(film, sourceID: source)
        #expect(store.downloads.count == 1)
        #expect(store.downloads.first?.state == .waiting)

        let channel = MediaItem(
            id: "channel", kind: .liveTV, title: "NRK1", rawTitle: "NRK1",
            streamURL: URL(string: "https://panel.test/play/token/m3u8")!
        )
        #expect(store.add(channel, sourceID: source) == nil)
        #expect(store.downloads.count == 1)
    }

    @MainActor
    @Test("An unfinished download is never offered as a local file")
    func onlyFinishedFilesArePlayable() async {
        let directory = DownloadFixtures.scratch()
        let store = DownloadStore(
            storage: KanalStorage(directory: directory), directory: directory
        )
        let film = DownloadFixtures.film()
        let source = UUID()
        store.add(film, sourceID: source)

        #expect(store.playableFile(for: film, sourceID: source) == nil)

        // Marked finished, but with nothing on the disk behind it — a purged
        // tvOS cache looks exactly like this, and playing it would strand
        // someone on a black screen rather than reaching the provider.
        store.recordFinished(store.downloads[0].fileName, size: 10)
        #expect(store.playableFile(for: film, sourceID: source) == nil)

        try? Data("video".utf8).write(to: store.fileURL(store.downloads[0]))
        #expect(store.playableFile(for: film, sourceID: source) != nil)
        // Another service asking for the same id gets nothing.
        #expect(store.playableFile(for: film, sourceID: UUID()) == nil)
    }

    @MainActor
    @Test("Deleting a download takes the file with it")
    func removingDeletesTheFile() async {
        let directory = DownloadFixtures.scratch()
        let store = DownloadStore(
            storage: KanalStorage(directory: directory), directory: directory
        )
        store.add(DownloadFixtures.film(), sourceID: nil)
        let record = store.downloads[0]
        try? Data("video".utf8).write(to: store.fileURL(record))

        store.remove(record.id)

        #expect(store.downloads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(record).path))
    }

    @MainActor
    @Test("Playback holds the queue, because the account allows one connection")
    func playbackHoldsTheQueue() async {
        let store = DownloadStore(storage: KanalStorage(directory: DownloadFixtures.scratch()))
        store.setPlaybackActive(true)
        #expect(store.isHeldForPlayback)
        store.setPlaybackActive(false)
        #expect(!store.isHeldForPlayback)
    }
}

@Suite("Taking things off Home")
struct ForgettingTests {

    @Test("Forgetting a title clears its position as well as its row")
    func forgetClearsProgressAndHistory() {
        var state = WatchState()
        let film = DownloadFixtures.film()
        state.record(WatchProgress(itemID: film.id, position: 600, duration: 5_400), item: film)

        state.forget(film.id)

        #expect(state.recentIDs.isEmpty)
        #expect(state.progress[film.id] == nil)
        #expect(state.recentItems[film.id] == nil)
    }

    @Test("Clearing history leaves favourites alone")
    func clearingHistoryKeepsFavourites() {
        var state = WatchState()
        state.toggleFavorite("kept")
        state.record(WatchProgress(itemID: "film", position: 60, duration: 600))
        state.recordChannel(groupID: "channel")

        state.clearHistory()

        #expect(state.favoriteIDs == ["kept"])
        #expect(state.recentIDs.isEmpty)
        #expect(state.recentChannelGroupIDs.isEmpty)
        #expect(state.progress.isEmpty)
    }

    @Test("Clearing favourites leaves history alone")
    func clearingFavouritesKeepsHistory() {
        var state = WatchState()
        state.toggleFavorite("gone")
        state.record(WatchProgress(itemID: "film", position: 600, duration: 5_400))

        state.clearFavorites()

        #expect(state.favoriteIDs.isEmpty)
        #expect(state.recentIDs == ["film"])
    }
}

enum DownloadFixtures {
    static func film(id: String = "film-1") -> MediaItem {
        MediaItem(
            id: id, kind: .movie, title: "Løvenes konge", rawTitle: "Løvenes konge",
            streamURL: URL(string: "https://panel.test/movie/\(id)")!
        )
    }

    static func record() -> Download {
        Download(id: "one", item: film(), sourceID: nil, fileName: "one.mkv")
    }

    static func fileExtension(for url: String) -> String {
        var item = film()
        item.streamURL = URL(string: url)!
        return Download.fileExtension(for: item)
    }

    static func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "kanal-downloads-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
