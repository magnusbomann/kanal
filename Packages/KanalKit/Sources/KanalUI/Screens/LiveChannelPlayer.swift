import AVFoundation
import KanalCore
import Network
import Observation
import SwiftUI

/// The session owns source selection; each decoder receives exactly one stream.
/// This prevents decoder fallback from silently overriding a manual selection.
///
/// It waits on evidence, not on a clock. An earlier version gave Apple's
/// player three seconds, the second decoder three more, and then moved to the
/// next feed — so on an evening when the provider needed four seconds to
/// answer, every feed of every channel was abandoned in turn and nothing ever
/// played. Each of those abandoned attempts was also a fresh connection on an
/// account that is allowed one. A feed is now only given up on when its
/// decoder says it failed, when the provider answers with its "offline" clip,
/// or when a picture that was moving has stopped for good.
@MainActor @Observable
final class LiveChannelSession {
    private(set) var system = SystemPlaybackController()
    private(set) var alternative: AlternativePlayerHandle?
    private(set) var recovery: LiveStreamRecovery?
    private(set) var stopped = false
    private(set) var waitingForNetwork = false
    /// Whether a feed played for long enough to be the channel rather than
    /// the provider's ten-second "this channel is offline" clip.
    private(set) var hasPlayed = false
    /// How many feeds this search has opened, and how many of them the
    /// provider answered with its offline clip.
    private(set) var attempts = 0
    private var offlineAttempts = 0
    private var connected: Bool?
    private var monitor: NWPathMonitor?
    private var generation = 0
    private var alternativeFailed = false
    private var triedAlternative = false
    private var isSettling = false
    private var alternativeStarted: TimeInterval = 0
    private var attemptBegan: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var lastProgress: TimeInterval = 0
    /// When the picture first moved on this attempt.
    private var firstProgress: TimeInterval?
    /// Set once this attempt has outlasted the offline clip.
    private var confirmed = false
    private var builder: AlternativePlayerBuilder?
    private var variants: [MediaItem] = []
    private var onPlayed: ((String) -> Void)?

    /// Longer than the provider's offline clip, which is ten seconds and
    /// plays perfectly. Anything still moving after this is the channel.
    private static let confirmAfter: TimeInterval = 12
    /// How long a picture that was moving may stand still before the feed is
    /// treated as gone.
    private static let stallLimit: TimeInterval = 8
    /// The second decoder reports no byte counts to wait on, so it gets a
    /// plain allowance — generous, because it is only reached after Apple's
    /// player has already refused the stream.
    private static let alternativePatience: TimeInterval = 20
    /// The backstop for a feed that neither plays nor fails. The system
    /// player normally reaches its own verdict well inside this.
    private static let openingCeiling: TimeInterval = 35
    /// Lets the provider stop counting the feed just released before the next
    /// one is asked for.
    private static let connectionSettle: Duration = .milliseconds(700)

