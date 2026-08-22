import Foundation

/// A single playable entry: a live channel, a movie, or one episode.
///
/// One flat type on purpose — playlists arrive as a flat list and every
/// grouping in the app is a *view* over these, computed at load time.
public struct MediaItem: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var kind: MediaKind

    /// Cleaned, human-facing title ("Breaking Bad", not "EN | Breaking Bad S01E04 1080p").
    public var title: String
    /// Exactly as it appeared in the playlist. Kept for search and debugging.
    public var rawTitle: String
    /// Other names this thing goes by — localised titles, original-language
    /// titles, common abbreviations. Populated by metadata enrichment; the
    /// search index treats them as first-class.
    public var alternateTitles: [String] = []

    public var streamURL: URL
    public var logoURL: URL?
    /// Group as declared by the provider (`group-title`), pre-cleanup.
    public var rawGroup: String?
    /// Normalized category ("Sports", "Nordic", "Documentary").
    public var category: String?

    /// XMLTV channel id, when the provider supplies one (`tvg-id`).
    public var channelID: String?
    /// Channel number (`tvg-chno`), used for numeric ordering when present.
    public var channelNumber: Int?
    public var language: String?
    public var countryCode: String?

    // Series grouping — only set when `kind == .series`.
    public var seriesName: String?
    public var season: Int?
    public var episode: Int?
    /// The provider's own id for the show, when the source is a panel that can
    /// list episodes on request. Nil for flat M3U playlists, where every
    /// episode is already its own entry.
    public var providerSeriesID: Int?

    public var year: Int?
    public var qualityTag: String?

    public init(
        id: String,
        kind: MediaKind,
        title: String,
        rawTitle: String,
        alternateTitles: [String] = [],
        streamURL: URL,
        logoURL: URL? = nil,
        rawGroup: String? = nil,
        category: String? = nil,
        channelID: String? = nil,
        channelNumber: Int? = nil,
        language: String? = nil,
        countryCode: String? = nil,
        seriesName: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        providerSeriesID: Int? = nil,
        year: Int? = nil,
        qualityTag: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rawTitle = rawTitle
        self.alternateTitles = alternateTitles
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.rawGroup = rawGroup
        self.category = category
        self.channelID = channelID
        self.channelNumber = channelNumber
        self.language = language
        self.countryCode = countryCode
        self.seriesName = seriesName
        self.season = season
        self.episode = episode
        self.providerSeriesID = providerSeriesID
        self.year = year
        self.qualityTag = qualityTag
    }

    /// Key used to fold episodes of the same show together.
    public var seriesKey: String? {
        guard kind == .series, let seriesName else { return nil }
        return seriesName.lowercased()
    }

    /// "S01E04" for episode rows.
    public var episodeCode: String? {
        guard let season, let episode else { return nil }
        return String(format: "S%02dE%02d", season, episode)
    }
}
