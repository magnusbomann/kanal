import Foundation

/// A known age limit for one title, and where it came from.
///
/// The provenance is not decoration. "Verified" is the promise this feature
/// makes to a parent, and a rating read off a national board is a different
/// claim from one guessed out of a category name — so the app records which it
/// has and only ever calls the first kind verified.
public struct ContentRating: Codable, Sendable, Hashable {

    public enum Source: String, Codable, Sendable, Hashable {
        /// A national film board, via TMDB's certification data.
        case board
        /// An age limit the provider wrote into the entry itself ("18+").
        case provider
        /// A grown-up approved this title by hand.
        case parent
    }

    public var rating: MaturityRating
    public var source: Source
    /// ISO country of the board that issued it, when there was one.
    public var country: String?
    public var recordedAt: Date

    public init(
        rating: MaturityRating,
        source: Source,
        country: String? = nil,
        recordedAt: Date = .now
    ) {
        self.rating = rating
        self.source = source
        self.country = country
        self.recordedAt = recordedAt
    }

    /// Whether this rating is strong enough to open a restricted profile on
    /// its own. A provider's own "18+" is trusted to *deny* but never to
    /// permit: panels label the adult section reliably and label everything
    /// else not at all, so the absence of a marker means nothing.
    public var isVerified: Bool { source == .board || source == .parent }
}

/// How a rating is filed so it survives a refresh.
///
/// Entry ids are built from the provider's stream URL, and those rotate — a
/// panel reissues tokens, and every rating keyed to one would be lost. The
/// title and year do not rotate, so that is the key.
public enum RatingKey {

    public static func of(_ item: MediaItem) -> String {
        make(title: item.seriesName ?? item.title, year: item.kind == .series ? nil : item.year)
    }

    public static func of(_ group: SeriesGroup) -> String {
        make(title: group.name, year: nil)
    }

    public static func make(title: String, year: Int?) -> String {
        let normalized = SearchNormalizer.normalize(title)
        guard let year else { return normalized }
        return "\(normalized)|\(year)"
    }
}

/// Every rating Kanal has learned, keyed by `RatingKey`.
///
/// One flat dictionary, persisted whole. Even a household that watches a
/// thousand different films stores well under a megabyte, and a single file
/// means a corrupt cache costs re-fetching rather than a broken launch.
public struct RatingIndex: Codable, Sendable {

    public private(set) var entries: [String: ContentRating]

    public init(entries: [String: ContentRating] = [:]) {
        self.entries = entries
    }

    public static let fileName = "content-ratings.json"

    public subscript(key: String) -> ContentRating? { entries[key] }

    public func rating(for item: MediaItem) -> ContentRating? { entries[RatingKey.of(item)] }

    /// Records a rating, keeping the stronger claim when one already exists.
    ///
    /// Strength is provenance first, then strictness. A parent's decision beats
    /// a board's, a board's beats a provider marker, and between two of equal
    /// standing the higher age wins — the same "round up, never down" rule that
    /// governs `MaturityRating.nearest`.
    public mutating func record(_ rating: ContentRating, for key: String) {
        guard let existing = entries[key] else {
            entries[key] = rating
            return
        }
        if rank(rating.source) > rank(existing.source) {
            entries[key] = rating
        } else if rank(rating.source) == rank(existing.source), rating.rating > existing.rating {
            entries[key] = rating
        }
    }

    public mutating func remove(_ key: String) {
        entries[key] = nil
    }

    private func rank(_ source: ContentRating.Source) -> Int {
        switch source {
        case .parent: 3
        case .board: 2
        case .provider: 1
        }
    }
}
