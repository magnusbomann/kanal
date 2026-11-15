import KanalCore
import SwiftUI

/// One search field across the whole library.
///
/// Two stages, and the second one is the point. The local index answers
/// instantly and offline. Only when that comes up short does Kanal ask what the
/// words mean — so someone searching "Løvenes konge" finds a provider entry
/// called "The Lion King" without ever knowing the two are different strings.
public struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    @State private var query = ""
    @State private var outcome = SearchOutcome(items: [])
    @State private var isSearchingWider = false
    @State private var searchTask: Task<Void, Never>?
    #if os(iOS)
    @FocusState private var isSearchFocused: Bool
    #endif

    public init() {}

    public var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: String(UIStrings.searchEmptyTitle),
                    message: String(UIStrings.searchEmptyBody)
                )
            } else if groupedResults.isEmpty {
                if isSearchingWider {
                    LoadingView(message: String(UIStrings.searchLookingWider))
                } else {
                    EmptyStateView(
                        symbol: "questionmark.circle",
                        title: String(UIStrings.searchNoResultsTitle),
                        message: String(UIStrings.searchNoResultsBody)
                    )
                }
            } else {
                results
            }
        }
        .background(KanalColor.background)
        .modifier(SearchField(query: $query, isFocused: focusBinding))
        .navigationTitle(Text(UIStrings.search))
        #if os(iOS)
        .task(id: navigator.searchFocusRequest) {
            guard navigator.searchFocusRequest > 0 else { return }
            await Task.yield()
            isSearchFocused = true
        }
        #endif
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onDisappear { searchTask?.cancel() }
    }

    private var focusBinding: FocusState<Bool>.Binding? {
        #if os(iOS)
        $isSearchFocused
        #else
        nil
        #endif
    }

    private var results: some View {
        List {
            if let matchedVia = outcome.matchedVia {
                TranslationNote(query: trimmedQuery, matchedTitle: matchedVia)
                    .kanalListRowBackground(KanalColor.background)
                    .kanalHiddenRowSeparator()
            }
            if !groupedResults.channels.isEmpty {
                Section {
                    ForEach(groupedResults.channels) { group in
                        Button {
                            navigator.play(
                                group,
                                remembered: model.watchState.workingVariants[group.id]
                            )
                        } label: {
                            SearchRow(channel: group)
                        }
                        .buttonStyle(.plain)
                        .kanalListRowBackground(KanalColor.background)
                    }
                } header: {
                    Text(CoreStrings.liveTV)
                }
            }

            if !groupedResults.movies.isEmpty {
                Section {
                    ForEach(groupedResults.movies) { movie in
                        Button {
                            navigator.showDetails(for: movie)
                        } label: {
                            SearchRow(item: movie)
                        }
                        .buttonStyle(.plain)
                        .kanalListRowBackground(KanalColor.background)
                    }
                } header: {
                    Text(CoreStrings.movies)
                }
            }

            if !groupedResults.series.isEmpty {
                Section {
                    ForEach(groupedResults.series) { group in
                        Button {
                            guard let first = group.episodes.first else { return }
                            navigator.showDetails(for: first, seriesGroup: group)
                        } label: {
                            SearchRow(series: group)
                        }
                        .buttonStyle(.plain)
                        .kanalListRowBackground(KanalColor.background)
                    }
                } header: {
                    Text(CoreStrings.series)
                }
            }
        }
        .listStyle(.plain)
        .kanalPlainListBackground()
        .overlay(alignment: .bottom) {
            if isSearchingWider {
                WideningIndicator()
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var groupedResults: LibrarySearchResults {
        model.library.groupedSearchResults(from: outcome.items)
    }

    /// Debounced: the local pass is cheap, but the widening pass is a network
    /// call and should not fire on every keystroke.
    private func scheduleSearch(_ newValue: String) {
        searchTask?.cancel()
        let needle = newValue.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else {
            outcome = SearchOutcome(items: [])
            isSearchingWider = false
            return
        }

        searchTask = Task {
            // A tiny debounce avoids starting the lazy provider-sized index
            // for letters the person is still in the middle of typing.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let local = await model.localSearch(needle)
            guard !Task.isCancelled else { return }
            outcome = SearchOutcome(items: local)
            guard local.count < 3 else {
                isSearchingWider = false
                return
            }

            try? await Task.sleep(for: .milliseconds(270))
            guard !Task.isCancelled else { return }
            isSearchingWider = true
            let result = await model.search(needle, localResults: local)
            guard !Task.isCancelled else { return }
            outcome = result
            isSearchingWider = false
        }
    }
}

/// Whether the system's own search field can be trusted here.
///
/// It cannot on a Mac running the iPad app. UIKit's search controller sizes
/// itself from the screen while it takes over the tab bar, and on a Mac that
/// lookup is an assertion — `_screenBasedFocusUnsupported` — so the app closed
/// the moment the field was activated or put away. Three crash reports, one
/// stack. The Mac gets a field Kanal draws itself; nothing else changes.
enum SearchFieldSupport {
    static let usesSystemField = !ProcessInfo.processInfo.isiOSAppOnMac
}

/// The search field: the system's where it works, Kanal's own where it does not.
struct SearchField: ViewModifier {
    @Binding var query: String
    let isFocused: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        #if os(iOS)
        if SearchFieldSupport.usesSystemField, let isFocused {
            content
                .searchable(text: $query, prompt: Text(UIStrings.searchPrompt))
                .searchFocused(isFocused)
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { inlineField }
        }
        #else
        content.searchable(text: $query, prompt: Text(UIStrings.searchPrompt))
        #endif
    }

    #if os(iOS)
    private var inlineField: some View {
        HStack(spacing: KanalMetrics.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KanalColor.secondaryText)
            inlineTextField
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(KanalColor.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(UIStrings.clear))
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.horizontal, KanalMetrics.md)
        .frame(minHeight: KanalMetrics.minTarget)
        .background(KanalColor.surface, in: .capsule)
        .padding(.horizontal, KanalMetrics.md)
        .padding(.vertical, KanalMetrics.sm)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(KanalColor.background)
    }

    @ViewBuilder
    private var inlineTextField: some View {
        let field = TextField(
            "", text: $query,
            prompt: Text(UIStrings.searchPrompt).foregroundStyle(KanalColor.secondaryText)
        )
        .textFieldStyle(.plain)
        .font(KanalFont.body(15))
        .foregroundStyle(KanalColor.primaryText)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.search)
        .accessibilityIdentifier("search.field")
        if let isFocused {
            field.focused(isFocused)
        } else {
            field
        }
    }
    #endif
}

