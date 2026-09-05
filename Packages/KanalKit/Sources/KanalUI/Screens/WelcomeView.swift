import KanalCore
import SwiftUI

/// Setup, in one field.
///
/// Everything a competitor asks for up front — playlist type, EPG url, buffer
/// size, category mapping — is either detected or defaulted. The machinery is
/// intentionally invisible: people bring the one thing their provider gave
/// them, and Kanal handles the vocabulary they should never have to learn.
public struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var detection: SourceDetector.Detection?
    @State private var credentialsPortal: PortalRequest?
    @State private var isWorking = false
    #if os(tvOS)
    @State private var showPairing: Bool
    #endif
    @State private var submissionError: String?
    @FocusState private var isFieldFocused: Bool

    private let onSuccess: (() -> Void)?
    private let replacementSource: PlaylistSource?

    public init(
        replacing replacementSource: PlaylistSource? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        self.replacementSource = replacementSource
        self.onSuccess = onSuccess
        #if os(tvOS)
        _showPairing = State(initialValue: replacementSource == nil)
        #endif
    }

    public var body: some View {
        #if os(tvOS)
        tvSetup
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.xl) {
                headline
                field
                reassurance
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.vertical, KanalMetrics.xxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(KanalColor.background)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $credentialsPortal) { request in
            XtreamCredentialsSheet(
                portal: request.url,
                replacing: replacementSource,
                onSuccess: onSuccess
            )
        }
        .onChange(of: input) { _, newValue in
            submissionError = nil
            detection = newValue.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : SourceDetector.detect(newValue)
        }
        #endif
    }

    #if os(tvOS)
    /// A single, remote-friendly setup screen. The QR route stays visible by
    /// default; manual entry is deliberately retained for repair and for a
    /// phone that cannot scan the code.
    private var tvSetup: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: KanalMetrics.xl) {
                if showPairing {
                    VStack(alignment: .leading, spacing: KanalMetrics.md) {
                        Text(UIStrings.pairingShowQR).kanalDisplay(64)
                        Text(UIStrings.pairingBody)
                            .font(KanalFont.body(24))
                            .foregroundStyle(KanalColor.secondaryText)
                    }
                } else {
                    headline
                }

                HStack(alignment: .top, spacing: KanalMetrics.xxl) {
                    if showPairing {
                        PairingView(showsHeader: false, showsClose: false)
                            .frame(maxWidth: .infinity, minHeight: 340)
                    }
                    manualSetup
                        .frame(maxWidth: showPairing ? 350 : 900)
                }
            }
            .padding(.horizontal, KanalMetrics.xxl)
            .padding(.vertical, KanalMetrics.xxl)
            .frame(maxWidth: 1680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(KanalColor.background)
        .sheet(item: $credentialsPortal) { request in
            XtreamCredentialsSheet(portal: request.url, replacing: replacementSource, onSuccess: onSuccess)
        }
        .onChange(of: input) { _, newValue in
            submissionError = nil
            detection = newValue.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : SourceDetector.detect(newValue)
        }
    }

    private var manualSetup: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Text(UIStrings.pairingManualTitle)
                .kanalLabel(26)
                .foregroundStyle(KanalColor.primaryText)
            Text(UIStrings.pairingManualBody)
                .font(KanalFont.body(22))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if showPairing && replacementSource == nil {
                Button(String(UIStrings.pairingManualTitle)) { showPairing = false }
                    .buttonStyle(KanalSecondaryButtonStyle(size: 22))
                Text(UIStrings.welcomeDisclaimer)
                    .font(KanalFont.body(22))
                    .foregroundStyle(KanalColor.secondaryText)
            } else {
                if replacementSource == nil {
                    Button(String(UIStrings.pairingShowQR)) { showPairing = true }
                        .buttonStyle(KanalSecondaryButtonStyle(size: 22))
                }
                field
                reassurance
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    // MARK: Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Text(UIStrings.appName)
                .kanalLabel(13)
                .foregroundStyle(KanalColor.accentSolid)

            VStack(alignment: .leading, spacing: -6) {
                if replacementSource == nil {
                    Text(UIStrings.welcomeHeadlineTop)
                        .kanalDisplay(headlineSize)
                        .foregroundStyle(KanalColor.primaryText)
                    Text(UIStrings.welcomeHeadlineBottom)
                        .kanalDisplay(headlineSize)
                        .foregroundStyle(KanalColor.secondaryText)
                } else {
                    Text(UIStrings.repairTitle)
                        .kanalDisplay(headlineSize)
                        .foregroundStyle(KanalColor.primaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(replacementSource == nil ? UIStrings.welcomeBody : UIStrings.repairBody)
                .font(KanalFont.body(16))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            HStack(spacing: KanalMetrics.sm) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KanalColor.tertiaryText)

                TextField(String(UIStrings.welcomeFieldPrompt), text: $input, axis: .vertical)
                    .font(KanalFont.body(16))
                    .foregroundStyle(KanalColor.primaryText)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isFieldFocused)
                    #if !os(tvOS)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #endif
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .disabled(isWorking)

                if !input.isEmpty {
                    Button {
                        input = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KanalColor.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel(Text(UIStrings.clear))
                }
            }
            .padding(.horizontal, fieldChromeInset)
            .padding(.vertical, fieldChromeInset)
            .frame(minHeight: 56)
            #if !os(tvOS)
            .kanalGlassPanel(cornerRadius: 18)
            #endif

            if let detection {
                DetectionSummary(detection: detection)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let submissionError {
                SetupErrorMessage(message: submissionError)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isWorking, let progress = model.connectionProgress {
                ConnectionProgressView(progress: progress, compact: true)
                    .padding(.horizontal, KanalMetrics.md)
            }

            HStack(spacing: KanalMetrics.md) {
                Button {
                    beginSubmission()
                } label: {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(continueTitle)
                    }
                }
                .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))
                .disabled(!canContinue || isWorking)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: detection)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: submissionError)
    }

    private var reassurance: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Divider().overlay(KanalColor.separator)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: KanalMetrics.md) {
                    ForEach(promiseChips, id: \.self) { text in
                        MetaChip(text)
                    }
                }
                VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                    ForEach(promiseChips, id: \.self) { text in
                        MetaChip(text)
                    }
                }
            }
            Text(UIStrings.welcomeDisclaimer)
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Behaviour

    /// tvOS text fields come with their own container, so ours would nest.
    private var fieldChromeInset: CGFloat {
        #if os(tvOS)
        0
        #else
        KanalMetrics.md
        #endif
    }

    private var headlineSize: CGFloat {
        #if os(tvOS)
        76
        #else
        44
        #endif
    }

    private var canContinue: Bool {
        switch detection {
        case .complete, .pastedText, .needsCredentials: true
        case .unrecognized, nil: false
        }
    }

    private var continueTitle: String {
        if case .needsCredentials = detection { return String(UIStrings.welcomeAddSignIn) }
        return String(UIStrings.welcomeContinue)
    }

    private var promiseChips: [String] {
        [
            String(UIStrings.welcomePromiseOneLink),
            String(UIStrings.welcomePromiseAutomatic),
            String(UIStrings.welcomePromisePrivate),
        ]
    }

    private func beginSubmission() {
        guard !isWorking else { return }
        isFieldFocused = false
        submissionError = nil
        if case .needsCredentials(let portal, _) = detection {
            credentialsPortal = PortalRequest(url: portal)
            return
        }
        isWorking = true

        // Capture the value tied to this spinner. The field is disabled until
        // the attempt settles, so a result can never appear under another URL.
        let submittedInput = input
        Task { await submit(submittedInput) }
    }

    private func submit(_ submittedInput: String) async {
        do {
            if let replacementSource {
                _ = try await model.repairSource(replacementSource, from: submittedInput)
            } else {
                _ = try await model.addSource(from: submittedInput)
            }
            onSuccess?()
        } catch {
            submissionError = error.localizedDescription
        }
        isWorking = false
    }
}

