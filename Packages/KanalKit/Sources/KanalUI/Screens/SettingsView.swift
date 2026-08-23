import KanalCore
import SwiftUI

/// Settings, deliberately short.
///
/// The promise is that Kanal needs no configuration, so this screen manages
/// sources and nothing else. Anything that could be decided automatically is
/// decided automatically instead of appearing here as a switch.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingSource = false
    @State private var renaming: PlaylistSource?
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
            profilesSection
            playlistsSection
            #if os(iOS)
            appleTVSection
            #endif
            librarySection
            if model.diagnostics.hasFindings {
                dataQualitySection
            }
            creditsSection
            disclaimerSection
        }
        .navigationTitle(Text(UIStrings.settings))
        .kanalPlainListBackground()
        .background(KanalColor.background)
        .sheet(isPresented: $isAddingSource) {
            NavigationStack { WelcomeView() }
        }
        .sheet(item: $renaming) { source in
            RenameSourceSheet(source: source)
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
        var parts: [String] = []
        switch source.kind {
        case .xtream: parts.append(String(UIStrings.sourceKindXtream))
        case .m3u: parts.append(String(UIStrings.sourceKindM3U))
        case .localFile: parts.append(String(UIStrings.sourceKindPasted))
        }
        if let refreshed = source.lastRefreshedAt {
            parts.append(String(UIStrings.sourceUpdated(
                refreshed.formatted(.relative(presentation: .named))
            )))
        }
        return parts.joined(separator: " · ")
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
