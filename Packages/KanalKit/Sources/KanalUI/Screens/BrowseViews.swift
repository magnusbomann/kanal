import KanalCore
import SwiftUI

/// Adaptive grid used by every browse screen.
struct LibraryGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let minimumWidth: CGFloat
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: KanalMetrics.md)],
                alignment: .leading,
                spacing: KanalMetrics.lg
            ) {
                ForEach(items) { item in
                    card(item)
                }
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.top, KanalMetrics.md)
            .padding(.bottom, KanalMetrics.xxl * 2)
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .background(KanalColor.background)
    }
}

/// Live TV, grouped by category with a category strip on top.
public struct ChannelsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var selectedCategory: String?
    @State private var mode: Mode
    @State private var sources: ChannelGroup?
    private let showsFavoritesOnly: Bool

    enum Mode: Hashable { case channels, guide }

    public init(initialCategory: String? = nil, showsFavoritesOnly: Bool = false) {
        self.showsFavoritesOnly = showsFavoritesOnly
        self._selectedCategory = State(initialValue: initialCategory)
        self._mode = State(
            initialValue: showsFavoritesOnly
                ? .channels
                : (LaunchOptions.liveMode == "guide" ? .guide : .channels)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // A sixth tab would push search under "More", and the guide is a
            // second way to look at the same channels rather than a new place.
            if model.guide != nil, !showsFavoritesOnly {
                Picker("", selection: $mode) {
                    Text(UIStrings.viewList).tag(Mode.channels)
                    Text(UIStrings.viewGuide).tag(Mode.guide)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, KanalMetrics.lg)
                .padding(.top, KanalMetrics.sm)
            }

            if mode == .guide {
                GuideView()
            } else {
                channelList
            }
        }
        .background(KanalColor.background)
        .navigationTitle(navigationTitle)
        .sheet(item: $sources) { group in
            ChannelSourcesSheet(group: group)
        }
    }

    private var channelList: some View {
        VStack(spacing: 0) {
            if !showsFavoritesOnly {
                CategoryStrip(
                    names: model.library.channelCategories.map(\.name),
                    selection: $selectedCategory
                )
            }
            LibraryGrid(items: groups, minimumWidth: gridWidth) { group in
                ChannelCard(
                    channel: group.primary,
                    nowPlaying: model.nowPlaying(on: group.primary),
                    isFavorite: isFavorite(group),
                    sourceCount: group.variants.count
                ) {
                    navigator.play(group, remembered: model.watchState.workingVariants[group.id])
                }
                .contextMenu {
                    FavoriteButton(id: favoriteID(for: group))
                    if group.hasAlternatives {
                        Button {
                            sources = group
                        } label: {
                            Label(String(UIStrings.otherSources), systemImage: "rectangle.stack")
                        }
                    }
                }
            }
        }
    }

    /// Folded so the same channel is not listed four times over — a real
    /// provider had 2,047 entries covering 657 actual channels.
    private var groups: [ChannelGroup] {
        let available = showsFavoritesOnly
            ? model.favoriteChannelGroups
            : model.library.channelGroups
        guard let selectedCategory else { return available }
        return available.filter { $0.categories.contains(selectedCategory) }
    }

    private var navigationTitle: Text {
        if showsFavoritesOnly {
            Text(UIStrings.shelfFavouriteChannels)
        } else if let selectedCategory {
            Text(CategoryLocalizer.display(selectedCategory))
        } else {
            Text(CoreStrings.liveTV)
        }
    }

    private func isFavorite(_ group: ChannelGroup) -> Bool {
        group.variants.contains { model.watchState.isFavorite($0.id) }
    }

    /// Favourites predate channel grouping and are stored against a concrete
    /// stream. Toggle the stream that made this group a favourite, rather than
    /// adding a second favourite to its primary variant.
    private func favoriteID(for group: ChannelGroup) -> String {
        group.variants.first { model.watchState.isFavorite($0.id) }?.id ?? group.primary.id
    }

    /// Two columns on a phone.
    ///
    /// 170 plus the 16pt gutter came to 356 against 354 of usable width, so
    /// the grid quietly fell back to a single very wide column.
    private var gridWidth: CGFloat {
        #if os(tvOS)
        400
        #else
        150
        #endif
    }
}

