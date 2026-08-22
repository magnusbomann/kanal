import KanalCore
import SwiftUI

/// The Apple TV side of handoff.
///
/// This screen exists because typing a provider URL with a remote is the worst
/// minute in any TV app. Kanal never asks anyone to do it.
public struct PairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var host: PairingHost?

    public init() {}

    public var body: some View {
        VStack(spacing: KanalMetrics.xl) {
            VStack(alignment: .leading, spacing: KanalMetrics.md) {
                Text(UIStrings.appName)
                    .kanalLabel(14)
                    .foregroundStyle(KanalColor.accentSolid)
                Text(UIStrings.pairingHeadline)
                    .kanalDisplay(KanalMetrics.scale * 40)
                    .foregroundStyle(KanalColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(UIStrings.pairingBody)
                    .font(KanalFont.body(KanalMetrics.scale * 14))
                    .foregroundStyle(KanalColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: KanalMetrics.xl) {
                codePanel
                statusPanel
            }
        }
        .padding(KanalMetrics.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KanalColor.background)
        .task {
            let host = PairingHost { sources in
                Task { @MainActor in
                    for source in sources { await model.add(source) }
                }
            }
            self.host = host
            host.start()
        }
        .onDisappear { host?.stop() }
        .onChange(of: statusIsReceived) { _, received in
            if received { dismiss() }
        }
    }

    @ViewBuilder
    private var codePanel: some View {
        if let invitation = host?.invitation, let url = invitation.url {
            VStack(spacing: KanalMetrics.md) {
                QRCode(contents: url.absoluteString)
                    .frame(width: KanalMetrics.scale * 210, height: KanalMetrics.scale * 210)
                    .padding(KanalMetrics.md)
                    .background(.white, in: .rect(cornerRadius: KanalMetrics.cardRadius, style: .continuous))

                Text(invitation.code)
                    .kanalDisplay(KanalMetrics.scale * 26)
                    .tracking(KanalMetrics.scale * 6)
                    .foregroundStyle(KanalColor.primaryText)
            }
        } else {
            ProgressView().controlSize(.large)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            switch host?.state ?? .idle {
            case .idle, .waiting:
                Label(String(UIStrings.pairingWaiting), systemImage: "iphone.radiowaves.left.and.right")
            case .receiving:
                Label(String(UIStrings.pairingReceiving), systemImage: "arrow.down.circle")
            case .received(let count):
                Label(String(UIStrings.playlistCount(count)), systemImage: "checkmark.circle.fill")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
            }

            Divider().overlay(KanalColor.separator)

            Text(UIStrings.pairingPrivacy)
                .font(KanalFont.body(KanalMetrics.scale * 12))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(KanalFont.body(KanalMetrics.scale * 14))
        .foregroundStyle(KanalColor.secondaryText)
        .frame(maxWidth: KanalMetrics.scale * 280, alignment: .leading)
    }

    private var statusIsReceived: Bool {
        if case .received = host?.state { return true }
        return false
    }
}
