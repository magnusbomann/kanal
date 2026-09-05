import KanalCore
import SwiftUI

/// The only extra step Kanal ever asks for: a username and password, and only
/// when the pasted link did not already carry them.
public struct XtreamCredentialsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public let portal: URL
    private let replacementSource: PlaylistSource?
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var submissionError: String?

    private let onSuccess: (() -> Void)?

    public init(
        portal: URL,
        replacing replacementSource: PlaylistSource? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        self.portal = portal
        self.replacementSource = replacementSource
        self.onSuccess = onSuccess
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.lg) {
                VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                    Text(UIStrings.signInTitle)
                        .kanalDisplay(32)
                        .foregroundStyle(KanalColor.primaryText)
                    Text(portal.host() ?? portal.absoluteString)
                        .font(KanalFont.body(14))
                        .foregroundStyle(KanalColor.secondaryText)
                }

                VStack(spacing: KanalMetrics.sm) {
                    field(UIStrings.signInUsername, text: $username, isSecure: false)
                    field(UIStrings.signInPassword, text: $password, isSecure: true)
                }

                if let submissionError {
                    SetupErrorMessage(message: submissionError)
                }

                if isWorking, let progress = model.connectionProgress {
                    ConnectionProgressView(progress: progress, compact: true)
                }

                Button {
                    beginConnection()
                } label: {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(UIStrings.signInConnect)
                    }
                }
                .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))
                .disabled(username.isEmpty || password.isEmpty || isWorking)

                Text(UIStrings.signInPrivacy)
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(KanalMetrics.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KanalColor.background)
        .scrollDismissesKeyboard(.interactively)
        #if !os(tvOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(KanalColor.background)
        #endif
        .onChange(of: username) { _, _ in submissionError = nil }
        .onChange(of: password) { _, _ in submissionError = nil }
    }

    @ViewBuilder
    private func field(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        Group {
            if isSecure {
                SecureField(String(label), text: text)
            } else {
                TextField(String(label), text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(KanalFont.body(16))
        .foregroundStyle(KanalColor.primaryText)
        #if !os(tvOS)
        .autocorrectionDisabled()
        #endif
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .padding(.horizontal, KanalMetrics.md)
        .frame(minHeight: 52)
        .kanalGlassPanel(cornerRadius: 16)
        .disabled(isWorking)
    }

    private func beginConnection() {
        guard !isWorking else { return }
        submissionError = nil
        isWorking = true
        Task { await connect() }
    }

    private func connect() async {
        do {
            if let replacementSource {
                try await model.repairXtreamSource(
                    replacementSource,
                    portal: portal,
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } else {
                try await model.addXtreamSource(
                    portal: portal,
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }
            dismiss()
            onSuccess?()
        } catch {
            submissionError = error.localizedDescription
        }
        isWorking = false
    }
}
