import Foundation

/// What follows the episode just finished.
///
/// Watching a series is watching a sequence, and stopping dead at the end of
/// every episode makes the viewer do the sequencing by hand. The rule is the
/// obvious one — next episode in the season, then the first of the season
/// after — and it stops at the end rather than looping.
public extension Library {

    /// The show an episode belongs to.
    func seriesGroup(containing episode: MediaItem) -> SeriesGroup? {
        guard let key = episode.seriesKey else { return nil }
        return series.first { $0.id == key }
    }

    /// The next episode of the same show, or nil at the end of the run.
    ///
    /// - Parameter episodes: the show's episodes. Passed in because a panel
    ///   loads them on request, and the copy in the library may be a stub.
    static func nextEpisode(after current: MediaItem, among episodes: [MediaItem]) -> MediaItem? {
        // Ordered the way someone watches: season, then episode. Anything
        // unnumbered sorts last rather than jumping the queue.
        let ordered = episodes.sorted {
            ($0.season ?? .max, $0.episode ?? .max) < ($1.season ?? .max, $1.episode ?? .max)
        }
        guard let index = ordered.firstIndex(where: { $0.id == current.id }) else { return nil }
        let next = ordered.index(after: index)
        guard next < ordered.endIndex else { return nil }

        let candidate = ordered[next]
        // An unnumbered extra is not "the next episode" of anything.
        guard candidate.season != nil || candidate.episode != nil else { return nil }
        return candidate
    }
}
