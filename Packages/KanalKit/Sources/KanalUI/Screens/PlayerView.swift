import AVFoundation
import AVKit
import KanalCore
import SwiftUI

/// Playback, with one set of controls over two engines.
///
/// AVFoundation takes live TV and MP4; VLC takes the Matroska that makes up
/// nearly every film a provider carries. Both wear `PlayerChrome`, because
/// Apple's own player chrome cannot be restyled and a close imitation of it
/// would leave the two paths visibly different in a way that reads as a bug.
public struct PlayerView: View {
    @Environment(AppModel.self) private var model
    /// Optional for the same reason as the navigator: the player is presented
    /// from more than one place, and a missing store must not be a crash.
    @Environment(PurchaseStore.self) private var purchases: PurchaseStore?
    /// Optional on purpose. A non-optional environment lookup is a hard crash
    /// when the value is absent, and the player is presented from more than
    /// one place — auto-advance is worth having, but not at that price.
    @Environment(Navigator.self) private var navigator: Navigator?
    @Environment(\.alternativePlayer) private var alternativePlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public let plan: PlaybackPlan
    public var item: MediaItem { plan.item }
    @State private var system = SystemPlaybackController()
    @State private var engine: PlaybackEngine = .system
    /// Set only when nothing more can be tried; until then a failed feed
    /// escalates to the next candidate instead of becoming a screen.
    @State private var alternativeError: PlaybackFailure?
    @State private var alternativeSnapshot: (position: TimeInterval, duration: TimeInterval) = (0, 0)
    @State private var handle: AlternativePlayerHandle?
    /// Prevents one failed system attempt from repeatedly rebuilding VLC as
    /// SwiftUI observes the same failure. A deliberate retry is still allowed.
    @State private var hasTriedAlternative = false
    /// Ignores a late callback from a VLC instance that has already been
    /// replaced by Retry.
    @State private var alternativeAttempt = 0
    /// Position in `PlaybackPlan.alternativeCandidateIndices`, not the raw URL
    /// index. VLC starts with every provider-original URL before guesses.
    @State private var alternativeCandidatePosition = 0
    @State private var alternativePlayingOwnerID: String?
    /// Whether this profile's language has already been applied to whatever
    /// is playing. Once per stream: after that the tracks belong to whoever is
    /// watching, and a preference must never undo a choice they just made.
    @State private var hasChosenAudioLanguage = false
    /// Counted down after an episode ends, before the next one starts itself.
    @State private var secondsUntilNext: Int?
    @State private var countdown: Task<Void, Never>?
    @State private var progressTask: Task<Void, Never>?
    /// What to say while nothing is on screen yet.
    @State private var stage: PlaybackStage = .connecting
    /// Gives up on a feed that has neither started nor failed.
    ///
    /// Both engines can sit in "opening" indefinitely — a panel that accepts
    /// the connection and then sends nothing produces no error to react to, so
    /// without this the picture is a spinner that never resolves and never
    /// explains itself.
    @State private var watchdog: Task<Void, Never>?
    /// Whether the wait has lasted long enough to be worth mentioning.
    ///
    /// Most streams open inside a few seconds. A card that appears and
    /// disappears again in that window is noise, not reassurance — so nothing
    /// is drawn over the picture until the wait stops being ordinary.
    @State private var showsWaitingUI = false
    @State private var stallVisible = false
    @State private var stallTask: Task<Void, Never>?
    @State private var playbackSourceID: UUID?
    @State private var playbackProfileID: UUID?
    /// See `LiveChannelPlayer.didReportEnd`.
    @State private var didReportEnd = false

    /// The engine currently playing, whichever it is.
    private var activeController: any PlaybackControlling {
        engine == .alternative ? (handle?.controller ?? system) : system
    }

    /// The episode queued up, once one has finished and another follows.
    private var pendingNext: MediaItem? {
        secondsUntilNext == nil ? nil : model.nextEpisode(after: item)
    }

