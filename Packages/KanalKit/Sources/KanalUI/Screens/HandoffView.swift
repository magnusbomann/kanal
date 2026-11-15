#if os(iOS)
import AVFoundation
import KanalCore
import SwiftUI

/// The phone side of handoff: point the camera at the Apple TV, done.
public struct HandoffView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var guest = PairingGuest()
    @State private var scanned: Pairing.Invitation?
    @State private var cameraDenied = false
    @State private var preparationError: String?
    /// An invitation that arrived as a link, rather than through this
    /// screen's own camera, is only acted on once someone has said yes.
    ///
    /// The link names where to send and carries the key to seal it with, and
    /// sending means the provider's sign-in and the household's profiles.
    /// Acting on it unasked let anyone on the same network collect all of
    /// that with one tapped link — and let a child's profile reach a screen
    /// that Settings keeps behind the code.
    private let requiresConfirmation: Bool
    @State private var isConfirmed = false
    @State private var isUnlocked = false

    public init(invitation: Pairing.Invitation? = nil, requiresConfirmation: Bool = false) {
        _scanned = State(initialValue: invitation)
        self.requiresConfirmation = requiresConfirmation && invitation != nil
    }

    /// The invitation to act on, once nothing stands in the way.
    private var approved: Pairing.Invitation? {
        requiresConfirmation && !isConfirmed ? nil : scanned
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let invitation = scanned, requiresConfirmation, !isConfirmed {
                if model.needsCodeForSettings, !isUnlocked {
                    ParentalCodeView(purpose: .unlock, dismissesOnSuccess: false) { entered in
                        guard model.parentalCode.matches(entered) else { return false }
                        isUnlocked = true
                        return true
                    }
                } else {
                    confirmation(for: invitation)
                }
            } else if scanned == nil && !cameraDenied {
                scanner
            } else {
                status
            }
        }
        .background(KanalColor.background)
        .navigationTitle(Text(UIStrings.handoffTitle))
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: approved) {
            guard let invitation = approved else { return }
            preparationError = nil
            while model.phase == .starting {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
            }
            do {
                let payload = try await model.makePairingPayload()
                guard !Task.isCancelled else { return }
                guest.send(payload, to: invitation)
            } catch {
                preparationError = error.localizedDescription
            }
        }
        .onDisappear { guest.cancel() }
    }

    private func confirmation(for invitation: Pairing.Invitation) -> some View {
        VStack(spacing: KanalMetrics.lg) {
            Spacer()
            Image(systemName: "appletv.fill")
                .font(.system(size: 40))
                .foregroundStyle(KanalColor.accentSolid)
            Text(UIStrings.handoffConfirmTitle)
                .font(KanalFont.section(19))
                .foregroundStyle(KanalColor.primaryText)
                .multilineTextAlignment(.center)
            Text(UIStrings.handoffConfirmBody(invitation.code))
                .font(KanalFont.body(14))
                .foregroundStyle(KanalColor.secondaryText)
                .multilineTextAlignment(.center)
            Button(String(UIStrings.handoffConfirmSend)) { isConfirmed = true }
                .buttonStyle(KanalPrimaryButtonStyle())
                .accessibilityIdentifier("handoff.confirm.send")
            Button(String(UIStrings.cancel)) { dismiss() }
                .buttonStyle(KanalSecondaryButtonStyle())
            Spacer()
        }
        .padding(KanalMetrics.lg)
        .frame(maxWidth: .infinity)
    }

    private var scanner: some View {
        ZStack {
            QRScannerView { code in
                guard scanned == nil,
                      let url = URL(string: code),
                      let invitation = Pairing.Invitation(url: url)
                else { return false }
                scanned = invitation
                return true
            } onDenied: {
                cameraDenied = true
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                Text(UIStrings.handoffAim)
                    .kanalLabel(13)
                    .foregroundStyle(.white)
                    .padding(.horizontal, KanalMetrics.lg)
                    .padding(.vertical, KanalMetrics.md)
                    .kanalGlassOverVideo(cornerRadius: 100)
                    .padding(.bottom, KanalMetrics.xxl)
            }
        }
    }

    private var status: some View {
        VStack(spacing: KanalMetrics.lg) {
            Spacer()
            if cameraDenied && scanned == nil {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(KanalColor.tertiaryText)
                Text(UIStrings.handoffCameraTitle)
                    .font(KanalFont.section(17))
                    .foregroundStyle(KanalColor.primaryText)
                Text(UIStrings.handoffCameraBody)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
                    .multilineTextAlignment(.center)
                Button(String(UIStrings.openSettings)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(KanalSecondaryButtonStyle())
            } else if let preparationError {
                Text(preparationError)
                    .font(KanalFont.body())
                    .foregroundStyle(KanalColor.secondaryText)
                Button(String(UIStrings.tryAgain)) {
                    self.preparationError = nil
                    scanned = nil
                }
                .buttonStyle(KanalSecondaryButtonStyle())
            } else {
                switch guest.state {
                case .idle, .searching:
                ProgressView().controlSize(.large).tint(KanalColor.accentSolid)
                Text(UIStrings.handoffFinding)
                    .font(KanalFont.section(17))
                    .foregroundStyle(KanalColor.primaryText)
                case .connecting, .transmitting, .awaitingReceipt:
                ProgressView().controlSize(.large).tint(KanalColor.accentSolid)
                Text(UIStrings.handoffSending)
                    .font(KanalFont.section(17))
                    .foregroundStyle(KanalColor.primaryText)
                case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(KanalColor.success)
                Text(UIStrings.handoffSent)
                    .font(KanalFont.section(17))
                    .foregroundStyle(KanalColor.primaryText)
                Text(UIStrings.handoffSentBody)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
                Button(String(UIStrings.done)) { dismiss() }
                    .buttonStyle(KanalPrimaryButtonStyle())
                case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(KanalColor.warning)
                Text(message)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
                    .multilineTextAlignment(.center)
                Button(String(UIStrings.tryAgain)) {
                    scanned = nil
                    cameraDenied = false
                }
                .buttonStyle(KanalSecondaryButtonStyle())
                }
            }

            Spacer()
        }
        .padding(KanalMetrics.lg)
        .frame(maxWidth: .infinity)
    }

}

