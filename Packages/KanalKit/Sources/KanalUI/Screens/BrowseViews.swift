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
            .padding(.bottom, KanalMetrics.xxl * 2)
        }
        .background(KanalColor.background)
    }
}

/// Live TV, grouped by category with a category strip on top.
public struct ChannelsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var selectedCategory: String?
    @State private var mode: Mode = LaunchOptions.liveMode == "guide" ? .guide : .channels
    @State private var sources: ChannelGroup?

    enum Mode: Hashable { case channels, guide }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // A sixth tab would push search under "More", and the guide is a
            // second way to look at the same channels rather than a new place.
            if model.guide != nil {
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
        .navigationTitle(Text(CoreStrings.liveTV))
        .sheet(item: $sources) { group in
            ChannelSourcesSheet(group: group)
        }
    }

    private var channelList: some View {
        VStack(spacing: 0) {
            CategoryStrip(
                names: model.library.channelCategories.map(\.name),
                selection: $selectedCategory
            )
            LibraryGrid(items: groups, minimumWidth: gridWidth) { group in
                ChannelCard(
                    channel: group.primary,
                    nowPlaying: model.nowPlaying(on: group.primary),
                    isFavorite: model.watchState.isFavorite(group.primary.id),
                    sourceCount: group.variants.count
                ) {
                    navigator.play(group, remembered: model.watchState.workingVariants[group.id])
                }
                .contextMenu {
                    FavoriteButton(id: group.primary.id)
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
        guard let selectedCategory else { return model.library.channelGroups }
        return model.library.channelGroups.filter { $0.categories.contains(selectedCategory) }
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

/// Films.
public struct MoviesView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var filter = LibraryFilter()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filter: $filter,
                categories: model.library.movieCategories.map(\.name),
                countries: model.library.availableCountries(),
                decades: model.library.availableDecades(among: model.library.movies)
            )
            if movies.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: String(UIStrings.filterNoResultsTitle),
                    message: String(UIStrings.filterNoResultsBody)
                )
            } else {
            LibraryGrid(items: movies, minimumWidth: gridWidth) { movie in
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
                }
            }
            }
        }
        .background(KanalColor.background)
        .navigationTitle(Text(CoreStrings.movies))
    }

    private var movies: [MediaItem] {
        model.library.movies(filter, ranking: model.discoveryRanking)
    }

    private var gridWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        120
        #endif
    }
}

/// Series, one poster per show.
public struct SeriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var filter = LibraryFilter()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filter: $filter,
                categories: model.library.seriesCategories.map(\.name),
                countries: [],
                decades: model.library.availableDecades(
                    among: model.library.series.compactMap(\.episodes.first)
                )
            )
            if series.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: String(UIStrings.filterNoResultsTitle),
                    message: String(UIStrings.filterNoResultsBody)
                )
            } else {
            LibraryGrid(items: series, minimumWidth: gridWidth) { group in
                PosterCard(
                    title: group.name,
                    artworkURL: group.artworkURL,
                    subtitle: String(UIStrings.episodeCount(group.episodes.count)),
                    enrich: group.episodes.first
                ) {
                    guard let first = group.episodes.first else { return }
                    navigator.showDetails(for: first, seriesGroup: group)
                }
                .contextMenu {
                    FavoriteButton(id: group.id)
                }
            }
            }
        }
        .background(KanalColor.background)
        .navigationTitle(Text(CoreStrings.series))
    }

    private var series: [SeriesGroup] {
        model.library.series(filter, ranking: model.discoveryRanking)
    }

    private var gridWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        120
        #endif
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KanalMetrics.md) {
                Text(episode.episodeCode ?? "–")
                    .kanalLabel(12)
                    .foregroundStyle(KanalColor.accentSolid)
                    .frame(width: 56, alignment: .leading)
                Text(episode.title)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(KanalColor.secondaryText)
            }
            .padding(.horizontal, KanalMetrics.md)
            .frame(minHeight: KanalMetrics.minTarget + 8)
            .background(KanalColor.surface, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(KanalCardButtonStyle())
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
