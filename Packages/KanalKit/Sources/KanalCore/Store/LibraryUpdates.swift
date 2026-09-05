import Foundation

/// The titles that appeared when a TV service last changed its catalogue.
///
/// Providers rarely supply a trustworthy "added at" value, and plain M3U
/// playlists do not have one at all. Comparing two successful catalogue loads
/// works for both kinds of service and, importantly, never calls an old title
/// new merely because the provider rotated the token in its stream URL.
public struct LibraryUpdates: Codable, Sendable, Equatable {
    public static let maximumDisplayAge: TimeInterval = 14 * 24 * 60 * 60

    public var movieKeys: [String]
    public var seriesKeys: [String]
    public var detectedAt: Date?

    public init(
        movieKeys: [String] = [],
        seriesKeys: [String] = [],
        detectedAt: Date? = nil
    ) {
        self.movieKeys = movieKeys
        self.seriesKeys = seriesKeys
        self.detectedAt = detectedAt
    }

    public var isEmpty: Bool { movieKeys.isEmpty && seriesKeys.isEmpty }

    public func isRecent(
        at date: Date = .now,
        maximumAge: TimeInterval = LibraryUpdates.maximumDisplayAge
    ) -> Bool {
        guard let detectedAt else { return false }
        let age = date.timeIntervalSince(detectedAt)
        return age >= 0 && age <= maximumAge
    }

    public var expirationDate: Date? {
        detectedAt?.addingTimeInterval(Self.maximumDisplayAge)
    }

    /// Finds additions between two non-empty snapshots.
    ///
    /// A first import has no "last time" to compare with, so it deliberately
    /// returns an empty result instead of labelling the whole service as new.
    public static func detect(
        previous: Library,
        current: Library,
        at date: Date = .now
    ) -> LibraryUpdates {
        guard !previous.isEmpty, !current.isEmpty else { return LibraryUpdates() }

        let knownMovies = Set(previous.movies.map(movieKey))
        var seenMovies = Set<String>()
        let movieKeys = current.movies.compactMap { movie -> String? in
            let key = movieKey(movie)
            guard !knownMovies.contains(key), seenMovies.insert(key).inserted else { return nil }
            return key
        }

        let knownSeries = Set(previous.series.map(seriesKey))
        var seenSeries = Set<String>()
        let seriesKeys = current.series.compactMap { series -> String? in
            let key = seriesKey(series)
            guard !knownSeries.contains(key), seenSeries.insert(key).inserted else { return nil }
            return key
        }

        guard !movieKeys.isEmpty || !seriesKeys.isEmpty else { return LibraryUpdates() }
        return LibraryUpdates(movieKeys: movieKeys, seriesKeys: seriesKeys, detectedAt: date)
    }

    /// Stable across signed/expiring URL changes. A missing year intentionally
    /// favours "already known" over flooding Home with false additions.
    public static func movieKey(_ item: MediaItem) -> String {
        let title = SearchNormalizer.normalize(item.title)
        return "\(title)|\(item.year.map(String.init) ?? "unknown")"
    }

    public static func seriesKey(_ group: SeriesGroup) -> String {
        if let providerID = group.providerSeriesID { return "provider|\(providerID)" }
        let title = SearchNormalizer.normalize(group.name)
        return "\(title)|\(group.year.map(String.init) ?? "unknown")"
    }
}

/// The already-resolved rows Home renders.
///
/// A real catalogue can contain hundreds of thousands of entries. Resolving
/// ids while SwiftUI redraws would repeatedly walk that catalogue, so AppModel
/// rebuilds this small snapshot only when the library or watch state changes.
public struct HomeContent: Sendable {
    public var continueWatching: [MediaItem]
    public var nextEpisodes: [MediaItem]
    public var recentChannels: [ChannelGroup]
    public var newMovies: [MediaItem]
    public var newSeries: [SeriesGroup]

    public init(
        continueWatching: [MediaItem] = [],
        nextEpisodes: [MediaItem] = [],
        recentChannels: [ChannelGroup] = [],
        newMovies: [MediaItem] = [],
        newSeries: [SeriesGroup] = []
    ) {
        self.continueWatching = continueWatching
        self.nextEpisodes = nextEpisodes
        self.recentChannels = recentChannels
        self.newMovies = newMovies
        self.newSeries = newSeries
    }
}