/// Films presented like a streaming-service landing page. The provider's full
/// catalogue is intentionally kept behind "See all" so opening the tab never
/// creates thousands of poster views or sorts the complete list on the UI
/// thread.
public struct MoviesView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    public init() {}

    public var body: some View {
        Group {
            if model.library.movies.isEmpty {
                if model.isRefreshingLibrary {
                    deferredLibraryProgress
                } else {
                    EmptyStateView(
                        symbol: "film",
                        title: String(UIStrings.moviesEmptyTitle),
                        message: String(UIStrings.moviesEmptyBody)
                    )
                }
            } else {
                landingPage
            }
        }
        .background(KanalColor.background)
        .navigationTitle(Text(CoreStrings.movies))
        .task { await model.prepareHome() }
    }

    private var deferredLibraryProgress: some View {
        VStack(spacing: KanalMetrics.md) {
            ProgressView()
            Text(UIStrings.updatingLibrary)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var landingPage: some View {
        let browse = model.discoveryPresentation.browse
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: KanalMetrics.xl) {
                if !continueWatching.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfContinueWatching),
                        itemWidth: backdropWidth
                    ) {
                        ForEach(continueWatching) { movie in
                            if let progress = model.progress(for: movie) {
                                ResumeCard(item: movie, progress: progress) {
                                    navigator.play(movie)
                                }
                            }
                        }
                    }
                }

                if !favoriteMovies.isEmpty {
                    movieShelf(
                        title: String(UIStrings.shelfFavouriteMovies),
                        movies: favoriteMovies
                    )
                }

                if !model.newlyAddedMovies.isEmpty {
                    movieShelf(
                        title: String(UIStrings.shelfRecentlyAdded),
                        movies: Array(model.newlyAddedMovies.prefix(24))
                    )
                }

                movieShelf(
                    title: String(
                        browse.topMoviesAreTrending
                            ? UIStrings.shelfTopMovies
                            : UIStrings.shelfFeaturedMovies
                    ),
                    movies: browse.topMovies,
                    onSeeAll: { navigator.push(.allMovies) }
                )

                if browse.newMoviesAreDiscoveryBased, !browse.newMovies.isEmpty {
                    movieShelf(
                        title: String(UIStrings.shelfNewMovies),
                        movies: browse.newMovies
                    )
                }

                let everyoneWatching = DiscoveryMerge.roundRobin(
                    browse.movieServiceShelves.map(\.items), id: \.id
                )
                if !everyoneWatching.isEmpty {
                    movieShelf(
                        title: String(UIStrings.shelfEveryoneWatching),
                        movies: everyoneWatching
                    )
                }

                if !browse.movieCategories.isEmpty {
                    browseHeading(String(UIStrings.browseMovieCategories))
                    ForEach(browse.movieCategories) { category in
                        movieShelf(
                            title: CategoryLocalizer.display(category.name),
                            movies: category.movies,
                            onSeeAll: {
                                navigator.push(.category(kind: .movie, name: category.name))
                            }
                        )
                    }
                }

                BrowseAllButton(
                    title: String(UIStrings.browseAllMovies),
                    count: String(UIStrings.filmCount(model.library.movies.count)),
                    symbol: MediaKind.movie.symbolName
                ) {
                    navigator.push(.allMovies)
                }
                .padding(.horizontal, KanalMetrics.lg)
            }
            .padding(.top, KanalMetrics.sm)
            .padding(.bottom, KanalMetrics.xxl * 2)
        }
    }

    private var continueWatching: [MediaItem] {
        Array(model.continueWatching.lazy.filter { $0.kind == .movie }.prefix(24))
    }

    private var favoriteMovies: [MediaItem] {
        Array(model.favoriteMovies.prefix(24))
    }

    private func movieShelf(
        title: String,
        movies: [MediaItem],
        onSeeAll: (() -> Void)? = nil
    ) -> some View {
        Shelf(title: title, itemWidth: posterWidth, onSeeAll: onSeeAll) {
            ForEach(movies) { movie in
                PosterCard(
                    title: movie.title,
                    artworkURL: movie.logoURL,
                    subtitle: movie.year.map(String.init),
                    progressFraction: model.progress(for: movie)?.fraction,
                    enrich: movie
                ) {
                    navigator.showDetails(for: movie)
                }
                .contextMenu {
                    FavoriteButton(id: movie.id)
                    DownloadButton(item: movie, style: .menu)
                }
            }
        }
    }

    private func browseHeading(_ title: String) -> some View {
        Text(title)
            .font(KanalFont.section(KanalMetrics.scale * 23))
            .foregroundStyle(KanalColor.primaryText)
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.bottom, -KanalMetrics.md)
    }


    private var posterWidth: CGFloat {
        #if os(tvOS)
        260
        #elseif os(iOS)
        sizeClass == .compact ? 116 : 150
        #else
        150
        #endif
    }

    private var backdropWidth: CGFloat {
        #if os(tvOS)
        420
        #elseif os(iOS)
        sizeClass == .compact ? 168 : 250
        #else
        250
        #endif
    }
}

