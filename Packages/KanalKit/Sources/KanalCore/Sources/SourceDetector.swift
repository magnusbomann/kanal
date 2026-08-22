import Foundation

/// Works out what a pasted string actually is.
///
/// This is the whole of Kanal's setup screen. Providers hand out URLs in half a
/// dozen shapes — `get.php` links with credentials in the query, bare portal
/// hosts, `/playlist/user/pass/m3u` paths, plain `.m3u8` files — and every other
/// app makes the user classify them. We classify instead.
public enum SourceDetector {

    public enum Detection: Sendable, Equatable {
        /// Enough information to build a source and start loading.
        case complete(PlaylistSource)
        /// A portal we recognised, but credentials are still missing.
        case needsCredentials(portal: URL, host: String)
        /// Playlist text pasted straight into the field.
        case pastedText(String)
        /// Not a URL we can use.
        case unrecognized(reason: String)
    }

    public static func detect(_ input: String) -> Detection {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unrecognized(reason: String(localized: CoreStrings.detectEmpty))
        }

        // Raw playlist text pasted straight in.
        if trimmed.hasPrefix("#EXTM3U") {
            return .pastedText(trimmed)
        }

        guard let url = normalizedURL(from: trimmed) else {
            return .unrecognized(reason: String(localized: CoreStrings.detectUnusable))
        }
        let host = url.host() ?? "Playlist"

        // 1. Xtream credentials carried in the query string.
        if let credentials = xtreamCredentialsFromQuery(url) {
            return .complete(
                PlaylistSource(
                    kind: .xtream,
                    name: host,
                    portalURL: portalRoot(of: url),
                    username: credentials.username,
                    password: credentials.password
                )
            )
        }

        // 2. Xtream credentials carried in the path: /playlist/USER/PASS/m3u
        if let credentials = xtreamCredentialsFromPath(url) {
            return .complete(
                PlaylistSource(
                    kind: .xtream,
                    name: host,
                    portalURL: portalRoot(of: url),
                    username: credentials.username,
                    password: credentials.password
                )
            )
        }

        // 3. A direct playlist file.
        let ext = url.pathExtension.lowercased()
        if ext == "m3u" || ext == "m3u8" {
            return .complete(
                PlaylistSource(kind: .m3u, name: host, playlistURL: url)
            )
        }

        // 4. A bare host, or a portal endpoint with no credentials on it.
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || Self.portalEndpoints.contains(where: { path.hasSuffix($0) }) {
            return .needsCredentials(portal: portalRoot(of: url), host: host)
        }

        // 5. Anything else that is still an http(s) URL: try it as a playlist.
        // Plenty of providers serve M3U from an extensionless path.
        return .complete(PlaylistSource(kind: .m3u, name: host, playlistURL: url))
    }

    /// Builds a source once the user supplies credentials for a bare portal.
    public static func xtreamSource(
        portal: URL,
        username: String,
        password: String,
        name: String? = nil
    ) -> PlaylistSource {
        PlaylistSource(
            kind: .xtream,
            name: name ?? portal.host() ?? "Provider",
            portalURL: portalRoot(of: portal),
            username: username,
            password: password
        )
    }

    // MARK: - Pieces

    private static let portalEndpoints = [
        "get.php", "player_api.php", "panel_api.php", "xmltv.php", "portal.php",
    ]

    /// Accepts input without a scheme, and tolerates the `m3u://` and
    /// `iptv://` schemes some providers hand out in QR codes.
    static func normalizedURL(from input: String) -> URL? {
        var text = input
        for scheme in ["m3u://", "m3u8://", "iptv://", "xtream://"] {
            if text.lowercased().hasPrefix(scheme) {
                text = "http://" + text.dropFirst(scheme.count)
            }
        }
        if !text.lowercased().hasPrefix("http://"), !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    static func portalRoot(of url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme ?? "http"
        components.host = url.host()
        components.port = url.port
        return components.url ?? url
    }

    static func xtreamCredentialsFromQuery(_ url: URL) -> (username: String, password: String)? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        let lookup = Dictionary(
            items.compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard let username = lookup["username"], let password = lookup["password"],
              !username.isEmpty, !password.isEmpty
        else { return nil }
        return (username, password)
    }

    /// Matches `/playlist/USER/PASS/m3u` and `/live/USER/PASS/...`.
    static func xtreamCredentialsFromPath(_ url: URL) -> (username: String, password: String)? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 3 else { return nil }
        let leadingKeywords: Set<String> = ["playlist", "live", "get", "iptv"]
        guard let first = components.first?.lowercased(), leadingKeywords.contains(first) else {
            return nil
        }
        let username = components[1]
        let password = components[2]
        guard !username.isEmpty, !password.isEmpty else { return nil }
        return (username, password)
    }
}
