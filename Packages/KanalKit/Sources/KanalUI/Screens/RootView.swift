import KanalCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @State private var downloads = DownloadStore()
    /// The offer, presented here and nowhere else. Both routes to it — the
    /// interstitial after a stream closes, and a tap on the watermark — end in
    /// this one flag, so two of them can never be up at once.
    @State private var isShowingPro = false
    @State private var isRepairingSource = false
    #if os(iOS)
    @State private var pairingInvitation: Pairing.Invitation?
    @State private var presentsPairing = false
    #endif

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
            .tint(KanalColor.accentSolid)
            // Wired once, so every screen that plays a film gets its other
            // listings as fallbacks without knowing they exist — and so a title
            // already on this device is played from the disk wherever it was
            // tapped, rather than only from the library screen.
            .onAppear {
                navigator.alternatives = { [weak model, weak downloads] item in
                    if let model,
                       let file = downloads?.playableFile(for: item, sourceID: model.activeSourceID) {
                        let local = item.playing(from: file)
                        return PlaybackPlan(item: local, candidates: [file], owners: [item.id])
                    }
                    return model?.playbackPlan(for: item)
                }
            }
            .task { await downloads.start() }
            // The provider allows one connection at a time. A download running
            // underneath a film does not slow it down — it takes the slot, and
            // the film stops.
            .onChange(of: navigator.playing != nil) { _, isPlaying in
                downloads.setPlaybackActive(isPlaying)
            }
            .onChange(of: model.activeProfileID) { previous, current in
                guard previous != nil, previous != current else { return }
                navigator.resetContentNavigation()
            }
            .onChange(of: model.activeSourceID) { previous, current in
                guard previous != nil, previous != current else { return }
                navigator.resetContentNavigation()
            }
            .task {
                #if DEBUG
                if LaunchOptions.opensPaywall {
                    purchases.seedSampleOffers()
                    isShowingPro = true
                } else {
                    await purchases.start()
                }
                #else
                await purchases.start()
                #endif
                #if DEBUG
                if LaunchOptions.resetsNudge {
                    await purchases.resetNudge()
                }
                #endif
            }
            .onChange(of: navigator.wantsPro) { _, wants in
                guard wants else { return }
                navigator.wantsPro = false
                isShowingPro = true
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    // Flush any debounced watch-state write before iOS/tvOS
                    // suspends the process. The player also checkpoints its
                    // current position; this covers changes made elsewhere.
                    #if os(iOS)
                    // Without an assertion iOS may suspend us between the local
                    // save and the iCloud write, and the other device resumes
                    // from an older position.
                    let assertion = UIApplication.shared.beginBackgroundTask()
                    Task {
                        await model.flushPendingWatchState()
                        UIApplication.shared.endBackgroundTask(assertion)
                    }
                    #else
                    Task { await model.flushPendingWatchState() }
                    #endif
                    Task { await downloads.flush() }
                    return
                }
                guard phase == .active, model.phase != .starting else { return }
                Task { await model.syncNow() }
            }
            .task {
                #if DEBUG
                if let panel = LaunchOptions.seededXtream {
                    try? await model.add(PlaylistSource(
                        kind: .xtream, name: "Test", portalURL: panel.portal,
                        username: panel.username, password: panel.password
                    ))
                } else if let seeded = LaunchOptions.seededSource {
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
                if let wanted = LaunchOptions.autoplayItemID,
                   let item = model.library.items.first(where: { $0.id == wanted }) {
                    navigator.play(item)
                }
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
            #if os(iOS)
            .onOpenURL { url in
                guard let invitation = Pairing.Invitation(url: url) else { return }
                pairingInvitation = invitation
                presentsPairing = true
            }
            .sheet(isPresented: $presentsPairing) {
                NavigationStack { HandoffView(invitation: pairingInvitation) }
                    .kanalEnvironment(model, navigator, purchases, downloads)
            }
            #endif
            .sheet(isPresented: $isShowingPro) {
                ProView()
                    .kanalEnvironment(model, navigator, purchases, downloads)
            }
            .sheet(isPresented: $isRepairingSource) {
                if let source = model.activeSource {
                    NavigationStack {
                        WelcomeView(
                            replacing: source,
                            onSuccess: { isRepairingSource = false }
                        )
                    }
                    .kanalEnvironment(model, navigator, purchases, downloads)
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
                        .kanalEnvironment(model, navigator, purchases, downloads)
                } else {
                    BlockedContentView { navigator.playing = nil }
                        .kanalEnvironment(model, navigator, purchases, downloads)
                }
            }
            // Last, so every sheet above is inside it. Attached first, the
            // sheets on this chain sat outside the environment they read.
            .kanalEnvironment(model, navigator, purchases, downloads)
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
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @Environment(PurchaseStore.self) private var purchases: PurchaseStore?
    @Environment(DownloadStore.self) private var downloads: DownloadStore?

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
        // Posters scrolled straight under the clock and battery with nothing
        // behind them. A short fade into the page colour keeps the status bar
        // legible without a hard bar across the artwork.
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    KanalColor.background
                        .frame(height: proxy.safeAreaInsets.top)
                    LinearGradient(
                        colors: [KanalColor.background, KanalColor.background.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: KanalMetrics.lg)
                }
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        #endif
        // Presented here rather than beside the player's full-screen cover:
        // two modals on one view is not something SwiftUI presents reliably.
        #if os(tvOS)
        .fullScreenCover(item: $navigator.showingDetails) { request in
            detail(request)
        }
        #else
        .sheet(item: $navigator.showingDetails) { request in
            detail(request)
        }
        #endif
    }

    private func detail(_ request: DetailRequest) -> some View {
        TitleDetailView(item: request.item, seriesGroup: request.seriesGroup)
            // One detail screen can replace another without the presentation
            // closing — following an actor to their other films. Tying the
            // identity to the request keeps the new title from inheriting the
            // old one's loaded description and chosen season.
            .id(request.id)
            // Handed over rather than inherited: the Mac build of the iPad
            // app crashed opening a film, inside a sheet's environment lookup.
            .kanalEnvironment(model, navigator, purchases, downloads)
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
        case .library(let section):
            MyLibraryView(section: section)
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

extension View {
    /// The app's shared objects, for content presented in a new hierarchy.
    func kanalEnvironment(
        _ model: AppModel, _ navigator: Navigator,
        _ purchases: PurchaseStore?, _ downloads: DownloadStore?
    ) -> some View {
        environment(model)
            .environment(navigator)
            .environment(purchases)
            .environment(downloads)
    }
}
