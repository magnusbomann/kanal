import KanalCore
import SwiftUI

/// The household: everyone's profile, and the code that protects them.
///
/// Reachable from settings and from the picker. Getting here from a child's
/// profile costs the code — otherwise the lock would only be as strong as a
/// child's willingness to press "Manage profiles".
public struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ProfileDraft?
    @State private var settingCode = false
    @State private var confirmingRemoval = false

    public init() {}

    public var body: some View {
        List {
            peopleSection
            codeSection
            if model.activeProfile?.isRestricted == true {
                withheldSection
            }
        }
        .navigationTitle(Text(UIStrings.profiles))
        .kanalPlainListBackground()
        .background(KanalColor.background)
        .sheet(item: $editing) { draft in
            NavigationStack { ProfileEditorView(draft: draft) }
        }
        .sheet(isPresented: $settingCode) {
            ParentalCodeView(purpose: .set) { code in
                model.setParentalCode(code)
            }
        }
        .sheet(isPresented: $confirmingRemoval) {
            ParentalCodeView(purpose: .unlock) { entered in
                guard model.parentalCode.matches(entered) else { return false }
                model.setParentalCode(nil)
                return true
            }
        }
    }

    private var peopleSection: some View {
        Section(String(UIStrings.sectionPeople)) {
            ForEach(model.profiles) { profile in
                Button {
                    editing = ProfileDraft(profile: profile)
                } label: {
                    HStack(spacing: KanalMetrics.md) {
                        ProfileAvatar(profile: profile, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: profile.displayName)
                                .font(KanalFont.body(16))
                                .foregroundStyle(KanalColor.primaryText)
                            Text(profile.isRestricted
                                ? profile.maturity.displayNameResource
                                : CoreStrings.maturityAdult)
                                .font(KanalFont.caption(11))
                                .foregroundStyle(KanalColor.secondaryText)
                        }
                        Spacer()
                        if profile.id == model.activeProfileID {
                            Text(UIStrings.inUse)
                                .font(KanalFont.caption(10))
                                .foregroundStyle(KanalColor.accentSolid)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(KanalColor.tertiaryText)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Button {
                editing = ProfileDraft(profile: nil)
            } label: {
                Label(String(UIStrings.addProfile), systemImage: "plus.circle.fill")
                    .foregroundStyle(KanalColor.accentSolid)
            }
        }
    }

    private var codeSection: some View {
        Section {
            Button(String(model.parentalCode.isSet ? UIStrings.changeCode : UIStrings.setCode)) {
                settingCode = true
            }
            if model.parentalCode.isSet {
                Button(String(UIStrings.removeCode), role: .destructive) {
                    confirmingRemoval = true
                }
            }
        } header: {
            Text(UIStrings.sectionParentalCode)
        } footer: {
            Text(model.parentalCode.isSet ? UIStrings.codeFooterSet : UIStrings.codeFooterUnset)
        }
    }

    /// Says plainly how much this profile is not being shown.
    ///
    /// A child's library looking small is a fact worth stating rather than
    /// hiding — it is the difference between "this app has nothing" and "a
    /// grown-up chose this".
    private var withheldSection: some View {
        Section {
            LabeledContent(
                String(UIStrings.labelHiddenHere),
                value: model.withheldCount.formatted()
            )
        } footer: {
            Text(UIStrings.withheldFooter)
        }
    }
}