/// Series presented as a curated landing page rather than every episode the
/// provider happened to return.
public struct SeriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    public init() {}

    public var body: some View {
        Group {
            if model.library.series.isEmpty {
                if model.isRefreshingLibrary {
                    deferredLibraryProgress
                } else {
                    EmptyStateView(
                        symbol: "rectangle.stack",
                        title: String(UIStrings.seriesEmptyTitle),
                        message: String(UIStrings.seriesEmptyBody)
                    )
                }
            } else {
                landingPage
            }
        }
        .background(KanalColor.background)
        .navigationTitle(Text(CoreStrings.series))
        .task { await model.prepareHome() }
    }

    private var deferredLibraryProgress: some View {
        VStack(spacing: KanalMetrics.md) {
            ProgressView()
            Text(UIStrings.updatingLibrary)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var landingPage: some View {
        let browse = model.discoveryPresentation.browse
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: KanalMetrics.xl) {
                if !continueWatching.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfContinueWatching),
                        itemWidth: backdropWidth
                    ) {
                        ForEach(continueWatching) { episode in
                            if let progress = model.progress(for: episode) {
                                ResumeCard(item: episode, progress: progress) {
                                    navigator.play(episode)
                                }
                            }
                        }
                    }
                }

                if !model.nextEpisodes.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfNextEpisode),
                        itemWidth: posterWidth
                    ) {
                        ForEach(model.nextEpisodes) { episode in
                            PosterCard(
                                title: episode.seriesName ?? episode.title,
                                artworkURL: episode.logoURL,
                                subtitle: episode.episodeCode,
                                enrich: episode
                            ) {
                                navigator.play(episode)
                            }
                        }
                    }
                }

                if !favoriteSeries.isEmpty {
                    seriesShelf(
                        title: String(UIStrings.shelfFavouriteSeries),
                        groups: favoriteSeries
                    )
                }

                if !model.newlyAddedSeries.isEmpty {
                    seriesShelf(
                        title: String(UIStrings.shelfRecentlyAdded),
                        groups: Array(model.newlyAddedSeries.prefix(24))
                    )
                }

                seriesShelf(
                    title: String(
                        browse.topSeriesAreTrending
                            ? UIStrings.shelfTopSeries
                            : UIStrings.shelfFeaturedSeries
                    ),
                    groups: browse.topSeries,
                    onSeeAll: { navigator.push(.allSeries) }
                )

                if browse.newSeriesAreDiscoveryBased, !browse.newSeries.isEmpty {
                    seriesShelf(
                        title: String(UIStrings.shelfNewSeries),
                        groups: browse.newSeries
                    )
                }

                let everyoneWatching = DiscoveryMerge.roundRobin(
                    browse.seriesServiceShelves.map { $0.items.compactMap(model.seriesGroup(for:)) },
                    id: \.id
                )
                if !everyoneWatching.isEmpty {
                    seriesShelf(
                        title: String(UIStrings.shelfEveryoneWatching),
                        groups: everyoneWatching
                    )
                }

                if !browse.seriesCategories.isEmpty {
                    browseHeading(String(UIStrings.browseSeriesCategories))
                    ForEach(browse.seriesCategories) { category in
                        seriesShelf(
                            title: CategoryLocalizer.display(category.name),
                            groups: category.series,
                            onSeeAll: {
                                navigator.push(.category(kind: .series, name: category.name))
                            }
                        )
                    }
                }

                BrowseAllButton(
                    title: String(UIStrings.browseAllSeries),
                    count: String(UIStrings.seriesCount(model.library.series.count)),
                    symbol: MediaKind.series.symbolName
                ) {
                    navigator.push(.allSeries)
                }
                .padding(.horizontal, KanalMetrics.lg)
            }
            .padding(.top, KanalMetrics.sm)
            .padding(.bottom, KanalMetrics.xxl * 2)
        }
    }

    private var continueWatching: [MediaItem] {
        Array(model.continueWatching.lazy.filter { $0.kind == .series }.prefix(24))
    }

    private var favoriteSeries: [SeriesGroup] {
        Array(model.favoriteSeries.prefix(24))
    }

    private func seriesShelf(
        title: String,
        groups: [SeriesGroup],
        onSeeAll: (() -> Void)? = nil
    ) -> some View {
        Shelf(title: title, itemWidth: posterWidth, onSeeAll: onSeeAll) {
            ForEach(groups) { group in
                seriesCard(group)
            }
        }
    }

    private func seriesCard(_ group: SeriesGroup) -> some View {
        PosterCard(
            title: group.name,
            artworkURL: group.artworkURL,
            subtitle: seriesSubtitle(group),
            enrich: group.episodes.first
        ) {
            guard let first = group.episodes.first else { return }
            navigator.showDetails(for: first, seriesGroup: group)
        }
        .contextMenu {
            FavoriteButton(id: group.id)
        }
    }

    private func seriesSubtitle(_ group: SeriesGroup) -> String? {
        if group.needsEpisodeLoad { return group.year.map(String.init) }
        return String(UIStrings.episodeCount(group.episodes.count))
    }

    private func browseHeading(_ title: String) -> some View {
        Text(title)
            .font(KanalFont.section(KanalMetrics.scale * 23))
            .foregroundStyle(KanalColor.primaryText)
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.bottom, -KanalMetrics.md)
    }


    private var posterWidth: CGFloat {
        #if os(tvOS)
        260
        #elseif os(iOS)
        sizeClass == .compact ? 116 : 150
        #else
        150
        #endif
    }

    private var backdropWidth: CGFloat {
        #if os(tvOS)
        420
        #elseif os(iOS)
        sizeClass == .compact ? 168 : 250
        #else
        250
        #endif
    }
}

