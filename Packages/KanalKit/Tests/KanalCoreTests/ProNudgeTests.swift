import Foundation
import Testing
@testable import KanalCore

/// When the free tier is allowed to ask for money.
///
/// Every test here is written from the review it prevents. The failure mode of
/// this feature is not a crash — it is someone deciding the app is greedy, and
/// that decision is made in the first ten minutes and never revisited.
@Suite("Asking for money")
struct ProNudgeTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plays and closes `count` streams, returning how many times the offer
    /// came up.
    private func watch(
        _ count: Int,
        nudge: inout ProNudge,
        from: Date,
        spacing: TimeInterval = 60,
        isPro: Bool = false,
        isRestricted: Bool = false
    ) -> Int {
        var shown = 0
        for index in 0..<count {
            if nudge.playbackClosed(
                didPlay: true,
                isPro: isPro,
                isRestricted: isRestricted,
                now: from.addingTimeInterval(Double(index) * spacing)
            ) {
                shown += 1
            }
        }
        return shown
    }

    @Test("The first streams someone watches are never interrupted")
    func staysQuietWhileTheAppIsStillProvingItself() {
        // The point of those first streams is finding out whether this
        // provider works at all. An offer on top of that asks someone to buy
        // something they have not yet seen do anything.
        var nudge = ProNudge()
        #expect(watch(3, nudge: &nudge, from: start) == 0)
    }

    @Test("It asks once the app has shown it works")
    func asksAfterThat() {
        var nudge = ProNudge()
        _ = watch(3, nudge: &nudge, from: start)
        #expect(nudge.playbackClosed(didPlay: true, isPro: false, isRestricted: false, now: start) == true)
    }

    @Test("A stream that never played is not an occasion to sell anything")
    func silentAfterFailure() {
        // The whole catalogue can fail on a provider that only serves Matroska
        // to an engine that cannot read it. Charging admission at that moment
        // is the single most expensive thing this screen could do.
        var nudge = ProNudge()
        _ = watch(10, nudge: &nudge, from: start)
        let later = start.addingTimeInterval(86_400)
        #expect(nudge.playbackClosed(didPlay: false, isPro: false, isRestricted: false, now: later) == false)
    }

    @Test("A child is never asked to buy anything")
    func silentInAChildProfile() {
        var nudge = ProNudge()
        #expect(watch(20, nudge: &nudge, from: start, isRestricted: true) == 0)
    }

    @Test("Someone who has paid is never asked again")
    func silentForSubscribers() {
        var nudge = ProNudge()
        #expect(watch(20, nudge: &nudge, from: start, isPro: true) == 0)
    }

    @Test("Channel surfing does not produce an offer per channel")
    func onlyOncePerCooldown() {
        // Ten channels in ten minutes is one ordinary evening, not ten
        // opportunities.
        var nudge = ProNudge()
        _ = watch(4, nudge: &nudge, from: start)
        let surfing = watch(10, nudge: &nudge, from: start.addingTimeInterval(1), spacing: 60)
        #expect(surfing == 0)
    }

    @Test("Being refused repeatedly makes it ask less often")
    func backsOff() {
        var nudge = ProNudge()
        let quarterHour = ProNudge().cooldown
        var clock = start
        // Five refusals at the shortest cooldown.
        for _ in 0..<20 {
            if nudge.playbackClosed(didPlay: true, isPro: false, isRestricted: false, now: clock) {
                nudge.recordDismissal()
            }
            clock = clock.addingTimeInterval(quarterHour + 1)
        }
        #expect(nudge.dismissals >= 5)
        #expect(nudge.cooldown > quarterHour)
    }

    @Test("Buying starts the counters over")
    func purchaseResets() {
        // A subscription that lapses a year later should meet the same patient
        // app a new install does, not a six-hour cooldown left over from before.
        var nudge = ProNudge()
        _ = watch(10, nudge: &nudge, from: start)
        nudge.recordDismissal()
        nudge.reset()
        #expect(nudge == ProNudge())
        #expect(watch(3, nudge: &nudge, from: start) == 0)
    }

    @Test("It survives a relaunch")
    func roundTrips() throws {
        var nudge = ProNudge()
        _ = watch(5, nudge: &nudge, from: start)
        nudge.recordDismissal()
        let data = try JSONEncoder().encode(nudge)
        #expect(try JSONDecoder().decode(ProNudge.self, from: data) == nudge)
    }
    @Test("TV offers stay quiet through channel changes and relaunches within a day")
    func televisionPacing() throws {
        var nudge = ProNudge()
        _ = watch(4, nudge: &nudge, from: start)
        let data = try JSONEncoder().encode(nudge)
        nudge = try JSONDecoder().decode(ProNudge.self, from: data)
        let duringDay = nudge.playbackClosed(didPlay: true, isPro: false, isRestricted: false,
                                    now: start.addingTimeInterval(3600), minimumInterval: 86400)
        #expect(!duringDay)
        let sameSession = nudge.playbackClosed(didPlay: true, isPro: false, isRestricted: false,
                                    now: start.addingTimeInterval(172800), allowsPrompt: false,
                                    minimumInterval: 86400)
        #expect(!sameSession)
        let nextSession = nudge.playbackClosed(didPlay: true, isPro: false, isRestricted: false,
                                   now: start.addingTimeInterval(172800), minimumInterval: 86400)
        #expect(nextSession)
        // Suppression still counts successful playback, without claiming an offer was shown.
        #expect(nudge.successfulPlaybacks == 7)
    }

}
