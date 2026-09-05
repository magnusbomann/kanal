import Foundation
import Testing
@testable import KanalCore

@Suite("Household replica merge")
struct HouseholdReplicaTests {
    private func snapshot(sources: [PlaylistSource] = [], profiles: [Profile] = [], states: [String: WatchState] = [:]) -> HouseholdSnapshot {
        HouseholdSnapshot(modifiedAt: Date(timeIntervalSince1970: 100), sources: sources, profiles: profiles, watchStates: states)
    }

    @Test("Concurrent favourite additions survive a merge")
    func concurrentFavouriteAdds() {
        let id = UUID()
        let profile = Profile(id: id, name: "Family")
        var leftState = WatchState(); leftState.favoriteIDs = ["left"]
        var rightState = WatchState(); rightState.favoriteIDs = ["right"]
        var left = HouseholdReplica(local: snapshot(profiles: [profile], states: [id.uuidString: leftState]), deviceID: "a")
        let right = HouseholdReplica(local: snapshot(profiles: [profile], states: [id.uuidString: rightState]), deviceID: "b")
        let merged = left.merge(remote: right.snapshot())
        #expect(merged.watchStates[id.uuidString]?.favoriteIDs == ["left", "right"])
    }

    @Test("A removal and an unrelated addition converge in either order")
    func concurrentRemovalAndAddition() throws {
        let id = UUID()
        let profile = Profile(id: id, name: "Family")
        var baseState = WatchState(); baseState.favoriteIDs = ["old"]
        let base = HouseholdReplica(local: snapshot(profiles: [profile], states: [id.uuidString: baseState]), deviceID: "base")
        var left = try JSONDecoder().decode(HouseholdReplica.self, from: JSONEncoder().encode(base))
        var right = try JSONDecoder().decode(HouseholdReplica.self, from: JSONEncoder().encode(base))
        var removed = WatchState(); removed.favoriteIDs = []
        var added = WatchState(); added.favoriteIDs = ["old", "new"]
        left.observe(local: snapshot(profiles: [profile], states: [id.uuidString: removed]))
        right.observe(local: snapshot(profiles: [profile], states: [id.uuidString: added]))
        var forward = left
        var backward = right
        let first = forward.merge(remote: right.snapshot())
        let second = backward.merge(remote: left.snapshot())
        #expect(first.watchStates[id.uuidString]?.favoriteIDs == ["new"])
        #expect(second.watchStates[id.uuidString]?.favoriteIDs == ["new"])
    }

    @Test("Independent profile edits are retained")
    func independentProfileEdits() {
        let id = UUID()
        let base = Profile(id: id, name: "Family")
        var left = HouseholdReplica(local: snapshot(profiles: [base]), deviceID: "a")
        var right = HouseholdReplica(local: snapshot(profiles: [base]), deviceID: "b")
        var lp = base; lp.name = "Home"
        var rp = base; rp.symbolName = "star.fill"
        left.observe(local: snapshot(profiles: [lp])); right.observe(local: snapshot(profiles: [rp]))
        let merged = left.merge(remote: right.snapshot())
        #expect(merged.profiles.first?.name == "Home")
        #expect(merged.profiles.first?.symbolName == "star.fill")
    }

    @Test("Merging the same snapshot is idempotent")
    func idempotentMerge() {
        var replica = HouseholdReplica(local: snapshot(), deviceID: "a")
        var state = WatchState(); state.favoriteIDs = ["film"]
        let profile = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Family")
        replica.observe(local: snapshot(profiles: [profile], states: [profile.id.uuidString: state]))
        let once = replica.merge(remote: replica.snapshot())
        let twice = replica.merge(remote: once)
        #expect(once == twice)
    }

    @Test("Deleted entries remain tombstoned after encoding and decoding")
    func tombstoneSurvivesRestart() throws {
        let source = PlaylistSource(kind: .m3u, name: "TV", playlistURL: URL(string: "https://example.test/list.m3u"))
        var replica = HouseholdReplica(local: snapshot(sources: [source]), deviceID: "a")
        replica.observe(local: snapshot())
        let data = try JSONEncoder().encode(replica)
        var restarted = try JSONDecoder().decode(HouseholdReplica.self, from: data)
        restarted.merge(remote: HouseholdReplica(local: snapshot(sources: [source]), deviceID: "z").snapshot())
        #expect(restarted.snapshot().sources.isEmpty)
    }

    @Test("History sanitization removes provider credentials")
    func historyIsSanitized() {
        let item = MediaItem(id: "movie", kind: .movie, title: "Movie", rawTitle: "Movie", streamURL: URL(string: "https://u:password@example.test/movie")!)
        var state = WatchState(); state.recentItems[item.id] = item; state.recentIDs = [item.id]
        let sanitized = snapshot(states: ["p": state]).sanitizedForSync()
        #expect(sanitized.watchStates["p"]?.recentItems[item.id]?.streamURL.scheme == "kanal-history")
        #expect(!String(describing: sanitized).contains("password"))
    }
}
