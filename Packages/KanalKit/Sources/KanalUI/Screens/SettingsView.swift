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

    public init() {}

    public var body: some View {
        List {
            playlistsSection
            #if os(iOS)
            appleTVSection
            #endif
            librarySection
            if model.diagnostics.hasFindings {
                dataQualitySection
            }
            disclaimerSection
        }
        .navigationTitle(Text(UIStrings.settings))
        .kanalPlainListBackground()
        .background(KanalColor.background)
        .sheet(isPresented: $isAddingSource) {
            NavigationStack { WelcomeView() }
        }
    }

    private var playlistsSection: some View {
        Section(String(UIStrings.sectionPlaylists)) {
            ForEach(model.sources) { source in
                SourceRow(source: source, isActive: source.id == model.activeSource?.id)
                    .contentShape(.rect)
                    .onTapGesture { Task { await model.switchTo(source) } }
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