/// The explicit full film library. Sorting happens away from the main actor;
/// cards are then introduced in batches as the viewer approaches the end.
struct MovieLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var filter: LibraryFilter
    @State private var movies: [MediaItem] = []
    @State private var isLoading = true

    init(initialCategory: String? = nil) {
        self._filter = State(initialValue: LibraryFilter(category: initialCategory))
    }

    var body: some View {
        let browse = model.discoveryPresentation.browse
        VStack(spacing: 0) {
            FilterBar(
                filter: $filter,
                categories: browse.movieFilterCategories,
                countries: browse.movieFilterCountries,
                decades: browse.movieFilterDecades
            )
            libraryContent
        }
        .background(KanalColor.background)
        .navigationTitle(navigationTitle)
        .task(id: request) { await loadMovies() }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if movies.isEmpty {
            EmptyStateView(
                symbol: "line.3.horizontal.decrease.circle",
                title: String(UIStrings.filterNoResultsTitle),
                message: String(UIStrings.filterNoResultsBody)
            )
        } else {
            IncrementalLibraryGrid(items: movies, minimumWidth: gridWidth) { movie in
                PosterCard(
                    title: movie.title,
                    artworkURL: movie.logoURL,
                    subtitle: movie.year.map(String.init),
                    progressFraction: model.progress(for: movie)?.fraction,
                    enrich: movie
                ) {
                    navigator.showDetails(for: movie)
                }
                .contextMenu {
                    FavoriteButton(id: movie.id)
                    DownloadButton(item: movie, style: .menu)
                }
            }
            .id(request)
        }
    }

    private var request: BrowseLoadRequest {
        BrowseLoadRequest(kind: .movie, revision: model.browseRevision, filter: filter)
    }

    private func loadMovies() async {
        isLoading = true
        movies = []
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        let library = model.library
        let ranking = model.discoveryPresentation.itemRanking
        let requestedFilter = filter
        let result = await BrowseLibrarySortQueue.shared.movies(
            in: library, filter: requestedFilter, ranking: ranking
        )
        guard !Task.isCancelled else { return }
        movies = result
        isLoading = false
    }

    private var navigationTitle: Text {
        filter.category.map { Text(CategoryLocalizer.display($0)) }
            ?? Text(CoreStrings.movies)
    }

    private var gridWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        120
        #endif
    }
}