/// Keeps a failed setup attempt beside the field that can repair it. This is
/// intentionally a message, not a dead-end error screen.
struct SetupErrorMessage: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: KanalMetrics.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KanalColor.warning)
            Text(message)
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.vertical, KanalMetrics.sm)
        .background(KanalColor.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Live feedback on what the pasted string turned out to be.
struct DetectionSummary: View {
    let detection: SourceDetector.Detection

    var body: some View {
        HStack(spacing: KanalMetrics.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(message)
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.vertical, KanalMetrics.sm)
        .background(KanalColor.surface, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var symbol: String {
        switch detection {
        case .complete: "checkmark.seal.fill"
        case .pastedText: "doc.on.clipboard.fill"
        case .needsCredentials: "person.badge.key.fill"
        case .unrecognized: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch detection {
        case .complete, .pastedText: KanalColor.success
        case .needsCredentials: KanalColor.accentSolid
        case .unrecognized: KanalColor.warning
        }
    }

    private var message: String {
        switch detection {
        case .complete:
            String(UIStrings.detectedReady)
        case .pastedText:
            String(UIStrings.detectedPastedText)
        case .needsCredentials:
            String(UIStrings.detectedSignInNeeded)
        case .unrecognized(let reason):
            reason
        }
    }
}

/// Identity wrapper so `.sheet(item:)` can be driven by a portal url without
/// conforming a standard-library type.
struct PortalRequest: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
