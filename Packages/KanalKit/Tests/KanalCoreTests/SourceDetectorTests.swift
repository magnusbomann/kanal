import Foundation
import Testing
@testable import KanalCore

@Suite("Source detection")
struct SourceDetectorTests {

    @Test("Recognises get.php links with credentials in the query")
    func getPHP() throws {
        let detection = SourceDetector.detect(
            "http://example.com:8080/get.php?username=abc&password=xyz&type=m3u_plus&output=ts"
        )
        guard case .complete(let source) = detection else {
            Issue.record("expected a complete source, got \(detection)")
            return
        }
        #expect(source.kind == .xtream)
        #expect(source.username == "abc")
        #expect(source.password == "xyz")
        #expect(source.portalURL?.absoluteString == "http://example.com:8080")
    }

    @Test("Recognises credentials carried in the path")
    func pathCredentials() throws {
        let detection = SourceDetector.detect("http://example.com/playlist/abc/xyz/m3u")
        guard case .complete(let source) = detection else {
            Issue.record("expected a complete source, got \(detection)")
            return
        }
        #expect(source.kind == .xtream)
        #expect(source.username == "abc")
        #expect(source.password == "xyz")
    }

    @Test("Recognises a plain playlist file")
    func plainFile() throws {
        let detection = SourceDetector.detect("https://iptv-org.github.io/iptv/index.m3u")
        guard case .complete(let source) = detection else {
            Issue.record("expected a complete source, got \(detection)")
            return
        }
        #expect(source.kind == .m3u)
        #expect(source.playlistURL?.absoluteString == "https://iptv-org.github.io/iptv/index.m3u")
    }

    @Test("Asks for credentials on a bare portal", arguments: [
        "example.com:8080",
        "http://example.com:8080/",
        "http://example.com:8080/player_api.php",
    ])
    func barePortal(input: String) {
        guard case .needsCredentials(let portal, _) = SourceDetector.detect(input) else {
            Issue.record("expected needsCredentials for \(input)")
            return
        }
        #expect(portal.absoluteString == "http://example.com:8080")
    }

    @Test("Accepts provider schemes from QR codes")
    func customScheme() throws {
        let detection = SourceDetector.detect("iptv://example.com/get.php?username=a&password=b")
        guard case .complete(let source) = detection else {
            Issue.record("expected a complete source, got \(detection)")
            return
        }
        #expect(source.kind == .xtream)
    }

    @Test("Takes pasted playlist text as-is")
    func pasted() {
        guard case .pastedText(let text) = SourceDetector.detect("#EXTM3U\n#EXTINF:-1,A\nhttp://a/1") else {
            Issue.record("expected pastedText")
            return
        }
        #expect(text.hasPrefix("#EXTM3U"))
    }

    @Test("Rejects input that is not a link")
    func garbage() {
        guard case .unrecognized = SourceDetector.detect("hello there") else {
            Issue.record("expected unrecognized")
            return
        }
    }
}
