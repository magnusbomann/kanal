import Foundation
import Testing
@testable import KanalCore

@Suite("Download versions")
struct DownloadOptionTests {
    @Test("Quality is read from a listing's name")
    func qualityFromName() {
        #expect(DownloadOption.quality(fromName: "Coco 4K (2017)") == "4K")
        #expect(DownloadOption.quality(fromName: "NO: Coco [UHD]") == "4K")
        #expect(DownloadOption.quality(fromName: "Coco FHD") == "1080p")
        #expect(DownloadOption.quality(fromName: "Coco 720p") == "720p")
        #expect(DownloadOption.quality(fromName: "Coco (2017)") == nil)
        // A year is not a resolution.
        #expect(DownloadOption.quality(fromName: "Blade Runner 2049") == nil)
    }

    @Test("Picture height maps to the names people use")
    func qualityFromHeight() {
        #expect(DownloadOption.quality(height: 2160) == "4K")
        #expect(DownloadOption.quality(height: 1080) == "1080p")
        #expect(DownloadOption.quality(height: 800) == "1080p" || DownloadOption.quality(height: 800) == "720p")
        #expect(DownloadOption.quality(height: 720) == "720p")
        #expect(DownloadOption.quality(height: 480) == "SD")
    }

    @Test("An M3U film from an Xtream panel leads back to its API")
    func panelFromStream() throws {
        let url = try #require(URL(string: "http://panel.example:8080/movie/alice/secret/12345.mkv"))
        let panel = try #require(XtreamClient.panel(forMovieStream: url))
        #expect(panel.streamID == 12345)
        let info = panel.client.actionURL("get_vod_info").absoluteString
        #expect(info.hasPrefix("http://panel.example:8080/player_api.php"))
        #expect(info.contains("username=alice"))
        #expect(info.contains("password=secret"))
    }

    @Test("Other stream addresses are not mistaken for a panel")
    func notAPanel() throws {
        #expect(XtreamClient.panel(forMovieStream: try #require(URL(string: "http://cdn.example/films/coco.mkv"))) == nil)
        #expect(XtreamClient.panel(forMovieStream: try #require(URL(string: "http://p.example/series/a/b/9.mkv"))) == nil)
    }
}