/// Explains a result that only turned up under another name.
struct TranslationNote: View {
    let query: String
    let matchedTitle: String

    var body: some View {
        HStack(spacing: KanalMetrics.sm) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KanalColor.accentSolid)
            Text(UIStrings.searchMatchedVia(matchedTitle))
                .font(KanalFont.body(13))
                .foregroundStyle(KanalColor.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.vertical, KanalMetrics.sm)
        .background(KanalColor.surface, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.vertical, KanalMetrics.xs)
    }
}

struct WideningIndicator: View {
    var body: some View {
        HStack(spacing: KanalMetrics.sm) {
            ProgressView().controlSize(.small)
            Text(UIStrings.searchWidening)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.secondaryText)
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.vertical, KanalMetrics.sm)
        .kanalGlassPill(interactive: false)
        .padding(.bottom, KanalMetrics.xxl * 2)
    }
}

struct SearchRow: View {
    let title: String
    let artworkURL: URL?
    let symbolName: String
    let subtitle: String

    init(item: MediaItem) {
        self.title = item.title
        self.artworkURL = item.logoURL
        self.symbolName = item.kind.symbolName
        self.subtitle = [item.year.map(String.init), item.category.map(CategoryLocalizer.display)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    init(channel: ChannelGroup) {
        self.title = channel.name
        self.artworkURL = channel.logoURL
        self.symbolName = MediaKind.liveTV.symbolName
        var details = channel.categories.prefix(1).map(CategoryLocalizer.display)
        if channel.hasAlternatives {
            details.append(String(UIStrings.sourceCount(channel.variants.count)))
        }
        self.subtitle = details.joined(separator: " · ")
    }

    init(series: SeriesGroup) {
        self.title = series.name
        self.artworkURL = series.artworkURL
        self.symbolName = MediaKind.series.symbolName
        if series.needsEpisodeLoad {
            self.subtitle = series.category.map(CategoryLocalizer.display) ?? ""
        } else {
            self.subtitle = String(UIStrings.episodeCount(series.episodes.count))
        }
    }

    var body: some View {
        HStack(spacing: KanalMetrics.md) {
            Artwork(url: artworkURL, title: title, symbol: symbolName, contentMode: .fit)
                .frame(width: 52, height: 52)
                .background(KanalColor.surface)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.primaryText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(KanalFont.body(12))
                        .foregroundStyle(KanalColor.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, KanalMetrics.xs)
    }
}
