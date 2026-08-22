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

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KanalMetrics.xl) {
                header

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

                if !model.favoriteChannels.isEmpty {
                    Shelf(
                        title: String(UIStrings.shelfFavouriteChannels),
                        itemWidth: cardWidth(.backdrop),
                        onSeeAll: { navigator.push(.allChannels) }
                    ) {
                        ForEach(model.favoriteChannels) { channel in
                            ChannelCard(
                                channel: channel,
                                nowPlaying: model.nowPlaying(on: channel),
                                isFavorite: true
                            ) {
                                navigator.play(channel)
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
                                subtitle: String(UIStrings.episodeCount(group.episodes.count)),
                                enrich: group.episodes.first
                            ) {
                                navigator.push(.series(id: group.id))
                            }
                        }
                    }
                }

                ForEach(topChannelCategories, id: \.name) { category in
                    Shelf(
                        title: CategoryLocalizer.display(category.name),
                        subtitle: String(UIStrings.channelCount(category.items.count)),
                        itemWidth: cardWidth(.backdrop),
                        onSeeAll: { navigator.push(.category(kind: .liveTV, name: category.name)) }
                    ) {
                        ForEach(category.items.prefix(20)) { channel in
                            ChannelCard(
                                channel: channel,
                                nowPlaying: model.nowPlaying(on: channel),
                                isFavorite: model.watchState.isFavorite(channel.id)
                            ) {
                                navigator.play(channel)
                            }
                        }
                    }
                }

                ForEach(topMovieCategories, id: \.name) { category in
                    Shelf(
                        title: CategoryLocalizer.display(category.name),
                        subtitle: String(UIStrings.filmCount(category.items.count)),
                        itemWidth: cardWidth(.poster),
                        onSeeAll: { navigator.push(.category(kind: .movie, name: category.name)) }
                    ) {
                        ForEach(category.items.prefix(20)) { movie in
                            PosterCard(
                                title: movie.title,
                                artworkURL: movie.logoURL,
                                subtitle: movie.year.map(String.init),
                                enrich: movie
                            ) {
                                navigator.play(movie)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, KanalMetrics.xxl * 2)
        }
        .background(KanalColor.background)
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack { SettingsView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.xs) {
            Text(greeting)
                .kanalLabel(12)
                .foregroundStyle(KanalColor.accentSolid)
            HStack(alignment: .firstTextBaseline) {
                Text(model.activeSource?.name ?? "Kanal")
                    .kanalDisplay(KanalMetrics.scale * 34)
                    .foregroundStyle(KanalColor.primaryText)
                Spacer()
                if model.isRefreshingGuide {
                    ProgressView()
                        .controlSize(.small)
                        .tint(KanalColor.tertiaryText)
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KanalColor.secondaryText)
                        .frame(width: 38, height: 38)
                        .kanalGlassPill()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(UIStrings.settings))
            }
            Text(librarySummary)
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.secondaryText)
        }
        .padding(.horizontal, KanalMetrics.lg)
        .padding(.top, KanalMetrics.md)
    }

    private var greeting: LocalizedStringResource {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<6: UIStrings.greetingNight
        case 6..<12: UIStrings.greetingMorning
        case 12..<18: UIStrings.greetingAfternoon
        default: UIStrings.greetingEvening
        }
    }

    private var librarySummary: String {
        let library = model.library
        var parts: [String] = []
        if !library.channels.isEmpty { parts.append(String(UIStrings.channelCount(library.channels.count))) }
        if !library.movies.isEmpty { parts.append(String(UIStrings.filmCount(library.movies.count))) }
        if !library.series.isEmpty { parts.append(String(UIStrings.seriesCount(library.series.count))) }
        return parts.isEmpty ? String(UIStrings.libraryEmpty) : parts.joined(separator: " · ")
    }

    /// Only the biggest few categories get a shelf; the rest live behind the tabs.
    private var topChannelCategories: [(name: String, items: [MediaItem])] {
        Array(model.library.channelCategories.prefix(4))
    }

    private var topMovieCategories: [(name: String, items: [MediaItem])] {
        Array(model.library.movieCategories.prefix(3))
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