    var controller: any PlaybackControlling { alternative?.controller ?? system }
    var currentID: String? { recovery?.current }
    var locked: Bool { recovery?.locked == true }
    var isCurrentPlaying: Bool {
        firstProgress != nil && !stopped && !waitingForNetwork && controller.isPlaying
    }
    /// True from the moment a feed is asked for until its picture moves.
    var isOpening: Bool {
        !stopped && !waitingForNetwork && recovery != nil && firstProgress == nil
    }
    /// True when the search ended because the provider itself said, for every
    /// feed tried, that the channel is off the air.
    var endedOffline: Bool { stopped && attempts > 0 && offlineAttempts == attempts }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(variants: [MediaItem], selected: String, locked: Bool,
               builder: AlternativePlayerBuilder?, suspended: Bool = false, onPlayed: @escaping (String) -> Void) {
        stopped = suspended
        self.variants = variants
        self.builder = builder
        self.onPlayed = onPlayed
        recovery = LiveStreamRecovery(order: variants.map(\.id), selected: selected,
                                      locked: locked, now: now)
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in self?.networkChanged(available) }
        }
        monitor.start(queue: DispatchQueue(label: "Kanal.live-network"))
        // Wait for the first path result, so starting offline never burns sources.
        waitingForNetwork = true
    }

    private func networkChanged(_ available: Bool) {
        guard monitor != nil, connected != available else { return }
        connected = available
        if !available {
            waitingForNetwork = true
            stopEngines()
        } else if waitingForNetwork {
            waitingForNetwork = false
            // An exhausted search stays exhausted even if connectivity changes.
            guard !stopped else { return }
            recovery?.retry(at: now)
            beginSearch()
        }
    }

    func setLocked(_ locked: Bool) { recovery?.locked = locked }

    func select(_ id: String) {
        guard variants.contains(where: { $0.id == id }) else { return }
        recovery = LiveStreamRecovery(order: variants.map(\.id), selected: id,
                                      locked: locked, now: now)
        stopped = false
        if connected == true { beginSearch() }
    }

    func retry() {
        recovery?.retry(at: now)
        stopped = false
        if connected == true { beginSearch() }
    }

    /// A deliberate start: the count of what has been tried begins again.
    private func beginSearch() {
        attempts = 0
        offlineAttempts = 0
        openCurrent(settling: false)
    }

    private func stopEngines() {
        generation += 1
        isSettling = false
        system.stop()
        alternative?.controller.stop()
        alternative = nil
        alternativeFailed = false
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        stopEngines()
    }

    private func openCurrent(settling: Bool) {
        stopEngines()
        guard let item = variants.first(where: { $0.id == currentID }) else {
            stopped = true
            return
        }
        lastPosition = 0
        firstProgress = nil
        confirmed = false
        triedAlternative = false
        attempts += 1
        // A new controller also isolates delayed KVO callbacks from old attempts.
        system = SystemPlaybackController()
        guard settling else {
            begin(item)
            return
        }
        isSettling = true
        let token = generation
        Task { [weak self] in
            try? await Task.sleep(for: Self.connectionSettle)
            guard let self, self.generation == token, self.isSettling else { return }
            self.isSettling = false
            self.begin(item)
        }
    }

    private func begin(_ item: MediaItem) {
        attemptBegan = now
        lastProgress = now
        system.start(plan: PlaybackPlan(item: item, candidates: [item.streamURL],
                                        owners: [item.id]), resumingAt: nil)
    }

    private func tryAlternative(at time: TimeInterval) -> Bool {
        guard alternative == nil, !triedAlternative, let builder,
              let item = variants.first(where: { $0.id == currentID }) else { return false }
        triedAlternative = true
        system.stop()
        generation += 1
        let token = generation
        alternative = builder(AlternativePlayerRequest(
            url: item.streamURL, isLive: true, startAt: nil,
            title: item.title, subtitle: nil, onReady: {},
            onProgress: { _, _ in },
            onFailure: { [weak self] _ in
                guard let self, self.generation == token else { return }
                self.alternativeFailed = true
            }, onClose: {}
        ))
        alternativeStarted = time
        lastPosition = 0
        firstProgress = nil
        return true
    }

    /// Called by a cancellable view task. Only advancing playback confirms success;
    /// a ready decoder or an open socket alone must not mark a dead feed as good.
    func tick() {
        guard connected == true, !waitingForNetwork, !stopped, !isSettling, recovery != nil else { return }
        let time = now
        let position = controller.position
        if controller.isPlaying, position.isFinite, position > lastPosition + 0.05 {
            lastProgress = time
            if firstProgress == nil { firstProgress = time }
            if !confirmed, let firstProgress, time - firstProgress >= Self.confirmAfter {
                confirmed = true
                hasPlayed = true
                recovery?.played()
                if let currentID { onPlayed?(currentID) }
            }
        }
        lastPosition = position

        let engineFailed = alternative == nil ? system.failure != nil : alternativeFailed
        if firstProgress != nil, !engineFailed {
            if time - lastProgress < Self.stallLimit { return }
            // A user's pause has no buffering and no terminal error. Leave it alone.
            if !controller.isPlaying, !controller.isBuffering {
                // The pause is not a stall, and neither is the moment after
                // it: without this, pressing play after ten seconds found the
                // stall limit already spent and tore down a working feed.
                lastProgress = time
                return
            }
            advance(at: time)
            return
        }

        if alternative == nil {
            // No verdict yet means the system player is still waiting on
            // evidence of its own: it keeps going while bytes arrive and
            // reports a failure when they stop.
            guard let failure = system.failure else {
                if time - attemptBegan >= Self.openingCeiling { advance(at: time) }
                return
            }
            if failure == .providerPlaceholder { offlineAttempts += 1 }
            if failure.shouldTryAlternativeEngine, tryAlternative(at: time) { return }
            advance(at: time)
        } else if alternativeFailed || time - alternativeStarted >= Self.alternativePatience {
            advance(at: time)
        }
    }

    /// Reopens this feed if it had been the channel, moves to the next one if
    /// not, and stops when the search has nothing left.
    private func advance(at time: TimeInterval) {
        if recovery?.failed(at: time) != nil {
            openCurrent(settling: true)
        } else {
            finish()
        }
    }

    private func finish() {
        stopped = true
        stopEngines()
    }
}

