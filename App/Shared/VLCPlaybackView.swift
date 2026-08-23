import KanalCore
import KanalUI
import SwiftUI

// VLCKit 3.7 ships one module per platform. Version 4 unified them but is
// still in alpha, and the decoder is not the place to run one.
#if os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

/// Playback for everything AVFoundation refuses.
///
/// A real provider's catalogue is almost entirely Matroska — 31,027 of 31,176
/// films on the one measured — and `AVPlayer` cannot open a single one. This
/// wears the same `PlayerChrome` as the system path, because two players that
/// look nearly alike read as a bug, and Apple's own chrome cannot be restyled
/// to match.
///
/// Lives in the app target rather than in `KanalKit` so the package, and its
/// tests, stay free of a very large binary dependency.
enum VLCPlayback {
    /// Builds the surface and the controller `PlayerView` will drive.
    @MainActor
    static func handle(for request: AlternativePlayerRequest) -> AlternativePlayerHandle {
        let controller = VLCPlaybackController(request: request)
        return AlternativePlayerHandle(
            surface: AnyView(VLCSurface(controller: controller)),
            controller: controller
        )
    }
}

/// Hands VLC a view to draw into.
struct VLCSurface: UIViewRepresentable {
    let controller: VLCPlaybackController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        // The controller keeps playing otherwise, audio and all.
    }
}

@MainActor
@Observable
final class VLCPlaybackController: PlaybackControlling {

    private(set) var isPlaying = false
    /// From the library entry, not from the stream — see `PlaybackControlling`.
    private(set) var isLiveContent = false
    private(set) var hasEnded = false
    private(set) var isBuffering = true
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var selectedAudioTrackID: PlaybackTrack.ID?
    private(set) var selectedSubtitleTrackID: PlaybackTrack.ID?

    private let request: AlternativePlayerRequest
    @ObservationIgnored private let player = VLCMediaPlayer()
    @ObservationIgnored private var proxy: PlayerDelegateProxy?
    private var hasSeekedToStart = false
    private var hasLoadedTracks = false

    init(request: AlternativePlayerRequest) {
        self.request = request
    }

    func attach(to view: UIView) {
        guard player.media == nil else {
            player.drawable = view
            return
        }

        isLiveContent = request.isLive
        hasEnded = false

        let media = VLCMedia(url: request.url)
        // Providers routinely refuse anything that does not look like a media
        // player, matching what the system path already sends.
        media.addOptions([
            "http-user-agent": "Kanal/1.0 (AppleCoreMedia)",
            // A few seconds of cache is the difference between smooth playback
            // and constant stalling on an ordinary home connection.
            "network-caching": 3000,
        ])

        let proxy = PlayerDelegateProxy(
            onState: { [weak self] state, playing in
                Task { @MainActor in self?.handle(state, isPlaying: playing) }
            },
            onTime: { [weak self] in
                Task { @MainActor in self?.sample() }
            }
        )
        self.proxy = proxy

        player.media = media
        player.drawable = view
        player.delegate = proxy
        player.play()
    }

    func stop() {
        sample()
        player.stop()
    }

    // MARK: PlaybackControlling

