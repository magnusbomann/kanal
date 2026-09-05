import KanalCore
import SwiftUI

/// The first screen: what you were watching, what you marked, then the rest.
///
/// Ordered by likelihood rather than by category. A person opening a TV app
/// almost always wants one of three things — resume, a favourite, or the
/// channel they watch every night — so those come before any browsing.
public struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var isShowingSettings = LaunchOptions.opensSettings
    @State private var isUnlockingSwitch = false

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KanalMetrics.xl) {
                header

                #if !os(tvOS)
                if !model.library.isEmpty {
                    searchEntry
                }
                #endif

                // A child's library can legitimately be empty — nothing has
                // been approved yet. Saying so is the difference between "this
                // app is broken" and "ask a grown-up", and the person who has
                // to tell them apart is seven.
                if model.library.isEmpty, model.isRestricted, model.phase == .ready {
                    EmptyStateView(
                        symbol: "hand.raised.fill",
                        title: String(UIStrings.childLibraryEmptyTitle),
                        message: String(UIStrings.childLibraryEmptyBody)
                    )
                    .frame(minHeight: 320)
                }

                if !model.continueWatching.isEmpty {
                    Shelf(title: String(UIStrings.shelfContinueWatching), itemWidth: cardWidth(.backdrop)) {
                        ForEach(model.continueWatching) { item in
                            if let progress = model.progress(for: item) {
                                ResumeCard(item: item, progress: progress) {
                                    navigator.play(item)
                                }
                            }
                        }
                    }
                }

                if !model.nextEpisodes.isEmpty {
                    Shelf(title: String(UIStrings.shelfNextEpisode), itemWidth: cardWidth(.poster)) {
                        ForEach(model.nextEpisodes) { episode in
                            PosterCard(
                                title: episode.seriesName ?? episode.title,
                                artworkURL: episode.logoURL,
                                subtitle: nextEpisodeSubtitle(episode),
                                enrich: episode
                            ) {
                                navigator.play(episode)
                            }
                        }
                    }
                }

                if !model.favoriteChannels.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfOnNow),
                        itemWidth: cardWidth(.backdrop),
                        onSeeAll: { navigator.push(.favoriteChannels) }
                    ) {
                        ForEach(model.favoriteChannelGroups) { group in
                            ChannelCard(
                                channel: group.primary,
                                nowPlaying: model.nowPlaying(on: group),
                                upNext: model.upcoming(on: group, limit: 1).first,
                                isFavorite: true,
                                sourceCount: group.variants.count
                            ) {
                                navigator.play(
                                    group,
                                    remembered: model.watchState.workingVariants[group.id]
                                )
                            }
                        }
                    }
                }

                if !model.recentChannelGroups.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfRecentChannels),
                        itemWidth: cardWidth(.backdrop)
                    ) {
                        ForEach(model.recentChannelGroups) { group in
                            ChannelCard(
                                channel: group.primary,
                                nowPlaying: model.nowPlaying(on: group),
                                upNext: model.upcoming(on: group, limit: 1).first,
                                isFavorite: group.variants.contains {
                                    model.watchState.isFavorite($0.id)
                                },
                                sourceCount: group.variants.count
                            ) {
                                navigator.play(
                                    group,
                                    remembered: model.watchState.workingVariants[group.id]
                                )
                            }
                        }
                    }
                }

                if !model.newlyAddedMovies.isEmpty || !model.newlyAddedSeries.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfRecentlyAdded),
                        subtitle: newContentSummary,
                        itemWidth: cardWidth(.poster)
                    ) {
                        ForEach(model.newlyAddedMovies) { movie in
                            PosterCard(
                                title: movie.title,
                                artworkURL: movie.logoURL,
                                subtitle: movie.year.map(String.init),
                                enrich: movie
                            ) {
                                navigator.showDetails(for: movie)
                            }
                        }
                        ForEach(model.newlyAddedSeries) { group in
                            PosterCard(
                                title: group.name,
                                artworkURL: group.artworkURL,
                                subtitle: group.year.map(String.init),
                                enrich: group.episodes.first
                            ) {
                                guard let first = group.episodes.first else { return }
                                navigator.showDetails(for: first, seriesGroup: group)
                            }
                        }
                    }
                }

                if !model.favoriteSeries.isEmpty {
                    Shelf(title: String(UIStrings.shelfFavouriteSeries), itemWidth: cardWidth(.poster)) {
                        ForEach(model.favoriteSeries) { group in
                            PosterCard(
                                title: group.name,
                                artworkURL: group.artworkURL,
                                subtitle: seriesSubtitle(group),
                                enrich: group.episodes.first
                            ) {
                                navigator.push(.series(id: group.id))
                            }
                        }
                    }
                }

                let browse = model.discoveryPresentation.browse

                if !browse.topMovies.isEmpty {
                    Shelf(
                        title: String(
                            browse.topMoviesAreTrending
                                ? UIStrings.shelfTopMovies
                                : UIStrings.shelfFeaturedMovies
                        ),
                        itemWidth: cardWidth(.poster),
                        onSeeAll: { navigator.push(.allMovies) }
                    ) {
                        ForEach(browse.topMovies) { movie in
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

                if !browse.topSeries.isEmpty {
                    Shelf(
                        title: String(
                            browse.topSeriesAreTrending
                                ? UIStrings.shelfTopSeries
                                : UIStrings.shelfFeaturedSeries
                        ),
                        itemWidth: cardWidth(.poster),
                        onSeeAll: { navigator.push(.allSeries) }
                    ) {
                        ForEach(browse.topSeries) { group in
                            seriesCard(group)
                        }
                    }
                }

                ForEach(browse.homeServiceSpotlights) { spotlight in
                    Shelf(
                        title: String(UIStrings.shelfOnService(spotlight.serviceName)),
                        itemWidth: cardWidth(.poster)
                    ) {
                        ForEach(spotlight.items) { item in
                            discoveryCard(item)
                        }
                    }
                }
            }
            .padding(.bottom, KanalMetrics.xxl * 2)
        }
        .background(KanalColor.background)
        .task { await model.prepareHome() }
        #if os(tvOS)
        .fullScreenCover(isPresented: $isShowingSettings) {
            NavigationStack { SettingsView() }
        }
        .fullScreenCover(isPresented: $isUnlockingSwitch) {
            unlockProfileSwitch
        }
        #else
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $isUnlockingSwitch) {
            unlockProfileSwitch
        }
        #endif
    }

    private var unlockProfileSwitch: some View {
        ParentalCodeView(purpose: .unlock) { entered in
            guard model.parentalCode.matches(entered) else { return false }
            model.beginChoosingProfile()
            return true
        }
    }

    private var searchEntry: some View {
        Button {
            navigator.openSearch()
        } label: {
            HStack(spacing: KanalMetrics.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KanalColor.accentSolid)
                Text(UIStrings.searchPrompt)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.secondaryText)
                Spacer(minLength: KanalMetrics.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KanalColor.tertiaryText)
            }
            .padding(.horizontal, KanalMetrics.md)
            .frame(minHeight: 52)
            .background(KanalColor.surface, in: .rect(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(KanalColor.separator, lineWidth: 1)
            }
        }
        .buttonStyle(KanalCardButtonStyle())
        .accessibilityLabel(Text(UIStrings.search))
        .padding(.horizontal, KanalMetrics.lg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.xs) {
            #if !os(tvOS)
            Text(greeting)
                .kanalLabel(12)
                .foregroundStyle(KanalColor.accentSolid)
            #endif
            HStack(alignment: .firstTextBaseline) {
                Text(UIStrings.homeQuestion)
                    .kanalDisplay(KanalMetrics.scale * 34)
                    .foregroundStyle(KanalColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                if model.isRefreshingGuide {
                    ProgressView()
                        .controlSize(.small)
                        .tint(KanalColor.tertiaryText)
                }
                if let profile = model.activeProfile, model.profiles.count > 1 || profile.isRestricted {
                    // The way back to "who is watching?". Behind the code when
                    // a restricted profile is in use — that is the whole point
                    // of the code, and this is the door it guards.
                    Button {
                        if model.canLeaveProfileWithoutCode {
                            model.beginChoosingProfile()
                        } else {
                            isUnlockingSwitch = true
                        }
                    } label: {
                        ProfileAvatar(profile: profile, size: headerControlSize)
                    }
                    .buttonStyle(KanalCardButtonStyle())
                    .accessibilityLabel(Text(UIStrings.switchProfile))
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: headerControlSize * 0.4, weight: .semibold))
                        .foregroundStyle(KanalColor.secondaryText)
                        .frame(width: headerControlSize, height: headerControlSize)
                        .kanalGlassPill()
                }
                .buttonStyle(KanalCardButtonStyle())
                .accessibilityLabel(Text(UIStrings.settings))
            }
        }
        .padding(.horizontal, KanalMetrics.lg)
        .padding(.top, KanalMetrics.md)
    }

    private var headerControlSize: CGFloat {
        #if os(tvOS)
        64
        #else
        38
        #endif
    }

    private var greeting: LocalizedStringResource {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<6: UIStrings.greetingNight
        case 6..<12: UIStrings.greetingMorning
        case 12..<18: UIStrings.greetingAfternoon
        default: UIStrings.greetingEvening
        }
    }

    private var newContentSummary: String {
        var parts: [String] = []
        if !model.newlyAddedMovies.isEmpty {
            parts.append(String(UIStrings.filmCount(model.newlyAddedMovies.count)))
        }
        if !model.newlyAddedSeries.isEmpty {
            parts.append(String(UIStrings.seriesCount(model.newlyAddedSeries.count)))
        }
        return parts.joined(separator: " · ")
    }

    private func nextEpisodeSubtitle(_ episode: MediaItem) -> String? {
        [episode.episodeCode, episode.episodeTitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    @ViewBuilder
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

    @ViewBuilder
    private func discoveryCard(_ item: MediaItem) -> some View {
        let group = item.kind == .series ? model.seriesGroup(for: item) : nil
        PosterCard(
            title: group?.name ?? item.title,
            artworkURL: group?.artworkURL ?? item.logoURL,
            subtitle: group.flatMap(seriesSubtitle) ?? item.year.map(String.init),
            progressFraction: model.progress(for: item)?.fraction,
            enrich: group?.episodes.first ?? item
        ) {
            navigator.showDetails(for: item, seriesGroup: group)
        }
        .contextMenu {
            FavoriteButton(id: group?.id ?? item.id)
        }
    }

    private func seriesSubtitle(_ group: SeriesGroup) -> String? {
        if group.needsEpisodeLoad { return group.year.map(String.init) }
        return String(UIStrings.episodeCount(group.episodes.count))
    }

    private enum CardShape { case poster, backdrop }

    /// Sized so a shelf always shows a slice of the next card — the cue that
    /// tells you the row scrolls without needing an arrow.
    private func cardWidth(_ shape: CardShape) -> CGFloat {
        #if os(tvOS)
        return shape == .poster ? 260 : 420
        #elseif os(iOS)
        let isCompact = sizeClass == .compact
        if shape == .poster { return isCompact ? 116 : 150 }
        return isCompact ? 168 : 250
        #else
        return shape == .poster ? 150 : 250
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
