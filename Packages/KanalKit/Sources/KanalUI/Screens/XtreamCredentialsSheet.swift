import KanalCore
import SwiftUI

/// The only extra step Kanal ever asks for: a username and password, and only
/// when the pasted link did not already carry them.
public struct XtreamCredentialsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public let portal: URL
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false

    public init(portal: URL) {
        self.portal = portal
    }

    public var body: some View {
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

            Button(String(UIStrings.signInConnect)) {
                Task {
                    isWorking = true
                    await model.addXtreamSource(
                        portal: portal,
                        username: username.trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                    isWorking = false
                    dismiss()
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
        .background(KanalColor.background)
        #if !os(tvOS)
        .presentationDetents([.medium])
        .presentationBackground(KanalColor.background)
        #endif
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
    }
}
