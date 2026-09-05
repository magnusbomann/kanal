import AVFoundation
import KanalCore
import Network
import Observation
import SwiftUI

/// The session owns source selection; each decoder receives exactly one stream.
/// This prevents decoder fallback from silently overriding a manual selection.
@MainActor @Observable
final class LiveChannelSession {
    private(set) var system = SystemPlaybackController()
    private(set) var alternative: AlternativePlayerHandle?
    private(set) var recovery: LiveStreamRecovery?
    private(set) var stopped = false
    private(set) var waitingForNetwork = false
    private(set) var hasPlayed = false
    private var connected: Bool?
    private var monitor: NWPathMonitor?
    private var generation = 0
    private var alternativeFailed = false
    private var attemptStarted: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var lastProgress: TimeInterval = 0
    private var currentPlaying = false
    private var builder: AlternativePlayerBuilder?
    private var variants: [MediaItem] = []
    private var onPlayed: ((String) -> Void)?

    var controller: any PlaybackControlling { alternative?.controller ?? system }
    var currentID: String? { recovery?.current }
    var locked: Bool { recovery?.locked == true }
    var isCurrentPlaying: Bool { currentPlaying && !stopped && !waitingForNetwork && controller.isPlaying }
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
            openCurrent()
        }
    }

    func setLocked(_ locked: Bool) { recovery?.locked = locked }

    func select(_ id: String) {
        guard variants.contains(where: { $0.id == id }) else { return }
        recovery = LiveStreamRecovery(order: variants.map(\.id), selected: id,
                                      locked: locked, now: now)
        stopped = false
        if connected == true { openCurrent() }
    }

    func retry() {
        recovery?.retry(at: now)
        stopped = false
        if connected == true { openCurrent() }
    }

    private func stopEngines() {
        generation += 1
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

    private func openCurrent() {
        stopEngines()
        guard let item = variants.first(where: { $0.id == currentID }) else {
            stopped = true
            return
        }
        attemptStarted = now
        lastProgress = now
        lastPosition = 0
        currentPlaying = false
        // A new controller also isolates delayed KVO callbacks from old attempts.
        system = SystemPlaybackController()
        system.start(plan: PlaybackPlan(item: item, candidates: [item.streamURL],
                                        owners: [item.id]), resumingAt: nil)
    }

    private func tryAlternative() -> Bool {
        guard alternative == nil, let builder,
              let item = variants.first(where: { $0.id == currentID }) else { return false }
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
        lastPosition = 0
        return true
    }

    /// Called by a cancellable view task. Only advancing playback confirms success;
    /// a ready decoder or an open socket alone must not mark a dead feed as good.
    func tick() {
        guard connected == true, !waitingForNetwork, !stopped, recovery != nil else { return }
        let time = now
        let position = controller.position
        if controller.isPlaying, position.isFinite, position > lastPosition + 0.05 {
            lastProgress = time
            if !currentPlaying {
                recovery?.played()
                if let currentID { onPlayed?(currentID) }
                currentPlaying = true
            }
            hasPlayed = true
        }
        lastPosition = position
        let working = currentPlaying && time - lastProgress < 8
        let failed = alternative == nil ? system.failure != nil : alternativeFailed
        if working && !failed { return }
        // A user's pause has no buffering and no terminal error. Leave it alone.
        if currentPlaying, !controller.isPlaying, !controller.isBuffering, !failed,
           recovery?.lastWorking == currentID { return }
        if recovery?.expired(at: time) == true && recovery?.lastWorking != currentID {
            finish()
            return
        }
        if failed || time - attemptStarted >= 6 || (hasPlayed && time - lastProgress >= 8) {
            if recovery?.lastWorking != currentID, alternative == nil, time - attemptStarted < 6, tryAlternative() { return }
            if recovery?.failed(at: time) != nil { openCurrent() } else { finish() }
        } else if time - attemptStarted >= 3, alternative == nil {
            _ = tryAlternative()
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
    var onPlaybackEnded: (Bool) -> Void = { _ in }
    @State private var session = LiveChannelSession()
    @State private var showsSources = false

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
                    onClose: { dismiss() }
                )
            }
            if session.waitingForNetwork || session.stopped {
                VStack(spacing: KanalMetrics.md) {
                    Text(session.waitingForNetwork ? UIStrings.streamWaiting : UIStrings.streamSearchStopped)
                        .font(KanalFont.section(17))
                    Text(session.waitingForNetwork ? UIStrings.streamWaitingBody : UIStrings.streamSearchStoppedBody)
                        .font(KanalFont.body(13))
                    Button(String(UIStrings.tryAgain)) { session.retry() }
                        .buttonStyle(KanalPrimaryButtonStyle(size: 14))
                    Button(String(UIStrings.streamChoose)) { showsSources = true }
                        .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                    Button(String(UIStrings.closePlayer)) { dismiss() }
                        .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(KanalMetrics.lg)
                .frame(maxWidth: 420)
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
            }
            if missingLock { showsSources = true }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                session.tick()
            }
        }
        .onDisappear {
            onPlaybackEnded(session.hasPlayed)
            session.stop()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    private var sourceButton: some View {
        Button { showsSources = true } label: {
            Image(systemName: session.locked ? "lock.fill" : "list.bullet")
                .foregroundStyle(.white)
                .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
                .kanalGlassOverVideo(cornerRadius: 100)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(UIStrings.streamChoose))
        .accessibilityIdentifier("player.sources")
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