/// A camera preview that reports QR payloads.
struct QRScannerView: UIViewControllerRepresentable {
    /// Returns whether the code was one this screen can use.
    let onScan: (String) -> Bool
    let onDenied: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.coordinator = context.coordinator
        controller.onDenied = onDenied
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Bool
        /// Scanning is one-shot: a QR code fires many times per second and the
        /// first frame is as good as the fiftieth. But only a code that was
        /// accepted ends it — any other QR in view (a router label, a poster)
        /// used to be the one shot, and the television's own code was then
        /// never read however long it was held up.
        private var hasScanned = false

        init(onScan: @escaping (String) -> Bool) {
            self.onScan = onScan
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            // Read the payload out before crossing into isolated code:
            // `AVMetadataObject` is not Sendable, but the string it carries is.
            guard let object = objects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue
            else { return }

            // The delegate queue is set to `.main` at configuration time, so
            // this callback genuinely arrives on the main actor.
            MainActor.assumeIsolated {
                guard !hasScanned else { return }
                hasScanned = onScan(value)
            }
        }
    }

    final class ScannerController: UIViewController {
        var coordinator: Coordinator?
        var onDenied: (() -> Void)?
        /// Touched only from `sessionQueue` once configured, per AVFoundation's
        /// own threading rules — `startRunning` blocks and must stay off main.
        nonisolated(unsafe) private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "kanal.scanner.session")
        private var preview: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            Task { @MainActor [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                if granted { self.configure() } else { self.onDenied?() }
            }
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                onDenied?()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onDenied?()
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            self.preview = preview

            sessionQueue.async { [session] in session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            sessionQueue.async { [session] in session.stopRunning() }
        }
    }
}
#endif
