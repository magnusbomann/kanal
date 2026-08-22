import Foundation
import Testing
@testable import KanalCore

@Suite("Stream formats")
struct StreamCandidatesTests {

    static func item(_ url: String, kind: MediaKind = .movie) -> MediaItem {
        MediaItem(
            id: "1", kind: kind, title: "T", rawTitle: "T",
            streamURL: URL(string: url)!
        )
    }

    @Test("A live stream is left alone")
    func liveUntouched() {
        let url = "http://p.tv/live/u/p/1.m3u8"
        #expect(StreamCandidates.candidates(for: Self.item(url, kind: .liveTV)) == [URL(string: url)!])
    }

    @Test("A playable container is left alone", arguments: ["mp4", "m4v", "mov", "ts", "m3u8"])
    func nativeUntouched(ext: String) {
        let url = "http://p.tv/movie/u/p/1.\(ext)"
        #expect(StreamCandidates.candidates(for: Self.item(url)).count == 1)
    }

    /// The case that broke every film and episode: panels serve VOD as MKV,
    /// which AVFoundation cannot open at all.
    @Test("An MKV is retried as formats Apple can open")
    func mkvGetsAlternatives() {
        let candidates = StreamCandidates.candidates(for: Self.item("http://p.tv/movie/u/p/1.mkv"))
        let extensions = candidates.map { $0.pathExtension }
        #expect(extensions == ["m3u8", "mp4", "ts", "mkv"])
        // The provider's own url is tried last, so a failure names what they published.
        #expect(candidates.last?.absoluteString == "http://p.tv/movie/u/p/1.mkv")
    }

    @Test("Every foreign container gets alternatives", arguments: ["mkv", "avi", "wmv", "flv"])
    func foreignRecognised(ext: String) {
        #expect(StreamCandidates.isForeign(URL(string: "http://p.tv/movie/u/p/1.\(ext)")!))
        #expect(StreamCandidates.candidates(for: Self.item("http://p.tv/movie/u/p/1.\(ext)")).count > 1)
    }
}

@Suite("Playback failures")
struct PlaybackFailureTests {

    static func failure(code: Int, url: String) -> PlaybackFailure {
        PlaybackFailure(
            error: NSError(domain: AVFoundationErrorDomainName, code: code),
            url: URL(string: url)!
        )
    }

    /// Measured on device: these are the codes an unopenable container gives,
    /// and both surface to the viewer as the same unhelpful "Cannot Open".
    @Test("Names the container when AVFoundation cannot open it", arguments: [-11828, -11829])
    func unsupportedContainer(code: Int) {
        #expect(Self.failure(code: code, url: "http://p.tv/movie/u/p/1.mkv") == .unsupportedContainer("mkv"))
    }

    @Test("Distinguishes a server that will not serve byte ranges")
    func notStreamable() {
        #expect(Self.failure(code: -11850, url: "http://p.tv/movie/u/p/1.mp4") == .serverNotStreamable)
    }

    @Test("A refused request is not reported as a broken file")
    func rejected() {
        #expect(Self.failure(code: -1013, url: "http://p.tv/movie/u/p/1.mp4") == .rejected)
    }

    @Test("No network is not reported as a broken file")
    func offline() {
        #expect(Self.failure(code: -1009, url: "http://p.tv/movie/u/p/1.mp4") == .offline)
    }
}

private let AVFoundationErrorDomainName = "AVFoundationErrorDomain"
