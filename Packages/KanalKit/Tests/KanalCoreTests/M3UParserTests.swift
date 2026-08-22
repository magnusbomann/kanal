import Foundation
import Testing
@testable import KanalCore

@Suite("M3U parsing")
struct M3UParserTests {

    let sample = """
    #EXTM3U x-tvg-url="http://example.com/epg.xml.gz"
    #EXTINF:-1 tvg-id="tv2.no" tvg-name="NO| TV 2 FHD" tvg-logo="http://img/tv2.png" tvg-chno="2" group-title="NO| Norge",NO| TV 2 FHD
    http://provider.tv/live/user/pass/1001.m3u8
    #EXTINF:-1 tvg-name="Blade Runner 2049" group-title="VOD - Movies",Blade Runner 2049 (2017)
    http://provider.tv/movie/user/pass/5001.mp4
    #EXTINF:-1 tvg-name="Breaking Bad S01E04",Breaking Bad S01E04
    http://provider.tv/series/user/pass/7001.mkv
    #EXTINF:-1,Local Radio
    #EXTGRP:Radio
    http://provider.tv/radio/9001
    """

    @Test("Reads the header EPG url")
    func epgURL() {
        let playlist = M3UParser().parse(sample)
        #expect(playlist.epgURL?.absoluteString == "http://example.com/epg.xml.gz")
    }

    @Test("Parses every entry")
    func itemCount() {
        #expect(M3UParser().parse(sample).items.count == 4)
    }

    @Test("Reads attributes off the EXTINF line")
    func attributes() throws {
        let item = try #require(M3UParser().parse(sample).items.first)
        #expect(item.channelID == "tv2.no")
        #expect(item.channelNumber == 2)
        #expect(item.logoURL?.absoluteString == "http://img/tv2.png")
        #expect(item.title == "TV 2")
        #expect(item.category == "Norge")
        #expect(item.kind == .liveTV)
    }

    @Test("Classifies movies from the url path")
    func movie() throws {
        let item = try #require(M3UParser().parse(sample).items.first { $0.title == "Blade Runner 2049" })
        #expect(item.kind == .movie)
        #expect(item.year == 2017)
    }

    @Test("Classifies series and keeps the show name")
    func series() throws {
        let item = try #require(M3UParser().parse(sample).items.first { $0.kind == .series })
        #expect(item.seriesName == "Breaking Bad")
        #expect(item.season == 1)
        #expect(item.episode == 4)
        #expect(item.episodeCode == "S01E04")
    }

    @Test("Honours #EXTGRP as the group")
    func extgrp() throws {
        let item = try #require(M3UParser().parse(sample).items.first { $0.title == "Local Radio" })
        #expect(item.rawGroup == "Radio")
    }

    @Test("Gives colliding tvg-ids distinct item ids")
    func duplicateIDs() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="dup",One
        http://a/1
        #EXTINF:-1 tvg-id="dup",Two
        http://a/2
        """
        let items = M3UParser().parse(text).items
        #expect(items.count == 2)
        #expect(items[0].id != items[1].id)
    }

    @Test("Skips entries with an unusable url")
    func badURL() {
        let text = """
        #EXTM3U
        #EXTINF:-1,Broken
        not a url at all
        """
        let playlist = M3UParser().parse(text)
        #expect(playlist.items.isEmpty)
        #expect(playlist.skippedLineCount == 1)
    }
}

@Suite("Classification")
struct MediaClassifierTests {

    func kind(title: String, url: String, group: String?) -> MediaKind {
        let cleaned = TitleCleaner.clean(title)
        return MediaClassifier.classify(
            title: cleaned.title,
            streamURL: URL(string: url)!,
            group: group,
            hasEpisodeMarker: cleaned.season != nil
        )
    }

    @Test("A live stream stays live even when its genre is called Series")
    func genreNamedSeries() {
        #expect(kind(title: "Beavis and Butt-Head", url: "https://cdn.example/live/abc.m3u8", group: "Series") == .liveTV)
        #expect(kind(title: "Best of MTV", url: "https://cdn.example/hls/mtv.m3u8", group: "Music;series") == .liveTV)
    }

    @Test("A live stream stays live when its genre is called Movies")
    func genreNamedMovies() {
        #expect(kind(title: "Movie Channel", url: "https://cdn.example/hls/x.m3u8", group: "Movies") == .liveTV)
    }

    @Test("Real VOD is still detected")
    func realVOD() {
        #expect(kind(title: "Blade Runner", url: "http://p.tv/movie/u/p/1.mp4", group: "VOD") == .movie)
        #expect(kind(title: "Show S01E02", url: "http://p.tv/series/u/p/2.mkv", group: "Series") == .series)
    }

    /// The shape a real panel uses: a format as a trailing path *segment* for
    /// live, and an opaque token for everything stored. An extension check
    /// alone reads a catalogue of hundreds of thousands of films as live TV.
    @Test("A format in the path names a live stream, not just an extension")
    func liveAsPathSegment() {
        #expect(kind(title: "NRK1", url: "http://p.tv/play/aB3xY9zQ7mK2pL5w/m3u8", group: "Norway") == .liveTV)
        #expect(kind(title: "NRK1", url: "http://p.tv/play/aB3xY9zQ7mK2pL5w/ts", group: "Norway") == .liveTV)
    }

    @Test("An opaque token with no format hint is stored media, not a channel")
    func opaqueTokenIsVOD() {
        // No extension, no /movie/ path, and a genre for a group: the only
        // thing left that distinguishes it is the shape of the last segment.
        #expect(kind(title: "Some Film", url: "http://p.tv/play/2dYu-ouRcW9G0wPFH7Vf", group: "Drama") == .movie)
        #expect(kind(title: "Show S01E02", url: "http://p.tv/play/2dYu-ouRcW9G0wPFH7Vf", group: "Drama") == .series)
    }

    @Test("A short, human-looking segment stays a channel")
    func shortSegmentStaysLive() {
        // Radio and numbered channels are addressed by something a person
        // could have typed, and must not be swept up as films.
        #expect(kind(title: "Local Radio", url: "http://p.tv/radio/9001", group: "Radio") == .liveTV)
        #expect(kind(title: "Channel 5", url: "http://p.tv/stream/105", group: "UK") == .liveTV)
    }

    @Test("Episode markers beat a live-looking url")
    func episodeBeatsLiveURL() {
        #expect(kind(title: "Show S02E05", url: "http://p.tv/live/u/p/3.m3u8", group: nil) == .series)
    }
}

@Suite("Category names")
struct CategoryNormalizerTests {

    @Test("Splits packed genre fields into a phrase")
    func packed() {
        #expect(CategoryNormalizer.normalize("Animation;comedy") == "Animation & Comedy")
    }

    @Test("Strips country markers")
    func markers() {
        #expect(CategoryNormalizer.normalize("NO| Norge") == "Norge")
        #expect(CategoryNormalizer.normalize("[SE] Sport") == "Sport")
    }

    @Test("Keeps short acronyms uppercase")
    func acronyms() {
        #expect(CategoryNormalizer.normalize("MTV music") == "MTV Music")
    }
}