struct LiveChannelPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.alternativePlayer) private var alternativePlayer
    @Environment(\.dismiss) private var dismiss
    let plan: PlaybackPlan
    var makeChrome: ((any PlaybackControlling, String, String?, AnyView) -> AnyView)? = nil
    var onClose: (() -> Void)? = nil
    var onPlaybackEnded: (Bool) -> Void = { _ in }
    @State private var session = LiveChannelSession()
    @State private var showsSources = false
    /// Whether closing has already said if anything played, so a late
    /// `onDisappear` does not say it again after the answer was consumed.
    @State private var didReportEnd = false

    private var group: ChannelGroup? {
        model.library.channelGroups.first { $0.id == plan.groupID || $0.variants.contains { $0.id == plan.item.id } }
    }
    private var groupID: String { group?.id ?? plan.groupID ?? plan.item.id }
    private var variants: [MediaItem] { group?.variants ?? [plan.item] }
    private var current: MediaItem? { variants.first { $0.id == session.currentID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let alternative = session.alternative {
                alternative.surface.ignoresSafeArea()
            } else {
                VideoSurface(player: session.system.player).ignoresSafeArea()
            }
            if let makeChrome {
                makeChrome(session.controller, group?.name ?? plan.item.title,
                           current?.rawTitle, AnyView(sourceButton))
            } else {
                PlayerChrome(
                    controller: session.controller, title: group?.name ?? plan.item.title,
                    subtitle: current?.rawTitle,
                    sourceAccessory: AnyView(sourceButton),
                    trailingAccessory: AnyView(AirPlayButton()),
                    onClose: closePlayback
                )
            }
            if session.isOpening, !session.waitingForNetwork {
                // Says what is happening instead of leaving a black screen. A
                // feed can take many seconds to answer, and a wait that says
                // nothing is the one people read as the app being broken.
                PlaybackStallPill(stage: openingStage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, KanalMetrics.xxl)
                    .allowsHitTesting(false)
            }
            if session.waitingForNetwork || session.stopped {
                VStack(spacing: KanalMetrics.md) {
                    Text(stoppedTitle)
                        .font(KanalFont.section(17))
                    Text(stoppedBody)
                        .font(KanalFont.body(13))
                    Button(String(UIStrings.tryAgain)) { session.retry() }
                        .buttonStyle(KanalPrimaryButtonStyle(size: 14))
                        .accessibilityIdentifier("player.failure.retry")
                    Button(String(UIStrings.streamChoose)) { showsSources = true }
                        .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                        .accessibilityIdentifier("player.failure.sources")
                    Button(String(UIStrings.closePlayer), action: closePlayback)
                        .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                        .accessibilityIdentifier("player.failure.close")
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(KanalMetrics.lg)
                .frame(maxWidth: KanalMetrics.playbackPanelWidth)
                .kanalGlassPanel()
            }
        }
        .sheet(isPresented: $showsSources) { sourcePicker }
        .task {
            let savedLock = model.watchState.lockedVariants[groupID]
            let validLock = variants.contains { $0.id == savedLock } ? savedLock : nil
            // If a provider removed the locked stream, require a manual choice.
            let missingLock = savedLock != nil && validLock == nil
            session.start(variants: variants, selected: validLock ?? plan.item.id,
                          locked: savedLock != nil, builder: alternativePlayer, suspended: missingLock) { id in
                model.rememberWorkingVariant(id, forGroup: groupID)
                model.recordChannel(groupID: groupID)
                // Said the moment it is true. The chrome's close button goes
                // straight to the presenting view, and the presenter asks
                // "did anything play?" as the cover comes down — before this
                // view has disappeared. Answered only on disappearing, every
                // channel counted as one that never started, and the free
                // tier's offer never came.
                onPlaybackEnded(true)
                didReportEnd = true
            }
            if missingLock { showsSources = true }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                session.tick()
            }
        }
        .onDisappear {
            if !didReportEnd { onPlaybackEnded(session.hasPlayed) }
            session.stop()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    /// "Connecting" for the first feed, "trying another source" after that.
    private var openingStage: PlaybackStage {
        let count = min(variants.count, LiveStreamRecovery.maximumSources)
        guard session.attempts > 1, count > 1 else { return .connecting }
        return .switchingSource(number: min(session.attempts, count), count: count)
    }

    private var stoppedTitle: LocalizedStringResource {
        if session.waitingForNetwork { return UIStrings.streamWaiting }
        return session.endedOffline ? UIStrings.playbackPlaceholderTitle : UIStrings.streamSearchStopped
    }

    private var stoppedBody: LocalizedStringResource {
        if session.waitingForNetwork { return UIStrings.streamWaitingBody }
        return session.endedOffline ? UIStrings.playbackPlaceholderBody : UIStrings.streamSearchStoppedBody
    }

    private func closePlayback() {
        // Said now, not left to `onDisappear`. Whoever presented the player
        // asks "did anything play?" when the cover has gone, and the cover's
        // dismissal is not promised to come after this view disappearing —
        // when it came first, a channel watched for an hour counted as one
        // that never started.
        onPlaybackEnded(session.hasPlayed)
        didReportEnd = true
        // Release the stream before removing the player. The owning view also
        // gets a direct chance to clear its navigation state.
        session.stop()
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var sourceButton: some View {
        HStack(spacing: KanalMetrics.sm) {
            #if os(tvOS)
            Button { model.toggleFavorite(favoriteID) } label: {
                Label(String(isFavorite ? UIStrings.removeFavourite : UIStrings.addFavourite),
                      systemImage: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(.white)
                    .font(KanalFont.label())
                    .padding(.horizontal, KanalMetrics.md)
                    .frame(minHeight: KanalMetrics.minTarget)
                    .kanalGlassOverVideo(cornerRadius: 100)
            }
            .buttonStyle(PlayerControlButtonStyle())
            .accessibilityIdentifier("player.favorite")
            #endif
        Button { showsSources = true } label: {
            Image(systemName: session.locked ? "lock.fill" : "list.bullet")
                .foregroundStyle(.white)
                .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
                .kanalGlassOverVideo(cornerRadius: 100)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityLabel(Text(UIStrings.streamChoose))
        .accessibilityIdentifier("player.sources")
        }
    }

    private var isFavorite: Bool {
        variants.contains { model.watchState.isFavorite($0.id) }
    }

    private var favoriteID: String {
        variants.first { model.watchState.isFavorite($0.id) }?.id ?? group?.primary.id ?? plan.item.id
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Text(UIStrings.streamChoose).font(KanalFont.section(22))
            Text(group?.name ?? plan.item.title).font(KanalFont.body(15))
            Toggle(String(UIStrings.streamLock), isOn: Binding(
                get: { session.locked },
                set: { value in
                    session.setLocked(value)
                    model.lockVariant(value ? session.currentID : nil, forGroup: groupID)
                }
            ))
            Text(UIStrings.streamLockBody).font(KanalFont.body(12))
            ScrollView {
                LazyVStack(spacing: KanalMetrics.sm) {
                    ForEach(Array(variants.enumerated()), id: \.element.id) { index, variant in
                        Button {
                            session.select(variant.id)
                            if session.locked { model.lockVariant(variant.id, forGroup: groupID) }
                            showsSources = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                SourceRowView(variant: variant, position: index + 1,
                                              isRemembered: model.watchState.workingVariants[groupID] == variant.id)
                                HStack {
                                    if variant.id == session.currentID {
                                        Text(session.isCurrentPlaying ? UIStrings.streamPlaying : UIStrings.streamSelected)
                                    }
                                    if variant.id == model.watchState.workingVariants[groupID] {
                                        Text(UIStrings.sourceLastWorked)
                                    }
                                    if variant.id == model.watchState.lockedVariants[groupID] {
                                        Label(String(UIStrings.streamLocked), systemImage: "lock.fill")
                                    }
                                }.font(KanalFont.body(12))
                            }
                        }.buttonStyle(KanalCardButtonStyle())
                    }
                }
            }
            Button(String(UIStrings.streamDone)) { showsSources = false }
                .buttonStyle(KanalSecondaryButtonStyle(size: 14))
        }
        .padding(KanalMetrics.lg)
        .foregroundStyle(KanalColor.primaryText)
        .background(KanalColor.background)
        #if !os(tvOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