    /// Counts down visibly rather than jumping straight into the next episode,
    /// so someone who has had enough can stop it.
    private func beginCountdownToNextEpisode() {
        guard let next = model.nextEpisode(after: item) else { return }

        // Finishing an episode means finishing it: recorded so it stops being
        // offered as something to continue.
        let snapshot = activeController
        if snapshot.duration > 0 {
            model.record(item: item, position: snapshot.duration, duration: snapshot.duration)
        }

        countdown?.cancel()
        secondsUntilNext = 8
        countdown = Task { @MainActor in
            while let remaining = secondsUntilNext, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                secondsUntilNext = remaining - 1
            }
            guard !Task.isCancelled else { return }
            advance(to: next)
        }
    }

    private func advance(to next: MediaItem) {
        countdown?.cancel()
        secondsUntilNext = nil
        guard let navigator else { return dismiss() }
        navigator.play(next)
    }

    private func closePlayback() {
        // Do not rely on a presentation animation to eventually tear down the
        // engines. Clearing the navigation item also covers nested player
        // views whose inherited dismiss action may target the wrong layer.
        countdown?.cancel()
        progressTask?.cancel()
        // Recorded before the cover is taken down; see `LiveChannelPlayer`.
        // A film has its answer here. A channel has already given its own,
        // and this view's engines never ran for it.
        if item.kind != .liveTV {
            navigator?.lastPlaybackPlayed = didPlay
            didReportEnd = true
        }
        system.stop()
        let closingHandle = handle
        handle = nil
        closingHandle?.controller.stop()
        // Anything still on its way from an engine now belongs to nobody.
        alternativeAttempt += 1
        navigator?.playing = nil
        dismiss()
    }

    public init(plan: PlaybackPlan) {
        self.plan = plan
    }

    public var body: some View {
        if item.kind == .liveTV {
            LiveChannelPlayer(plan: plan, makeChrome: { controller, title, subtitle, sources in
                AnyView(PlayerChrome(
                    controller: controller, title: title, subtitle: subtitle,
                    sourceAccessory: sources,
                    trailingAccessory: AnyView(AirPlayButton()), watermark: watermark,
                    onClose: closePlayback
                ))
            }, onClose: closePlayback, onPlaybackEnded: { played in
                navigator?.lastPlaybackPlayed = played
            })
        } else {
            recordedBody
        }
    }

    private var recordedBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine == .alternative {
                // Pinned to the attempt, not to the surrounding layout. The
                // surface tearing down is what stops the engine, so it must
                // happen when a feed is actually replaced and never merely
                // because a sibling — the chrome, the loading card — came or
                // went. Absent for the moment between two feeds.
                if let handle {
                    handle.surface
                        .id(alternativeAttempt)
                        .ignoresSafeArea()
                }
                if let alternativeError {
                    errorOverlay(alternativeError)
                } else if let handle, !isOpening {
                    // Held back until there is a picture. A play button over a
                    // black screen invites a press that does nothing, and sits
                    // exactly where the loading card wants to be.
                    PlayerChrome(
                        controller: handle.controller,
                        title: item.title,
                        subtitle: subtitle,
                        trailingAccessory: handle.airPlay.map { AnyView(AirPlayActionButton(action: $0)) }
                            ?? AnyView(AirPlayButton()),
                        watermark: watermark,
                        sourceControl: alternativeSourceControl,
                        onClose: closePlayback
                    )
                }
            } else {
                VideoSurface(player: system.player)
                    .ignoresSafeArea()
                if let failure = system.failure {
                    // A recoverable system failure is handed to VLC on the
                    // same update. Keeping it off screen avoids flashing a
                    // technical error before the alternative surface appears.
                    if !canTryAlternative(after: failure) {
                        errorOverlay(failure)
                    }
                } else if !isOpening {
                    PlayerChrome(
                        controller: system,
                        title: item.title,
                        subtitle: subtitle,
                        trailingAccessory: AnyView(AirPlayButton()),
                        watermark: watermark,
                        onClose: closePlayback
                    )
                }
            }
            if showsLoadingScreen {
                PlaybackLoadingView(
                    item: item, subtitle: subtitle, stage: stage, onCancel: closePlayback
                )
                .transition(.opacity)
            } else if showsStallPill {
                PlaybackStallPill(stage: .buffering)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, KanalMetrics.xxl)
            }

            if let next = pendingNext, let seconds = secondsUntilNext {
                NextEpisodeOverlay(
                    episode: next,
                    secondsRemaining: seconds,
                    onPlayNow: { advance(to: next) },
                    onStop: {
                        countdown?.cancel()
                        closePlayback()
                    }
                )
                .padding(KanalMetrics.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(.opacity)
            }
        }
        #if os(tvOS)
        // The chrome owns Menu once it is up; while it is held back, this does.
        // So does an error: with no chrome up there is nothing else to hear
        // Menu, and it used to do nothing at all on the failure screen.
        .onExitCommand {
            let failed = engine == .alternative ? alternativeError != nil : system.failure != nil
            if isOpening || failed { closePlayback() }
        }
        #endif
        .task { startPlayback() }
        .onChange(of: activeController.isBuffering) { _, buffering in
            // Short hitches are part of streaming. Only a stall long enough to
            // look like a stop earns a word about it.
            stallTask?.cancel()
            guard buffering, didPlay else {
                stallVisible = false
                return
            }
            stallTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                stallVisible = true
            }
        }
        // Track lists arrive after playback begins and can arrive more than
        // once, so this watches for them rather than running at start.
        .onChange(of: activeController.audioTracks) { _, _ in
            chooseAudioLanguageIfNeeded()
        }
        .onChange(of: activeController.hasEnded) { _, ended in
            guard ended else { return }
            beginCountdownToNextEpisode()
        }

        // Format, byte-range and otherwise generic media failures are routed
        // across rather than shown to anyone as an error. Connectivity and
        // credentials would fail in both engines, so those stay actionable.
        .onChange(of: system.failure) { _, failure in
            guard let failure else { return }
            guard canTryAlternative(after: failure) else {
                // The error is on screen with its own Retry. A watchdog left
                // running replaced it twenty seconds later with another.
                watchdog?.cancel()
                return
            }
            startAlternativePlayback()
        }
        .onChange(of: didPlay) { _, played in
            guard played else { return }
            watchdog?.cancel()
        }
        .onChange(of: activeController.isPlaying) { wasPlaying, isPlaying in
            // Playing again after the end — rewinding to rewatch the last
            // scene — is someone saying they are not done with this episode.
            if isPlaying, secondsUntilNext != nil {
                countdown?.cancel()
                secondsUntilNext = nil
            }
            // A pause is an explicit checkpoint. This also covers a pause
            // issued by the system while the app is backgrounding.
            guard wasPlaying, !isPlaying else { return }
            checkpointProgress()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            checkpointProgress()
        }
        .onDisappear {
            countdown?.cancel()
            progressTask?.cancel()
            watchdog?.cancel()
            stallTask?.cancel()
            // Read before the engines are torn down: closing a stream that
            // never played is the one case that must not be asked for money.
            if !didReportEnd { navigator?.lastPlaybackPlayed = didPlay }
            recordProgress()
            alternativeAttempt += 1
            Task { await model.flushPendingWatchState() }
            // Whichever engine is running, not just the built-in one.
            system.stop()
            handle?.controller.stop()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    /// Whether anything actually reached the screen.
    ///
    /// Not "did we try" — a provider url that failed in both engines leaves the
    /// viewer with nothing, and the app has no business celebrating that with
    /// an offer.
    private var didPlay: Bool {
        system.playingOwnerID != nil || alternativePlayingOwnerID != nil
    }

    /// Free tier only, and never over a child's viewing.
    private var watermark: AnyView? {
        guard let purchases, !purchases.isPro, !model.isRestricted else { return nil }
        return AnyView(FreeWatermark { navigator?.wantsPro = true; closePlayback() })
    }

    private var subtitle: String? {
        item.kind == .liveTV
            ? model.nowPlaying(on: item)?.title
            : item.category.map(CategoryLocalizer.display)
    }

    private func alternativeRequest(
        for attempt: Int,
        candidateIndex: Int
    ) -> AlternativePlayerRequest {
        AlternativePlayerRequest(
            url: plan.candidates[candidateIndex],
            isLive: item.kind == .liveTV,
            startAt: resumePosition,
            title: item.title,
            subtitle: subtitle,
            onReady: {
                guard attempt == alternativeAttempt else { return }
                alternativePlayingOwnerID = plan.owner(at: candidateIndex)
            },
            onProgress: { position, duration in
                guard attempt == alternativeAttempt else { return }
                alternativeSnapshot = (position, duration)
            },
            onFailure: { message in
                guard attempt == alternativeAttempt else { return }
                let order = plan.alternativeCandidateIndices
                if alternativeCandidatePosition + 1 < order.count {
                    stage = .switchingSource(
                        number: alternativeCandidatePosition + 2, count: order.count
                    )
                    startAlternativePlayback(at: alternativeCandidatePosition + 1)
                } else {
                    watchdog?.cancel()
                    alternativeError = .other(message)
                }
            },
            onPlaceholder: {
                guard attempt == alternativeAttempt else { return }
                // The provider's own word that this listing is gone. Asking it
                // again in another container gets the same clip, so the format
                // guesses are skipped and the next listing of the film is
                // tried — or, with none left, the viewer is told.
                let next = alternativeCandidatePosition + 1
                if next < plan.variantCount {
                    stage = .switchingSource(number: next + 1, count: plan.variantCount)
                    startAlternativePlayback(at: next)
                } else {
                    watchdog?.cancel()
                    handle?.controller.stop()
                    alternativeError = .providerPlaceholder
                }
            },
            onClose: closePlayback
        )
    }

    /// The same control the system engine offers, for the engine that has no
    /// plan of its own to walk.
    ///
    /// VLC is handed one url at a time, so "try another source" has to be
    /// answered here, where the plan lives. It steps to the next feed's own url
    /// rather than the next candidate, since the format guesses in between
    /// belong to the feed the viewer has just rejected.
    private var alternativeSourceControl: SourceControl? {
        let order = plan.alternativeCandidateIndices
        guard plan.variantCount > 1, !order.isEmpty else { return nil }
        let current = order.indices.contains(alternativeCandidatePosition)
            ? order[alternativeCandidatePosition]
            : 0
        return SourceControl(
            number: plan.variantNumber(at: current),
            count: plan.variantCount,
            isSwitching: false,
            onSwitch: {
                // Wraps, so someone who has been through every feed is offered
                // the first again rather than a dead end.
                let next = (alternativeCandidatePosition + 1) % order.count
                startAlternativePlayback(at: next)
            }
        )
    }

    /// Starts the sound in the language this profile asked for, if the file
    /// has it.
    ///
    /// Silent when it does not: a Norwegian dub that was never recorded is not
    /// an error, and saying so would put a message in front of a child for
    /// something no one can act on. The picker still lists everything the file
    /// carries, so a grown-up can see for themselves what was available.
    private func chooseAudioLanguageIfNeeded() {
        guard !hasChosenAudioLanguage else { return }
        let controller = activeController
        guard let wanted = AudioLanguagePreference.track(
            matching: model.activeProfile?.preferredAudioLanguage,
            in: controller.audioTracks,
            selected: controller.selectedAudioTrackID
        ) else { return }
        hasChosenAudioLanguage = true
        controller.selectAudioTrack(wanted.id)
    }

    private var resumePosition: TimeInterval? {
        model.progress(for: item).flatMap { $0.isWorthResuming ? $0.position : nil }
    }

    // MARK: Waiting for a picture

    /// How long a wait is allowed to pass unremarked. Measured against the
    /// provider: an ordinary Matroska film opened in three to five seconds,
    /// so anything still black at four is worth explaining.
    private static let quietSeconds = 4
    /// When a wait stops reading as normal and starts reading as broken.
    private static let slowSeconds = 10
    /// When a feed that has produced nothing is given up on. Long enough for a
    /// large file on a slow line, short enough that nobody sits through it
    /// twice wondering whether the remote is broken.
    private static let firstFrameSeconds = 20

    /// Narrates the wait, then acts on it.
    ///
    /// Every stage here is a statement about the same feed. The last one is
    /// not: it stops waiting and moves to another, because a panel that holds
    /// a connection open without sending anything will never produce the error
    /// the rest of this screen is built to react to.
    private func beginWatchdog(from initial: PlaybackStage = .connecting) {
        watchdog?.cancel()
        stage = initial
        // A source switch is not a fresh start: whoever is watching has been
        // waiting through the feed it replaced, and is owed the reason now.
        if case .switchingSource = initial {} else { showsWaitingUI = false }
        watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.quietSeconds))
            guard !Task.isCancelled, !didPlay else { return }
            showsWaitingUI = true
            if case .switchingSource = stage {} else { stage = .buffering }

            try? await Task.sleep(for: .seconds(Self.slowSeconds - Self.quietSeconds))
            guard !Task.isCancelled, !didPlay else { return }
            stage = .slow

            try? await Task.sleep(for: .seconds(Self.firstFrameSeconds - Self.slowSeconds))
            guard !Task.isCancelled, !didPlay else { return }
            abandonSilentFeed()
        }
    }

    /// Moves to the next feed of the same title, or explains that there are no
    /// more. Reached only from the watchdog: a feed that reports a real error
    /// is already handled where that error arrives.
    private func abandonSilentFeed() {
        let order = plan.alternativeCandidateIndices
        // The system engine has somewhere to escalate to even on its first
        // silence: the whole point of carrying a second decoder.
        if engine == .system, alternativePlayer != nil, !order.isEmpty {
            stage = .switchingSource(number: 1, count: order.count)
            startAlternativePlayback()
            return
        }
        let next = alternativeCandidatePosition + 1
        guard alternativePlayer != nil, order.indices.contains(next) else {
            watchdog?.cancel()
            alternativeError = .timedOut
            return
        }
        stage = .switchingSource(number: next + 1, count: order.count)
        startAlternativePlayback(at: next)
    }

    /// Whether the poster-and-status screen belongs over the picture.
    ///
    /// Only before the first frame. Once something has played, covering it
    /// again would hide the very thing a viewer is waiting to see move — a
    /// re-buffer gets the pill instead.
    /// Between pressing play and the first frame, with nothing yet wrong.
    private var isOpening: Bool {
        // The system engine's failure only counts while it is the engine in
        // use. It stays set after the film is handed to VLC, and counting it
        // there meant the hand-off showed a play button over black instead of
        // the loading card.
        alternativeError == nil && (engine == .alternative || system.failure == nil) && !didPlay
    }

    private var showsLoadingScreen: Bool { isOpening && showsWaitingUI }

    private var showsStallPill: Bool {
        alternativeError == nil && didPlay && stallVisible
    }

    private func startPlayback() {
        playbackSourceID = model.activeSourceID
        playbackProfileID = model.activeProfileID
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                checkpointProgress()
            }
        }
        hasChosenAudioLanguage = false
        // Without a second engine there is nothing to escalate to, so the
        // system player takes everything and guesses at formats on failure.
        engine = alternativePlayer == nil ? .system : PlaybackEngine.preferred(for: item)
        guard engine == .system else {
            startAlternativePlayback()
            return
        }
        hasTriedAlternative = false
        beginWatchdog()
        system.start(plan: plan, resumingAt: resumePosition)
    }

    /// Starts a fresh VLC instance. Rebuilding is intentional: once a decoder
    /// reports a terminal error, replaying its existing media object is less
    /// reliable than giving the same request to a clean one.
    private func startAlternativePlayback(at position: Int = 0) {
        guard let alternativePlayer else { return }
        let order = plan.alternativeCandidateIndices
        guard order.indices.contains(position) else { return }
        let candidateIndex = order[position]

        // Whether a connection is being let go of right now. The provider
        // allows one and is slow to notice it has gone.
        let releasesStream = system.isHoldingStream || handle != nil
        system.stop()
        handle?.controller.stop()
        handle = nil
        hasTriedAlternative = true
        hasChosenAudioLanguage = false
        alternativeCandidatePosition = position
        alternativePlayingOwnerID = nil
        alternativeError = nil
        alternativeSnapshot = (0, 0)
        alternativeAttempt += 1
        let attempt = alternativeAttempt
        // A deliberate source switch says so; a fresh start says "connecting".
        if case .switchingSource = stage {
            beginWatchdog(from: stage)
        } else {
            beginWatchdog()
        }
        engine = .alternative
        let request = alternativeRequest(for: attempt, candidateIndex: candidateIndex)
        guard releasesStream else {
            handle = alternativePlayer(request)
            return
        }
        // The same pause the system engine takes between feeds: asking again
        // on the heels of a release is answered with the "offline" clip.
        Task { @MainActor in
            try? await Task.sleep(for: SystemPlaybackController.connectionSettle)
            guard attempt == alternativeAttempt else { return }
            handle = alternativePlayer(request)
        }
    }

    private func canTryAlternative(after failure: PlaybackFailure) -> Bool {
        alternativePlayer != nil
            && !hasTriedAlternative
            && failure.shouldTryAlternativeEngine
    }

    /// Retry stays with the engine the viewer actually saw fail. In
    /// particular, a failed VLC fallback must not silently jump back to the
    /// same AVFoundation path that already rejected the stream.
    private func retryPlayback() {
        alternativeError = nil
        switch engine {
        case .system:
            beginWatchdog()
            system.retry()
        case .alternative:
            startAlternativePlayback()
        }
    }

    private func recordProgress() {
        // A delayed dismissal can race a source/profile switch. Never attach
        // an outgoing player's position to the newly active household state.
        guard playbackSourceID == model.activeSourceID,
              playbackProfileID == model.activeProfileID else { return }
        // A channel that finally played on its third variant should open on
        // that one next time.
        let playingOwner = engine == .alternative
            ? alternativePlayingOwnerID
            : system.playingOwnerID
        if let groupID = plan.groupID, let playingOwner {
            model.rememberWorkingVariant(playingOwner, forGroup: groupID)
        }
        if item.kind == .liveTV {
            // Closing a stream that never reached Ready must not make a broken
            // channel look like something the viewer recently watched.
            guard playingOwner != nil else { return }
            let groupID = plan.groupID
                ?? model.library.channelGroup(containing: item)?.id
                ?? item.id
            model.recordChannel(groupID: groupID)
            return
        }
        // Only what actually played has a position worth keeping; a film
        // closed while it was still opening would otherwise be filed at zero.
        guard playingOwner != nil else { return }
        let snapshot = engine == .alternative ? alternativeSnapshot : system.snapshot()
        guard snapshot.duration > 0 else { return }
        model.record(item: item, position: snapshot.position, duration: snapshot.duration)
    }

    private func checkpointProgress() {
        recordProgress()
        Task { await model.flushPendingWatchState() }
    }

    // MARK: Failure

    /// Says what actually went wrong. "Cannot Open" covers three unrelated
    /// causes, and a viewer can only act on one of them if told which.
    private func errorOverlay(_ failure: PlaybackFailure) -> some View {
        VStack(spacing: KanalMetrics.md) {
            Image(systemName: symbol(for: failure))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(KanalColor.warning)
            Text(title(for: failure))
                .font(KanalFont.section(17))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(explanation(for: failure))
                .font(KanalFont.body(13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: KanalMetrics.md) {
                Button(String(UIStrings.closePlayer), action: closePlayback)
                    .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                Button(String(UIStrings.tryAgain)) { retryPlayback() }
                    .buttonStyle(KanalPrimaryButtonStyle(size: 14))
            }
        }
        .padding(KanalMetrics.xl)
        .frame(maxWidth: 420)
        .kanalGlassPanel()
    }

    private func symbol(for failure: PlaybackFailure) -> String {
        switch failure {
        case .unsupportedContainer: "film.stack"
        case .serverNotStreamable: "server.rack"
        case .rejected: "person.badge.key.fill"
        case .offline: "wifi.slash"
        case .timedOut: "hourglass"
        case .providerPlaceholder: "tv.slash"
        case .other: "exclamationmark.triangle.fill"
        }
    }

    private func title(for failure: PlaybackFailure) -> LocalizedStringResource {
        switch failure {
        case .unsupportedContainer: UIStrings.playbackUnsupportedTitle
        case .serverNotStreamable: UIStrings.playbackServerTitle
        case .rejected: UIStrings.playbackRejectedTitle
        case .offline: UIStrings.playbackOfflineTitle
        case .timedOut: UIStrings.playbackTimeoutTitle
        // This screen only ever shows films and episodes, and the channel
        // wording would be wrong for them.
        case .providerPlaceholder: UIStrings.playbackTimeoutTitle
        case .other: UIStrings.streamFailedTitle
        }
    }

    private func explanation(for failure: PlaybackFailure) -> String {
        switch failure {
        case .unsupportedContainer(let container):
            String(UIStrings.playbackUnsupportedBody(container.uppercased()))
        case .serverNotStreamable: String(UIStrings.playbackServerBody)
        case .rejected: String(UIStrings.playbackRejectedBody)
        case .offline: String(UIStrings.playbackOfflineBody)
        case .timedOut: String(UIStrings.playbackTimeoutBody)
        case .providerPlaceholder: String(UIStrings.playbackTimeoutBody)
        case .other(let message): message
        }
    }
}

