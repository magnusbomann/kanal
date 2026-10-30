import AVFoundation
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
        enableEngineLogging()
        let controller = VLCPlaybackController(request: request)
        return AlternativePlayerHandle(
            surface: AnyView(VLCSurface(controller: controller)),
            controller: controller
        )
    }

    /// Lets libvlc say what it is doing.
    ///
    /// The engine's own account is the only place a decoder or video-output
    /// failure is written down — `VLCMediaPlayerState` reports "opening" and
    /// then nothing, which is indistinguishable from a slow line. Debug builds
    /// only: this is verbose, and a release build has nowhere to put it.
    #if DEBUG
    private nonisolated(unsafe) static var hasEnabledLogging = false

    @MainActor
    private static func enableEngineLogging() {
        guard !hasEnabledLogging else { return }
        hasEnabledLogging = true
        let logger = VLCConsoleLogger()
        logger.level = .debug
        VLCLibrary.shared().loggers = [logger]
    }
    #else
    @MainActor
    private static func enableEngineLogging() {}
    #endif
}

/// Hands VLC a view to draw into.
struct VLCSurface: UIViewRepresentable {
    let controller: VLCPlaybackController

    func makeUIView(context: Context) -> VLCHostView {
        let view = VLCHostView()
        view.backgroundColor = .black
        view.onReady = { host in controller.attach(to: host) }
        view.onDismantle = { controller.stop() }
        return view
    }

    func updateUIView(_ view: VLCHostView, context: Context) {}

    static func dismantleUIView(_ view: VLCHostView, coordinator: ()) {
        // The controller keeps playing otherwise, audio and all — and not every
        // way out of a player runs the code that closes it deliberately.
        view.onDismantle?()
        view.onReady = nil
        view.onDismantle = nil
    }
}