/// The explicit full series library, ranked against SeriesGroup ids rather
/// than episode ids so discovery ordering finally applies to shows.
struct SeriesLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var filter: LibraryFilter
    @State private var series: [SeriesGroup] = []
    @State private var isLoading = true

    init(initialCategory: String? = nil) {
        self._filter = State(initialValue: LibraryFilter(category: initialCategory))
    }

    var body: some View {
        let browse = model.discoveryPresentation.browse
        VStack(spacing: 0) {
            FilterBar(
                filter: $filter,
                categories: browse.seriesFilterCategories,
                countries: browse.seriesFilterCountries,
                decades: browse.seriesFilterDecades
            )
            libraryContent
        }
        .background(KanalColor.background)
        .navigationTitle(navigationTitle)
        .task(id: request) { await loadSeries() }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if series.isEmpty {
            EmptyStateView(
                symbol: "line.3.horizontal.decrease.circle",
                title: String(UIStrings.filterNoResultsTitle),
                message: String(UIStrings.filterNoResultsBody)
            )
        } else {
            IncrementalLibraryGrid(items: series, minimumWidth: gridWidth) { group in
                PosterCard(
                    title: group.name,
                    artworkURL: group.artworkURL,
                    subtitle: seriesSubtitle(group),
                    enrich: group.episodes.first
                ) {
                    guard let first = group.episodes.first else { return }
                    navigator.showDetails(for: first, seriesGroup: group)
                }
                .contextMenu {
                    FavoriteButton(id: group.id)
                }
            }
            .id(request)
        }
    }

    private var request: BrowseLoadRequest {
        BrowseLoadRequest(kind: .series, revision: model.browseRevision, filter: filter)
    }

    private func loadSeries() async {
        isLoading = true
        series = []
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        let library = model.library
        let ranking = model.discoveryPresentation.seriesRanking
        let requestedFilter = filter
        let result = await BrowseLibrarySortQueue.shared.series(
            in: library, filter: requestedFilter, ranking: ranking
        )
        guard !Task.isCancelled else { return }
        series = result
        isLoading = false
    }

    private func seriesSubtitle(_ group: SeriesGroup) -> String? {
        if group.needsEpisodeLoad { return group.year.map(String.init) }
        return String(UIStrings.episodeCount(group.episodes.count))
    }

    private var navigationTitle: Text {
        filter.category.map { Text(CategoryLocalizer.display($0)) }
            ?? Text(CoreStrings.series)
    }

    private var gridWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        120
        #endif
    }
}

private struct BrowseLoadRequest: Hashable {
    var kind: MediaKind
    var revision: UInt64
    var filter: LibraryFilter
}

/// Full-library sorts share one background executor. Together with the
/// cancellation checkpoints in LibraryFilter, changing chips quickly cannot
/// leave several 400k-entry sorts competing for CPU and memory.
private actor BrowseLibrarySortQueue {
    static let shared = BrowseLibrarySortQueue()

    func movies(
        in library: Library, filter: LibraryFilter, ranking: [String: Int]
    ) -> [MediaItem] {
        guard !Task.isCancelled else { return [] }
        return library.movies(filter, ranking: ranking)
    }

    func series(
        in library: Library, filter: LibraryFilter, ranking: [String: Int]
    ) -> [SeriesGroup] {
        guard !Task.isCancelled else { return [] }
        return library.series(filter, ranking: ranking)
    }
}

