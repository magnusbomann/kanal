import KanalCore
import SwiftUI

/// "Who is watching?"
///
/// This screen does two jobs at once, and the second is why it is worth having
/// even in a household that barely uses profiles: the catalogue loads *behind*
/// it. A real provider is 135 MB and takes the better part of a minute; the
/// seconds a person spends finding their own face are seconds nobody spends
/// looking at a progress bar.
///
/// So the loading state here is a quiet line of text, never a blocker. Picking
/// a profile while the library is still arriving is allowed — the app simply
/// lands on the loading screen it would have shown anyway.
public struct ProfilePickerView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ProfileDraft?
    @State private var isManaging = false
    @State private var codeChallenge: CodeChallenge?

    public init() {}

    public var body: some View {
        ZStack {
            KanalColor.background.ignoresSafeArea()

            VStack(spacing: KanalMetrics.xl) {
                Spacer(minLength: 0)

                Text(UIStrings.whoIsWatching)
                    .kanalDisplay(KanalMetrics.scale * 34)
                    .foregroundStyle(KanalColor.primaryText)
                    .multilineTextAlignment(.center)

                grid

                status

                Spacer(minLength: 0)

                Button(String(UIStrings.manageProfiles)) {
                    guardedByCode { isManaging = true }
                }
                .buttonStyle(KanalSecondaryButtonStyle(size: 14))
                .padding(.bottom, KanalMetrics.xl)
            }
            .padding(.horizontal, KanalMetrics.lg)
        }
        .sheet(item: $editing) { draft in
            NavigationStack { ProfileEditorView(draft: draft) }
        }
        .sheet(isPresented: $isManaging) {
            NavigationStack { ProfilesView() }
        }
        .sheet(item: $codeChallenge) { challenge in
            ParentalCodeView(purpose: .unlock) { entered in
                guard model.parentalCode.matches(entered) else { return false }
                challenge.onSuccess()
                return true
            }
        }
    }

    // MARK: - Pieces

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: KanalMetrics.lg) {
            ForEach(model.profiles) { profile in
                Button {
                    Task { await model.activate(profile) }
                } label: {
                    VStack(spacing: KanalMetrics.sm) {
                        ProfileAvatar(
                            profile: profile,
                            size: avatarSize,
                            isSelected: profile.id == model.activeProfileID
                        )
                        Text(profile.displayName)
                            .font(KanalFont.section(15))
                            .foregroundStyle(KanalColor.primaryText)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }

            // Adding a profile is a grown-up's action, so it asks for the code
            // when one is set — otherwise a child could simply make themselves
            // a new profile with no limit.
            Button {
                guardedByCode { editing = ProfileDraft(profile: nil) }
            } label: {
                VStack(spacing: KanalMetrics.sm) {
                    RoundedRectangle(cornerRadius: avatarSize * 0.24, style: .continuous)
                        .strokeBorder(KanalColor.separator, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .frame(width: avatarSize, height: avatarSize)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: avatarSize * 0.3, weight: .semibold))
                                .foregroundStyle(KanalColor.secondaryText)
                        }
                    Text(UIStrings.addProfile)
                        .font(KanalFont.section(15))
                        .foregroundStyle(KanalColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 720)
    }

    /// What the app is doing behind this screen. Silent once the library is up.
    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .loading(let message):
            Label {
                Text(message)
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(KanalFont.body(13))
            .foregroundStyle(KanalColor.secondaryText)
        case .failed(let message):
            Text(message)
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.warning)
                .multilineTextAlignment(.center)
        default:
            if model.isRefreshingLibrary {
                Label {
                    Text(UIStrings.updatingLibrary)
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.tertiaryText)
            }
        }
    }

    /// Runs an action, behind the parental code when one is set.
    ///
    /// The picker is reachable from a child's profile — that is how a parent
    /// takes the device back — so everything on it that could widen access has
    /// to be held.
    private func guardedByCode(_ action: @escaping () -> Void) {
        if model.parentalCode.isSet {
            codeChallenge = CodeChallenge(onSuccess: action)
        } else {
            action()
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: avatarSize + KanalMetrics.lg), spacing: KanalMetrics.lg)]
    }

    private var avatarSize: CGFloat {
        #if os(tvOS)
        160
        #else
        104
        #endif
    }
}

/// A pending action waiting on the parental code.
struct CodeChallenge: Identifiable {
    let id = UUID()
    let onSuccess: () -> Void
}

/// A profile being created or edited. Wrapped so `sheet(item:)` can carry
/// "new profile" as a value rather than needing a second boolean.
struct ProfileDraft: Identifiable {
    let id = UUID()
    let profile: Profile?
}
