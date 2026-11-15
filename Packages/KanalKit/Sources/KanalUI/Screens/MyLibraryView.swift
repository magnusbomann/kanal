import KanalCore
import SwiftUI

/// Everything this household has told the app to keep: downloads, favourites
/// and the history behind Continue watching.
///
/// One screen for all three because they are one idea — the things you put
/// there yourself, as opposed to the hundreds of thousands of things your
/// provider put there. And because the request that produced this screen was
/// really one request: *let me take things off my home screen again.*
public struct MyLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @Environment(DownloadStore.self) private var downloads: DownloadStore?

    @State private var section: LibrarySection
    @State private var confirmingClear = false

    public init(section: LibrarySection = .downloads) {
        self._section = State(initialValue: section)
    }

    public var body: some View {
        VStack(spacing: 0) {
            picker
            content
        }
        .background(KanalColor.background)
        .navigationTitle(Text(UIStrings.libraryTitle))
        // Emptying a whole section is the one action here that cannot be
        // undone by tapping again, so it asks first.
        .confirmationDialog(
            Text(clearTitle ?? String(UIStrings.libraryTitle)),
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            if let clearTitle {
                Button(clearTitle, role: .destructive, action: clear)
            }
            Button(String(UIStrings.cancel), role: .cancel) {}
        } message: {
            Text(UIStrings.libraryClearConfirm)
        }
    }

    private var picker: some View {
        Picker("", selection: $section) {
            Text(UIStrings.librarySectionDownloads).tag(LibrarySection.downloads)
            Text(UIStrings.librarySectionFavourites).tag(LibrarySection.favourites)
            Text(UIStrings.librarySectionContinue).tag(LibrarySection.continueWatching)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, KanalMetrics.lg)
        .padding(.top, KanalMetrics.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .downloads: downloadsSection
        case .favourites: favouritesSection
        case .continueWatching: continueSection
        }
    }

    // MARK: Downloads

    @ViewBuilder
    private var downloadsSection: some View {
        if let downloads, !visibleDownloads.isEmpty {
            List {
                if downloads.isHeldForPlayback, !downloads.inProgress.isEmpty {
                    Text(UIStrings.downloadHeld)
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
                }
                ForEach(visibleDownloads) { record in
                    DownloadRow(record: record) { play(record, in: downloads) }
                        .kanalRowActions(
                            title: String(
                                record.isFinished ? UIStrings.downloadRemove : UIStrings.downloadCancel
                            )
                        ) {
                            downloads.remove(record.id)
                        }
                }
                storageFooter(downloads)
                clearRow
            }
            .kanalPlainListBackground()
        } else {
            EmptyStateView(
                symbol: "arrow.down.circle",
                title: String(UIStrings.downloadsEmptyTitle),
                message: String(UIStrings.downloadsEmptyBody)
            )
        }
    }

    /// The downloads this profile may know about.
    ///
    /// Downloads belong to the device, not to a profile, so a film a parent
    /// saved for themselves sat in a child's library with its title and
    /// poster — unplayable, but visible, and removable. A restricted profile
    /// is shown what its own rules allow and nothing else.
    private var visibleDownloads: [Download] {
        guard let downloads else { return [] }
        guard model.isRestricted else { return downloads.downloads }
        return downloads.downloads.filter { model.canPlay($0.item) }
    }

    @ViewBuilder
    private func storageFooter(_ downloads: DownloadStore) -> some View {
        VStack(alignment: .leading, spacing: KanalMetrics.xs) {
            Text(UIStrings.downloadsStorage(DownloadSize.text(
                visibleDownloads.reduce(Int64(0)) { $0 + $1.byteCount }
            )))
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
            #if os(tvOS)
            // Said plainly rather than discovered later: on Apple TV the system
            // owns this space and can take it back.
            Text(UIStrings.downloadsTelevisionNote)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
        .listRowBackground(Color.clear)
    }

    /// Plays a finished download straight from the file. An unfinished one is
    /// not offered: half a film is not something to open.
    private func play(_ record: Download, in downloads: DownloadStore) {
        guard record.isFinished,
              let file = downloads.playableFile(for: record.item, sourceID: record.sourceID)
        else { return }
        navigator.play(record.item.playing(from: file))
    }

    // MARK: Favourites

    @ViewBuilder
    private var favouritesSection: some View {
        let channels = model.favoriteChannelGroups
        let movies = model.favoriteMovies
        let series = model.favoriteSeries

        if channels.isEmpty, movies.isEmpty, series.isEmpty {
            EmptyStateView(
                symbol: "heart",
                title: String(UIStrings.favouritesEmptyTitle),
                message: String(UIStrings.favouritesEmptyBody)
            )
        } else {
            List {
                ForEach(channels) { group in
                    TitleRow(
                        title: group.primary.title,
                        subtitle: model.nowPlaying(on: group)?.title,
                        artworkURL: group.primary.logoURL,
                        symbol: MediaKind.liveTV.symbolName
                    ) {
                        navigator.play(group, remembered: model.watchState.workingVariants[group.id])
                    }
                    .kanalRowActions(title: String(UIStrings.removeFavourite)) {
                        model.removeFavorite(favoriteID(for: group))
                    }
                }
                ForEach(movies) { movie in
                    TitleRow(
                        title: movie.title,
                        subtitle: movie.year.map(String.init),
                        artworkURL: movie.logoURL,
                        symbol: MediaKind.movie.symbolName,
                        enrich: movie
                    ) {
                        navigator.showDetails(for: movie)
                    }
                    .kanalRowActions(title: String(UIStrings.removeFavourite)) {
                        model.removeFavorite(movie.id)
                    }
                }
                ForEach(series) { group in
                    TitleRow(
                        title: group.name,
                        subtitle: group.year.map(String.init),
                        artworkURL: group.artworkURL,
                        symbol: MediaKind.series.symbolName,
                        enrich: group.episodes.first
                    ) {
                        navigator.push(.series(id: group.id))
                    }
                    .kanalRowActions(title: String(UIStrings.removeFavourite)) {
                        model.removeFavorite(group.id)
                    }
                }
                clearRow
            }
            .kanalPlainListBackground()
        }
    }

    /// Favourites predate channel grouping and are stored against one stream,
    /// so removal has to find the stream that was marked.
    private func favoriteID(for group: ChannelGroup) -> String {
        group.variants.first { model.watchState.isFavorite($0.id) }?.id ?? group.primary.id
    }

    // MARK: Continue watching

    @ViewBuilder
    private var continueSection: some View {
        let resumable = model.continueWatching
        let channels = model.recentChannelGroups

        if resumable.isEmpty, channels.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: String(UIStrings.continueEmptyTitle),
                message: String(UIStrings.continueEmptyBody)
            )
        } else {
            List {
                ForEach(resumable) { item in
                    TitleRow(
                        title: item.seriesName ?? item.title,
                        subtitle: resumeSubtitle(item),
                        artworkURL: item.logoURL,
                        symbol: item.kind.symbolName,
                        enrich: item.kind == .liveTV ? nil : item
                    ) {
                        navigator.play(item)
                    }
                    .kanalRowActions(title: String(UIStrings.historyRemove)) {
                        model.forgetProgress(for: item)
                    }
                }
                ForEach(channels) { group in
                    TitleRow(
                        title: group.primary.title,
                        subtitle: model.nowPlaying(on: group)?.title,
                        artworkURL: group.primary.logoURL,
                        symbol: MediaKind.liveTV.symbolName
                    ) {
                        navigator.play(group, remembered: model.watchState.workingVariants[group.id])
                    }
                    .kanalRowActions(title: String(UIStrings.recentChannelRemove)) {
                        model.forgetChannel(group)
                    }
                }
                clearRow
            }
            .kanalPlainListBackground()
        }
    }

    private func resumeSubtitle(_ item: MediaItem) -> String? {
        guard let progress = model.progress(for: item) else { return nil }
        let minutes = Int(progress.remaining / 60)
        return minutes >= 1
            ? String(UIStrings.minutesLeft(minutes))
            : String(UIStrings.nearlyFinished)
    }

    // MARK: Clearing a whole section

    /// At the foot of the list rather than in the navigation bar: emptying a
    /// section is the last thing on the screen, not the first, and a
    /// destructive action next to Back is one crowded tap away from an accident.
    @ViewBuilder
    private var clearRow: some View {
        if let clearTitle {
            Button(clearTitle, role: .destructive) { confirmingClear = true }
                .font(KanalFont.body(14))
                .listRowBackground(Color.clear)
        }
    }

    private var clearTitle: String? {
        switch section {
        case .downloads:
            visibleDownloads.isEmpty ? nil : String(UIStrings.downloadsRemoveAll)
        case .favourites:
            model.watchState.favoriteIDs.isEmpty ? nil : String(UIStrings.favouritesClearAll)
        case .continueWatching:
            model.continueWatching.isEmpty && model.recentChannelGroups.isEmpty
                ? nil
                : String(UIStrings.historyClear)
        }
    }

    private func clear() {
        switch section {
        case .downloads:
            // Only what this profile can see — never a grown-up's films from
            // a child's screen.
            if model.isRestricted {
                visibleDownloads.forEach { downloads?.remove($0.id) }
            } else {
                downloads?.removeAll()
            }
        case .favourites: model.clearFavorites()
        case .continueWatching: model.clearWatchHistory()
        }
    }
}

