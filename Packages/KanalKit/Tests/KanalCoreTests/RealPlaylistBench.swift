import Foundation
import Testing
@testable import KanalCore

/// Measured against a real provider catalogue, not a synthetic one.
///
/// Enable with a path to an .m3u on disk:
///
///     KANAL_BENCH_M3U=/tmp/real.m3u swift test --filter RealPlaylistBench
@Suite(
    "Real playlist",
    .enabled(if: ProcessInfo.processInfo.environment["KANAL_BENCH_M3U"] != nil)
)
struct RealPlaylistBench {

    @Test("Parsing and organising a full catalogue")
    func parseCost() throws {
        let path = ProcessInfo.processInfo.environment["KANAL_BENCH_M3U"]!
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let text = String(decoding: data, as: UTF8.self)

        var mark = Date()
        let playlist = M3UParser().parse(text)
        let parse = Date().timeIntervalSince(mark)

        mark = Date()
        let library = Library(items: playlist.items)
        let organise = Date().timeIntervalSince(mark)

        mark = Date()
        let json = try JSONEncoder().encode(playlist.items)
        let encodeJSON = Date().timeIntervalSince(mark)

        let snapshot = LibraryCache.Snapshot(
            items: playlist.items, savedAt: .now, sourceID: UUID()
        )
        mark = Date()
        let packed = LibraryCache.encode(snapshot)
        let encode = Date().timeIntervalSince(mark)

        mark = Date()
        let restored = LibraryCache.decode(packed)
        let decode = Date().timeIntervalSince(mark)
        #expect(restored?.items.count == playlist.items.count)

        print("""

          entries      \(playlist.items.count)
          source       \(data.count / 1_048_576) MB
          parse        \(String(format: "%.2f", parse))s
          organise     \(String(format: "%.2f", organise))s
          as JSON      \(json.count / 1_048_576) MB (\(String(format: "%.2f", encodeJSON))s)
          cache write  \(String(format: "%.2f", encode))s -> \(packed.count / 1_048_576) MB
          cache read   \(String(format: "%.2f", decode))s

          channels \(library.channels.count)  films \(library.movies.count)  series \(library.series.count)
        """)
        #expect(!playlist.items.isEmpty)
    }
}
