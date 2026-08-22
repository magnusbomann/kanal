import Foundation

/// Where a library comes from.
///
/// The user never picks one of these. They paste a string, Kanal works out
/// which case it is, and the choice only ever surfaces as a label.
public enum SourceKind: String, Codable, Sendable, Hashable {
    /// A plain `.m3u` / `.m3u8` URL we fetch and parse.
    case m3u
    /// Xtream Codes: a portal host plus username and password, which gives us
    /// categories, series metadata and EPG for free.
    case xtream
    /// Playlist text the user pasted or a file they imported.
    case localFile
}

public struct PlaylistSource: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var kind: SourceKind
    /// User-facing name. Defaults to the host, renameable later.
    public var name: String

    /// For `.m3u` and `.localFile`: the playlist location.
    public var playlistURL: URL?
    /// For `.xtream`: the portal root, e.g. `http://example.com:8080`.
    public var portalURL: URL?
    public var username: String?
    public var password: String?

    /// EPG location. Discovered automatically; only set by hand as a fallback.
    public var epgURL: URL?

    public var createdAt: Date
    public var lastRefreshedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: SourceKind,
        name: String,
        playlistURL: URL? = nil,
        portalURL: URL? = nil,
        username: String? = nil,
        password: String? = nil,
        epgURL: URL? = nil,
        createdAt: Date = .now,
        lastRefreshedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.playlistURL = playlistURL
        self.portalURL = portalURL
        self.username = username
        self.password = password
        self.epgURL = epgURL
        self.createdAt = createdAt
        self.lastRefreshedAt = lastRefreshedAt
    }
}
