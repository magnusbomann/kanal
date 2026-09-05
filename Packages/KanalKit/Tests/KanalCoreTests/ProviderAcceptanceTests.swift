import Foundation
import Testing
@testable import KanalCore

@Suite("Provider connection acceptance")
struct ProviderAcceptanceTests {
    enum Expected: Sendable { case readyXtream, readyPlaylist, asksForSignIn }

    @Test("Common provider links all enter the simple setup flow", arguments: [
        ("http://tv.example:8080/get.php?username=alice&password=secret&type=m3u_plus", Expected.readyXtream),
        ("https://tv.example/player_api.php?username=alice&password=secret", Expected.readyXtream),
        ("http://tv.example/playlist/alice/secret/m3u", Expected.readyXtream),
        ("xtream://tv.example/live/alice/secret/123.ts", Expected.readyXtream),
        ("https://cdn.example/subscription.m3u", Expected.readyPlaylist),
        ("https://cdn.example/lineup.m3u8?token=secret", Expected.readyPlaylist),
        ("https://cdn.example/api/list?device=apple", Expected.readyPlaylist),
        ("tv.example:8080", Expected.asksForSignIn),
        ("https://tv.example/player_api.php", Expected.asksForSignIn),
    ])
    func providerShape(input: String, expected: Expected) {
        switch (SourceDetector.detect(input), expected) {
        case (.complete(let source), .readyXtream):
            #expect(source.kind == .xtream)
            #expect(source.username == "alice")
            #expect(source.password == "secret")
        case (.complete(let source), .readyPlaylist):
            #expect(source.kind == .m3u)
            #expect(source.playlistURL != nil)
        case (.needsCredentials, .asksForSignIn):
            break
        default:
            Issue.record("Unexpected setup result for \(input)")
        }
    }

    @Test("Provider playlist variations still become playable entries")
    func playlistShapes() {
        let text = """
        #EXTM3U url-tvg="https://guide.example/epg.xml.gz"
        #EXTINF:-1 tvg-id="one" tvg-logo="https://img.example/one.png" group-title="NO | News",NRK 1 HD
        https://edge.example/live/u/p/1.ts
        #EXTINF:-1,Film Title (2025)
        https://edge.example/movie/u/p/2.mkv
        #EXTINF:-1 group-title="Series",Show Name S01E02 - Episode
        https://edge.example/series/u/p/3.mp4
        """
        let result = M3UParser().parse(text)
        #expect(result.items.count == 3)
        #expect(Set(result.items.map(\.kind)) == [.liveTV, .movie, .series])
        #expect(result.epgURL?.host() == "guide.example")
    }
}

@Suite("Redacted support reports")
struct SupportReportTests {
    @Test("A report never includes provider credentials or URL paths")
    func redaction() {
        let source = PlaylistSource(
            kind: .xtream,
            name: "Secret provider",
            portalURL: URL(string: "https://tv.example:8443/private/path?token=topsecret"),
            username: "alice",
            password: "hunter2"
        )
        let summary = SupportReport.sourceSummary(source)
        let report = SupportReport(
            appVersion: "1.0",
            system: "Test OS",
            phase: "failed",
            sourceCount: 1,
            activeSource: summary,
            channelCount: 10,
            movieCount: 20,
            seriesCount: 30,
            guideProgrammeCount: 40,
            guideCoveragePercent: 50,
            guideWasRepaired: true,
            guideIsPartial: false,
            skippedPlaylistLines: 2
        ).text

        #expect(report.contains("tv.example:8443"))
        #expect(!report.contains("alice"))
        #expect(!report.contains("hunter2"))
        #expect(!report.contains("topsecret"))
        #expect(!report.contains("private/path"))
        #expect(!report.contains("Secret provider"))
    }
}
