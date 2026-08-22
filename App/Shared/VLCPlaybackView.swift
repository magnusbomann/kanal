import KanalCore
import KanalUI
import SwiftUI
import VLCKit

/// Playback for everything AVFoundation refuses.
///
/// This is the whole reason VLCKit is here. A real provider's catalogue is
/// almost entirely Matroska — 31,027 of 31,176 films on the one measured — and
/// `AVPlayer` cannot open a single one of them. The system player still leads
/// for live TV and MP4, because it brings picture-in-picture, AirPlay and the
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

    static func dismantleUIViewController(
        _ controller: VLCPlaybackController,
        coordinator: Coordinator
    ) {
        controller.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    struct Coordinator {}
}

final class VLCPlaybackController: UIViewController, VLCMediaPlayerDelegate {

    private let request: AlternativePlayerRequest
    private let player = VLCMediaPlayer()
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
        // Providers routinely refuse anything that does not look like a player,
        // matching what the system path already sends.
        media?.addOptions([
            "http-user-agent": "Kanal/1.0 (AppleCoreMedia)",
            // A few seconds of network cache is the difference between smooth
            // playback and constant stalling on a home connection.
            "network-caching": 3000,
        ])

        player.media = media
        player.drawable = view
        player.delegate = self
        player.play()
    }

    func stop() {
        reportProgress()
        player.stop()
    }

    // MARK: - VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .playing:
            seekToStartIfNeeded()
        case .error:
            request.onFailure(String(localized: CoreStrings.alternativeEngineFailed))
        case .stopped:
            reportProgress()
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        reportProgress()
    }

    // MARK: - Position

    /// Resuming has to wait for playback to actually begin — seeking a stream
    /// that has not opened yet is silently ignored.
    private func seekToStartIfNeeded() {
        guard !hasSeekedToStart, let start = request.startAt, start > 1 else { return }
        hasSeekedToStart = true
        player.time = VLCTime(number: NSNumber(value: Int(start * 1000)))
    }

    private func reportProgress() {
        let position = Double(player.time.value?.intValue ?? 0) / 1000
        let length = Double(player.media?.length.value?.intValue ?? 0) / 1000
        guard length > 0 else { return }
        request.onProgress(position, length)
    }
}
