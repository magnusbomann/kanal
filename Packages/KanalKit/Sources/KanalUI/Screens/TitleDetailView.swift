import KanalCore
import SwiftUI

/// What you are about to put on.
///
/// One screen between choosing something and playing it, because "an action
/// film from 1998" and "the one everybody is talking about" look identical in
/// a grid. Play is the first thing on it and needs one tap, so the cost of
/// knowing is a single press — everything else is there to be glanced at, not
/// read.
///
/// Channels never come here. Tapping a channel means "put this on now".
public struct TitleDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    public let item: MediaItem
    /// Set when the entry is one episode of a show, so the whole run can be
    /// offered rather than just the episode that was tapped.
    public let seriesGroup: SeriesGroup?

    @State private var details: TitleDetails?
    @State private var isLoading = true
    @State private var person: CastMember?
    @State private var season: Int?
    /// Something picked from an actor's other work, waiting for their sheet to
    /// close before it takes this screen's place.
    @State private var pendingTitle: MediaItem?

    public init(item: MediaItem, seriesGroup: SeriesGroup? = nil) {
        self.item = item
        self.seriesGroup = seriesGroup
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.lg) {
                backdrop
                VStack(alignment: .leading, spacing: KanalMetrics.lg) {
                    heading
                    actions
                    if let overview { about(overview) }
                    if let cast = details?.cast, !cast.isEmpty { castRow(cast) }
                    if let group = seriesGroup { episodeSection(group) }
                    if isLoading == false && details == nil { noInformation }
                }
                .padding(.horizontal, KanalMetrics.lg)
            }
            .padding(.bottom, KanalMetrics.xxl)
        }
        .background(KanalColor.background)
        .scrollIndicators(.hidden)
        .task(id: item.id) {
            details = await model.metadata.details(for: item)
            isLoading = false
        }
        .task(id: seriesGroup?.id) {
            // A panel lists shows without their episodes; they arrive on
            // request. A flat playlist already has them and this does nothing.
            guard let seriesGroup else { return }
            await model.loadEpisodesIfNeeded(for: seriesGroup)
        }
        .sheet(item: $person, onDismiss: openPending) { member in
            PersonSheet(member: member) { chosen in
                // Opened after this sheet has gone, not during: swapping the
                // screen underneath a modal that is still on top of it is how
                // you end up with a detail screen nobody can reach.
                pendingTitle = chosen
            }
        }
        #if !os(tvOS)
        .presentationBackground(KanalColor.background)
        #endif
    }

    // MARK: Pieces

    @ViewBuilder
    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let url = details?.backdropURL ?? details?.posterURL {
                    Artwork(url: url, title: displayTitle, symbol: item.kind.symbolName)
                } else {
                    EnrichedArtwork(item: item)
                }
            }
            .aspectRatio(KanalMetrics.backdropAspect, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()

            // The image has to hand over to the page without a seam.
            LinearGradient(
                colors: [KanalColor.background.opacity(0), KanalColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            Text(displayTitle)
                .kanalDisplay(KanalMetrics.scale * 30)
                .foregroundStyle(KanalColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: KanalMetrics.sm) {
                if let rating = details?.rating {
                    RatingChip(rating: rating)
                }
                if let year = details?.year ?? item.year {
                    MetaChip(year.formatted(.number.grouping(.never)))
                }
                if let minutes = details?.runtimeMinutes {
                    MetaChip(String(UIStrings.detailRuntime(minutes)))
                }
                // What the provider carries, not what the show has. A chip
                // saying five seasons above three of them is a lie by omission.
                if let carried = seriesGroup.map({ seasonNumbers($0).count }), carried > 0 {
                    MetaChip(String(UIStrings.seasonCount(carried)))
                } else if let seasons = details?.seasonCount, seasons > 0 {
                    MetaChip(String(UIStrings.seasonCount(seasons)))
                }
            }

            if let genres = details?.genres, !genres.isEmpty {
                Text(genres.prefix(3).joined(separator: " · "))
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
            } else if let category = item.category {
                Text(CategoryLocalizer.display(category))
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: KanalMetrics.sm) {
            Button {
                navigator.play(playableItem)
                dismiss()
            } label: {
                Label(playLabel, systemImage: "play.fill")
            }
            .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))

            HStack(spacing: KanalMetrics.sm) {
                Button {
                    model.toggleFavorite(favoriteID)
                } label: {
                    Label(
                        String(isFavorite ? UIStrings.removeFavourite : UIStrings.addFavourite),
                        systemImage: isFavorite ? "heart.fill" : "heart"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(KanalSecondaryButtonStyle(fullWidth: true, size: 13))
            }
        }
    }

    private func about(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            Text(UIStrings.detailOverview)
                .kanalLabel(12)
                .foregroundStyle(KanalColor.tertiaryText)
            Text(text)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func castRow(_ cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            Text(UIStrings.detailCast)
                .kanalLabel(12)
                .foregroundStyle(KanalColor.tertiaryText)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: KanalMetrics.md) {
                    ForEach(cast) { member in
                        Button { person = member } label: {
                            CastPortrait(member: member)
                        }
                        .buttonStyle(KanalCardButtonStyle())
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func episodeSection(_ group: SeriesGroup) -> some View {
        let seasons = seasonNumbers(group)

        VStack(alignment: .leading, spacing: KanalMetrics.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(UIStrings.detailEpisodes)
                    .kanalLabel(12)
                    .foregroundStyle(KanalColor.tertiaryText)
                Spacer()
                if !visibleEpisodes(group).isEmpty {
                    Text(UIStrings.episodeCount(visibleEpisodes(group).count))
                        .font(KanalFont.body(12))
                        .foregroundStyle(KanalColor.tertiaryText)
                }
            }

            if model.isLoadingEpisodes(group) {
                HStack(spacing: KanalMetrics.sm) {
                    ProgressView().controlSize(.small)
                    Text(UIStrings.loadingEpisodes)
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, KanalMetrics.md)

            } else if let failure = model.episodeLoadFailure(for: group) {
                VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                    Text(failure)
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
                    Button(String(UIStrings.tryAgain)) {
                        Task { await model.loadEpisodesIfNeeded(for: group) }
                    }
                    .buttonStyle(KanalSecondaryButtonStyle(size: 13))
                }

            } else {
                // Only worth a picker when there is more than one season to
                // pick between.
                if seasons.count > 1 {
                    seasonPicker(seasons)
                }
                episodeList(group)
            }
        }
    }

    private func seasonPicker(_ seasons: [Int]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: KanalMetrics.sm) {
                ForEach(seasons, id: \.self) { number in
                    Button(String(UIStrings.seasonNumber(number))) {
                        season = number
                    }
                    .buttonStyle(KanalChipButtonStyle(isSelected: selectedSeason(seasons) == number))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// Every episode of the chosen season. Not truncated: a long-running show
    /// is exactly the case where someone is looking for one particular episode.
    private func episodeList(_ group: SeriesGroup) -> some View {
        LazyVStack(spacing: KanalMetrics.sm) {
            ForEach(visibleEpisodes(group)) { episode in
                EpisodeRow(
                    episode: episode,
                    progress: model.progress(for: episode)?.fraction
                ) {
                    navigator.play(episode)
                    dismiss()
                }
            }
        }
    }

    private func seasonNumbers(_ group: SeriesGroup) -> [Int] {
        Array(Set(model.episodes(for: group).compactMap(\.season))).sorted()
    }

    /// Falls back to the first season rather than showing nothing before a
    /// choice has been made.
    private func selectedSeason(_ seasons: [Int]) -> Int? {
        season ?? seasons.first
    }

    private func visibleEpisodes(_ group: SeriesGroup) -> [MediaItem] {
        let all = model.episodes(for: group)
        let seasons = seasonNumbers(group)
        guard seasons.count > 1, let chosen = selectedSeason(seasons) else {
            return all.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
        }
        return all
            .filter { $0.season == chosen }
            .sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    private var noInformation: some View {
        Text(UIStrings.detailNoInfo)
            .font(KanalFont.body(13))
            .foregroundStyle(KanalColor.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Replaces this screen with the title chosen from the person sheet.
    ///
    /// A show arrives as one entry; the detail screen wants the whole run, so
    /// the group is looked up the same way every other screen looks it up.
    private func openPending() {
        guard let chosen = pendingTitle else { return }
        pendingTitle = nil
        let group = chosen.kind == .series ? model.seriesGroup(for: chosen) : nil
        navigator.showDetails(for: chosen, seriesGroup: group)
    }

    // MARK: Values

    private var displayTitle: String {
        details?.title ?? seriesGroup?.name ?? item.seriesName ?? item.title
    }

    private var overview: String? {
        details?.overview.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var favoriteID: String { seriesGroup?.id ?? item.id }
    private var isFavorite: Bool { model.watchState.isFavorite(favoriteID) }

    /// For a show, the episode to start on: where they left off, else the first.
    private var playableItem: MediaItem {
        guard let group = seriesGroup else { return item }
        let episodes = visibleEpisodes(group)
        let unfinished = episodes.first { model.progress(for: $0)?.isWorthResuming == true }
        return unfinished ?? episodes.first ?? item
    }

    private var playLabel: String {
        if model.progress(for: playableItem)?.isWorthResuming == true {
            return String(UIStrings.detailResume)
        }
        if let code = playableItem.episodeCode {
            return String(UIStrings.detailPlayEpisode(code))
        }
        return String(UIStrings.detailPlay)
    }
}

/// A score, shown the way people read one.
struct RatingChip: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text(rating.formatted(.number.precision(.fractionLength(1))))
        }
        .kanalLabel(11)
        .foregroundStyle(KanalColor.primaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(KanalColor.surfaceElevated, in: .capsule)
        .accessibilityLabel(Text(verbatim: "\(rating.formatted(.number.precision(.fractionLength(1)))) / 10"))
    }
}

struct CastPortrait: View {
    let member: CastMember

    var body: some View {
        VStack(spacing: KanalMetrics.xs) {
            Artwork(url: member.profileURL, title: member.name, symbol: "person.fill")
                .frame(width: portrait, height: portrait)
                .clipShape(.circle)

            Text(member.name)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.primaryText)
                .lineLimit(1)
            if let role = member.role {
                Text(role)
                    .font(KanalFont.body(11))
                    .foregroundStyle(KanalColor.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: portrait + 20)
    }

    #if os(tvOS)
    private var portrait: CGFloat { 130 }
    #else
    private var portrait: CGFloat { 72 }
    #endif
}
