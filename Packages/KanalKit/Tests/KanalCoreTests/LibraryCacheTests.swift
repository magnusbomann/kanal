import Foundation
import Testing
@testable import KanalCore

@Suite("Library cache")
struct LibraryCacheTests {

    static let sourceID = UUID()

    static let items: [MediaItem] = [
        MediaItem(
            id: "live-1", kind: .liveTV, title: "TV 2", rawTitle: "NO| TV 2 FHD",
            streamURL: URL(string: "http://p.tv/play/abc/m3u8")!,
            logoURL: URL(string: "http://img/tv2.png"),
            rawGroup: "NO| Norge", category: "Norge",
            channelID: "tv2.no", channelNumber: 2,
            language: "no", countryCode: "NO", qualityTag: "FHD"
        ),
        MediaItem(
            id: "movie-1", kind: .movie, title: "Løvenes konge", rawTitle: "Løvenes konge (1994)",
            alternateTitles: ["The Lion King"],
            streamURL: URL(string: "http://p.tv/play/2dYu-ouRcW9G0wPFH7Vf")!,
            category: "Family", year: 1994
        ),
        MediaItem(
            id: "ep-1", kind: .series, title: "Show S01E02", rawTitle: "Show S01E02",
            streamURL: URL(string: "http://p.tv/play/xyz")!,
            seriesName: "Show", season: 1, episode: 2, providerSeriesID: 77
        ),
    ]

    @Test("Every field survives a round trip")
    func roundTrip() throws {
        let snapshot = LibraryCache.Snapshot(
            items: Self.items, savedAt: Date(timeIntervalSince1970: 1_787_000_000),
            sourceID: Self.sourceID
        )
        let decoded = try #require(LibraryCache.decode(LibraryCache.encode(snapshot)))

        #expect(decoded.sourceID == Self.sourceID)
        #expect(decoded.savedAt == snapshot.savedAt)
        #expect(decoded.items == Self.items)
    }

    @Test("Non-ASCII titles survive")
    func unicode() throws {
        let decoded = try #require(
            LibraryCache.decode(LibraryCache.encode(
                LibraryCache.Snapshot(items: Self.items, savedAt: .now, sourceID: Self.sourceID)
            ))
        )
        #expect(decoded.items[1].title == "Løvenes konge")
        #expect(decoded.items[1].alternateTitles == ["The Lion King"])
    }

    @Test("An empty catalogue is valid")
    func empty() throws {
        let decoded = try #require(
            LibraryCache.decode(LibraryCache.encode(
                LibraryCache.Snapshot(items: [], savedAt: .now, sourceID: Self.sourceID)
            ))
        )
        #expect(decoded.items.isEmpty)
    }

    /// A cache is a convenience. Anything wrong with it must cost a refresh,
    /// never a crash on launch.
    @Test("Corrupt data is refused rather than trusted")
    func refusesCorruption() {
        let good = LibraryCache.encode(
            LibraryCache.Snapshot(items: Self.items, savedAt: .now, sourceID: Self.sourceID)
        )
        #expect(LibraryCache.decode(Data()) == nil)
        #expect(LibraryCache.decode(Data([0, 1, 2, 3])) == nil)
        // Truncated part-way through the entries.
        #expect(LibraryCache.decode(good.prefix(good.count / 2)) == nil)
        // Right length, wrong magic.
        var wrongMagic = good
        wrongMagic[0] = 0xFF
        #expect(LibraryCache.decode(wrongMagic) == nil)
    }

    @Test("The file name is scoped to one source")
    func fileName() {
        let name = LibraryCache.fileName(for: Self.sourceID)
        #expect(name.contains(Self.sourceID.uuidString))
        #expect(name != LibraryCache.fileName(for: UUID()))
    }
}
