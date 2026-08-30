import KanalCore
import SwiftUI

public enum AppTab: Hashable {
    case home, live, movies, series, search

    init?(argument: String) {
        switch argument {
        case "home": self = .home
        case "live": self = .live
        case "movies", "films": self = .movies
        case "series": self = .series
        case "search": self = .search
        default: return nil
        }
    }
}

/// Everything the app can push. One enum so every screen navigates the same way.
public enum Route: Hashable {
    case category(kind: MediaKind, name: String)
    case series(id: String)
    case allChannels
    case favoriteChannels
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
/// A title someone wants to know about before committing to it.
public struct DetailRequest: Identifiable {
    public let item: MediaItem
    public let seriesGroup: SeriesGroup?
    public var id: String { seriesGroup?.id ?? item.id }

    public init(item: MediaItem, seriesGroup: SeriesGroup? = nil) {
        self.item = item
        self.seriesGroup = seriesGroup
    }
}

@MainActor
@Observable
public final class Navigator {
    // Each tab owns its own back stack. Sharing one NavigationPath made a
    // movie route pushed from Home appear on the Series tab after switching.
    public var homePath = NavigationPath()
    public var livePath = NavigationPath()
    public var moviesPath = NavigationPath()
    public var seriesPath = NavigationPath()
    public var searchPath = NavigationPath()
    public var playing: PlaybackRequest?
    public var showingDetails: DetailRequest?
    public var selectedTab: AppTab
    /// Incrementing lets an already-mounted Search tab focus again.
    public var searchFocusRequest: UInt64 = 0
    /// Whether the stream that just closed had actually reached the screen.
    /// Read by the shell when it decides whether to offer Pluss.
    public var lastPlaybackPlayed = false
    /// Set by anything that wants the offer shown — the watermark, a settings
    /// row, the interstitial's own pacing. The shell owns the presentation,
    /// because a view that is dismissing itself cannot present anything.
    public var wantsPro = false

    public init() {
        selectedTab = LaunchOptions.startTab.flatMap(AppTab.init(argument:)) ?? .home
    }

    /// Builds the fallbacks for a single entry, when the library knows of any.
    ///
    /// Set once by the shell. Films arrive at `play` from a dozen places — a
    /// shelf, a search result, a detail screen, an actor's other work — and
    /// none of them should have to remember that the provider listed the same
    /// film four times. Without it playback still works, with the one stream
    /// the caller had.
    public var alternatives: (@MainActor (MediaItem) -> PlaybackPlan?)?

    /// Plays a single entry — a film, an episode, a one-off stream.
    public func play(_ item: MediaItem) {
        playing = PlaybackRequest(plan: alternatives?(item) ?? PlaybackPlan(item: item))
    }

    /// Plays a channel, with every stream that carries it behind the first.
    public func play(_ group: ChannelGroup, remembered: String? = nil) {
        playing = PlaybackRequest(plan: PlaybackPlan(group: group, remembered: remembered))
    }

    /// Plays a specific stream the viewer chose from the alternatives.
    public func play(_ variant: MediaItem, from group: ChannelGroup) {
        playing = PlaybackRequest(plan: PlaybackPlan(group: group, explicitlyChosen: variant))
    }

    /// Opens the screen that says what something is before playing it.
    ///
    /// Only for films and shows. A channel is a thing you put on, not a thing
    /// you read about, so tapping one plays it.
    public func showDetails(for item: MediaItem, seriesGroup: SeriesGroup? = nil) {
        showingDetails = DetailRequest(item: item, seriesGroup: seriesGroup)
    }

    public func push(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .live: livePath.append(route)
        case .movies: moviesPath.append(route)
        case .series: seriesPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    public func openSearch() {
        searchPath = NavigationPath()
        selectedTab = .search
        searchFocusRequest &+= 1
    }

    /// A profile or TV-service switch invalidates every title-bearing route.
    /// Clearing details here prevents an adult title sheet from reappearing
    /// after a child profile becomes active.
    public func resetContentNavigation() {
        playing = nil
        showingDetails = nil
        homePath = NavigationPath()
        livePath = NavigationPath()
        moviesPath = NavigationPath()
        seriesPath = NavigationPath()
        searchPath = NavigationPath()
    }
}
