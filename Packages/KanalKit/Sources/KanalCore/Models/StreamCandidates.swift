import Foundation

/// Which URLs are worth trying for one entry, and in what order.
///
/// AVFoundation plays a narrow set of containers. Measured on device:
///
/// | container | result |
/// | --- | --- |
/// | `.mp4`, `.m4v`, `.mov`, `.ts`, `.m3u8` | plays |
/// | `.mkv` | fails, `-11828 Cannot Open` |
/// | `.avi` | fails, `-11829 Cannot Open` |
///
/// IPTV panels serve most of their film and series catalogue as MKV, which is
/// why live TV works and nothing else does. Many panels will however serve the
/// same stream in another container if simply asked for it by extension, so
/// before reporting failure Kanal tries the ones Apple can actually open.
public enum StreamCandidates {

    /// Containers AVFoundation opens.
    public static let native: Set<String> = ["m3u8", "mp4", "m4v", "mov", "ts", "mpd"]

    /// Containers it refuses, however well-formed.
    public static let foreign: Set<String> = [
        "mkv", "avi", "wmv", "flv", "webm", "divx", "rmvb", "ogv", "3gp", "mpg", "mpeg",
    ]

    /// Extensions worth asking a panel for, best first. HLS leads because a
    /// panel that transcodes will hand back something that also seeks properly.
    private static let preferred = ["m3u8", "mp4", "ts"]

    /// True when Apple's player has no chance with this url as written.
    public static func isForeign(_ url: URL) -> Bool {
        foreign.contains(url.pathExtension.lowercased())
    }

    /// URLs to attempt, in order. Always ends with the provider's own url, so
    /// a failure is reported against what they actually published.
    public static func candidates(for item: MediaItem) -> [URL] {
        let url = item.streamURL
        let ext = url.pathExtension.lowercased()

        // Live streams and already-playable containers need no help.
        guard item.kind != .liveTV, !ext.isEmpty, !native.contains(ext) else {
            return [url]
        }

        var result: [URL] = []
        for candidate in preferred where candidate != ext {
            result.append(url.deletingPathExtension().appendingPathExtension(candidate))
        }
        result.append(url)
        return result
    }
}
