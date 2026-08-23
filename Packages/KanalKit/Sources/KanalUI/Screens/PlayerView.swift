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
    @Environment(\.alternativePlayer) private var alternativePlayer
    @Environment(\.dismiss) private var dismiss

    public let plan: PlaybackPlan
    public var item: MediaItem { plan.item }
    @State private var system = SystemPlaybackController()
    @State private var engine: PlaybackEngine = .system
    @State private var alternativeError: String?
    @State private var alternativeSnapshot: (position: TimeInterval, duration: TimeInterval) = (0, 0)
    @State private var handle: AlternativePlayerHandle?

    public init(plan: PlaybackPlan) {
        self.plan = plan
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine == .alternative, let handle {
                handle.surface
                    .ignoresSafeArea()
                if let alternativeError {
                    errorOverlay(.other(alternativeError))
                } else {
                    PlayerChrome(
                        controller: handle.controller,
                        title: item.title,
                        subtitle: subtitle,
                        onClose: { dismiss() }
                    )
                }
            } else {
                VideoSurface(player: system.player)
                    .ignoresSafeArea()
                if let failure = system.failure {
                    errorOverlay(failure)
                } else {
                    PlayerChrome(
                        controller: system,
                        title: item.title,
                        subtitle: subtitle,
                        trailingAccessory: AnyView(AirPlayButton()),
                        onClose: { dismiss() }
                    )
                }
            }
        }
        .task { startPlayback() }
        // A container the system player cannot open is routed across rather
        // than shown to anyone as an error.
        .onChange(of: system.failure) { _, failure in
            guard let failure, alternativePlayer != nil else { return }
            if case .unsupportedContainer = failure {
                system.stop()
                handle = alternativePlayer?(alternativeRequest)
                engine = .alternative
            }
        }
        .onDisappear {
            recordProgress()
            system.stop()
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    private var subtitle: String? {
        item.kind == .liveTV
            ? model.nowPlaying(on: item)?.title
            : item.category.map(CategoryLocalizer.display)
    }

    private var alternativeRequest: AlternativePlayerRequest {
        AlternativePlayerRequest(
            url: item.streamURL,
            startAt: resumePosition,
            title: item.title,
            subtitle: subtitle,
            onProgress: { position, duration in
                alternativeSnapshot = (position, duration)
            },
            onFailure: { message in alternativeError = message },
            onClose: { dismiss() }
        )
    }

    private var resumePosition: TimeInterval? {
        model.progress(for: item).flatMap { $0.isWorthResuming ? $0.position : nil }
    }

    private func startPlayback() {
        // Without a second engine there is nothing to escalate to, so the
        // system player takes everything and guesses at formats on failure.
        engine = alternativePlayer == nil ? .system : PlaybackEngine.preferred(for: item)
        guard engine == .system else {
            handle = alternativePlayer?(alternativeRequest)
            return
        }
        system.start(plan: plan, resumingAt: resumePosition)
    }

    private func recordProgress() {
        // A channel that finally played on its third variant should open on
        // that one next time.
        if let owner = system.playingOwnerID, owner != item.id {
            model.rememberWorkingVariant(owner, forGroup: item.id)
        }
        guard item.kind != .liveTV else { return }
        let snapshot = engine == .alternative ? alternativeSnapshot : system.snapshot()
        guard snapshot.duration > 0 else { return }
        model.record(itemID: item.id, position: snapshot.position, duration: snapshot.duration)
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
                Button(String(UIStrings.closePlayer)) { dismiss() }
                    .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                Button(String(UIStrings.tryAgain)) { system.retry() }
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
        case .serverNotStreamable: String(UIStrings.playbackServerBody)
        case .rejected: String(UIStrings.playbackRejectedBody)
        case .offline: String(UIStrings.playbackOfflineBody)
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
            .frame(width: 40, height: 40)
            .kanalGlassOverVideo(cornerRadius: 100)
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
