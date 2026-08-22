import Foundation

/// Search over a whole library.
///
/// Built once per refresh rather than per keystroke: providers ship libraries
/// of 50,000 entries, and normalising those on every character typed would
/// stutter. The index is a sorted postings list, so a prefix lookup is two
/// binary searches and no scan.
public struct SearchIndex: Sendable {

    /// One searchable entry, pre-normalised.
    struct Entry: Sendable {
        let itemIndex: Int
        /// Normalised primary title — what ranking is measured against.
        let title: String
        /// Everything searchable, including the provider's raw string.
        let haystack: String
    }

    private let entries: [Entry]
    /// `(token, entryIndex)` sorted by token, for prefix lookups.
    private let postings: [Posting]

    struct Posting: Sendable {
        let token: String
        let entry: Int
    }

    public init(items: [MediaItem]) {
        var entries: [Entry] = []
        var postings: [Posting] = []
        entries.reserveCapacity(items.count)

        for (itemIndex, item) in items.enumerated() {
            let title = SearchNormalizer.normalize(item.title)

            // The provider's own spelling is searchable too: someone who knows
            // their list as "NO| VIAPLAY SPORT 1 FHD" should find it that way.
            var parts = [item.title, item.rawTitle]
            parts.append(contentsOf: item.alternateTitles)
            if let seriesName = item.seriesName { parts.append(seriesName) }
            if let category = item.category { parts.append(category) }

            let haystack = SearchNormalizer.normalize(parts.joined(separator: " "))
            let entryIndex = entries.count
            entries.append(Entry(itemIndex: itemIndex, title: title, haystack: haystack))

            for token in Set(haystack.split(separator: " ").map(String.init)) {
                postings.append(Posting(token: token, entry: entryIndex))
            }
        }

        postings.sort { $0.token < $1.token }
        self.entries = entries
        self.postings = postings
    }

    public static let empty = SearchIndex(items: [])

    /// Item indices, best match first.
    ///
    /// Every query token must prefix-match a word — "lion k" finds "The Lion
    /// King" but "lionk" does not, which is the behaviour people expect from a
    /// search field that updates as they type.
    public func search(_ query: String, limit: Int = 200) -> [Int] {
        let tokens = SearchNormalizer.tokenize(query)
        guard !tokens.isEmpty else { return [] }

        var candidates: Set<Int>?
        for token in tokens {
            let matches = entryIndices(withPrefix: token)
            if matches.isEmpty { return [] }
            candidates = candidates.map { $0.intersection(matches) } ?? matches
            if candidates?.isEmpty == true { return [] }
        }
        guard let candidates else { return [] }

        let normalizedQuery = tokens.joined(separator: " ")
        return candidates
            .map { (entry: $0, score: score(entry: $0, query: normalizedQuery, tokens: tokens)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return entries[lhs.entry].title < entries[rhs.entry].title
            }
            .prefix(limit)
            .map { entries[$0.entry].itemIndex }
    }

    // MARK: - Lookup

    private func entryIndices(withPrefix prefix: String) -> Set<Int> {
        var low = 0
        var high = postings.count
        while low < high {
            let mid = (low + high) / 2
            if postings[mid].token < prefix { low = mid + 1 } else { high = mid }
        }

        var result: Set<Int> = []
        var index = low
        while index < postings.count, postings[index].token.hasPrefix(prefix) {
            result.insert(postings[index].entry)
            index += 1
        }
        return result
    }

    /// Ranking, strongest signal first. The length penalty is what puts
    /// "Frost" above "Frost Fishing Championship 2019" for the query "frost".
    private func score(entry index: Int, query: String, tokens: [String]) -> Int {
        let entry = entries[index]
        var score = 0

        if entry.title == query {
            score = 1000
        } else if entry.title.hasPrefix(query) {
            score = 600
        } else if entry.title.contains(query) {
            score = 400
        } else if tokens.allSatisfy({ token in wordPrefixMatch(entry.title, token) }) {
            score = 300
        } else {
            // Matched only through the raw title, series name or category.
            score = 120
        }

        score -= min(entry.title.count, 120)
        return score
    }

    private func wordPrefixMatch(_ haystack: String, _ token: String) -> Bool {
        haystack.split(separator: " ").contains { $0.hasPrefix(token) }
    }
}
