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
public struct PlaybackRequest: Identifiable, Hashable {
    public let item: MediaItem
    public var id: String { item.id }

    public init(item: MediaItem) {
        self.item = item
    }
}

/// Shared navigation state, so a card in any tab can open the player.
@MainActor
@Observable
public final class Navigator {
    public var path = NavigationPath()
    public var playing: PlaybackRequest?

    public init() {}

    public func play(_ item: MediaItem) {
        playing = PlaybackRequest(item: item)
    }

    public func push(_ route: Route) {
        path.append(route)
    }
}
