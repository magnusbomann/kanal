import Foundation
import Testing
@testable import KanalCore

@Suite("Bounded live stream recovery")
struct LiveStreamRecoveryTests {
    @Test func stopsAfterThreeDistinctSources() {
        var recovery = LiveStreamRecovery(order: ["a", "b", "c", "d"], selected: "a", locked: false, now: 0)
        #expect(recovery.failed(at: 1) == "b")
        #expect(recovery.failed(at: 2) == "c")
        #expect(recovery.failed(at: 3) == nil)
    }

    @Test func decoderChangesCannotExtendDeadline() {
        var recovery = LiveStreamRecovery(order: ["a", "b"], selected: "a", locked: false, now: 10)
        #expect(!recovery.expired(at: 29.9))
        #expect(recovery.expired(at: 30))
        #expect(recovery.failed(at: 30) == nil)
    }

    @Test func retriesWorkingSourceBeforeSwitching() {
        var recovery = LiveStreamRecovery(order: ["a", "b"], selected: "a", locked: false, now: 0)
        recovery.played()
        #expect(recovery.failed(at: 100) == "a")
        #expect(recovery.failed(at: 102) == "b")
        #expect(recovery.failed(at: 103) == nil)
    }

    @Test func lockedSourceNeverFallsThrough() {
        var recovery = LiveStreamRecovery(order: ["a", "b"], selected: "b", locked: true, now: 0)
        recovery.played()
        #expect(recovery.failed(at: 100) == "b")
        #expect(recovery.failed(at: 101) == nil)
        recovery.retry(at: 200)
        #expect(recovery.current == "b")
        #expect(recovery.locked)
    }

    @Test func manualChoiceOutsideTopThreeIsTriedFirst() {
        var recovery = LiveStreamRecovery(order: ["a", "b", "c", "d"], selected: "d", locked: false, now: 0)
        #expect(recovery.current == "d")
        #expect(recovery.failed(at: 1) == "a")
        #expect(recovery.failed(at: 2) == "b")
        #expect(recovery.failed(at: 3) == nil)
    }

    @Test func networkReturnKeepsSourceAndResetsBudget() {
        var recovery = LiveStreamRecovery(order: ["a", "b"], selected: "b", locked: false, now: 0)
        recovery.retry(at: 1000)
        #expect(recovery.current == "b")
        #expect(!recovery.expired(at: 1001))
        #expect(recovery.attempted == ["b"])
    }

    @Test func aSecondOutageGetsOneSameSourceRetryAfterRecovery() {
        var recovery = LiveStreamRecovery(order: ["a", "b"], selected: "a", locked: false, now: 0)
        recovery.played()
        #expect(recovery.failed(at: 100) == "a")
        recovery.played()
        #expect(recovery.failed(at: 200) == "a")
        #expect(recovery.failed(at: 201) == "b")
    }

    @Test func anUnplayableLockedSourceStopsImmediately() {
        var recovery = LiveStreamRecovery(order: ["a", "b"], selected: "a", locked: true, now: 0)
        #expect(recovery.failed(at: 1) == nil)
        recovery.locked = false
        #expect(recovery.failed(at: 2) == "b")
    }

    @Test func lockPersistsSeparatelyFromSuccessfulSource() throws {
        var watch = WatchState()
        watch.lockedVariants["channel"] = "a"
        watch.rememberWorkingVariant("b", forGroup: "channel")
        let restored = try JSONDecoder().decode(WatchState.self, from: JSONEncoder().encode(watch))
        #expect(restored.lockedVariants["channel"] == "a")
        #expect(restored.workingVariants["channel"] == "b")
        let legacy = try JSONDecoder().decode(WatchState.self, from: Data("{}".utf8))
        #expect(legacy.lockedVariants.isEmpty)
    }
}
