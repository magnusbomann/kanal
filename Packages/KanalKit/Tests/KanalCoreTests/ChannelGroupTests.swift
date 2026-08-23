import Foundation
import Testing
@testable import KanalCore

@Suite("Folding duplicate channels")
struct ChannelGroupTests {

    static func channel(_ title: String, url: String, category: String? = nil) -> MediaItem {
        MediaItem(
            id: "\(title)|\(url)", kind: .liveTV, title: TitleCleaner.clean(title).title,
            rawTitle: title, streamURL: URL(string: url)!, category: category,
            qualityTag: TitleCleaner.clean(title).qualityTag
        )
    }

    /// The common case on a real provider: one stream listed under several
    /// categories. Folding these away is pure gain.
    @Test("The same stream in several categories becomes one channel")
    func sameStreamManyCategories() throws {
        let library = Library(items: [
            Self.channel("V sport 1", url: "http://p.tv/a/m3u8", category: "Norway"),
            Self.channel("V sport 1", url: "http://p.tv/a/m3u8", category: "Norway Sport"),
            Self.channel("V sport 1", url: "http://p.tv/a/m3u8", category: "All Sport"),
        ])
        let group = try #require(library.channelGroups.first)
        #expect(library.channelGroups.count == 1)
        #expect(group.variants.count == 1)
        #expect(group.categories == ["All Sport", "Norway", "Norway Sport"])
        #expect(group.hasAlternatives == false)
    }

    /// The case that matters: different streams for the same channel. Losing
    /// these would throw away feeds that work when the first one does not.
    @Test("Different streams are kept as alternatives")
    func keepsAlternatives() throws {
        let library = Library(items: [
            Self.channel("V sport 1", url: "http://p.tv/plain/m3u8"),
            Self.channel("V sport 1 HD", url: "http://p.tv/hd/m3u8"),
            Self.channel("V sport 1 HD | raw", url: "http://p.tv/raw/m3u8"),
        ])
        let group = try #require(library.channelGroups.first)
        #expect(library.channelGroups.count == 1)
        #expect(group.variants.count == 3, "no working stream may be discarded")
        #expect(group.hasAlternatives)
    }

    @Test("Alternatives are ordered by how promising they look")
    func ordersByQuality() throws {
        let library = Library(items: [
            Self.channel("Eurosport 1 SD", url: "http://p.tv/sd/m3u8"),
            Self.channel("Eurosport 1 HD | raw", url: "http://p.tv/raw/m3u8"),
            Self.channel("Eurosport 1 HD", url: "http://p.tv/hd/m3u8"),
        ])
        let group = try #require(library.channelGroups.first)
        // HD leads, then the raw feed, then SD. Nothing is dropped.
        #expect(group.primary.rawTitle == "Eurosport 1 HD")
        #expect(group.variants.last?.rawTitle == "Eurosport 1 SD")
    }

    @Test("The shortest name represents the group")
    func shortestName() throws {
        let library = Library(items: [
            Self.channel("V sport golf HD | raw", url: "http://p.tv/1/m3u8"),
            Self.channel("V sport golf", url: "http://p.tv/2/m3u8"),
        ])
        #expect(library.channelGroups.first?.name == "V sport golf")
    }

    @Test("Channels that merely resemble each other stay apart")
    func doesNotOvermerge() {
        let library = Library(items: [
            Self.channel("V sport 1", url: "http://p.tv/1/m3u8"),
            Self.channel("V sport 2", url: "http://p.tv/2/m3u8"),
            Self.channel("V sport premium", url: "http://p.tv/3/m3u8"),
        ])
        #expect(library.channelGroups.count == 3)
    }

    @Test("A channel can be traced back to its group")
    func findsGroup() throws {
        let library = Library(items: [
            Self.channel("NRK1", url: "http://p.tv/a/m3u8"),
            Self.channel("NRK1 HD", url: "http://p.tv/b/m3u8"),
        ])
        let item = try #require(library.channels.first)
        #expect(library.channelGroup(containing: item)?.variants.count == 2)
    }
}

@Suite("What to try, and in what order")
struct PlaybackPlanTests {

    static func channel(_ title: String, url: String) -> MediaItem {
        MediaItem(
            id: url, kind: .liveTV, title: title, rawTitle: title,
            streamURL: URL(string: url)!
        )
    }

    let group = ChannelGroup(
        id: "v sport 1",
        name: "V sport 1",
        variants: [
            Self.channel("V sport 1 HD", url: "http://p.tv/hd/m3u8"),
            Self.channel("V sport 1", url: "http://p.tv/plain/m3u8"),
            Self.channel("V sport 1 raw", url: "http://p.tv/raw/m3u8"),
        ],
        categories: ["Norway"]
    )

    @Test("Every variant is reachable")
    func coversEveryVariant() {
        let plan = PlaybackPlan(group: group)
        #expect(Set(plan.owners).count == 3)
        #expect(plan.candidates.count >= 3)
    }

    @Test("The variant that last worked is tried first")
    func remembersWhatWorked() throws {
        let plan = PlaybackPlan(group: group, remembered: "http://p.tv/raw/m3u8")
        #expect(plan.owner(at: 0) == "http://p.tv/raw/m3u8")
        // And nothing is lost by reordering.
        #expect(Set(plan.owners).count == 3)
    }

    /// Someone opening the alternatives is doing so because the remembered
    /// stream let them down, so their pick has to win.
    @Test("An explicit choice beats the remembered one")
    func explicitChoiceWins() {
        let chosen = group.variants[1]
        let plan = PlaybackPlan(group: group, explicitlyChosen: chosen)
        #expect(plan.owner(at: 0) == chosen.id)
        #expect(plan.item.id == chosen.id)
        // The others remain available behind it.
        #expect(Set(plan.owners).count == 3)
    }

    @Test("A film has no variants, only formats")
    func filmPlan() {
        let film = MediaItem(
            id: "m", kind: .movie, title: "Film", rawTitle: "Film",
            streamURL: URL(string: "http://p.tv/movie/u/p/1.mkv")!
        )
        let plan = PlaybackPlan(item: film)
        #expect(plan.owners.allSatisfy { $0 == "m" })
        #expect(plan.candidates.last?.pathExtension == "mkv")
    }

    @Test("Knows when there is nothing left to try")
    func knowsTheEnd() {
        let plan = PlaybackPlan(group: group)
        #expect(plan.isLast(plan.candidates.count - 1))
        #expect(!plan.isLast(0))
    }
}

@Suite("Remembering what worked")
struct WorkingVariantTests {

    @Test("An older saved state still decodes")
    func decodesOlderState() throws {
        // Written before workingVariants existed.
        let json = Data("""
        {"favoriteIDs":["a"],"hiddenCategoryNames":[],"progress":{},"recentIDs":["a"]}
        """.utf8)
        let state = try JSONDecoder().decode(WatchState.self, from: json)
        #expect(state.favoriteIDs == ["a"])
        #expect(state.workingVariants.isEmpty)
    }

    @Test("The working variant survives a round trip")
    func roundTrip() throws {
        var state = WatchState()
        state.rememberWorkingVariant("stream-2", forGroup: "v sport 1")
        let decoded = try JSONDecoder().decode(
            WatchState.self, from: JSONEncoder().encode(state)
        )
        #expect(decoded.workingVariants["v sport 1"] == "stream-2")
    }
}
