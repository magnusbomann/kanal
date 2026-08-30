import KanalCore
import SwiftUI

/// The app shell.
///
/// One `AppModel` and one `Navigator` are injected here and read everywhere
/// else, so a card in any tab can start playback without threading closures
/// back up the view tree.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    @State private var navigator = Navigator()
    @State private var purchases = PurchaseStore()
    /// The offer, presented here and nowhere else. Both routes to it — the
    /// interstitial after a stream closes, and a tap on the watermark — end in
    /// this one flag, so two of them can never be up at once.
    @State private var isShowingPro = false
    @State private var isRepairingSource = false

    public init() {}

    public var body: some View {
        // Wrapped so the startup task survives.
        //
        // `content` switches between phases, and `start()` changes the phase
        // — so a task attached to it is cancelled by its own first await, and
        // anything after that never runs. The container's identity is stable,
        // and the task with it.
        ZStack {
            content
        }
            .environment(model)
            .environment(navigator)
            .environment(purchases)
            .tint(KanalColor.accentSolid)
            .onChange(of: model.activeProfileID) { previous, current in
                guard previous != nil, previous != current else { return }
                navigator.resetContentNavigation()
            }
            .onChange(of: model.activeSourceID) { previous, current in
                guard previous != nil, previous != current else { return }
                navigator.resetContentNavigation()
            }
            .task {
                await purchases.start()
                #if DEBUG
                if LaunchOptions.resetsNudge {
                    await purchases.resetNudge()
                }
                if LaunchOptions.opensPaywall {
                    purchases.seedSampleOffers()
                    isShowingPro = true
                }
                #endif
            }
            .onChange(of: navigator.wantsPro) { _, wants in
                guard wants else { return }
                navigator.wantsPro = false
                isShowingPro = true
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, model.phase != .starting else { return }
                Task { await model.syncNow() }
            }
            .task {
                #if DEBUG
                if let seeded = LaunchOptions.seededSource {
                    try? await model.add(PlaylistSource(
                        kind: .m3u, name: "Test", playlistURL: seeded
                    ))
                } else {
                    await model.start()
                }
                #else
                await model.start()
                #endif
                #if DEBUG
                if let index = LaunchOptions.autoplayMovieIndex,
                   model.library.movies.indices.contains(index) {
                    navigator.play(model.library.movies[index])
                }
                if let index = LaunchOptions.autoplayChannelIndex,
                   model.library.channelGroups.indices.contains(index) {
                    navigator.play(model.library.channelGroups[index])
                }
                if let index = LaunchOptions.openSeriesIndex,
                   model.library.series.indices.contains(index) {
                    let group = model.library.series[index]
                    if let first = group.episodes.first {
                        navigator.showDetails(for: first, seriesGroup: group)
                    }
                }
                if let index = LaunchOptions.detailsMovieIndex {
                    // The root view swaps as the phase settles, which would
                    // take the sheet with it.
                    try? await Task.sleep(for: .milliseconds(600))
                    if model.library.movies.indices.contains(index) {
                        navigator.showDetails(for: model.library.movies[index])
                    }
                }
                #endif
            }
            .sheet(isPresented: $isShowingPro) {
                ProView()
                    .environment(purchases)
            }
            .sheet(isPresented: $isRepairingSource) {
                if let source = model.activeSource {
                    NavigationStack {
                        WelcomeView(
                            replacing: source,
                            onSuccess: { isRepairingSource = false }
                        )
                    }
                }
            }
            .fullScreenCoverCompat(item: Binding(
                get: { navigator.playing },
                set: { navigator.playing = $0 }
            ), onDismiss: {
                // Closing a stream is where the free tier asks. Everything
                // about *whether* to ask lives in `ProNudge`; this only
                // supplies the two facts it cannot see from Core.
                if purchases.playbackClosed(
                    didPlay: navigator.lastPlaybackPlayed,
                    isRestricted: model.isRestricted
                ) {
                    isShowingPro = true
                }
                navigator.lastPlaybackPlayed = false
            }) { request in
                // The last gate. The library a profile browses is already
                // filtered, but a handoff from an iPhone, a stale navigation
                // path or a resumed shelf can all hand the player something
                // that was never on screen — and the player is where that
                // would otherwise become playback.
                if model.canPlay(request.item) {
                    PlayerView(plan: request.plan)
                        .environment(model)
                        .environment(purchases)
                } else {
                    BlockedContentView { navigator.playing = nil }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isChoosingProfile {
            // Shown over whatever the app is doing, so the catalogue loads
            // while someone picks their face rather than after it.
            ProfilePickerView()
        } else {
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
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
            SourceFailureView(
                message: message,
                retry: { Task { await model.refreshActiveSource() } },
                repair: { isRepairingSource = true }
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

    public init() {}

    public var body: some View {
        @Bindable var navigator = navigator

        TabView(selection: $navigator.selectedTab) {
            Tab(String(UIStrings.tabHome), systemImage: "house.fill", value: AppTab.home) {
                stack(path: $navigator.homePath) { HomeView() }
            }
            Tab(String(CoreStrings.liveTV), systemImage: MediaKind.liveTV.symbolName, value: AppTab.live) {
                stack(path: $navigator.livePath) { ChannelsView() }
            }
            Tab(String(CoreStrings.movies), systemImage: MediaKind.movie.symbolName, value: AppTab.movies) {
                stack(path: $navigator.moviesPath) { MoviesView() }
            }
            Tab(String(CoreStrings.series), systemImage: MediaKind.series.symbolName, value: AppTab.series) {
                stack(path: $navigator.seriesPath) { SeriesView() }
            }
            Tab(value: AppTab.search, role: .search) {
                stack(path: $navigator.searchPath) { SearchView() }
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        // Presented here rather than beside the player's full-screen cover:
        // two modals on one view is not something SwiftUI presents reliably.
        .sheet(item: $navigator.showingDetails) { request in
            TitleDetailView(item: request.item, seriesGroup: request.seriesGroup)
                // One detail screen can replace another without the sheet
                // closing — following an actor to their other films. Tying the
                // identity to the request keeps the new title from inheriting
                // the old one's loaded description and chosen season.
                .id(request.id)
        }
    }

    @ViewBuilder
    private func stack<Content: View>(
        path: Binding<NavigationPath>, @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
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
        case .allChannels:
            ChannelsView()
        case .favoriteChannels:
            ChannelsView(showsFavoritesOnly: true)
        case .allMovies:
            MovieLibraryView()
        case .allSeries:
            SeriesLibraryView()
        case .category(kind: .liveTV, name: let name):
            ChannelsView(initialCategory: name)
        case .category(kind: .movie, name: let name):
            MovieLibraryView(initialCategory: name)
        case .category(kind: .series, name: let name):
            SeriesLibraryView(initialCategory: name)
        }
    }
}

extension View {
    /// `fullScreenCover` does not exist on macOS; fall back to a sheet there.
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, onDismiss: onDismiss, content: content)
        #else
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
