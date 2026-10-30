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

    /// Measured on a real panel: Norway's and Denmark's "TV 2" share the
    /// name exactly. Folded together, the guide mixed both schedules.
    @Test("The same name in two countries stays two channels")
    func sameNameTwoCountries() {
        let library = Library(items: [
            Self.channel("TV 2", url: "http://p.tv/no/m3u8", category: "Norway"),
            Self.channel("TV 2", url: "http://p.tv/dk/m3u8", category: "Denmark"),
        ])
        #expect(library.channelGroups.count == 2)
        #expect(library.channelGroups.allSatisfy { $0.variants.count == 1 })
    }

    /// Measured on a real panel, beside a plain "NRK1".
    @Test("A low-bandwidth feed is a fallback, not a second channel")
    func lowBandwidthFoldsIn() throws {
        let library = Library(items: [
            Self.channel("NRK1 Lav Internett hastighet", url: "http://p.tv/low/m3u8", category: "Norway"),
            Self.channel("NRK1", url: "http://p.tv/hd/m3u8", category: "Norway"),
        ])
        let group = try #require(library.channelGroups.first)
        #expect(library.channelGroups.count == 1)
        #expect(group.name == "NRK1")
        #expect(group.primary.streamURL.absoluteString == "http://p.tv/hd/m3u8")
    }

    /// Splitting by country must not cost sport its feeds: a listing under
    /// no country joins the country most listings came from.
    @Test("Countryless listings stay with the dominant country")
    func countrylessJoinsDominant() throws {
        let library = Library(items: [
            Self.channel("V sport 1", url: "http://p.tv/a/m3u8", category: "Norway"),
            Self.channel("V sport 1", url: "http://p.tv/b/m3u8", category: "Norway Sport"),
            Self.channel("V sport 1", url: "http://p.tv/c/m3u8", category: "Premier League"),
            Self.channel("V sport 1", url: "http://p.tv/d/m3u8", category: "Sweden"),
        ])
        #expect(library.channelGroups.count == 2)
        let norway = try #require(library.channelGroups.first { $0.categories.contains("Norway") })
        #expect(norway.variants.count == 3)
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

/// Frame rate describes delivery, not identity.
///
/// Names taken verbatim from the measured provider, where six channels were
/// split this way — every one of them sport, which is exactly where a viewer
/// most needs a second feed to fall back on.
@Suite("Frame-rate feeds belong to their channel")
struct FrameRateFoldingTests {

    @Test("A 50FPS feed joins its channel rather than starting a new one")
    func fiftyFramesFolds() throws {
        let library = Library(items: [
            ChannelGroupTests.channel("V sport Premier League", url: "http://p.tv/1/m3u8"),
            ChannelGroupTests.channel("V sport Premier League HD", url: "http://p.tv/2/m3u8"),
            ChannelGroupTests.channel("V sport Premier League HD | 50FPS", url: "http://p.tv/3/m3u8"),
        ])
        #expect(library.channelGroups.count == 1, "one channel, not two cards")
        let group = try #require(library.channelGroups.first)
        #expect(group.variants.count == 3)
    }

    /// The smoothest feed of a football match is the one worth opening on,
    /// but never at the cost of dropping to standard definition for it.
    @Test("A high frame rate leads, resolution first")
    func frameRateOrdering() throws {
        let library = Library(items: [
            ChannelGroupTests.channel("V sport Premier League", url: "http://p.tv/1/m3u8"),
            ChannelGroupTests.channel("V sport Premier League HD", url: "http://p.tv/2/m3u8"),
            ChannelGroupTests.channel("V sport Premier League HD | 50FPS", url: "http://p.tv/3/m3u8"),
        ])
        let group = try #require(library.channelGroups.first)
        #expect(group.primary.rawTitle == "V sport Premier League HD | 50FPS")
    }

    @Test("A numbered channel is still its own channel")
    func numbersAreNotQuality() {
        let library = Library(items: [
            ChannelGroupTests.channel("V sport Premier League HD | 50FPS", url: "http://p.tv/1/m3u8"),
            ChannelGroupTests.channel("V sport Premier League 1 HD | 50FPS", url: "http://p.tv/2/m3u8"),
            ChannelGroupTests.channel("V sport Premier League 2 HD | 50FPS", url: "http://p.tv/3/m3u8"),
        ])
        #expect(library.channelGroups.count == 3)
    }
}

/// A plan mixes two kinds of step, and only one of them costs a connection.
@Suite("Where one feed ends and the next begins")
struct PlanVariantBoundaryTests {

    static func group() -> ChannelGroup {
        let library = Library(items: [
            ChannelGroupTests.channel("V sport Premier League HD | 50FPS", url: "http://p.tv/1/m3u8"),
            ChannelGroupTests.channel("V sport Premier League HD", url: "http://p.tv/2/m3u8"),
            ChannelGroupTests.channel("V sport Premier League", url: "http://p.tv/3/m3u8"),
        ])
        return library.channelGroups[0]
    }

    /// Live streams are asked for exactly as published, so each candidate is a
    /// feed of its own and every step between them opens a new connection.
    @Test("Every channel candidate is a fresh connection")
    func liveCandidatesAreAllFeeds() {
        let plan = PlaybackPlan(group: Self.group())
        #expect(plan.variantCount == 3)
        #expect(plan.variantStarts == [0, 1, 2])
        #expect((0..<3).allSatisfy(plan.isVariantStart))
        #expect(plan.crossesVariant(advancingFrom: 0))
        #expect(!plan.crossesVariant(advancingFrom: 2), "nothing follows the last")
    }

    @Test("Sources are counted the way a viewer would count them")
    func numbering() {
        let plan = PlaybackPlan(group: Self.group())
        #expect((0..<3).map(plan.variantNumber) == [1, 2, 3])
    }

    @Test("The next feed is found by owner, not by candidate")
    func nextFeed() {
        let plan = PlaybackPlan(group: Self.group())
        #expect(plan.nextVariantStart(after: 0) == 1)
        #expect(plan.nextVariantStart(after: 2) == nil, "the last feed has no successor")
    }

    /// A film asking the same panel for another container is not a second
    /// feed, and must not be counted or waited for as though it were.
    @Test("Format guesses on one stream are a single source")
    func formatGuessesAreOneSource() {
        let item = MediaItem(
            id: "1", kind: .movie, title: "T", rawTitle: "T",
            streamURL: URL(string: "http://p.tv/movie/u/p/1.mkv")!
        )
        let plan = PlaybackPlan(item: item)
        #expect(plan.candidates.count == 4)
        #expect(plan.variantCount == 1)
        #expect(!plan.crossesVariant(advancingFrom: 0))
        #expect(!plan.isVariantStart(1))
    }
}

/// A refusal arriving moments after another stream was released is most often
/// the provider still counting it, not a broken feed.
@Suite("A refusal that may just be the connection limit")
struct ConnectionLimitTests {

    @Test("Refusals and unreadable servers are worth one patient retry")
    func retriable() {
        #expect(PlaybackFailure.rejected.mayBeConnectionLimit)
        #expect(PlaybackFailure.serverNotStreamable.mayBeConnectionLimit)
        #expect(PlaybackFailure.other("Cannot Open").mayBeConnectionLimit)
    }

    /// No amount of waiting turns Matroska into something AVFoundation opens,
    /// and a device with no network will not find one by asking twice.
    @Test("Waiting cannot fix a container or a missing network")
    func notRetriable() {
        #expect(!PlaybackFailure.unsupportedContainer("mkv").mayBeConnectionLimit)
        #expect(!PlaybackFailure.offline.mayBeConnectionLimit)
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
