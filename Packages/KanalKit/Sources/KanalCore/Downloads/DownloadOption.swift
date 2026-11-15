import Foundation

/// One version of a film that can be downloaded, and what it would cost.
///
/// The picture is nearly all of a film's size, and providers routinely list
/// the same film several times — 4K, 1080p, 720p. Choosing the version is
/// therefore the one choice that changes the download by a factor rather than
/// a few percent, so it is offered before anything starts.
public struct DownloadOption: Identifiable, Sendable, Hashable {
    public var item: MediaItem
    /// "4K", "1080p", "720p", "SD" — from the provider's own account of the
    /// file when it gives one, from the listing's name when it does not.
    public var quality: String?
    /// Bitrate times running time. Nil when the provider says neither.
    public var estimatedBytes: Int64?

    public var id: String { item.id }

    public init(item: MediaItem, quality: String? = nil, estimatedBytes: Int64? = nil) {
        self.item = item
        self.quality = quality
        self.estimatedBytes = estimatedBytes
    }

    /// Picture height as people say it.
    static func quality(height: Int) -> String {
        switch height {
        case 1600...: "4K"
        case 900...: "1080p"
        case 600...: "720p"
        default: "SD"
        }
    }

    /// Read from a listing's name or tag when the provider gave no facts.
    static func quality(fromName name: String) -> String? {
        let upper = name.uppercased()
        let tokens = Set(upper.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if tokens.contains("4K") || tokens.contains("UHD") || tokens.contains("2160P") || tokens.contains("2160") {
            return "4K"
        }
        if tokens.contains("FHD") || tokens.contains("1080P") || tokens.contains("1080") { return "1080p" }
        if tokens.contains("HD") || tokens.contains("720P") || tokens.contains("720") { return "720p" }
        if tokens.contains("SD") || tokens.contains("480P") { return "SD" }
        return nil
    }
}

extension DownloadOption {
    /// The file's real size, asked of the server itself: one byte requested,
    /// the total read from the answer's headers, the connection dropped.
    ///
    /// Needed because panels commonly leave the bitrate out of their film
    /// info — the measured one gives running time and nothing else. Callers
    /// ask one version at a time: the account allows one connection.
    static func probeSize(of url: URL) async -> Int64? {
        guard !url.isFileURL else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("Kanal/1.0 (AppleCoreMedia)", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        // Not reading the body is what lets the connection go at once.
        bytes.task.cancel()
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last.flatMap({ Int64($0) }), total > 0 {
            return total
        }
        // A server ignoring the range still says how long the whole is —
        // unless it is streaming, which has no length to give.
        if http.statusCode == 200, http.expectedContentLength > 1_000_000 {
            return http.expectedContentLength
        }
        return nil
    }
}

extension XtreamClient {
    /// What the panel says about one film's file, from `get_vod_info`.
    ///
    /// An API request, not a stream: it does not take the account's one
    /// playback connection, so it is safe to ask while something plays.
    func downloadFacts(streamID: Int) async -> (height: Int?, bytes: Int64?) {
        let url = actionURL("get_vod_info", extra: [URLQueryItem(name: "vod_id", value: String(streamID))])
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Kanal/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["info"] as? [String: Any]
        else { return (nil, nil) }

        let video = info["video"] as? [String: Any]
        let height = Self.number(video?["height"]).map(Int.init)
        let seconds = Self.number(info["duration_secs"])
        // Kilobits per second, for the whole file.
        let bitrate = Self.number(info["bitrate"])
        var bytes: Int64?
        if let seconds, let bitrate, seconds > 0, bitrate > 0 {
            bytes = Int64(bitrate * 1000 / 8 * seconds)
        }
        return (height, bytes)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    /// The panel behind a film's stream address, for M3U playlists that came
    /// from an Xtream panel: `/movie/<user>/<password>/<id>.<ext>` carries
    /// everything the API needs.
    static func panel(forMovieStream url: URL) -> (client: XtreamClient, streamID: Int)? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[parts.count - 4] == "movie",
              let id = Int((parts[parts.count - 1] as NSString).deletingPathExtension),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path = ""
        components.query = nil
        guard let portal = components.url else { return nil }
        return (XtreamClient(portal: portal, username: parts[parts.count - 3], password: parts[parts.count - 2]), id)
    }
}