/// The view VLC draws into, which does not admit to existing too early.
///
/// `makeUIView` hands back a view with no size that is in no window yet, and
/// VLC builds its video output from whatever it is given at the moment it is
/// given it. A zero-sized, unparented drawable is tolerated by the simulator's
/// software renderer and is not tolerated by the real one on an Apple TV: the
/// stream opens, buffers, and never produces a picture — with no error, since
/// as far as libvlc is concerned nothing failed.
///
/// So playback waits for the one moment that is actually safe: a real size,
/// inside a real window.
final class VLCHostView: UIView {
    var onReady: ((UIView) -> Void)?
    var onDismantle: (() -> Void)?
    private var hasStarted = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        startIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        startIfReady()
    }

    private func startIfReady() {
        guard !hasStarted, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        hasStarted = true
        onReady?(self)
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
    private var hasReportedReady = false
    private var hasStopped = false
    /// The view on the phone. The film is drawn here unless a mirrored
    /// television has taken it — see `ExternalDisplay`.
    @ObservationIgnored private weak var localView: UIView?
    @ObservationIgnored private var displayObserver: (any NSObjectProtocol)?
    #if os(iOS)
    /// Set while the film is being carried to an AirPlay television. VLC is
    /// stopped meanwhile; every control is forwarded here instead.
    @ObservationIgnored private var relay: AirPlayRelay?
    @ObservationIgnored private var relayView: RelayPlayerView?
    @ObservationIgnored private var relayPolling: Task<Void, Never>?
    @ObservationIgnored private var routeObserver: (any NSObjectProtocol)?
    /// A failed attempt is not retried until the person picks a television
    /// again, so a film that cannot be carried never loops.
    @ObservationIgnored private var relayBlocked = false
    /// Where VLC picks up again after a failed attempt.
    @ObservationIgnored private var resumeAfterRelay: TimeInterval?
    #endif

    init(request: AlternativePlayerRequest) {
        self.request = request
    }

    func attach(to view: UIView) {
        guard !hasStopped else { return }
        localView = view
        guard player.media == nil else {
            player.drawable = drawable
            return
        }
        #if os(iOS)
        displayObserver = NotificationCenter.default.addObserver(
            forName: ExternalDisplay.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hasStopped else { return }
                self.player.drawable = self.drawable
            }
        }
        if !request.isLive {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.routeChanged() }
            }
        }
        #endif

        isLiveContent = request.isLive
        hasEnded = false

        let media = VLCMedia(url: request.url)
        // Providers routinely refuse anything that does not look like a media
        // player, matching what the system path already sends.
        media.addOptions([
            "http-user-agent": "Kanal/1.0 (AppleCoreMedia)",
            // A few seconds of cache is the difference between smooth playback
            // and constant stalling on an ordinary home connection.
            //
            // Deliberately left where it is. This one is paid for in startup
            // time — VLC fills it before it shows anything — and a film that
            // begins at once is worth more than a longer cushion.
            "network-caching": 3000,
            // The read-ahead, which is where a real cushion comes from. It runs
            // in its own thread and keeps filling regardless of what the
            // player is doing, so a pause now builds a reserve instead of
            // stopping three seconds in. In KiB: 64 MiB against a default of
            // 16, which on an Apple TV is a rounding error next to the
            // catalogue and buys minutes rather than seconds on an ordinary
            // film.
            "prefetch-buffer-size": 65536,
            // Providers drop long-lived connections routinely, and a film is a
            // long-lived connection. Without this, a drop that VLC could have
            // resumed from ends the stream instead.
            "http-reconnect": true,
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
        player.drawable = drawable
        player.delegate = proxy
        player.play()
    }

    /// Ends playback for good.
    ///
    /// `stop()` alone is not enough. It returns before libvlc has finished
    /// tearing the input down, and a player that still holds its media, its
    /// drawable and its delegate can keep decoding audio into a screen that is
    /// no longer on — which is heard as a film still running behind the app.
    /// Releasing what it holds is what actually ends it, and the delegate goes
    /// first so nothing that arrives on the way out is acted on.
    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        sample()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        #if os(iOS)
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        endRelay()
        #endif
        player.delegate = nil
        proxy = nil
        player.stop()
        player.drawable = nil
        player.media = nil
        isPlaying = false
        isBuffering = false
    }

    // MARK: AirPlay

    #if os(iOS)
    /// Picking a television in the route picker arrives here as a route
    /// change. Nothing else ever starts the relay.
    private func routeChanged() {
        guard !hasStopped, !request.isLive, hasReportedReady else { return }
        guard let route = AirPlayRelay.airPlayRouteID else {
            relayBlocked = false
            return
        }
        // A HomePod or other speaker is AirPlay too, but takes no picture.
        // Once one has shown that, films stay in VLC while it is chosen.
        guard relay == nil, !relayBlocked, !Self.audioOnlyRoutes.contains(route) else { return }
        beginRelay(route: route)
    }

    /// AirPlay receivers found to take sound only, for the life of the app.
    private static var audioOnlyRoutes: Set<String> = []

    private func beginRelay(route: String) {
        let start = Double(player.time.intValue) / 1000
        let language = audioTracks.first { $0.id == selectedAudioTrackID }?.languageCode
        let relay = AirPlayRelay(url: request.url, userAgent: "Kanal/1.0 (AppleCoreMedia)", language: language)
        self.relay = relay
        // The provider allows one connection. VLC lets go of it before the
        // repackager asks for it.
        player.stop()
        isBuffering = true

        if let host = localView {
            let view = RelayPlayerView(player: relay.player)
            view.frame = host.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(view)
            relayView = view
        }

        relay.start(at: start) { [weak self] outcome in
            guard let self, self.relay === relay else { return }
            switch outcome {
            case .started:
                self.pollRelay(route: route)
            case .failed(let position):
                self.returnToVLC(at: position)
            }
        }
    }

    private func pollRelay(route: String) {
        relayPolling?.cancel()
        let started = Date.now
        relayPolling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let relay = self.relay else { return }
                self.position = relay.position
                if relay.duration > 0 { self.duration = relay.duration }
                self.isPlaying = relay.isPlaying
                self.isBuffering = relay.isBuffering
                if relay.hasEnded { self.hasEnded = true }
                if relay.hasRunDry {
                    // Picked up by VLC on the phone rather than left frozen.
                    self.returnToVLC(at: relay.position)
                    return
                }
                // Video goes to the receiver only if it can show it. If after
                // a few seconds it has not, this was a speaker, and VLC
                // plays better than a repackaged copy does on the phone.
                if !relay.player.isExternalPlaybackActive,
                   AirPlayRelay.airPlayRouteID == route,
                   Date.now.timeIntervalSince(started) > 4 {
                    Self.audioOnlyRoutes.insert(route)
                    self.returnToVLC(at: relay.position)
                    return
                }
                if self.duration > 0 { self.request.onProgress(self.position, self.duration) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Hands the film back to VLC on the phone, where the relay left it.
    /// Not tried again until the person picks a receiver anew.
    private func returnToVLC(at position: TimeInterval) {
        endRelay()
        relayBlocked = true
        resumeAfterRelay = position
        isBuffering = true
        player.play()
    }

    private func endRelay() {
        relayPolling?.cancel()
        relayPolling = nil
        relay?.stop()
        relay = nil
        relayView?.removeFromSuperview()
        relayView = nil
    }
    #endif

    /// Where the picture goes: the television while one is mirrored, the
    /// phone otherwise.
    private var drawable: UIView? {
        #if os(iOS)
        if let external = ExternalDisplay.shared.surface { return external }
        #endif
        return localView
    }

    // MARK: PlaybackControlling

    func togglePlayPause() {
        #if os(iOS)
        if let relay {
            relay.togglePlayPause()
            isPlaying = relay.isPlaying
            return
        }
        #endif
        if player.isPlaying { player.pause() } else { player.play() }
        isPlaying = player.isPlaying
    }

    func seek(to seconds: TimeInterval) {
        #if os(iOS)
        if let relay {
            relay.seek(to: seconds)
            position = seconds
            return
        }
        #endif
        player.time = VLCTime(int: Int32(max(seconds, 0) * 1000))
        position = seconds
    }

    func skip(by seconds: TimeInterval) {
        seek(to: max(position + seconds, 0))
    }

    func selectAudioTrack(_ id: PlaybackTrack.ID?) {
        guard let id, let index = Int32(id) as Int32? else { return }
        #if os(iOS)
        if let relay {
            relay.selectAudioLanguage(audioTracks.first { $0.id == id }?.languageCode)
            selectedAudioTrackID = id
            return
        }
        #endif
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
        #if os(iOS)
        // VLC is stopped on purpose while the television plays; what it
        // says about that is not news.
        guard relay == nil else { return }
        #endif
        isPlaying = playing
        // A player that is playing has started, whatever state the notification
        // happened to carry. VLCKit coalesces state changes, so reading
        // `player.state` when the callback lands can step straight past
        // `.playing` — and a stream that is demonstrably running must never be
        // mistaken for one that never started.
        if playing { reportStarted() }
        switch state {
        case .playing:
            reportStarted()
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
        #if os(iOS)
        guard relay == nil else { return }
        #endif
        position = Double(player.time.intValue) / 1000
        duration = Double(player.media?.length.intValue ?? 0) / 1000
        isPlaying = player.isPlaying
        // The clock moving is the least deniable evidence there is that this
        // stream started, and it arrives even when no state change did.
        if position > 0 { reportStarted() }
        guard duration > 0 else { return }
        request.onProgress(position, duration)
    }

    /// Says, once, that there is a picture.
    private func reportStarted() {
        isBuffering = false
        if !hasReportedReady {
            hasReportedReady = true
            request.onReady()
        }
        seekToStartIfNeeded()
        loadTracksIfNeeded()
        #if os(iOS)
        if let resume = resumeAfterRelay {
            resumeAfterRelay = nil
            seek(to: resume)
        }
        // Picked before the film had started: carry it now.
        routeChanged()
        #endif
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

        // The language libvlc parsed out of the container, by track id.
        //
        // Worth the extra lookup: measured across fourteen children's films on
        // a real provider, every one declared a proper `nor`/`dan`/`swe` code,
        // while two of them titled every track "Stereo". Reading the name and
        // hoping would have failed those two outright — and they were The Lion
        // King and Inside Out 2.
        let languages = Self.languagesByTrackID(in: player.media)
        audioTracks = Self.tracks(
            names: player.audioTrackNames,
            indexes: player.audioTrackIndexes,
            languages: languages
        )
        subtitleTracks = Self.tracks(
            names: player.videoSubTitlesNames,
            indexes: player.videoSubTitlesIndexes,
            languages: languages
        )
        selectedAudioTrackID = String(player.currentAudioTrackIndex)
        let subtitleIndex = player.currentVideoSubTitleIndex
        selectedSubtitleTrackID = subtitleIndex >= 0 ? String(subtitleIndex) : nil
    }

    /// VLC returns parallel arrays, and includes a "Disable" entry for
    /// subtitles that the chrome already offers as "Off".
    static func tracks(
        names: [Any], indexes: [Any], languages: [Int: String] = [:]
    ) -> [PlaybackTrack] {
        zip(names, indexes).compactMap { name, index in
            guard let title = name as? String,
                  let number = (index as? NSNumber)?.intValue,
                  number >= 0
            else { return nil }
            return PlaybackTrack(
                id: String(number),
                name: title,
                // What the container declared, before what the label implies.
                languageCode: languages[number] ?? Self.languageCode(in: title)
            )
        }
    }

    /// Track id to declared language, read from the container itself.
    ///
    /// `tracksInformation` is only populated once the media has been parsed,
    /// which by the first `.playing` it has been. An empty result simply
    /// leaves every track to be identified by its name, as before.
    static func languagesByTrackID(in media: VLCMedia?) -> [Int: String] {
        guard let rows = media?.tracksInformation as? [[String: Any]] else { return [:] }
        var result: [Int: String] = [:]
        for row in rows {
            guard let id = (row[VLCMediaTracksInformationId] as? NSNumber)?.intValue,
                  let language = row[VLCMediaTracksInformationLanguage] as? String,
                  !language.isEmpty
            else { continue }
            result[id] = language
        }
        return result
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

#if os(iOS)
/// Shows the relayed film on the phone too — black with the system's own
/// "playing on" treatment while the television has it, the picture again if
/// the person takes it back.
final class RelayPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        (layer as? AVPlayerLayer)?.player = player
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { nil }
}
#endif

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

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        onState(player.state, player.isPlaying)
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        onTime()
    }
}
