import KanalCore
import SwiftUI

/// Everything the app can push. One enum so every screen navigates the same way.
public enum Route: Hashable {
    case category(kind: MediaKind, name: String)
    case series(id: String)
    case allChannels
    case allMovies
    case allSeries
}

/// What is currently playing full screen, if anything.
public struct PlaybackRequest: Identifiable {
    public let plan: PlaybackPlan
    public var item: MediaItem { plan.item }
    public var id: String { plan.item.id }

    public init(plan: PlaybackPlan) {
        self.plan = plan
    }
}

/// Shared navigation state, so a card in any tab can open the player.
@MainActor
@Observable
public final class Navigator {
    public var path = NavigationPath()
    public var playing: PlaybackRequest?

    public init() {}

    /// Plays a single entry — a film, an episode, a one-off stream.
    public func play(_ item: MediaItem) {
        playing = PlaybackRequest(plan: PlaybackPlan(item: item))
    }

    /// Plays a channel, with every stream that carries it behind the first.
    public func play(_ group: ChannelGroup, remembered: String? = nil) {
        playing = PlaybackRequest(plan: PlaybackPlan(group: group, remembered: remembered))
    }

    /// Plays a specific stream the viewer chose from the alternatives.
    public func play(_ variant: MediaItem, from group: ChannelGroup) {
        playing = PlaybackRequest(plan: PlaybackPlan(group: group, explicitlyChosen: variant))
    }

    public func push(_ route: Route) {
        path.append(route)
    }
}
