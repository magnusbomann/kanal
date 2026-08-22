import KanalCore
import SwiftUI

/// The app shell.
///
/// One `AppModel` and one `Navigator` are injected here and read everywhere
/// else, so a card in any tab can start playback without threading closures
/// back up the view tree.
public struct RootView: View {
    @State private var model = AppModel()
    @State private var navigator = Navigator()

    public init() {}

    public var body: some View {
        content
            .environment(model)
            .environment(navigator)
            .tint(KanalColor.accentSolid)
            .task {
                await model.start()
                #if DEBUG
                if let index = LaunchOptions.autoplayMovieIndex,
                   model.library.movies.indices.contains(index) {
                    navigator.play(model.library.movies[index])
                }
                #endif
            }
            .fullScreenCoverCompat(item: Binding(
                get: { navigator.playing },
                set: { navigator.playing = $0 }
            )) { request in
                PlayerView(item: request.item)
                    .environment(model)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .starting:
            // Deliberately bare. A spinner here would flash for a fraction of
            // a second on every launch; a plain background simply reads as the
            // launch screen still being up.
            KanalColor.background.ignoresSafeArea()

        case .welcome:
            NavigationStack {
                if model.hasCompletedIntro {
                    WelcomeView()
                } else {
                    OnboardingView()
                }
            }
        case .loading(let message):
            LoadingView(message: message)
        case .failed(let message):
            EmptyStateView(
                symbol: "antenna.radiowaves.left.and.right.slash",
                title: String(UIStrings.loadFailedTitle),
                message: message,
                actionTitle: String(UIStrings.tryAgain),
                action: { Task { await model.refreshActiveSource() } }
            )
        case .ready:
            MainTabView()
        }
    }
}

/// The tab shell. Liquid Glass handles the bar itself; the only thing worth
/// customising is letting it shrink out of the way while you scroll.
public struct MainTabView: View {
    @Environment(Navigator.self) private var navigator
    @State private var selection: TabIdentifier = LaunchOptions.startTab
        .flatMap(TabIdentifier.init(argument:)) ?? .home

    public enum TabIdentifier: Hashable {
        case home, live, series, movies, search

        init?(argument: String) {
            switch argument {
            case "home": self = .home
            case "live": self = .live
            case "series": self = .series
            case "movies", "films": self = .movies
            case "search": self = .search
            default: return nil
            }
        }
    }

    public init() {}

    public var body: some View {
        @Bindable var navigator = navigator

        TabView(selection: $selection) {
            Tab(String(UIStrings.tabHome), systemImage: "house.fill", value: TabIdentifier.home) {
                stack { HomeView() }
            }
            Tab(String(CoreStrings.liveTV), systemImage: MediaKind.liveTV.symbolName, value: TabIdentifier.live) {
                stack { ChannelsView() }
            }
            Tab(String(CoreStrings.series), systemImage: MediaKind.series.symbolName, value: TabIdentifier.series) {
                stack { SeriesView() }
            }
            Tab(String(CoreStrings.movies), systemImage: MediaKind.movie.symbolName, value: TabIdentifier.movies) {
                stack { MoviesView() }
            }
            Tab(value: TabIdentifier.search, role: .search) {
                stack { SearchView() }
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
    }
}

struct RouteView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let route: Route

    var body: some View {
        switch route {
        case .series(let id):
            SeriesDetailView(seriesID: id)
        case .allChannels, .category(kind: .liveTV, name: _):
            ChannelsView()
        case .allMovies, .category(kind: .movie, name: _):
            MoviesView()
        case .allSeries, .category(kind: .series, name: _):
            SeriesView()
        }
    }
}

extension View {
    /// `fullScreenCover` does not exist on macOS; fall back to a sheet there.
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}
