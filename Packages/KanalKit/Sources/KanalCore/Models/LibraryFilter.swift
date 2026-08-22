import Foundation

/// How a browsing screen is narrowed and ordered.
///
/// A provider's catalogue arrives unordered, so alphabetical browsing drops
/// someone into a random action film from 1998. The default here is the order
/// the outside world ranked things in, with the rest as deliberate choices.
public struct LibraryFilter: Sendable, Equatable {

    public enum Sort: String, Sendable, CaseIterable, Identifiable {
        /// What the recommendation rows ranked highest, then everything else.
        case recommended
        case newest
        case oldest
        case alphabetical

        public var id: String { rawValue }
    }

    public var sort: Sort
    /// The provider's own category, kept in their spelling so filters survive
    /// a change of interface language.
    public var category: String?
    /// Two-letter code, only offered when the library actually carries it.
    public var country: String?
    /// The 1990s are `1990`.
    public var decade: Int?

    public init(
        sort: Sort = .recommended,
        category: String? = nil,
        country: String? = nil,
        decade: Int? = nil
    ) {
        self.sort = sort
        self.category = category
        self.country = country
        self.decade = decade
    }

    public var isNarrowed: Bool {
        category != nil || country != nil || decade != nil
    }

    public var activeCount: Int {
        [category != nil, country != nil, decade != nil].count { $0 }
    }
}

public extension Library {

    /// Films, narrowed and ordered.
    ///
    /// - Parameter ranking: entry ids in recommended order, from whatever the
    ///   discovery rows turned up. Empty simply means recommended sorts the
    ///   same as newest.
    func movies(_ filter: LibraryFilter, ranking: [String: Int] = [:]) -> [MediaItem] {
        apply(filter, to: movies, ranking: ranking)
    }

    func series(_ filter: LibraryFilter, ranking: [String: Int] = [:]) -> [SeriesGroup] {
        let narrowed = series.filter { group in
            matches(filter, category: group.category, country: nil, year: group.year)
        }
        return sort(narrowed, by: filter.sort, ranking: ranking,
                    key: { $0.id }, year: { $0.year }, name: { $0.name })
    }

    /// Countries worth offering as a filter, most common first.
    ///
    /// Returns nothing when the library barely carries the field — an empty
    /// control is worse than no control.
    func availableCountries(minimum: Int = 3) -> [String] {
        var counts: [String: Int] = [:]
        for item in items {
            guard let code = item.countryCode?.uppercased(), code.count == 2 else { continue }
            counts[code, default: 0] += 1
        }
        return counts
            .filter { $0.value >= minimum }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    /// Decades the library actually spans.
    func availableDecades(among items: [MediaItem]) -> [Int] {
        Set(items.compactMap { $0.year.map { ($0 / 10) * 10 } })
            .filter { $0 >= 1900 }
            .sorted(by: >)
    }

    // MARK: - Applying

    private func apply(
        _ filter: LibraryFilter, to items: [MediaItem], ranking: [String: Int]
    ) -> [MediaItem] {
        let narrowed = items.filter {
            matches(filter, category: $0.category, country: $0.countryCode, year: $0.year)
        }
        return sort(narrowed, by: filter.sort, ranking: ranking,
                    key: { $0.id }, year: { $0.year }, name: { $0.title })
    }

    private func matches(
        _ filter: LibraryFilter, category: String?, country: String?, year: Int?
    ) -> Bool {
        if let wanted = filter.category, category != wanted { return false }
        if let wanted = filter.country, country?.uppercased() != wanted.uppercased() { return false }
        if let decade = filter.decade {
            guard let year, (year / 10) * 10 == decade else { return false }
        }
        return true
    }

    private func sort<Element>(
        _ elements: [Element],
        by sort: LibraryFilter.Sort,
        ranking: [String: Int],
        key: (Element) -> String,
        year: (Element) -> Int?,
        name: (Element) -> String
    ) -> [Element] {
        switch sort {
        case .alphabetical:
            return elements
                .map { (sortKey: name($0).lowercased(), element: $0) }
                .sorted { $0.sortKey < $1.sortKey }
                .map(\.element)

        case .newest:
            // Entries with no year sink rather than claiming to be oldest.
            return elements.sorted { (year($0) ?? -1) > (year($1) ?? -1) }

        case .oldest:
            return elements.sorted { (year($0) ?? .max) < (year($1) ?? .max) }

        case .recommended:
            // Ranked entries first in their given order, then the newest of
            // whatever is left — an unranked catalogue still opens on
            // something current rather than something arbitrary.
            return elements.sorted { lhs, rhs in
                switch (ranking[key(lhs)], ranking[key(rhs)]) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return (year(lhs) ?? -1) > (year(rhs) ?? -1)
                }
            }
        }
    }
}
