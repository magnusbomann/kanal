import Foundation

/// Which engine should open a given stream.
///
/// The system player is preferred wherever it works: it brings
/// picture-in-picture, AirPlay, the tvOS transport bar and the system's own
/// subtitle and audio menus, none of which a bundled decoder gets for free.
///
/// It just cannot open Matroska. Measured against a real provider's catalogue,
/// 31,027 of 31,176 films were `.mkv` — so for most of what people actually
/// want to watch, the second engine is not a fallback but the main path.
public enum PlaybackEngine: String, Sendable, Equatable {
    /// AVFoundation.
    case system
    /// Whatever decoder the app supplied, in practice VLC.
    case alternative

    public static func preferred(for item: MediaItem) -> PlaybackEngine {
        let ext = item.streamURL.pathExtension.lowercased()

        // Live streams are HLS or MPEG-TS, which the system handles well.
        if item.kind == .liveTV { return .system }
        // No extension at all: give the system player the first attempt, since
        // an extensionless url is usually a redirect to something standard.
        if ext.isEmpty { return .system }
        return StreamCandidates.native.contains(ext) ? .system : .alternative
    }
}
