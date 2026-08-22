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
    @Environment(\.dismiss) private var dismiss

    public let item: MediaItem
    @State private var controller = PlayerController()

    public init(item: MediaItem) {
        self.item = item
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SystemPlayer(controller: controller)
                .ignoresSafeArea()

            if controller.isStalled {
                stallOverlay
            }
            if let message = controller.errorMessage {
                errorOverlay(message)
            }
        }
        .task {
            let resume = model.progress(for: item).flatMap { progress in
                progress.isWorthResuming ? progress.position : nil
            }
            controller.start(item: item, resumingAt: resume)
        }
        .onDisappear {
            let snapshot = controller.snapshot()
            if item.kind != .liveTV, snapshot.duration > 0 {
                model.record(
                    itemID: item.id,
                    position: snapshot.position,
                    duration: snapshot.duration
                )
            }
            controller.stop()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
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

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: KanalMetrics.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(KanalColor.warning)
            Text(UIStrings.streamFailedTitle)
                .font(KanalFont.section(17))
                .foregroundStyle(.white)
            Text(message)
                .font(KanalFont.body(13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(String(UIStrings.tryAgain)) { controller.retry() }
                .buttonStyle(KanalSecondaryButtonStyle())
        }
        .padding(KanalMetrics.xl)
        .frame(maxWidth: 380)
        .kanalGlassPanel()
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
    public private(set) var errorMessage: String?

    private var statusObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var currentItem: MediaItem?
    private var resumeTarget: TimeInterval?

    public init() {}

    public func start(item: MediaItem, resumingAt resume: TimeInterval?) {
        currentItem = item
        resumeTarget = resume
        errorMessage = nil

        configureAudioSession()

        // A player-style agent keeps providers from refusing the connection.
        let asset = AVURLAsset(
            url: item.streamURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": "Kanal/1.0 (AppleCoreMedia)",
                ],
            ]
        )
        let playerItem = AVPlayerItem(asset: asset)
        // Live streams should join at the edge, not at the start of the buffer.
        playerItem.automaticallyPreservesTimeOffsetFromLive = item.kind == .liveTV

        observe(playerItem)
        player.replaceCurrentItem(with: playerItem)
        player.play()

        if let resume, item.kind != .liveTV {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
    }

    public func retry() {
        guard let currentItem else { return }
        start(item: currentItem, resumingAt: resumeTarget)
    }

    public func stop() {
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

    private func observe(_ playerItem: AVPlayerItem) {
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    self.errorMessage = item.error?.localizedDescription
                        ?? String(CoreStrings.badResponse)
                } else if item.status == .readyToPlay {
                    self.errorMessage = nil
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
