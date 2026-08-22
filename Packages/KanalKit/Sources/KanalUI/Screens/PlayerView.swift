import AVKit
import KanalCore
import SwiftUI

/// Playback.
///
/// Wraps `AVPlayerViewController` rather than SwiftUI's `VideoPlayer` because
/// the system controller is what gives us picture-in-picture, the tvOS transport
/// bar, subtitle and audio-track menus and AirPlay for free — all things people
/// expect from an Apple app and no reason to rebuild.
public struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.alternativePlayer) private var alternativePlayer
    @Environment(\.dismiss) private var dismiss

    public let item: MediaItem
    @State private var controller = PlayerController()
    @State private var engine: PlaybackEngine = .system
    @State private var alternativeError: String?
    /// Progress reported by the second engine, which has no AVPlayer to read.
    @State private var alternativeProgress: (position: TimeInterval, duration: TimeInterval) = (0, 0)

    public init(item: MediaItem) {
        self.item = item
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine == .alternative, let alternativePlayer {
                alternativePlayer(alternativeRequest)
                    .ignoresSafeArea()
                if let alternativeError {
                    errorOverlay(.other(alternativeError))
                }
            } else {
                SystemPlayer(controller: controller)
                    .ignoresSafeArea()
                if controller.isStalled {
                    stallOverlay
                }
                if let failure = controller.failure {
                    errorOverlay(failure)
                }
            }
        }
        .task { startPlayback() }
        // The system player is tried first wherever it might work, but when it
        // reports a container it cannot open there is no reason to show anyone
        // an error we can simply route around.
        .onChange(of: controller.failure) { _, failure in
            guard let failure, alternativePlayer != nil else { return }
            if case .unsupportedContainer = failure {
                controller.stop()
                engine = .alternative
            }
        }
        .onDisappear {
            recordProgress()
            controller.stop()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    private var alternativeRequest: AlternativePlayerRequest {
        AlternativePlayerRequest(
            url: item.streamURL,
            startAt: resumePosition,
            onProgress: { position, duration in
                alternativeProgress = (position, duration)
            },
            onFailure: { message in
                alternativeError = message
            }
        )
    }

    private var resumePosition: TimeInterval? {
        model.progress(for: item).flatMap { $0.isWorthResuming ? $0.position : nil }
    }

    private func startPlayback() {
        // Without a second engine there is nothing to escalate to, so the
        // system player takes everything and guesses at formats on failure.
        engine = alternativePlayer == nil ? .system : PlaybackEngine.preferred(for: item)
        guard engine == .system else { return }
        controller.start(item: item, resumingAt: resumePosition)
    }

    private func recordProgress() {
        guard item.kind != .liveTV else { return }
        let snapshot = engine == .alternative
            ? PlayerController.Snapshot(
                position: alternativeProgress.position,
                duration: alternativeProgress.duration
            )
            : controller.snapshot()
        guard snapshot.duration > 0 else { return }
        model.record(itemID: item.id, position: snapshot.position, duration: snapshot.duration)
    }

    private var stallOverlay: some View {
        VStack(spacing: KanalMetrics.md) {
            ProgressView().tint(.white)
            Text(UIStrings.buffering)
                .kanalLabel(12)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(KanalMetrics.lg)
        .kanalGlassOverVideo()
        .allowsHitTesting(false)
    }

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
            Button(String(UIStrings.tryAgain)) { controller.retry() }
                .buttonStyle(KanalSecondaryButtonStyle())
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
        case .other: "exclamationmark.triangle.fill"
        }
    }

    private func title(for failure: PlaybackFailure) -> LocalizedStringResource {
        switch failure {
        case .unsupportedContainer: UIStrings.playbackUnsupportedTitle
        case .serverNotStreamable: UIStrings.playbackServerTitle
        case .rejected: UIStrings.playbackRejectedTitle
        case .offline: UIStrings.playbackOfflineTitle
        case .other: UIStrings.streamFailedTitle
        }
    }

    private func explanation(for failure: PlaybackFailure) -> String {
        switch failure {
        case .unsupportedContainer(let container):
            String(UIStrings.playbackUnsupportedBody(container.uppercased()))
        case .serverNotStreamable:
            String(UIStrings.playbackServerBody)
        case .rejected:
            String(UIStrings.playbackRejectedBody)
        case .offline:
            String(UIStrings.playbackOfflineBody)
        case .other(let message):
            message
        }
    }
}

/// Owns the `AVPlayer` and the observations the UI reacts to.
@MainActor
@Observable
public final class PlayerController {

