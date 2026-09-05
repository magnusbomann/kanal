import Foundation

/// Which unrated titles to spend the first age lookups on.
///
/// A restricted profile is an allowlist: a film appears only once a board has
/// been consulted about it. Verification works through every unrated title in
/// the approved sections — tens of thousands of them on a real provider, at a
/// rate TMDB is entitled to limit — and it worked through them in whatever
/// order the panel happened to send.
///
/// That is the second half of why a child's Home looked random. Even once the
/// rows ask the right question, the well-known children's film they want to
/// lead with is invisible until its turn comes round, which could be days.
/// Meanwhile the row falls below its minimum and collapses to the catalogue's
/// own order.
///
/// So the titles the recommendations are about to ask for go first. This
/// changes **when** an answer arrives, never what the answer is or what it
/// permits: the board still decides, and an unrated title is still hidden.
public enum DiscoveryVerificationOrder {

    /// Normalised title to its position in the recommendations, best first.
    ///
    /// Matched by name alone rather than through `Library.item(matching:)`.
    /// Ordering a queue does not need the year check that displaying a row
    /// does — the cost of being wrong here is verifying a film slightly
    /// earlier than it deserved, and the strict matcher would mean building a
    /// search index over the whole catalogue for no better answer.
    public static func ranking(for shelves: [DiscoveryShelf]) -> [String: Int] {
        var ranking: [String: Int] = [:]
        var position = 0
        for shelf in shelves {
            for title in shelf.titles {
                for name in title.names {
                    let key = SearchNormalizer.normalize(name)
                    guard key.count >= 2, ranking[key] == nil else { continue }
                    ranking[key] = position
                    position += 1
                }
            }
        }
        return ranking
    }

    /// The same pool, with everything the rows want at the front.
    ///
    /// A stable partition rather than a sort: whatever order the pool arrived
    /// in is the order the rest keeps, so the queue stays predictable between
    /// passes and nothing is starved by being renamed.
    public static func prioritised(
        _ items: [MediaItem], by ranking: [String: Int]
    ) -> [MediaItem] {
        guard !ranking.isEmpty else { return items }

        var wanted: [(rank: Int, item: MediaItem)] = []
        var rest: [MediaItem] = []
        rest.reserveCapacity(items.count)

        for item in items {
            let name = SearchNormalizer.normalize(item.seriesName ?? item.title)
            if let rank = ranking[name] {
                wanted.append((rank, item))
            } else {
                rest.append(item)
            }
        }
        guard !wanted.isEmpty else { return items }
        return wanted.sorted { $0.rank < $1.rank }.map(\.item) + rest
    }
}
