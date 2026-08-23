import Foundation
import Testing
@testable import KanalCore

@Suite("What plays next")
struct NextEpisodeTests {

    static func episode(_ season: Int?, _ number: Int?, show: String = "Breaking Bad") -> MediaItem {
        MediaItem(
            id: "\(show)-\(season.map(String.init) ?? "x")-\(number.map(String.init) ?? "x")",
            kind: .series,
            title: "\(show) S\(season ?? 0)E\(number ?? 0)",
            rawTitle: "raw",
            streamURL: URL(string: "http://p.tv/play/\(show)\(season ?? 0)\(number ?? 0)")!,
            seriesName: show, season: season, episode: number
        )
    }

    let run = [
        episode(1, 1), episode(1, 2), episode(1, 3),
        episode(2, 1), episode(2, 2),
    ]

    @Test("The next episode of the same season")
    func withinSeason() {
        let next = Library.nextEpisode(after: Self.episode(1, 1), among: run)
        #expect(next?.season == 1)
        #expect(next?.episode == 2)
    }

    /// The end of a season is not the end of the show.
    @Test("Rolls over into the next season")
    func acrossSeasons() {
        let next = Library.nextEpisode(after: Self.episode(1, 3), among: run)
        #expect(next?.season == 2)
        #expect(next?.episode == 1)
    }

    @Test("Stops at the end rather than looping")
    func stopsAtTheEnd() {
        #expect(Library.nextEpisode(after: Self.episode(2, 2), among: run) == nil)
    }

    @Test("Order comes from the numbers, not from the list")
    func ordersByNumber() {
        let shuffled = run.shuffled()
        let next = Library.nextEpisode(after: Self.episode(1, 2), among: shuffled)
        #expect(next?.episode == 3)
    }

    /// An unnumbered extra is not "the next episode" of anything.
    @Test("An unnumbered extra never plays automatically")
    func skipsUnnumbered() {
        let withExtra = [Self.episode(1, 1), Self.episode(nil, nil)]
        #expect(Library.nextEpisode(after: Self.episode(1, 1), among: withExtra) == nil)
    }

    @Test("An episode not in the list has no successor")
    func unknownEpisode() {
        #expect(Library.nextEpisode(after: Self.episode(9, 9), among: run) == nil)
    }

    @Test("A single episode stands alone")
    func onlyEpisode() {
        let one = [Self.episode(1, 1)]
        #expect(Library.nextEpisode(after: one[0], among: one) == nil)
    }

    @Test("A film has nothing after it")
    func filmHasNoNext() {
        let library = Library(items: [
            MediaItem(
                id: "m", kind: .movie, title: "Film", rawTitle: "Film",
                streamURL: URL(string: "http://p.tv/play/m")!
            ),
        ])
        #expect(library.seriesGroup(containing: library.movies[0]) == nil)
    }

    @Test("An episode can find its own show")
    func findsItsShow() throws {
        let library = Library(items: run)
        let group = try #require(library.seriesGroup(containing: run[0]))
        #expect(group.episodes.count == 5)
    }
}