    public struct Snapshot: Sendable {
        public var position: TimeInterval
        public var duration: TimeInterval
    }

    public private(set) var player = AVPlayer()
    public private(set) var isStalled = false
    /// Set once every candidate has been tried, never before.
    public private(set) var failure: PlaybackFailure?

    private var statusObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var currentItem: MediaItem?
    private var resumeTarget: TimeInterval?
    /// Formats still worth trying for this entry.
    private var candidates: [URL] = []
    private var candidateIndex = 0
    private var timeout: Task<Void, Never>?

    public init() {}

    public func start(item: MediaItem, resumingAt resume: TimeInterval?) {
        currentItem = item
        resumeTarget = resume
        failure = nil
        candidates = StreamCandidates.candidates(for: item)
        candidateIndex = 0

        configureAudioSession()
        play(candidates[0], kind: item.kind)
    }

    /// Attempts one candidate url. Failure advances to the next rather than
    /// stopping, because a panel that will not serve MKV will often serve the
    /// same film as HLS if simply asked.
    private func play(_ url: URL, kind: MediaKind) {

        // A player-style agent keeps providers from refusing the connection.
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": "Kanal/1.0 (AppleCoreMedia)",
                ],
            ]
        )
        let playerItem = AVPlayerItem(asset: asset)
        // Live streams should join at the edge, not at the start of the buffer.
        playerItem.automaticallyPreservesTimeOffsetFromLive = kind == .liveTV

        observe(playerItem, url: url)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        startTimeout(for: url)

        if let resume = resumeTarget, kind != .liveTV {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
    }

    /// Some streams neither play nor fail.
    ///
    /// An AVI, measured on device, leaves `AVPlayerItem.status` at `.unknown`
    /// indefinitely — no error is ever delivered, so the spinner simply never
    /// stops. A viewer reads that as the app being broken. Giving up after a
    /// while and saying why is the only honest behaviour.
    private func startTimeout(for url: URL) {
        timeout?.cancel()
        // Speculative candidates get less patience than the provider's own url.
        let isLast = candidateIndex + 1 >= candidates.count
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

    /// Moves to the next candidate, or reports the failure if there are none.
    ///
    /// Every candidate before the last is a guess at a format the panel might
    /// also serve, so *any* failure on one — a 404 as readily as a bad
    /// container — just means the guess was wrong. Only the provider's own url
    /// comes last, and only its failure is worth showing to anyone.
    private func advance(after error: (any Error)?, url: URL) {
        guard let item = currentItem else { return }

        timeout?.cancel()

        guard candidateIndex + 1 < candidates.count else {
            failure = PlaybackFailure(error: error, url: url)
            player.pause()
            return
        }
        candidateIndex += 1
        play(candidates[candidateIndex], kind: item.kind)
    }

    public func retry() {
        guard let currentItem else { return }
        start(item: currentItem, resumingAt: resumeTarget)
    }

    /// The url actually being attempted, for diagnostics.
    public var currentURL: URL? {
        candidates.indices.contains(candidateIndex) ? candidates[candidateIndex] : nil
    }

    public func stop() {
        timeout?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        bufferObservation = nil
    }

    public func snapshot() -> Snapshot {
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        return Snapshot(
            position: position.isFinite ? position : 0,
            duration: duration.isFinite ? duration : 0
        )
    }

    private func observe(_ playerItem: AVPlayerItem, url: URL) {
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .failed:
                    self.advance(after: item.error, url: url)
                case .readyToPlay:
                    self.failure = nil
                    self.timeout?.cancel()
                default:
                    break
                }
            }
        }
        bufferObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.isStalled = !item.isPlaybackLikelyToKeepUp
            }
        }
    }

    private func configureAudioSession() {
        #if !os(macOS)
        // Keeps audio playing when the phone is on silent, as a TV app should.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}

/// `AVPlayerViewController`, bridged.
struct SystemPlayer {
    let controller: PlayerController
}

#if os(iOS) || os(tvOS)
extension SystemPlayer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let viewController = AVPlayerViewController()
        viewController.player = controller.player
        viewController.allowsPictureInPicturePlayback = true
        #if os(iOS)
        viewController.canStartPictureInPictureAutomaticallyFromInline = true
        viewController.videoGravity = .resizeAspect
        #endif
        return viewController
    }

    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        if viewController.player !== controller.player {
            viewController.player = controller.player
        }
    }
}
#else
extension SystemPlayer: NSViewRepresentable {
    // AppKit ships `AVPlayerView` rather than a view controller.
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = controller.player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== controller.player {
            view.player = controller.player
        }
    }
}
#endif
