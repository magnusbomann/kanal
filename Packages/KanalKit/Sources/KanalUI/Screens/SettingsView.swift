import KanalCore
import SwiftUI

/// Settings, deliberately short.
///
/// The promise is that Kanal needs no configuration, so this screen manages
/// sources and nothing else. Anything that could be decided automatically is
/// decided automatically instead of appearing here as a switch.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @Environment(Navigator.self) private var navigator: Navigator?
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingSource = false
    @State private var renaming: PlaylistSource?
    @State private var repairing: PlaylistSource?
    /// Whether the code has been given during this visit. Not remembered:
    /// walking out of settings and back in asks again, which is the behaviour
    /// a parent expects from a lock.
    @State private var isUnlocked = false

    public init() {}

    public var body: some View {
        Group {
            if model.needsCodeForSettings, !isUnlocked {
                // Settings is where a playlist is added and a profile's limits
                // are set. Left open, it would be the way around every other
                // control on this screen.
                ParentalCodeView(purpose: .unlock) { entered in
                    guard model.parentalCode.matches(entered) else { return false }
                    isUnlocked = true
                    return true
                }
            } else {
                settings
            }
        }
    }

    private var settings: some View {
        List {
            proSection
            profilesSection
            audioSection
            playlistsSection
            #if os(iOS)
            appleTVSection
            #endif
            syncSection
            librarySection
            if model.diagnostics.hasFindings {
                dataQualitySection
            }
            supportSection
            creditsSection
            disclaimerSection
            #if DEBUG
            developerSection
            #endif
        }
        .navigationTitle(Text(UIStrings.settings))
        .kanalPlainListBackground()
        .background(KanalColor.background)
        .toolbar {
            #if os(tvOS)
            ToolbarItem(placement: .cancellationAction) {
                Button(String(UIStrings.done)) { dismiss() }
            }
            #endif
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $isAddingSource) {
            addSourceView
        }
        .fullScreenCover(item: $renaming) { source in
            RenameSourceSheet(source: source)
        }
        .fullScreenCover(item: $repairing) { source in
            repairSourceView(source)
        }
        #else
        .sheet(isPresented: $isAddingSource) {
            addSourceView
        }
        .sheet(item: $renaming) { source in
            RenameSourceSheet(source: source)
        }
        .sheet(item: $repairing) { source in
            repairSourceView(source)
        }
        #endif
    }

    private var addSourceView: some View {
        NavigationStack {
            WelcomeView(onSuccess: { isAddingSource = false })
        }
    }

    private func repairSourceView(_ source: PlaylistSource) -> some View {
        NavigationStack {
            WelcomeView(replacing: source, onSuccess: { repairing = nil })
        }
    }

    /// Where someone goes looking when they want to pay, or to check that
    /// they already have. A subscription with no visible state is the kind
    /// people cancel because they cannot tell what they are paying for.
    @ViewBuilder
    private var proSection: some View {
        Section(String(UIStrings.proSettingsSection)) {
            if purchases.isPro {
                Label {
                    Text(UIStrings.proSettingsActive)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(KanalColor.accentSolid)
                }
                #if os(iOS)
                Link(
                    String(UIStrings.proSettingsManage),
                    destination: URL(string: "https://apps.apple.com/account/subscriptions")!
                )
                #endif
            } else {
                Button {
                    navigator?.wantsPro = true
                } label: {
                    Label {
                        Text(UIStrings.proSettingsUpgrade)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(KanalColor.accentSolid)
                    }
                }
            }
        }
    }

    #if DEBUG
    /// Pluss without paying. Compiled out of every build that is not a debug
    /// build, alongside the `-kanal-pro` launch argument and `KANAL_PRO`.
    /// Deliberately unlocalised — nobody outside this repository sees it.
    private var developerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { purchases.isPro },
                set: { value in Task { await purchases.setDebugPro(value) } }
            )) {
                Text(verbatim: "Force Kanal Pluss")
            }
            Button {
                Task { await purchases.setDebugPro(nil) }
            } label: {
                Text(verbatim: "Use the real receipt")
            }
        } header: {
            Text(verbatim: "Developer")
        } footer: {
            Text(verbatim: "Also: -kanal-pro 1 as a launch argument, or KANAL_PRO=1.")
        }
    }
    #endif

    private var syncSection: some View {
        Section(String(UIStrings.sectionSync)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncStatusTitle)
                    if case .current(let date) = model.syncState {
                        Text(UIStrings.syncLastUpdated(
                            date.formatted(.relative(presentation: .named))
                        ))
                            .font(KanalFont.body(12))
                            .foregroundStyle(KanalColor.tertiaryText)
                    } else if case .failed(let message) = model.syncState {
                        Text(verbatim: message)
                            .font(KanalFont.body(12))
                            .foregroundStyle(KanalColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: syncStatusSymbol)
                    .foregroundStyle(syncStatusColour)
            }

            Button {
                Task { await model.syncNow() }
            } label: {
                Label(String(UIStrings.syncNow), systemImage: "arrow.trianglehead.2.clockwise.rotate.90.icloud")
            }
            .disabled(model.syncState == .syncing)

            Text(UIStrings.syncBody)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
        }
    }

    private var syncStatusTitle: String {
        switch model.syncState {
        case .waiting: String(UIStrings.syncWaiting)
        case .syncing: String(UIStrings.syncWorking)
        case .current: String(UIStrings.syncCurrent)
        case .unavailable: String(UIStrings.syncUnavailable)
        case .failed: String(UIStrings.syncFailed)
        }
    }

    private var syncStatusSymbol: String {
        switch model.syncState {
        case .waiting: "icloud"
        case .syncing: "arrow.trianglehead.2.clockwise.rotate.90.icloud"
        case .current: "checkmark.icloud.fill"
        case .unavailable, .failed: "exclamationmark.icloud.fill"
        }
    }

    private var syncStatusColour: Color {
        switch model.syncState {
        case .current: KanalColor.success
        case .unavailable, .failed: KanalColor.warning
        default: KanalColor.accentSolid
        }
    }

    private var profilesSection: some View {
        Section(String(UIStrings.sectionProfiles)) {
            NavigationLink {
                ProfilesView()
            } label: {
                HStack(spacing: KanalMetrics.md) {
                    if let profile = model.activeProfile {
                        ProfileAvatar(profile: profile, size: 32)
                    }
                    Text(UIStrings.profiles)
                }
            }
            if model.profiles.count > 1 {
                Button(String(UIStrings.switchProfile)) {
                    model.beginChoosingProfile()
                }
            }
        }
    }

    /// The one playback preference worth a settings row.
    ///
    /// Off unless someone asks for it: most people watching a foreign film
    /// want the language it was made in, and a dub chosen on their behalf
    /// because of the phone's region would be the app deciding a matter of
    /// taste. A child's profile is set the other way round when it is created,
    /// and a parent adjusts that where they set the age limit.
    @ViewBuilder
    private var audioSection: some View {
        if let profile = model.activeProfile {
            AudioLanguagePicker(
                selection: Binding(
                    get: { profile.preferredAudioLanguage },
                    set: { language in
                        var updated = profile
                        updated.preferredAudioLanguage = language
                        Task { await model.updateProfile(updated) }
                    }
                ),
                footer: profile.isRestricted
                    ? UIStrings.audioLanguageChildFooter
                    : UIStrings.audioLanguageFooter
            )
        }
    }

    private var playlistsSection: some View {
        Section(String(UIStrings.sectionPlaylists)) {
            ForEach(model.sources) { source in
                SourceRow(source: source, isActive: source.id == model.activeSource?.id)
                    .contentShape(.rect)
                    .onTapGesture { Task { await model.switchTo(source) } }
                    #if !os(tvOS)
                    .swipeActions(edge: .leading) {
                        Button(String(UIStrings.rename)) { renaming = source }
                            .tint(KanalColor.accentSolid)
                    }
                    .contextMenu {
                        Button {
                            renaming = source
                        } label: {
                            Label(String(UIStrings.rename), systemImage: "pencil")
                        }
                        Button {
                            repairing = source
                        } label: {
                            Label(String(UIStrings.changeTVService), systemImage: "wrench.and.screwdriver")
                        }
                    }
                    #endif
                    #if !os(tvOS)
                    .swipeActions {
                        Button(String(UIStrings.remove), role: .destructive) {
                            Task { await model.remove(source) }
                        }
                    }
                    #endif
            }
            Button {
                isAddingSource = true
            } label: {
                Label(String(UIStrings.addPlaylist), systemImage: "plus.circle.fill")
                    .foregroundStyle(KanalColor.accentSolid)
            }
        }
    }

    #if os(iOS)
    private var appleTVSection: some View {
        Section(String(UIStrings.sectionAppleTV)) {
            NavigationLink {
                HandoffView()
            } label: {
                Label(String(UIStrings.handoffTitle), systemImage: "appletv.fill")
            }
            .disabled(model.sources.isEmpty)
            Text(UIStrings.handoffSettingsHint)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
        }
    }
    #endif

    private var librarySection: some View {
        Section(String(UIStrings.sectionLibrary)) {
            LabeledContent(String(UIStrings.labelChannels), value: model.library.channels.count.formatted())
            LabeledContent(String(UIStrings.labelFilms), value: model.library.movies.count.formatted())
            LabeledContent(String(UIStrings.labelSeries), value: model.library.series.count.formatted())
            LabeledContent(
                String(UIStrings.labelGuide),
                value: String(model.guide == nil ? UIStrings.guideNotLoaded : UIStrings.guideLoaded)
            )
            Button(String(UIStrings.refreshNow)) {
                Task { await model.refreshActiveSource() }
            }
        }
    }

    /// Only shown when there is something to report. A clean load says nothing,
    /// because a permanent "everything is fine" row is just noise.
    private var dataQualitySection: some View {
        Section(String(UIStrings.sectionDataQuality)) {
            let diagnostics = model.diagnostics

            if diagnostics.skippedPlaylistLines > 0 {
                finding(
                    String(UIStrings.skippedLines(diagnostics.skippedPlaylistLines)),
                    symbol: "list.bullet.rectangle"
                )
            }
            if !diagnostics.guideRepairs.isEmpty {
                finding(String(UIStrings.guideRepaired), symbol: "bandage")
            }
            if diagnostics.guideIsPartial {
                finding(String(UIStrings.guidePartial), symbol: "scissors")
            }
            if diagnostics.guideProgrammes > 0, diagnostics.channelsWithID > 0 {
                finding(
                    String(UIStrings.guideCoverage(Int(diagnostics.guideCoverage * 100))),
                    symbol: "chart.pie"
                )
                finding(
                    String(UIStrings.guideProgrammes(diagnostics.guideProgrammes)),
                    symbol: "calendar"
                )
            }

            Text(UIStrings.dataQualityIntro)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
        }
    }

    private func finding(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .font(KanalFont.body(14))
                .foregroundStyle(KanalColor.primaryText)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(KanalColor.warning)
        }
    }

    private var supportSection: some View {
        Section(String(UIStrings.sectionSupport)) {
            NavigationLink {
                SupportReportView()
            } label: {
                Label(String(UIStrings.supportTitle), systemImage: "lifepreserver.fill")
            }
        }
    }

    /// TMDB's terms require this attribution wherever their data appears, so it
    /// is shown whenever the app was built with a key. Wikidata is CC0 and
    /// requires nothing — crediting it is simply right.
    private var creditsSection: some View {
        Section(String(UIStrings.sectionCredits)) {
            NavigationLink {
                LicensesView()
            } label: {
                Label(String(UIStrings.licenses), systemImage: "doc.text")
            }
            Text(UIStrings.creditWikidata)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
            if model.usesArtworkProvider {
                Text(UIStrings.creditTMDB)
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.tertiaryText)
            }
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text(UIStrings.settingsDisclaimer)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
        }
    }
}

