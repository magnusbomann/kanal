import Foundation

/// Something the outside world says is worth watching.
///
/// Kanal never shows one of these directly — a recommendation for a film the
/// viewer's provider does not carry is worse than no recommendation. They are
/// only ever used to *order* and *group* what is already in the library.
public struct DiscoveryTitle: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// Every name it goes by, so matching works whatever the provider called it.
    public var names: [String]
    public var year: Int?
    public var isSeries: Bool
    public var posterPath: String?
    public var overview: String?
    public var popularity: Double

    public init(
        id: Int,
        names: [String],
        year: Int? = nil,
        isSeries: Bool = false,
        posterPath: String? = nil,
        overview: String? = nil,
        popularity: Double = 0
    ) {
        self.id = id
        self.names = DiscoveryTitle.deduplicate(names)
        self.year = year
        self.isSeries = isSeries
        self.posterPath = posterPath
        self.overview = overview
        self.popularity = popularity
    }

    public var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
    }

    public var displayName: String { names.first ?? "" }

    static func deduplicate(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { name in
            let key = SearchNormalizer.normalize(name)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }
}

/// A row of recommendations, and where it came from.
public struct DiscoveryShelf: Codable, Sendable, Identifiable, Hashable {
    public enum Source: Codable, Sendable, Hashable {
        case trending
        case newReleases
        /// A streaming service, by its id and name in the viewer's region.
        case service(id: Int, name: String)
    }

    public var id: String
    public var source: Source
    public var kind: MediaKind
    public var titles: [DiscoveryTitle]
    public var fetchedAt: Date

    public init(id: String, source: Source, kind: MediaKind, titles: [DiscoveryTitle], fetchedAt: Date = .now) {
        self.id = id
        self.source = source
        self.kind = kind
        self.titles = titles
        self.fetchedAt = fetchedAt
    }
}
