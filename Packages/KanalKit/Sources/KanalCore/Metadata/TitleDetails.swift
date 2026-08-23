import Foundation

/// Enough about a film or show to decide whether to watch it.
///
/// Deliberately not everything TMDB knows. The question this answers is "what
/// am I about to put on?", so it carries what someone glances at — a picture,
/// a rating, how long it is, roughly what happens, and who is in it — and
/// nothing they would have to read.
public struct TitleDetails: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var isSeries: Bool
    public var title: String
    public var overview: String?
    public var year: Int?
    public var genres: [String]
    /// Out of ten, as TMDB scores it. Nil when too few people have voted for
    /// the number to mean anything.
    public var rating: Double?
    public var runtimeMinutes: Int?
    public var seasonCount: Int?
    public var episodeCount: Int?
    public var posterPath: String?
    public var backdropPath: String?
    public var cast: [CastMember]

    public init(
        id: Int,
        isSeries: Bool,
        title: String,
        overview: String? = nil,
        year: Int? = nil,
        genres: [String] = [],
        rating: Double? = nil,
        runtimeMinutes: Int? = nil,
        seasonCount: Int? = nil,
        episodeCount: Int? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        cast: [CastMember] = []
    ) {
        self.id = id
        self.isSeries = isSeries
        self.title = title
        self.overview = overview
        self.year = year
        self.genres = genres
        self.rating = rating
        self.runtimeMinutes = runtimeMinutes
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.cast = cast
    }

    public var posterURL: URL? { TMDBImage.url(posterPath, width: 500) }
    public var backdropURL: URL? { TMDBImage.url(backdropPath, width: 1280) }

    /// Whether there is enough here to be worth a screen of its own.
    public var isSubstantial: Bool {
        overview?.isEmpty == false || !cast.isEmpty || !genres.isEmpty
    }
}

/// Someone in it, and who they played.
public struct CastMember: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var name: String
    public var role: String?
    public var profilePath: String?

    public init(id: Int, name: String, role: String? = nil, profilePath: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.profilePath = profilePath
    }

    public var profileURL: URL? { TMDBImage.url(profilePath, width: 185) }
}

/// A person, and what else they are in.
public struct PersonProfile: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var name: String
    public var biography: String?
    public var profilePath: String?
    public var knownFor: [KnownRole]

    public init(
        id: Int, name: String, biography: String? = nil,
        profilePath: String? = nil, knownFor: [KnownRole] = []
    ) {
        self.id = id
        self.name = name
        self.biography = biography
        self.profilePath = profilePath
        self.knownFor = knownFor
    }

    public var profileURL: URL? { TMDBImage.url(profilePath, width: 300) }
}

public struct KnownRole: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var title: String
    public var isSeries: Bool
    public var posterPath: String?
    public var popularity: Double

    public init(id: Int, title: String, isSeries: Bool, posterPath: String?, popularity: Double) {
        self.id = id
        self.title = title
        self.isSeries = isSeries
        self.posterPath = posterPath
        self.popularity = popularity
    }

    public var posterURL: URL? { TMDBImage.url(posterPath, width: 342) }
}

enum TMDBImage {
    static func url(_ path: String?, width: Int) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w\(width)\(path)")
    }
}
