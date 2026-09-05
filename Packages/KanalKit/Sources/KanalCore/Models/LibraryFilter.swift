import Foundation

/// How a browsing screen is narrowed and ordered.
///
/// A provider's catalogue arrives unordered, so alphabetical browsing drops
/// someone into a random action film from 1998. The default here is the order
/// the outside world ranked things in, with the rest as deliberate choices.
public struct LibraryFilter: Sendable, Equatable, Hashable {

    public enum Sort: String, Sendable, CaseIterable, Identifiable, Hashable {
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
        var narrowed: [SeriesGroup] = []
        narrowed.reserveCapacity(series.count)
        for (index, group) in series.enumerated() {
            if index.isMultiple(of: 1_024), Task.isCancelled { return [] }
            if matches(filter, category: group.category, country: nil, year: group.year) {
                narrowed.append(group)
            }
        }
        return sort(narrowed, by: filter.sort, ranking: ranking,
                    key: { $0.id }, year: { $0.year }, name: { $0.name })
    }

    /// Countries worth offering as a filter, most common first.
    ///
    /// Returns nothing when the library barely carries the field — an empty
    /// control is worse than no control.
    func availableCountries(minimum: Int = 3) -> [String] {
        availableCountries(among: movies, minimum: minimum)
    }

    func availableCountries(among items: [MediaItem], minimum: Int = 3) -> [String] {
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
        var narrowed: [MediaItem] = []
        narrowed.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 1_024), Task.isCancelled { return [] }
            if matches(
                filter, category: item.category, country: item.countryCode, year: item.year
            ) {
                narrowed.append(item)
            }
        }
        return sort(narrowed, by: filter.sort, ranking: ranking,
                    key: { $0.id }, year: { $0.year }, name: { $0.title })
    }

    private func matches(
        _ filter: LibraryFilter, category: String?, country: String?, year: Int?
    ) -> Bool {
        if let wanted = filter.category {
            let other = String(localized: CoreStrings.otherCategory)
            if wanted == other {
                // Nil categories are presented as a real "Other" bucket.
                // A provider may also literally call its bucket "Other".
                if category != nil, category != wanted { return false }
            } else if category != wanted {
                return false
            }
        }
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
        var entries: [LibrarySortEntry<Element>] = []
        entries.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            if index.isMultiple(of: 1_024), Task.isCancelled { return [] }
            entries.append(LibrarySortEntry(
                element: element,
                ranking: ranking[key(element)],
                year: year(element),
                name: sort == .alphabetical ? name(element).lowercased() : ""
            ))
        }

        let ordered = cancellableMergeSort(entries) { lhs, rhs in
            switch sort {
            case .alphabetical:
                return lhs.name < rhs.name
            case .newest:
                // Entries with no year sink rather than claiming to be oldest.
                return (lhs.year ?? -1) > (rhs.year ?? -1)
            case .oldest:
                return (lhs.year ?? .max) < (rhs.year ?? .max)
            case .recommended:
                // Ranked entries first in their given order, then the newest
                // of whatever is left.
                switch (lhs.ranking, rhs.ranking) {
                case let (left?, right?) where left != right: return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return (lhs.year ?? -1) > (rhs.year ?? -1)
                }
            }
        }
        return ordered.map(\.element)
    }
}

private struct LibrarySortEntry<Element> {
    var element: Element
    var ranking: Int?
    var year: Int?
    var name: String
}

/// Swift's standard sort cannot stop once its caller is cancelled. A full
/// provider catalogue can take long enough that three stale filter requests
/// would otherwise keep running together. This stable merge sort checks at
/// every chunk and hands the shared sort queue back promptly.
private func cancellableMergeSort<Element>(
    _ input: [Element],
    precedes: (Element, Element) -> Bool
) -> [Element] {
    guard input.count > 1 else { return Task.isCancelled ? [] : input }
    var source = input
    var destination = input
    var width = 1

    while width < source.count {
        guard !Task.isCancelled else { return [] }
        var start = 0
        while start < source.count {
            guard !Task.isCancelled else { return [] }
            let middle = min(start + width, source.count)
            let end = min(start + width * 2, source.count)
            var left = start
            var right = middle
            var output = start

            while left < middle, right < end {
                // Prefer the left entry when neither strictly precedes the
                // other, preserving the input order for equal keys.
                if precedes(source[right], source[left]) {
                    destination[output] = source[right]
                    right += 1
                } else {
                    destination[output] = source[left]
                    left += 1
                }
                output += 1
            }
            while left < middle {
                destination[output] = source[left]
                left += 1
                output += 1
            }
            while right < end {
                destination[output] = source[right]
                right += 1
                output += 1
            }
            start = end
        }
        swap(&source, &destination)
        width *= 2
    }
    return source
}
