import Foundation
import Testing
@testable import KanalCore

@Suite("Index cost", .serialized)
struct PerfCheck {
    @Test("Indexing a provider-sized library stays off the critical path")
    func bigLibrary() {
        let words = ["Sport", "Nyheter", "Kino", "Drama", "Løvenes", "Skjønnheten", "Action", "Kids", "HD", "Viaplay"]
        var items: [MediaItem] = []
        items.reserveCapacity(50_000)
        for index in 0..<50_000 {
            let title = (0..<3).map { words[(index + $0 * 7) % words.count] }.joined(separator: " ") + " \(index)"
            items.append(
                MediaItem(
                    id: "\(index)",
                    kind: .movie,
                    title: title,
                    rawTitle: "NO| \(title) FHD",
                    streamURL: URL(string: "http://a/\(index).mp4")!
                )
            )
        }

        let buildStart = Date()
        let index = SearchIndex(items: items)
        let buildSeconds = Date().timeIntervalSince(buildStart)

        let queryStart = Date()
        let hits = index.search("skjonnheten")
        let querySeconds = Date().timeIntervalSince(queryStart)

        print("BUILD \(String(format: "%.2f", buildSeconds))s  QUERY \(String(format: "%.4f", querySeconds))s  hits \(hits.count)")
        #expect(!hits.isEmpty)
        #expect(querySeconds < 0.5)
    }
}