struct SourceRow: View {
    let source: PlaylistSource
    let isActive: Bool

    var body: some View {
        HStack(spacing: KanalMetrics.md) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? KanalColor.accentSolid : KanalColor.tertiaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.primaryText)
                Text(subtitle)
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.secondaryText)
            }
        }
    }

    private var subtitle: String {
        if let refreshed = source.lastRefreshedAt {
            return String(UIStrings.sourceUpdated(
                refreshed.formatted(.relative(presentation: .named))
            ))
        }
        return String(UIStrings.sourceReady)
    }
}


/// Renaming a playlist.
///
/// The name Kanal detects is the provider's hostname, which is where a list
/// came from rather than what anyone calls it. One field, prefilled, done.
struct RenameSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let source: PlaylistSource
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.lg) {
            Text(UIStrings.renameTitle)
                .kanalDisplay(30)
                .foregroundStyle(KanalColor.primaryText)

            TextField(String(UIStrings.renamePrompt), text: $name)
                .textFieldStyle(.plain)
                .font(KanalFont.body(17))
                .foregroundStyle(KanalColor.primaryText)
                .padding(.horizontal, KanalMetrics.md)
                .frame(minHeight: 52)
                #if !os(tvOS)
                .kanalGlassPanel(cornerRadius: 16)
                #endif

            Text(UIStrings.renameHint)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(String(UIStrings.save)) {
                Task {
                    await model.rename(source, to: name)
                    dismiss()
                }
            }
            .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer(minLength: 0)
        }
        .padding(KanalMetrics.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KanalColor.background)
        .onAppear { name = source.name }
        #if !os(tvOS)
        .presentationDetents([.medium])
        .presentationBackground(KanalColor.background)
        #endif
    }
}
