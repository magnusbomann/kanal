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
    /// Seconds. Zero duration means live, where scrubbing makes no sense.
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
    /// Live streams have no meaningful length, so the scrubber hides itself.
    var isLive: Bool { duration <= 0 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
