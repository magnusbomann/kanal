import KanalCore
import SwiftUI

/// The controls for narrowing a browse screen.
///
/// Menus rather than a sheet: choosing "newest" should be two taps, not a
/// modal. Controls that would be empty are not drawn at all — a country filter
/// on a catalogue with no country data is a dead end dressed as a feature.
public struct FilterBar: View {
    @Binding public var filter: LibraryFilter

    public let categories: [String]
    public let countries: [String]
    public let decades: [Int]

    public init(
        filter: Binding<LibraryFilter>,
        categories: [String],
        countries: [String],
        decades: [Int]
    ) {
        self._filter = filter
        self.categories = categories
        self.countries = countries
        self.decades = decades
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: KanalMetrics.sm) {
                sortMenu

                if !categories.isEmpty {
                    menu(
                        label: filter.category.map(CategoryLocalizer.display)
                            ?? String(UIStrings.filterGenre),
                        isActive: filter.category != nil
                    ) {
                        Button(String(UIStrings.filterAll)) { filter.category = nil }
                        Divider()
                        ForEach(categories, id: \.self) { category in
                            Button(CategoryLocalizer.display(category)) { filter.category = category }
                        }
                    }
                }

                if !countries.isEmpty {
                    menu(
                        label: filter.country.map(countryName) ?? String(UIStrings.filterCountry),
                        isActive: filter.country != nil
                    ) {
                        Button(String(UIStrings.filterAll)) { filter.country = nil }
                        Divider()
                        ForEach(countries, id: \.self) { code in
                            Button(countryName(code)) { filter.country = code }
                        }
                    }
                }

                if decades.count > 1 {
                    menu(
                        label: filter.decade.map { String(UIStrings.decadeLabel($0)) }
                            ?? String(UIStrings.filterDecade),
                        isActive: filter.decade != nil
                    ) {
                        Button(String(UIStrings.filterAll)) { filter.decade = nil }
                        Divider()
                        ForEach(decades, id: \.self) { decade in
                            Button(String(UIStrings.decadeLabel(decade))) { filter.decade = decade }
                        }
                    }
                }

                if filter.isNarrowed {
                    Button(String(UIStrings.filterClear)) {
                        filter = LibraryFilter(sort: filter.sort)
                    }
                    .buttonStyle(KanalChipButtonStyle(isSelected: false))
                }
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.vertical, KanalMetrics.sm)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var sortMenu: some View {
        menu(label: sortName(filter.sort), isActive: filter.sort != .recommended) {
            ForEach(LibraryFilter.Sort.allCases) { option in
                Button(sortName(option)) { filter.sort = option }
            }
        }
    }

    @ViewBuilder
    private func menu(
        label: String, isActive: Bool, @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: KanalMetrics.xs) {
                Text(label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .menuStyle(.button)
        .buttonStyle(KanalChipButtonStyle(isSelected: isActive))
    }

    private func sortName(_ sort: LibraryFilter.Sort) -> String {
        switch sort {
        case .recommended: String(UIStrings.sortRecommended)
        case .newest: String(UIStrings.sortNewest)
        case .oldest: String(UIStrings.sortOldest)
        case .alphabetical: String(UIStrings.sortAlphabetical)
        }
    }

    /// Foundation already knows every country's name in the viewer's language.
    private func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
