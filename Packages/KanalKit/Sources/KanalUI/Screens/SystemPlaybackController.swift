import AVFoundation
import AVKit
import Foundation
import KanalCore
import Observation

/// Playback through AVFoundation.
///
/// Kanal drives `AVPlayer` directly rather than through `AVPlayerViewController`
/// so that both engines can wear the same controls. The controller's chrome is
/// private and cannot be restyled, and imitating it would leave the two paths
/// *nearly* alike — which is the version that looks broken. What is kept from
/// the system are the things a custom layer cannot replace: hardware decoding,
/// picture-in-picture and AirPlay.
@MainActor
@Observable
public final class SystemPlaybackController: PlaybackControlling {

    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var failure: PlaybackFailure?

    public private(set) var audioTracks: [PlaybackTrack] = []
    public private(set) var subtitleTracks: [PlaybackTrack] = []
    public private(set) var selectedAudioTrackID: PlaybackTrack.ID?
    public private(set) var selectedSubtitleTrackID: PlaybackTrack.ID?

    @ObservationIgnored public let player = AVPlayer()

    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var bufferObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleGroup: AVMediaSelectionGroup?

    private var plan: PlaybackPlan?
    private var resumeTarget: TimeInterval?
    private var candidateIndex = 0
    @ObservationIgnored private var timeout: Task<Void, Never>?

    /// The library entry whose stream is actually playing. A channel may carry
    /// several variants, and the one that worked is worth remembering.
    public private(set) var playingOwnerID: String?

    public init() {}

    // MARK: Lifecycle

    public func start(plan: PlaybackPlan, resumingAt resume: TimeInterval?) {
        self.plan = plan
        resumeTarget = resume
        failure = nil
        candidateIndex = 0
        configureAudioSession()
        play(plan.candidates[0], kind: plan.item.kind)
    }

    public func retry() {
        guard let plan else { return }
        start(plan: plan, resumingAt: resumeTarget)
    }

    public func stop() {
        timeout?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation = nil
        bufferObservation = nil
        rateObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    public func snapshot() -> (position: TimeInterval, duration: TimeInterval) {
        (position, duration)
    }

    // MARK: PlaybackControlling

    public func togglePlayPause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    public func seek(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    public func skip(by seconds: TimeInterval) {
        seek(to: max(position + seconds, 0))
    }

    public func selectAudioTrack(_ id: PlaybackTrack.ID?) {
        select(id, in: audioGroup) { self.selectedAudioTrackID = $0 }
    }

    public func selectSubtitleTrack(_ id: PlaybackTrack.ID?) {
        select(id, in: subtitleGroup) { self.selectedSubtitleTrackID = $0 }
    }

    private func select(
        _ id: PlaybackTrack.ID?,
        in group: AVMediaSelectionGroup?,
        update: (PlaybackTrack.ID?) -> Void
    ) {
        guard let group, let item = player.currentItem else { return }
        guard let id else {
            item.select(nil, in: group)
            update(nil)
            return
        }
        guard let option = group.options.first(where: { Self.identifier(for: $0) == id }) else {
            return
        }
        item.select(option, in: group)
        update(id)
    }

    // MARK: Playing one candidate

    private func play(_ url: URL, kind: MediaKind) {
        // A player-style agent keeps providers from refusing the connection.
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Kanal/1.0 (AppleCoreMedia)",
            ]]
        )
        let playerItem = AVPlayerItem(asset: asset)
        // Live streams should join at the edge, not at the start of the buffer.
        playerItem.automaticallyPreservesTimeOffsetFromLive = kind == .liveTV

        observe(playerItem, url: url)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        loadTracks(from: asset, item: playerItem)
        startTimeout(for: url)

        if let resume = resumeTarget, kind != .liveTV {
            seek(to: resume)
        }
    }

    /// An AVI, measured on device, leaves `AVPlayerItem.status` at `.unknown`
    /// indefinitely — no error is ever delivered, so the spinner simply never
    /// stops. A viewer reads that as the app being broken. Giving up after a
    /// while and saying why is the only honest behaviour.
    private func startTimeout(for url: URL) {
        timeout?.cancel()
        // Speculative candidates get less patience than the provider's own url.
        let isLast = plan?.isLast(candidateIndex) ?? true
        let seconds: Double = isLast ? 15 : 6

        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.player.currentItem?.status != .readyToPlay else { return }
                self.advance(after: nil, url: url)
            }
        }
    }

    /// Every candidate before the last is a guess at a format the panel might
    /// also serve, so any failure on one just means the guess was wrong. Only
    /// the provider's own url comes last, and only its failure is worth
    /// reporting.
    private func advance(after error: (any Error)?, url: URL) {
        guard let plan else { return }
        timeout?.cancel()

        guard candidateIndex + 1 < plan.candidates.count else {
            failure = PlaybackFailure(error: error, url: url)
            player.pause()
            return
        }
        candidateIndex += 1
        play(plan.candidates[candidateIndex], kind: plan.item.kind)
    }

    private func observe(_ playerItem: AVPlayerItem, url: URL) {
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .failed: self.advance(after: item.error, url: url)
                case .readyToPlay:
                    self.timeout?.cancel()
                    self.failure = nil
                    self.playingOwnerID = self.plan?.owner(at: self.candidateIndex)
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                default: break
                }
            }
        }
        bufferObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.isBuffering = !item.isPlaybackLikelyToKeepUp }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in self?.isPlaying = player.rate != 0 }
        }

        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if self.duration == 0, let length = self.player.currentItem?.duration.seconds,
                   length.isFinite {
                    self.duration = length
                }
            }
        }
    }

    /// Track lists arrive asynchronously, so the picker fills in shortly after
    /// playback starts rather than blocking it.
    private func loadTracks(from asset: AVURLAsset, item: AVPlayerItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
            self.subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)

            self.audioTracks = (self.audioGroup?.options ?? []).map(Self.track)
            self.subtitleTracks = (self.subtitleGroup?.options ?? []).map(Self.track)

            if let group = self.audioGroup,
               let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
                self.selectedAudioTrackID = Self.identifier(for: selected)
            }
            if let group = self.subtitleGroup,
               let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
                self.selectedSubtitleTrackID = Self.identifier(for: selected)
            }
        }
    }

    static func identifier(for option: AVMediaSelectionOption) -> String {
        "\(option.mediaType.rawValue)|\(option.displayName)|\(option.extendedLanguageTag ?? "")"
    }

    static func track(for option: AVMediaSelectionOption) -> PlaybackTrack {
        PlaybackTrack(
            id: identifier(for: option),
            name: option.displayName,
            languageCode: option.extendedLanguageTag
        )
    }

    private func configureAudioSession() {
        #if !os(macOS)
        // Keeps audio playing when the phone is on silent, as a TV app should.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
