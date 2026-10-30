import Foundation
import Testing
@testable import KanalCore

@Suite("Joining a household without a second owner")
struct DuplicateOwnerTests {

    private static let ownerName = String(localized: CoreStrings.profileDefaultOwnerName)

    private static func snapshot(_ profiles: [Profile], states: [String: WatchState] = [:]) -> HouseholdSnapshot {
        HouseholdSnapshot(sources: [], profiles: profiles, watchStates: states)
    }

    /// Seen on Apple TV: two profiles both called "Me" after setup.
    @Test("An untouched default owner steps aside for the household's")
    func untouchedOwnerStepsAside() {
        let local = Self.snapshot([Profile.makeOwner(named: Self.ownerName)])
        let remote = Self.snapshot([Profile.makeOwner(named: Self.ownerName)])
        let result = AppModel.withoutUnusedOwner(local, joining: remote)
        #expect(result.profiles.isEmpty)
    }

    @Test("A default owner someone has used is kept")
    func usedOwnerIsKept() {
        let owner = Profile.makeOwner(named: Self.ownerName)
        var state = WatchState()
        state.favoriteIDs = ["channel-1"]
        let local = Self.snapshot([owner], states: [owner.id.uuidString: state])
        let remote = Self.snapshot([Profile.makeOwner(named: Self.ownerName)])
        #expect(AppModel.withoutUnusedOwner(local, joining: remote).profiles == [owner])
    }

    @Test("Nothing changes without a household to join")
    func noRemote() {
        let local = Self.snapshot([Profile.makeOwner(named: Self.ownerName)])
        #expect(AppModel.withoutUnusedOwner(local, joining: nil) == local)
        #expect(AppModel.withoutUnusedOwner(local, joining: Self.snapshot([])) == local)
    }
}