    func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
        isPlaying = player.isPlaying
    }

    func seek(to seconds: TimeInterval) {
        player.time = VLCTime(int: Int32(max(seconds, 0) * 1000))
        position = seconds
    }

    func skip(by seconds: TimeInterval) {
        seek(to: max(position + seconds, 0))
    }

    func selectAudioTrack(_ id: PlaybackTrack.ID?) {
        guard let id, let index = Int32(id) as Int32? else { return }
        player.currentAudioTrackIndex = index
        selectedAudioTrackID = id
    }

    func selectSubtitleTrack(_ id: PlaybackTrack.ID?) {
        // VLC uses -1 for "no subtitles" rather than a separate call.
        player.currentVideoSubTitleIndex = id.flatMap { Int32($0) } ?? -1
        selectedSubtitleTrackID = id
    }

    // MARK: Engine callbacks

    private func handle(_ state: VLCMediaPlayerState, isPlaying playing: Bool) {
        isPlaying = playing
        switch state {
        case .playing:
            isBuffering = false
            seekToStartIfNeeded()
            loadTracksIfNeeded()
        case .opening:
            isBuffering = true
        case .buffering:
            // VLC reports buffering continuously while playing too, so this
            // only counts when the picture has actually stopped moving.
            isBuffering = !playing
        case .error:
            isBuffering = false
            request.onFailure(String(localized: CoreStrings.alternativeEngineFailed))
        case .stopped, .ended:
            isBuffering = false
            sample()
            // Only a recording can end; a broadcast that stops has dropped out.
            if state == .ended, !isLiveContent { hasEnded = true }
        default:
            break
        }
    }

    private func sample() {
        position = Double(player.time.intValue) / 1000
        duration = Double(player.media?.length.intValue ?? 0) / 1000
        isPlaying = player.isPlaying
        guard duration > 0 else { return }
        request.onProgress(position, duration)
    }

    /// Resuming has to wait for playback to actually begin — seeking a stream
    /// that has not opened yet is silently ignored.
    private func seekToStartIfNeeded() {
        guard !hasSeekedToStart, let start = request.startAt, start > 1 else { return }
        hasSeekedToStart = true
        seek(to: start)
    }

    /// Track lists only exist once the file is open, so they arrive with the
    /// first `.playing` rather than at construction.
    private func loadTracksIfNeeded() {
        guard !hasLoadedTracks else { return }
        hasLoadedTracks = true

        audioTracks = Self.tracks(
            names: player.audioTrackNames, indexes: player.audioTrackIndexes
        )
        subtitleTracks = Self.tracks(
            names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes
        )
        selectedAudioTrackID = String(player.currentAudioTrackIndex)
        let subtitleIndex = player.currentVideoSubTitleIndex
        selectedSubtitleTrackID = subtitleIndex >= 0 ? String(subtitleIndex) : nil
    }

    /// VLC returns parallel arrays, and includes a "Disable" entry for
    /// subtitles that the chrome already offers as "Off".
    static func tracks(names: [Any], indexes: [Any]) -> [PlaybackTrack] {
        zip(names, indexes).compactMap { name, index in
            guard let title = name as? String,
                  let number = (index as? NSNumber)?.intValue,
                  number >= 0
            else { return nil }
            return PlaybackTrack(
                id: String(number),
                name: title,
                languageCode: Self.languageCode(in: title)
            )
        }
    }

    /// Track names arrive like "Track 1 - [Norwegian]" or "English [eng]".
    static func languageCode(in name: String) -> String? {
        guard let open = name.lastIndex(of: "["), let close = name.lastIndex(of: "]"),
              open < close
        else { return nil }
        let inside = String(name[name.index(after: open)..<close])
        return inside.count == 2 || inside.count == 3 ? inside : nil
    }
}

/// Bridges VLC's delegate onto the main actor.
///
/// `VLCMediaPlayerDelegate` carries no isolation and `VLCMediaPlayer` is not
/// `Sendable`, so rather than assuming which thread VLC calls from, the proxy
/// reads what it needs where the call lands and forwards only values.
private final class PlayerDelegateProxy: NSObject, VLCMediaPlayerDelegate, @unchecked Sendable {
    private let onState: @Sendable (VLCMediaPlayerState, Bool) -> Void
    private let onTime: @Sendable () -> Void

    init(
        onState: @escaping @Sendable (VLCMediaPlayerState, Bool) -> Void,
        onTime: @escaping @Sendable () -> Void
    ) {
        self.onState = onState
        self.onTime = onTime
    }

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let player = aNotification?.object as? VLCMediaPlayer else { return }
        onState(player.state, player.isPlaying)
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        onTime()
    }
}
