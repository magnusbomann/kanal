import Foundation

/// A title as some outside source knows it, flattened to what Kanal needs.
public struct ResolvedTitle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// The name it is most likely to be listed under by an IPTV provider —
    /// usually the original or English title.
    public var canonicalName: String
    /// The name a Norwegian viewer would call it, when the source has one.
    public var localizedName: String?
    /// Every name it goes by, deduplicated, canonical first.
    public var allNames: [String]
    public var year: Int?
    public var isSeries: Bool
    public var posterURL: URL?
    public var overview: String?

    public init(
        id: String,
        canonicalName: String,
        localizedName: String? = nil,
        allNames: [String],
        year: Int? = nil,
        isSeries: Bool = false,
        posterURL: URL? = nil,
        overview: String? = nil
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.localizedName = localizedName
        self.allNames = ResolvedTitle.deduplicate(allNames)
        self.year = year
        self.isSeries = isSeries
        self.posterURL = posterURL
        self.overview = overview
    }

    static func deduplicate(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { name in
            let key = SearchNormalizer.normalize(name)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    /// True when one of this title's names is exactly what was typed.
    public func matches(normalizedQuery query: String) -> Bool {
        allNames.contains { SearchNormalizer.normalize($0) == query }
    }

    public func loosonMatches(normalizedQuery query: String) -> Bool {
        allNames.contains { SearchNormalizer.normalize($0).hasPrefix(query) }
    }
}

/// Somewhere Kanal can ask what a title is called elsewhere.
///
/// Deliberately narrow. Kanal needs one thing above all — the other names a
/// film goes by — and that is cheap enough to get from a free, key-less source.
/// Artwork is a bonus that only some providers can offer.
public protocol MetadataProvider: Sendable {
    var providerName: String { get }
    /// Whether this source can supply poster artwork.
    var providesArtwork: Bool { get }

    func lookup(name: String, year: Int?, isSeries: Bool?) async throws -> [ResolvedTitle]
}
