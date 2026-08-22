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
/// This is why VLC is here at all. A real provider's catalogue is almost
/// entirely Matroska — 31,027 of 31,176 films on the one measured — and
/// `AVPlayer` cannot open a single one. The system player still leads for live
/// TV and MP4, because it brings picture-in-picture, AirPlay and the
/// platform's own transport controls; this takes what is left.
///
/// Lives in the app target rather than in `KanalKit` so the package, and its
/// tests, stay free of a very large binary dependency.
struct VLCPlaybackView: UIViewControllerRepresentable {
    let request: AlternativePlayerRequest

    func makeUIViewController(context: Context) -> VLCPlaybackController {
        VLCPlaybackController(request: request)
    }

    func updateUIViewController(_ controller: VLCPlaybackController, context: Context) {}

    static func dismantleUIViewController(_ controller: VLCPlaybackController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
final class VLCPlaybackController: UIViewController {

    private let request: AlternativePlayerRequest
    private let player = VLCMediaPlayer()
    private var proxy: PlayerDelegateProxy?
    private var hasSeekedToStart = false

    init(request: AlternativePlayerRequest) {
        self.request = request
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

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
            onState: { [weak self] state in
                Task { @MainActor in self?.handle(state) }
            },
            onTime: { [weak self] in
                Task { @MainActor in self?.reportProgress() }
            }
        )
        self.proxy = proxy

        player.media = media
        player.drawable = view
        player.delegate = proxy
        player.play()
    }

    func stop() {
        reportProgress()
        player.stop()
    }

    // MARK: - State

    private func handle(_ state: VLCMediaPlayerState) {
        switch state {
        case .playing:
            seekToStartIfNeeded()
        case .error:
            request.onFailure(String(localized: CoreStrings.alternativeEngineFailed))
        case .stopped, .ended:
            reportProgress()
        default:
            break
        }
    }

    /// Resuming has to wait for playback to actually begin — seeking a stream
    /// that has not opened yet is silently ignored.
    private func seekToStartIfNeeded() {
        guard !hasSeekedToStart, let start = request.startAt, start > 1 else { return }
        hasSeekedToStart = true
        player.time = VLCTime(int: Int32(start * 1000))
    }

    private func reportProgress() {
        let position = Double(player.time.intValue) / 1000
        let length = Double(player.media?.length.intValue ?? 0) / 1000
        guard length > 0 else { return }
        request.onProgress(position, length)
    }
}

/// Bridges VLC's delegate onto the main actor.
///
/// `VLCMediaPlayerDelegate` carries no isolation and `VLCMediaPlayer` is not
/// `Sendable`, so rather than assuming which thread VLC calls from, the proxy
/// reads what it needs where the call lands and forwards only values.
private final class PlayerDelegateProxy: NSObject, VLCMediaPlayerDelegate, @unchecked Sendable {
    private let onState: @Sendable (VLCMediaPlayerState) -> Void
    private let onTime: @Sendable () -> Void

    init(
        onState: @escaping @Sendable (VLCMediaPlayerState) -> Void,
        onTime: @escaping @Sendable () -> Void
    ) {
        self.onState = onState
        self.onTime = onTime
    }

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let player = aNotification?.object as? VLCMediaPlayer else { return }
        onState(player.state)
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        onTime()
    }
}