/// A full catalogue still exists when someone asks for it, but only enough
/// cards to fill the next screens are mounted at a time.
private struct IncrementalLibraryGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let minimumWidth: CGFloat
    @ViewBuilder let card: (Item) -> Card
    @State private var visibleCount = 60

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: KanalMetrics.md)],
                alignment: .leading,
                spacing: KanalMetrics.lg
            ) {
                ForEach(items.prefix(visibleCount)) { item in
                    card(item)
                }
                if visibleCount < items.count {
                    ProgressView()
                        .frame(minHeight: KanalMetrics.minTarget)
                        .onAppear {
                            visibleCount = min(visibleCount + 60, items.count)
                        }
                }
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.bottom, KanalMetrics.xxl * 2)
        }
        .background(KanalColor.background)
    }
}

private struct BrowseAllButton: View {
    let title: String
    let count: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KanalMetrics.md) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KanalColor.accentSolid)
                    .frame(width: 42, height: 42)
                    .background(KanalColor.accentSolid.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KanalFont.section(16))
                        .foregroundStyle(KanalColor.primaryText)
                    Text(count)
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
                }
                Spacer(minLength: KanalMetrics.md)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KanalColor.tertiaryText)
            }
            .padding(KanalMetrics.md)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(KanalColor.surface, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(KanalCardButtonStyle())
    }
}