/// A row in the library: artwork, two lines, and a way to remove it.
struct TitleRow: View {
    let title: String
    var subtitle: String?
    var artworkURL: URL?
    var symbol: String
    /// Set for a film or an episode, so the row shows the real poster rather
    /// than the provider's monogram placeholder. Left nil for a channel, whose
    /// own logo is the right picture.
    var enrich: MediaItem?
    var accessory: AnyView?
    var action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        artworkURL: URL? = nil,
        symbol: String,
        enrich: MediaItem? = nil,
        accessory: AnyView? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.symbol = symbol
        self.enrich = enrich
        self.accessory = accessory
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: KanalMetrics.md) {
                Group {
                    if let enrich {
                        EnrichedArtwork(item: enrich, symbol: symbol)
                    } else {
                        Artwork(url: artworkURL, title: title, symbol: symbol, contentMode: .fit)
                    }
                }
                    .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
                    .background(KanalColor.surfaceElevated)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KanalFont.section(15))
                        .foregroundStyle(KanalColor.primaryText)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(KanalFont.body(12))
                            .foregroundStyle(KanalColor.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: KanalMetrics.sm)
                if let accessory { accessory }
            }
            .padding(.vertical, KanalMetrics.xs)
            .frame(minHeight: KanalMetrics.minTarget)
        }
        .buttonStyle(KanalCardButtonStyle())
    }

    private var thumbnailWidth: CGFloat {
        #if os(tvOS)
        180
        #else
        76
        #endif
    }
}

/// A download's own row: the same shape as every other, with its state where
/// the subtitle goes.
struct DownloadRow: View {
    let record: Download
    let action: () -> Void

    var body: some View {
        TitleRow(
            title: record.item.title,
            subtitle: DownloadSummary.text(record),
            artworkURL: record.item.logoURL,
            symbol: record.item.kind.symbolName,
            enrich: record.item,
            accessory: AnyView(accessory),
            action: action
        )
    }

    @ViewBuilder
    private var accessory: some View {
        switch record.state {
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(KanalColor.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(KanalColor.warning)
        case .waiting, .downloading:
            if let fraction = record.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .tint(KanalColor.accentSolid)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

extension View {
    /// The way a row is removed on each platform: a swipe where there is a
    /// finger, a long press where there is a remote.
    @ViewBuilder
    func kanalRowActions(title: String, perform: @escaping () -> Void) -> some View {
        contextMenu {
            Button(title, role: .destructive, action: perform)
        }
        #if !os(tvOS)
        .swipeActions(edge: .trailing) {
            Button(title, role: .destructive, action: perform)
        }
        #endif
    }
}
