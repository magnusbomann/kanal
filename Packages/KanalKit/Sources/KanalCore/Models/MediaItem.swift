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
    /// This episode's own title, when the provider wrote one after the code —
    /// "Pilot" in "Breaking Bad S01E01 Pilot".
    public var episodeTitle: String?
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
        episodeTitle: String? = nil,
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
        self.episodeTitle = episodeTitle
        self.season = season
        self.episode = episode
        self.providerSeriesID = providerSeriesID
        self.year = year
        self.qualityTag = qualityTag
    }

    /// The same entry, played from somewhere else — in practice a downloaded
    /// file on this device.
    ///
    /// The id is deliberately unchanged: watch progress, favourites and the
    /// Continue watching row are all keyed by it, and a film watched offline is
    /// the same film.
    public func playing(from url: URL) -> MediaItem {
        var copy = self
        copy.streamURL = url
        return copy
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

// MARK: - Identity without the address

public extension MediaItem {
    /// The id of a playlist entry that brought none of its own.
    ///
    /// It has to change when the address does and stay put otherwise, so it
    /// is made from the title and the stream. But not from the stream's text:
    /// a provider's stream address routinely *is* the login —
    /// `/movie/USER/PASS/123.mkv` — and ids are what favourites and history
    /// are keyed by, which travel to iCloud and into backups. A fingerprint
    /// identifies the address just as well and says nothing about it.
    static func derivedID(rawTitle: String, stream: String) -> String {
        "\(rawTitle)|\(fingerprint(stream))"
    }

    /// FNV-1a, 64 bits. Chosen for speed — this runs once per entry of a
    /// four-hundred-thousand-entry catalogue on every launch.
    static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// An id written by an earlier build, with any address in it replaced by
    /// its fingerprint — the id the same entry is given today.
    ///
    /// Covers the scoped forms too ("<source>|<title>|<address>") and the
    /// "#2" suffix that tells repeated entries apart. Anything without an
    /// address in it comes back unchanged.
    static func scrubbedID(_ id: String) -> String {
        guard let scheme = id.range(of: "://") else { return id }
        // Walk back from "://" over the scheme's letters to the bar before it.
        var start = scheme.lowerBound
        while start > id.startIndex {
            let previous = id.index(before: start)
            let character = id[previous]
            guard character.isLetter || character.isNumber || "+.-".contains(character) else { break }
            start = previous
        }
        guard start > id.startIndex, id[id.index(before: start)] == "|" else { return id }

        var address = id[start...]
        var suffix = ""
        if let hash = address.lastIndex(of: "#"),
           address[address.index(after: hash)...].allSatisfy(\.isNumber),
           address.index(after: hash) < address.endIndex {
            suffix = String(address[hash...])
            address = address[..<hash]
        }
        return id[..<start] + fingerprint(String(address)) + suffix
    }
}
