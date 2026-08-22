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

    public init() {}

    public var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: String(UIStrings.searchEmptyTitle),
                    message: String(UIStrings.searchEmptyBody)
                )
            } else if outcome.items.isEmpty {
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
        .searchable(text: $query, prompt: Text(UIStrings.searchPrompt))
        .navigationTitle(Text(UIStrings.search))
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onDisappear { searchTask?.cancel() }
    }

    private var results: some View {
        List {
            if let matchedVia = outcome.matchedVia {
                TranslationNote(query: trimmedQuery, matchedTitle: matchedVia)
                    .kanalListRowBackground(KanalColor.background)
                    .kanalHiddenRowSeparator()
            }
            ForEach(outcome.items) { item in
                Button {
                    navigator.play(item)
                } label: {
                    SearchRow(item: item)
                }
                .buttonStyle(.plain)
                .kanalListRowBackground(KanalColor.background)
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

        // Show local hits immediately, then widen behind them.
        outcome = SearchOutcome(items: model.library.search(needle))

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let hadLocalHits = outcome.items.count >= 3
            if !hadLocalHits { isSearchingWider = true }
            let result = await model.search(needle)
            guard !Task.isCancelled else { return }
            outcome = result
            isSearchingWider = false
        }
    }
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
    let item: MediaItem

    var body: some View {
        HStack(spacing: KanalMetrics.md) {
            Artwork(url: item.logoURL, title: item.title, symbol: item.kind.symbolName, contentMode: .fit)
                .frame(width: 52, height: 52)
                .background(KanalColor.surface)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.primaryText)
                    .lineLimit(1)
                Text([item.kind.displayName, item.category.map(CategoryLocalizer.display)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, KanalMetrics.xs)
    }
}