/// One show: seasons across, episodes down.
public struct SeriesDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    public let seriesID: String
    @State private var selectedSeason: Int?

    public init(seriesID: String) {
        self.seriesID = seriesID
    }

    public var body: some View {
        Group {
            if let group {
                content(group)
            } else {
                EmptyStateView(
                    symbol: "rectangle.stack",
                    title: String(UIStrings.seriesNotFound),
                    message: String(UIStrings.seriesNotFoundBody)
                )
            }
        }
        .background(KanalColor.background)
    }

    private var group: SeriesGroup? {
        model.library.series.first { $0.id == seriesID }
    }

    @ViewBuilder
    private func content(_ group: SeriesGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.lg) {
                HStack(alignment: .top, spacing: KanalMetrics.lg) {
                    Group {
                        if let first = group.episodes.first {
                            EnrichedArtwork(item: first, symbol: "rectangle.stack")
                        } else {
                            Artwork(url: group.artworkURL, title: group.name, symbol: "rectangle.stack")
                        }
                    }
                        .aspectRatio(KanalMetrics.posterAspect, contentMode: .fill)
                        .frame(width: 130)
                        .clipShape(.rect(cornerRadius: KanalMetrics.cardRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                        Text(group.name)
                            .kanalDisplay(28)
                            .foregroundStyle(KanalColor.primaryText)
                        HStack(spacing: KanalMetrics.sm) {
                            if let year = group.year { MetaChip(String(year)) }
                            let seasons = seasonNumbers(group)
                            if !seasons.isEmpty { MetaChip(String(UIStrings.seasonCount(seasons.count))) }
                            MetaChip(String(UIStrings.episodeCount(model.episodes(for: group).count)))
                        }
                        if let first = model.episodes(for: group).first, first.episode != nil {
                            Button(String(UIStrings.playFirstEpisode)) { navigator.play(first) }
                                .buttonStyle(KanalPrimaryButtonStyle(size: 14))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KanalMetrics.lg)

                CategoryStrip(
                    names: seasonNumbers(group).map { String(UIStrings.seasonNumber($0)) },
                    // Matched by position rather than by parsing the label
                    // back apart: "Season 2" is a translated string and its
                    // word order is not ours to assume.
                    selection: Binding(
                        get: { selectedSeason.map { String(UIStrings.seasonNumber($0)) } },
                        set: { newValue in
                            selectedSeason = seasonNumbers(group).first {
                                String(UIStrings.seasonNumber($0)) == newValue
                            }
                        }
                    )
                )

                episodeList(group)
                    .padding(.horizontal, KanalMetrics.lg)
                    .padding(.bottom, KanalMetrics.xxl * 2)
            }
            .padding(.top, KanalMetrics.md)
        }
        // Panels list shows without their episodes; fetch them on arrival.
        .task(id: group.id) {
            await model.loadEpisodesIfNeeded(for: group)
        }
    }

    @ViewBuilder
    private func episodeList(_ group: SeriesGroup) -> some View {
        let episodes = episodes(in: group)
        if model.isLoadingEpisodes(group) {
            HStack(spacing: KanalMetrics.sm) {
                ProgressView().controlSize(.small)
                Text(UIStrings.loadingEpisodes)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KanalMetrics.xl)
        } else if let failure = model.episodeLoadFailure(for: group) {
            VStack(spacing: KanalMetrics.sm) {
                Text(UIStrings.episodesFailed)
                    .font(KanalFont.section(15))
                    .foregroundStyle(KanalColor.primaryText)
                Text(failure)
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
                    .multilineTextAlignment(.center)
                Button(String(UIStrings.tryAgain)) {
                    Task { await model.loadEpisodesIfNeeded(for: group) }
                }
                .buttonStyle(KanalSecondaryButtonStyle(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KanalMetrics.xl)
        } else if episodes.isEmpty {
            Text(UIStrings.noEpisodesListed)
                .font(KanalFont.body(14))
                .foregroundStyle(KanalColor.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, KanalMetrics.xl)
        } else {
            LazyVStack(spacing: KanalMetrics.sm) {
                ForEach(episodes) { episode in
                    EpisodeRow(episode: episode) { navigator.play(episode) }
                }
            }
        }
    }

    private func seasonNumbers(_ group: SeriesGroup) -> [Int] {
        Array(Set(model.episodes(for: group).compactMap(\.season))).sorted()
    }

    private func episodes(in group: SeriesGroup) -> [MediaItem] {
        let all = model.episodes(for: group)
        guard let selectedSeason else { return all }
        return all.filter { $0.season == selectedSeason }
            .sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }
}

struct EpisodeRow: View {
    let episode: MediaItem
    /// How far in, when it has been started. Nil for unwatched.
    var progress: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: KanalMetrics.sm) {
                HStack(spacing: KanalMetrics.md) {
                    Text(episode.episodeCode ?? "–")
                        .kanalLabel(12)
                        .foregroundStyle(KanalColor.accentSolid)
                        .frame(width: 56, alignment: .leading)

                    // The episode's own title, not the show's — the show's name
                    // is already at the top of the screen.
                    Text(episodeTitle)
                        .font(KanalFont.body(15))
                        .foregroundStyle(KanalColor.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(KanalColor.secondaryText)
                }

                if let progress, progress > 0.01 {
                    ProgressLine(fraction: progress)
                        .padding(.leading, 56 + KanalMetrics.md)
                }
            }
            .padding(.horizontal, KanalMetrics.md)
            .padding(.vertical, KanalMetrics.sm)
            .frame(minHeight: KanalMetrics.minTarget + 8)
            .background(KanalColor.surface, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(KanalCardButtonStyle())
    }

    /// The provider's own episode title when there is one, and the code when
    /// there is not — repeating the show's name on every row says nothing.
    private var episodeTitle: String {
        episode.episodeTitle ?? episode.episodeCode ?? episode.title
    }
}

/// Horizontal filter chips. "All" is always first and always selected by default.
struct CategoryStrip: View {
    let names: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: KanalMetrics.sm) {
                chip(title: String(UIStrings.filterAll), isSelected: selection == nil) { selection = nil }
                ForEach(names, id: \.self) { name in
                    // Shown translated, selected by the provider's own name:
                    // filters must survive the viewer changing their language.
                    chip(title: CategoryLocalizer.display(name), isSelected: selection == name) {
                        selection = selection == name ? nil : name
                    }
                }
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.vertical, KanalMetrics.sm)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(KanalChipButtonStyle(isSelected: isSelected))
    }
}

struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        Button {
            model.toggleFavorite(id)
        } label: {
            Label(
                String(model.watchState.isFavorite(id) ? UIStrings.removeFavourite : UIStrings.addFavourite),
                systemImage: model.watchState.isFavorite(id) ? "heart.slash" : "heart"
            )
        }
    }
}
