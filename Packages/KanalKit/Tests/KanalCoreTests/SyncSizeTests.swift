import Foundation
import Testing
@testable import KanalCore

/// A household that watches television must keep fitting in iCloud's megabyte.
@Suite("Sync payload size")
struct SyncSizeTests {
    private func film(_ index: Int) -> MediaItem {
        MediaItem(
            id: "movie-\(index)", kind: .movie, title: "Film number \(index)", rawTitle: "Film number \(index) (2020)",
            streamURL: URL(string: "http://example.com/movie/u/p/\(index).mkv")!, year: 2020
        )
    }

    private func watched(_ range: Range<Int>) -> WatchState {
        var state = WatchState()
        for index in range {
            state.record(
                WatchProgress(itemID: "movie-\(index)", position: 600, duration: 6000,
                              updatedAt: Date(timeIntervalSince1970: Double(1_000_000 + index))),
                item: film(index)
            )
        }
        return state
    }

    @Test("A long viewing history stays far below the iCloud limit")
    func fullHistoryFits() throws {
        let profiles = (0..<4).map { Profile(id: UUID(), name: "Profile \($0)") }
        var states: [String: WatchState] = [:]
        var replica = HouseholdReplica(deviceID: "a")
        // Two hundred and sixty titles each, watched over many sessions, so
        // the oldest sixty age out and leave their tombstones behind.
        for batch in stride(from: 0, to: 260, by: 20) {
            for profile in profiles { states[profile.id.uuidString] = watched(0..<(batch + 20)) }
            replica.observe(local: HouseholdSnapshot(
                modifiedAt: .now, sources: [], profiles: profiles, watchStates: states
            ))
        }
        let snapshot = replica.snapshot()
        let state = try #require(snapshot.watchStates[profiles[0].id.uuidString])
        #expect(state.recentIDs.count == 200)
        #expect(state.progress.count == 200, "positions age out with the history they belong to")

        // One version record per entry, not one per field of it.
        let records = snapshot.syncRecords ?? [:]
        #expect(records.count < 4 * 200 * 4 + 600)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let packed = ICloudHouseholdSync.packed(try encoder.encode(snapshot.sanitizedForSync()))
        #expect(packed.count < 450_000, "was \(packed.count) bytes against a 900 kB limit")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(HouseholdSnapshot.self, from: ICloudHouseholdSync.unpacked(packed))
        #expect(restored.watchStates[profiles[0].id.uuidString]?.recentIDs.count == 200)
    }

