import Foundation
import KanalCore
import Observation

/// What the on-screen controls need from whichever engine is playing.
///
/// Both engines get the same chrome through this. When VLC replaced
/// `AVPlayerViewController` for Matroska, everything that controller gave for
/// free — pause, scrubbing, track selection, a way out — went with it, and the
/// only way to be sure both paths behave alike is to drive them through one
/// interface.
@MainActor
public protocol PlaybackControlling: AnyObject, Observable {
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }
    /// True once playback has run to the end. Reset by starting something new.
    var hasEnded: Bool { get }
    /// Whether this is a broadcast rather than a recording.
    ///
    /// Taken from what the entry *is*, never inferred from its length. A film
    /// has no known duration until its stream has loaded, and a Matroska one
    /// may never report a duration at all — guessing from that put a red LIVE
    /// badge on films and took away the scrubber.
    var isLiveContent: Bool { get }
    /// Seconds. Zero means the length is not known yet, or never will be.
    var position: TimeInterval { get }
    var duration: TimeInterval { get }

    var audioTracks: [PlaybackTrack] { get }
    var subtitleTracks: [PlaybackTrack] { get }
    var selectedAudioTrackID: PlaybackTrack.ID? { get }
    /// Nil means subtitles are off.
    var selectedSubtitleTrackID: PlaybackTrack.ID? { get }

    func togglePlayPause()
    func seek(to seconds: TimeInterval)
    /// Negative skips backwards.
    func skip(by seconds: TimeInterval)
    func selectAudioTrack(_ id: PlaybackTrack.ID?)
    func selectSubtitleTrack(_ id: PlaybackTrack.ID?)
}

public extension PlaybackControlling {
    var isLive: Bool { isLiveContent }

    /// Whether there is a length to scrub through. A live stream never has
    /// one; a recording has one once its stream has said so.
    var isScrubbable: Bool { !isLiveContent && duration > 0 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
