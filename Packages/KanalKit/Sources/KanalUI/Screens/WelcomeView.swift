import KanalCore
import SwiftUI

/// Setup, in one field.
///
/// Everything a competitor asks for up front — playlist type, EPG url, buffer
/// size, category mapping — is either detected or defaulted. The screen shows
/// what it worked out as you type, so the automation is visible rather than
/// something you have to trust blindly.
public struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var detection: SourceDetector.Detection?
    @State private var credentialsPortal: PortalRequest?
    @State private var isWorking = false
    @State private var isPairing = false
    @FocusState private var isFieldFocused: Bool

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.xl) {
                headline
                #if os(tvOS)
                // Typing a provider url with a remote is the worst minute in
                // any TV app, so the phone route comes first and the field is
                // the fallback rather than the other way round.
                handoffInvitation
                #endif
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
            XtreamCredentialsSheet(portal: request.url)
        }
        .onChange(of: input) { _, newValue in
            detection = newValue.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : SourceDetector.detect(newValue)
        }
    }

    // MARK: Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Text(UIStrings.appName)
                .kanalLabel(13)
                .foregroundStyle(KanalColor.accentSolid)

            VStack(alignment: .leading, spacing: -6) {
                Text(UIStrings.welcomeHeadlineTop)
                    .kanalDisplay(headlineSize)
                    .foregroundStyle(KanalColor.primaryText)
                Text(UIStrings.welcomeHeadlineBottom)
                    .kanalDisplay(headlineSize)
                    .foregroundStyle(KanalColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(UIStrings.welcomeBody)
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

                if !input.isEmpty {
                    Button {
                        input = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KanalColor.tertiaryText)
                    }
                    .buttonStyle(.plain)
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

            HStack(spacing: KanalMetrics.md) {
                Button {
                    Task { await submit() }
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
    }

    private var reassurance: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Divider().overlay(KanalColor.separator)
            HStack(spacing: KanalMetrics.md) {
                ForEach(formatChips, id: \.self) { text in
                    MetaChip(text)
                }
            }
            Text(UIStrings.welcomeDisclaimer)
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if os(tvOS)
    private var handoffInvitation: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Button(String(UIStrings.welcomeHandoffAction)) { isPairing = true }
                .buttonStyle(KanalPrimaryButtonStyle(size: 18))
            Text(UIStrings.welcomeHandoffHint)
                .font(KanalFont.body(KanalMetrics.scale * 12))
                .foregroundStyle(KanalColor.tertiaryText)
        }
        .fullScreenCover(isPresented: $isPairing) {
            PairingView()
        }
    }
    #endif

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

    private var formatChips: [String] {
        [
            String(UIStrings.formatM3U),
            String(UIStrings.formatXtream),
            String(UIStrings.formatGuide),
        ]
    }

    private func submit() async {
        isFieldFocused = false
        if case .needsCredentials(let portal, _) = detection {
            credentialsPortal = PortalRequest(url: portal)
            return
        }
        isWorking = true
        await model.addSource(from: input)
        isWorking = false
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
        case .complete(let source):
            switch source.kind {
            case .xtream:
                String(UIStrings.detectedXtream(host: source.portalURL?.host() ?? ""))
            case .m3u:
                String(UIStrings.detectedM3U(host: source.playlistURL?.host() ?? ""))
            case .localFile:
                String(UIStrings.detectedFile)
            }
        case .pastedText:
            String(UIStrings.detectedPastedText)
        case .needsCredentials(_, let host):
            String(UIStrings.detectedNeedsCredentials(host: host))
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
