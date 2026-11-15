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
    /// From the library entry, not from the stream. See `PlaybackControlling`.
    public private(set) var isLiveContent = false
    public private(set) var hasEnded = false
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
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleGroup: AVMediaSelectionGroup?

    private var plan: PlaybackPlan?
    private var resumeTarget: TimeInterval?
    private var candidateIndex = 0
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var pendingOpen: Task<Void, Never>?

    /// True while one feed has been let go and the next has not yet arrived.
    ///
    /// Separate from `isBuffering` because it means something different to the
    /// person watching: buffering is this picture catching up, switching is a
    /// different picture on its way. A spinner that says neither is what makes
    /// a four-second wait feel like a hang.
    public private(set) var isSwitchingSource = false
    /// Which feed is being watched, counting from one, and how many there are.
    public private(set) var sourceNumber = 1
    public private(set) var sourceCount = 1

    /// The library entry whose stream is actually playing. A channel may carry
    /// several variants, and the one that worked is worth remembering.
    public private(set) var playingOwnerID: String?

    public init() {}

    // MARK: Lifecycle

    public func start(plan: PlaybackPlan, resumingAt resume: TimeInterval?) {
        isLiveContent = plan.item.kind == .liveTV
        hasEnded = false
        self.plan = plan
        resumeTarget = resume
        failure = nil
        sourceCount = plan.variantCount
        configureAudioSession()
        #if os(iOS)
        // AirPlay proper rather than a mirrored picture, also while the phone
        // is mirroring: the app owns the mirrored screen (see the iOS app's
        // ExternalDisplay), and leaving this off would draw nothing there.
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        open(candidate: 0, settling: false)
    }

    public func retry() {
        guard let plan else { return }
        start(plan: plan, resumingAt: resumeTarget)
    }

    public func stop() {
        timeout?.cancel()
        pendingOpen?.cancel()
        isSwitchingSource = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
        bufferObservation = nil
        rateObservation = nil
        isBuffering = false
        release()
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

    // MARK: Choosing a feed

    /// Whether there is another stream carrying this channel to fall back on.
    public var canSwitchSource: Bool { (plan?.variantCount ?? 1) > 1 }

    /// Move to the next feed because the viewer said this one is no good.
    ///
    /// Deliberately a single step with no list attached. A provider's own
    /// wording for its feeds — "Norway Sport", "All Sport", "50FPS" — describes
    /// where the entry was filed, not what the picture looks like, so offering
    /// it as a menu asks the viewer to choose on information they do not have.
    /// One button that means "not this one, try another" asks nothing.
    ///
    /// Wraps around rather than running out: someone who has been through every
    /// feed is usually better served by the first one again than by a dead end.
    public func switchSource() {
        guard let plan, canSwitchSource else { return }
        let next = plan.nextVariantStart(after: candidateIndex) ?? 0
        failure = nil
        open(candidate: next, settling: true)
    }

    /// Opens one candidate, optionally pausing first.
    ///
    /// A provider account is commonly allowed a single connection at a time —
    /// the test panel's `max_connections` is exactly 1 — and the slot the old
    /// stream held is not free the moment the socket closes: measured there,
    /// `active_cons` fell to zero 40 to 50 seconds after a stream was
    /// abandoned. Releasing the current item before asking for the next, and
    /// letting a beat pass, is what keeps the replacement from being refused
    /// the connection its predecessor is still holding.
    private func open(candidate index: Int, settling: Bool) {
        guard let plan, plan.candidates.indices.contains(index) else { return }
        timeout?.cancel()
        pendingOpen?.cancel()

        candidateIndex = index
        sourceNumber = plan.variantNumber(at: index)
        hasRetriedForConnection = false
        release()

        guard settling else {
            play(plan.candidates[index], kind: plan.item.kind)
            return
        }
        // Stays true until the new feed is actually on screen, not until the
        // request goes out — the wait a viewer feels is the several seconds
        // before the picture returns, and that is the whole span the label has
        // to cover. Cleared on `readyToPlay`, or when a failure is reported.
        isSwitchingSource = true
        pendingOpen = Task { [weak self] in
            try? await Task.sleep(for: Self.connectionSettle)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let plan = self.plan else { return }
                self.play(plan.candidates[index], kind: plan.item.kind)
            }
        }
    }

    /// Long enough for the socket to be gone before the next one opens, short
    /// enough that nobody reads it as a stall. Measured against the panel, the
    /// gap barely moves the median — around four seconds either way — but an
    /// overlapping request is the one thing that reliably gets refused.
    private static let connectionSettle: Duration = .milliseconds(700)

    /// Lets go of the current stream without tearing down the controller.
    private func release() {
        if player.currentItem != nil { Self.noteStreamReleased() }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// When any player in the app last let go of a stream.
    ///
    /// A provider that counts connections goes on counting one for a while
    /// after it closes, and answers the next request with its "offline" clip.
    /// That is worth one patient retry — but only then. With nothing recently
    /// released, the same clip means what it says, and retrying it only makes
    /// someone wait twice to be told a channel is off the air.
    private static var lastStreamRelease: ContinuousClock.Instant?

    /// Called by whichever engine closes a stream, this one or the second.
    public static func noteStreamReleased() {
        lastStreamRelease = .now
    }

    private static var releasedAStreamRecently: Bool {
        guard let lastStreamRelease else { return false }
        return ContinuousClock.now - lastStreamRelease < .seconds(60)
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
        // Opening is waiting, and the controls should say so. The observer
        // only reports changes, so without this a stream that is still
        // connecting looks exactly like one that is idle.
        isBuffering = true
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
    ///
    /// What it gives up *on* matters as much as when. A fixed deadline was the
    /// wrong shape: timed against the panel, a channel switch delivered video
    /// in around four seconds most of the time but occasionally took
    /// twenty-five, and the old six-second limit condemned the whole tail. Each
    /// premature verdict then opened another connection while the previous one
    /// was still being held, so a channel with three feeds could report itself
    /// dead in eighteen seconds when its second feed was fine.
    ///
    /// So this waits on evidence rather than on a clock: as long as the stream
    /// is loading anything at all, it keeps waiting. Only silence runs out.
    private func startTimeout(for url: URL) {
        timeout?.cancel()
        // A format guess costs nothing to abandon — the same feed will answer
        // again. A fresh feed has a connection to win first.
        let isFreshConnection = plan?.isVariantStart(candidateIndex) ?? true
        let silenceAllowed: Double = isFreshConnection ? 9 : 5
        let ceiling: Double = isFreshConnection ? 30 : 12

        timeout = Task { [weak self] in
            let started = ContinuousClock.now
            var lastProgress = started
            var loadedSeconds: Double = -1

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                let verdict = await MainActor.run { () -> (done: Bool, loaded: Double)? in
                    guard let self, let item = self.player.currentItem else { return nil }
                    guard item.status != .readyToPlay else { return (true, 0) }
                    return (false, Self.bufferedSeconds(of: item))
                }
                guard let verdict else { return }
                if verdict.done { return }

                // Any growth in what has been fetched means the provider is
                // answering, however slowly, and is worth waiting out.
                if verdict.loaded > loadedSeconds {
                    loadedSeconds = verdict.loaded
                    lastProgress = .now
                }
                let silent = ContinuousClock.now - lastProgress
                let elapsed = ContinuousClock.now - started
                guard silent > .seconds(silenceAllowed) || elapsed > .seconds(ceiling) else {
                    continue
                }
                await MainActor.run {
                    guard let self, self.player.currentItem?.status != .readyToPlay else { return }
                    self.advance(after: nil, url: url)
                }
                return
            }
        }
    }

    /// How much of the stream has actually arrived.
    private static func bufferedSeconds(of item: AVPlayerItem) -> Double {
        item.loadedTimeRanges
            .map(\.timeRangeValue.duration.seconds)
            .filter(\.isFinite)
            .reduce(0, +)
    }

    /// Every candidate before the last is a guess at a format the panel might
    /// also serve, so any failure on one just means the guess was wrong. Only
    /// the provider's own url comes last, and only its failure is worth
    /// reporting.
    private func advance(
        after error: (any Error)?, url: URL, because known: PlaybackFailure? = nil
    ) {
        guard let plan else { return }
        timeout?.cancel()
        let reason = known ?? PlaybackFailure(error: error, url: url)

        // A refusal moments after letting go of another stream is most often
        // the provider still counting the connection we just closed, not a
        // dead feed. Condemning it there would walk through every remaining
        // variant collecting the same answer, and each attempt makes the next
        // one likelier to be refused too. One patient retry costs a moment and
        // keeps a working feed.
        // Only where a connection was actually being opened. Asking the same
        // feed for another container reuses one, so a failure there is about
        // the container and waiting would only add up: four guesses, four
        // pointless pauses, on every film that never had a chance.
        let openedAConnection = plan.isVariantStart(candidateIndex)
        // The offline clip is only suspect when a stream was let go moments
        // ago; otherwise the provider is simply saying the feed is down.
        let worthRetrying = reason != .providerPlaceholder || Self.releasedAStreamRecently
        if reason.mayBeConnectionLimit, worthRetrying, !hasRetriedForConnection, openedAConnection {
            hasRetriedForConnection = true
            let index = candidateIndex
            release()
            // Same label as a deliberate switch. From the sofa the two are the
            // same event: this picture is gone and another is being fetched.
            isSwitchingSource = true
            pendingOpen = Task { [weak self] in
                try? await Task.sleep(for: Self.connectionRetryDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let plan = self.plan else { return }
                    self.play(plan.candidates[index], kind: plan.item.kind)
                }
            }
            return
        }

        guard candidateIndex + 1 < plan.candidates.count else {
            isSwitchingSource = false
            isBuffering = false
            failure = reason
            // Let go rather than pause: a paused item keeps its connection,
            // and the provider goes on counting it against the next attempt.
            release()
            return
        }
        // Crossing into a different feed needs the same pause a deliberate
        // switch does; another container from the same feed does not.
        open(
            candidate: candidateIndex + 1,
            settling: plan.crossesVariant(advancingFrom: candidateIndex)
        )
    }

    /// A finite length under two minutes. A real live playlist reports an
    /// indefinite one; the measured offline clip was a single ten-second
    /// segment.
    static func isPlaceholderLength(_ duration: CMTime) -> Bool {
        let seconds = duration.seconds
        return duration.isNumeric && seconds.isFinite && seconds > 0 && seconds < 120
    }

    /// Long enough for the panel to stop counting the stream just released.
    private static let connectionRetryDelay: Duration = .seconds(3)
    /// One retry per candidate, so a genuinely dead feed still gets abandoned.
    @ObservationIgnored private var hasRetriedForConnection = false

    private func observe(_ playerItem: AVPlayerItem, url: URL) {
        // The end of a recording is a fact the system reports; inferring it
        // from the clock races the last frame.
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isLiveContent else { return }
                self.hasEnded = true
            }
        }

        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .failed: self.advance(after: item.error, url: url)
                case .readyToPlay:
                    // Live television never ends. A live channel that arrives
                    // as a short recording is the panel's offline clip.
                    if self.plan?.item.kind == .liveTV, Self.isPlaceholderLength(item.duration) {
                        self.advance(after: nil, url: url, because: .providerPlaceholder)
                        return
                    }
                    // The same clip stands in for a film the provider no
                    // longer has. Told apart from a genuinely short title by
                    // having no sound, which no real film lacks.
                    if self.plan?.item.kind != .liveTV, Self.isPlaceholderLength(item.duration),
                       !item.tracks.contains(where: { $0.assetTrack?.mediaType == .audio }) {
                        self.advance(after: nil, url: url, because: .providerPlaceholder)
                        return
                    }
                    self.timeout?.cancel()
                    self.failure = nil
                    self.isSwitchingSource = false
                    self.isBuffering = !item.isPlaybackLikelyToKeepUp
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
