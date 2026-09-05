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
    /// Stops playback and releases the stream.
    ///
    /// Part of the protocol because closing the player has to stop whichever
    /// engine is running. Stopping only the built-in one left VLC playing
    /// audio after the screen had gone, which reads as a close button that
    /// does nothing.
    func stop()
    func seek(to seconds: TimeInterval)
    /// Negative skips backwards.
    func skip(by seconds: TimeInterval)
    func selectAudioTrack(_ id: PlaybackTrack.ID?)
    func selectSubtitleTrack(_ id: PlaybackTrack.ID?)

    /// Whether another stream carries the same channel.
    ///
    /// Defaulted, because only the engine that walks a `PlaybackPlan` has
    /// feeds to walk between. A film has one source and the control never
    /// appears over it.
    var canSwitchSource: Bool { get }
    /// True while the old feed has been let go and the new one has not opened.
    var isSwitchingSource: Bool { get }
    /// Which feed this is, counting from one, and how many exist.
    var sourceNumber: Int { get }
    var sourceCount: Int { get }
    /// Give up on this feed and try the next one carrying the same channel.
    func switchSource()
}

public extension PlaybackControlling {
    var isLive: Bool { isLiveContent }

    var canSwitchSource: Bool { false }
    var isSwitchingSource: Bool { false }
    var sourceNumber: Int { 1 }
    var sourceCount: Int { 1 }
    func switchSource() {}

    /// Whether there is a length to scrub through. A live stream never has
    /// one; a recording has one once its stream has said so.
    var isScrubbable: Bool { !isLiveContent && duration > 0 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