/// The video itself: an `AVPlayerLayer` rather than `AVPlayerViewController`,
/// so our own controls can sit on top. Picture-in-picture is attached here,
/// since it is one of the few things a custom layer cannot reimplement.
struct VideoSurface {
    let player: AVPlayer
}

#if os(iOS) || os(tvOS)
extension VideoSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        #if os(iOS)
        context.coordinator.attachPictureInPicture(to: view.playerLayer)
        #endif
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        #if os(iOS)
        private var pictureInPicture: AVPictureInPictureController?

        func attachPictureInPicture(to layer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            let controller = AVPictureInPictureController(playerLayer: layer)
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPicture = controller
        }
        #endif
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#else
extension VideoSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#endif

/// The system route picker. There is no way to reimplement AirPlay, so this is
/// Apple's own control dropped into our chrome.
struct AirPlayButton: View {
    var body: some View {
        #if os(iOS)
        RoutePicker()
            .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
            .kanalGlassOverVideo(cornerRadius: 100)
        #else
        EmptyView()
        #endif
    }
}

/// AirPlay for an engine that has to prepare first. Looks like the system
/// picker; what it does on a tap is the engine's business.
struct AirPlayActionButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        #if os(iOS)
        Button { action() } label: {
            Image(systemName: "airplay.video")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
                .kanalGlassOverVideo(cornerRadius: 100)
                .contentShape(.circle)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityIdentifier("player.airplay")
        .accessibilityLabel(Text(verbatim: "AirPlay"))
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