    @Test("A payload written before compression is still read")
    func uncompressedPayload() throws {
        let json = Data(#"{"modifiedAt":"2026-01-01T00:00:00Z","sources":[],"profiles":[],"watchStates":{}}"#.utf8)
        #expect(try ICloudHouseholdSync.unpacked(json) == json)
    }

    @Test("One unreadable history entry does not empty the profile")
    func halfWrittenEntry() throws {
        let json = """
        {"favoriteIDs":["nrk1"],
         "progress":{"good":{"itemID":"good","position":10,"duration":100,"updatedAt":0},
                     "broken":{"position":10,"updatedAt":0}},
         "recentIDs":["good","broken"]}
        """
        let state = try JSONDecoder().decode(WatchState.self, from: Data(json.utf8))
        #expect(state.favoriteIDs == ["nrk1"])
        #expect(state.progress.keys.sorted() == ["good"])
    }

    @Test("Forgetting a title on one device while it plays on another leaves both readable")
    func forgetWhilePlaying() throws {
        let id = UUID()
        let profile = Profile(id: id, name: "Family")
        var start = watched(0..<3)
        start.favoriteIDs = ["nrk1"]
        let base = HouseholdReplica(
            local: HouseholdSnapshot(modifiedAt: .now, sources: [], profiles: [profile], watchStates: [id.uuidString: start]),
            deviceID: "base"
        )
        var phone = try JSONDecoder().decode(HouseholdReplica.self, from: JSONEncoder().encode(base))
        var television = try JSONDecoder().decode(HouseholdReplica.self, from: JSONEncoder().encode(base))

        var forgotten = start
        forgotten.forget("movie-1")
        phone.observe(local: HouseholdSnapshot(modifiedAt: .now, sources: [], profiles: [profile], watchStates: [id.uuidString: forgotten]))

        var playing = start
        playing.record(WatchProgress(itemID: "movie-1", position: 900, duration: 6000), item: film(1))
        television.observe(local: HouseholdSnapshot(modifiedAt: .now, sources: [], profiles: [profile], watchStates: [id.uuidString: playing]))

        for merged in [phone.merge(remote: television.snapshot()), television.merge(remote: phone.snapshot())] {
            let state = try #require(merged.watchStates[id.uuidString], "the profile's state must survive the merge")
            #expect(state.favoriteIDs == ["nrk1"])
            // Whichever side won, the entry is whole or absent — never half.
            if let progress = state.progress["movie-1"] { #expect(progress.duration == 6000) }
        }
    }
}

/// A provider's stream address is routinely its login. It must not ride along
/// inside the ids that favourites and history are keyed by.
@Suite("Ids carry no address")
struct IdentityWithoutAddressTests {
    private let secret = "http://panel.example:8080/movie/kari/hemmelig123/42.mkv"

    @Test("A playlist entry's id identifies the stream without containing it")
    func parserIDs() {
        let text = "#EXTM3U\n#EXTINF:-1,Film A\n\(secret)\n#EXTINF:-1,Film A\n\(secret)\n#EXTINF:-1,Film B\nhttp://panel.example:8080/movie/kari/hemmelig123/43.mkv\n"
        let items = M3UParser().parse(text).items
        #expect(items.count == 3)
        #expect(Set(items.map(\.id)).count == 3)
        #expect(items.allSatisfy { !$0.id.contains("hemmelig123") && !$0.id.contains("://") })
        // Stable: the same playlist gives the same ids on the next refresh.
        #expect(M3UParser().parse(text).items.map(\.id) == items.map(\.id))
    }

    @Test("An id from an earlier build becomes today's id for the same entry")
    func scrubbing() {
        let today = MediaItem.derivedID(rawTitle: "Film A", stream: secret)
        #expect(MediaItem.scrubbedID("Film A|\(secret)") == today)
        #expect(MediaItem.scrubbedID("Film A|\(secret)#2") == today + "#2")
        #expect(MediaItem.scrubbedID("3F2504E0-4F89-11D3-9A0C-0305E82C3301|Film A|\(secret)")
                == "3F2504E0-4F89-11D3-9A0C-0305E82C3301|" + today)
        #expect(MediaItem.scrubbedID(today) == today)
        #expect(MediaItem.scrubbedID("movie-204927") == "movie-204927")
        #expect(MediaItem.scrubbedID("nrk1.no") == "nrk1.no")
    }

    @Test("Saved favourites and history are rewritten on reading, and nothing synced names the login")
    func savedState() throws {
        let old = "Film A|\(secret)"
        let json = """
        {"favoriteIDs":["\(old)"],"recentIDs":["src|\(old)"],
         "progress":{"src|\(old)":{"itemID":"src|\(old)","position":10,"duration":100,"updatedAt":0}},
         "workingVariants":{"film a":"\(old)"}}
        """
        let state = try JSONDecoder().decode(WatchState.self, from: Data(json.utf8))
        let today = MediaItem.derivedID(rawTitle: "Film A", stream: secret)
        #expect(state.favoriteIDs == [today])
        #expect(state.recentIDs == ["src|" + today])
        #expect(state.progress["src|" + today]?.itemID == "src|" + today)
        #expect(state.workingVariants["film a"] == today)

        let id = UUID()
        var replica = HouseholdReplica(deviceID: "a")
        replica.observe(local: HouseholdSnapshot(
            modifiedAt: .now, sources: [], profiles: [Profile(id: id, name: "Family")],
            watchStates: [id.uuidString: state]
        ))
        let wire = String(decoding: try JSONEncoder().encode(replica.snapshot().sanitizedForSync()), as: UTF8.self)
        #expect(!wire.contains("hemmelig123"))
    }
}
