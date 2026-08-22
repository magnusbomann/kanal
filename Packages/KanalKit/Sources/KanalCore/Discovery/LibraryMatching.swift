import Foundation

/// Finds the entry in someone's own library that a recommendation refers to.
///
/// Deliberately strict. A shelf headed "Popular on Netflix" that opens the
/// wrong film is worse than a shorter shelf, so a match needs the names to
/// agree outright and the year not to contradict — near-misses are dropped
/// rather than guessed at.
public extension Library {

    /// The library entry for a recommendation, or nil if it isn't carried.
    func item(matching title: DiscoveryTitle) -> MediaItem? {
        let wantedKind: MediaKind = title.isSeries ? .series : .movie

        for name in title.names {
            let normalized = SearchNormalizer.normalize(name)
            guard normalized.count >= 2 else { continue }

            for candidate in search(name, limit: 12) {
                guard candidate.kind == wantedKind else { continue }
                guard namesAgree(candidate, normalized: normalized) else { continue }
                guard yearsAgree(candidate.year, title.year) else { continue }
                return candidate
            }
        }
        return nil
    }

    /// Every entry that matches, in the order the recommendations came in —
    /// which is the order the outside world ranked them.
    func items(matching titles: [DiscoveryTitle], limit: Int = 24) -> [MediaItem] {
        var result: [MediaItem] = []
        var seen = Set<String>()
        for title in titles {
            guard let item = item(matching: title), seen.insert(item.id).inserted else { continue }
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    private func namesAgree(_ item: MediaItem, normalized: String) -> Bool {
        let title = SearchNormalizer.normalize(item.seriesName ?? item.title)
        if title == normalized { return true }
        // Providers append quality and language noise the cleaner missed.
        // A prefix is fine; a title merely *containing* the words is not, or
        // "The Lion King" would match "Making The Lion King".
        return title.hasPrefix(normalized + " ")
    }

    /// Absent years never block a match; disagreeing ones always do.
    private func yearsAgree(_ lhs: Int?, _ rhs: Int?) -> Bool {
        guard let lhs, let rhs else { return true }
        return abs(lhs - rhs) <= 1
    }
}
