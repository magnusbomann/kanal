import KanalCore
import SwiftUI

/// Creating or changing one person's profile.
///
/// The order of this screen is the argument it makes: who, then what they may
/// watch, then — only for a child — what a grown-up has actually let through.
/// The last section is not an advanced option tucked at the bottom. It is the
/// mechanism, because an IPTV catalogue carries no age limits of its own and
/// no honest app can pretend the unlabelled remainder is safe.
struct ProfileEditorView: View {
    @State private var showsAllCategories = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let draft: ProfileDraft

    @State private var name = ""
    @State private var symbolName = Profile.avatarSymbols[0]
    @State private var colorIndex = 0
    @State private var isChild = false
    @State private var maturity: MaturityRating = .six
    @State private var allowedCategories: Set<String> = []
    @State private var allowedTitleKeys: Set<String> = []
    @State private var hasLoaded = false

    var body: some View {
        List {
            identitySection
            kindSection
            if isChild {
                limitSection
                accessSection
                if !withheld.isEmpty { withheldSection }
            }
            if existing != nil, model.profiles.count > 1 {
                deleteSection
            }
        }
        .navigationTitle(Text(existing == nil ? UIStrings.newProfile : UIStrings.editProfile))
        .kanalPlainListBackground()
        .background(KanalColor.background)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(UIStrings.save)) { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(String(UIStrings.cancel)) { dismiss() }
            }
        }
        .onAppear(perform: load)
    }

    private var existing: Profile? { draft.profile }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            HStack(spacing: KanalMetrics.lg) {
                ProfileAvatar(profile: preview, size: 72)
                TextField(String(UIStrings.profileNamePlaceholder), text: $name)
                    .font(KanalFont.section(18))
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }
            .padding(.vertical, KanalMetrics.xs)

            symbolPicker
            colorPicker
        }
    }

    private var symbolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KanalMetrics.sm) {
                ForEach(Profile.avatarSymbols, id: \.self) { symbol in
                    Button {
                        symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                symbol == symbolName ? KanalColor.accentSolid : KanalColor.secondaryText
                            )
                            .frame(width: 44, height: 44)
                            .kanalGlassPill()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, KanalMetrics.xs)
        }
    }

    private var colorPicker: some View {
        HStack(spacing: KanalMetrics.sm) {
            ForEach(Array(Profile.avatarColors.enumerated()), id: \.offset) { index, hex in
                Button {
                    colorIndex = index
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().strokeBorder(
                                index == colorIndex ? KanalColor.primaryText : .clear, lineWidth: 2
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, KanalMetrics.xs)
    }

    private var kindSection: some View {
        Section {
            Toggle(String(UIStrings.profileIsChild), isOn: $isChild)
        } footer: {
            Text(isChild ? UIStrings.profileChildFooter : UIStrings.profileAdultFooter)
        }
    }

    private var limitSection: some View {
        Section(String(UIStrings.sectionAgeLimit)) {
            Picker(String(UIStrings.ageLimit), selection: $maturity) {
                ForEach(MaturityRating.childOptions, id: \.self) { rating in
                    Text(rating.displayNameResource).tag(rating)
                }
            }
            #if !os(tvOS)
            .pickerStyle(.segmented)
            #endif
        }
    }

    /// What a grown-up has let through.
    ///
    /// Suggestions come from the provider's own section names and are never
    /// pre-ticked. Suggesting is a service; ticking on someone's behalf would
    /// be the app quietly making a decision it has no evidence for.
    private var accessSection: some View {
        Section {
            if suggestions.isEmpty && otherCategories.isEmpty {
                Text(UIStrings.noCategoriesYet)
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
            }
            ForEach(suggestions, id: \.name) { suggestion in
                categoryRow(suggestion.name, count: suggestion.count, isSuggested: true)
            }
            if !otherCategories.isEmpty {
                // tvOS has no DisclosureGroup, so the rest of the categories
                // fold behind a plain toggle instead of a twisty.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsAllCategories.toggle()
                    }
                } label: {
                    HStack {
                        Text(UIStrings.allCategories)
                            .foregroundStyle(KanalColor.primaryText)
                        Spacer()
                        Image(systemName: showsAllCategories ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(KanalColor.secondaryText)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if showsAllCategories {
                    ForEach(otherCategories, id: \.name) { category in
                        categoryRow(category.name, count: category.count, isSuggested: false)
                    }
                }
            }
        } header: {
            Text(UIStrings.sectionAllowedContent)
        } footer: {
            Text(model.canVerifyRatings
                ? UIStrings.allowedContentFooter
                : UIStrings.allowedContentFooterNoProvider)
        }
    }

    /// Titles an approved section would have shown, held back by an age
    /// rating — and the place a grown-up disagrees with one.
    ///
    /// Identifying a film from a provider's playlist is guesswork often enough
    /// that a rating nobody can see or overrule would eventually hide something
    /// a parent knows is fine, with no way to say so.
    private var withheldSection: some View {
        Section {
            ForEach(withheld, id: \.item.id) { entry in
                Button {
                    if allowedTitleKeys.contains(RatingKey.of(entry.item)) {
                        allowedTitleKeys.remove(RatingKey.of(entry.item))
                    } else {
                        allowedTitleKeys.insert(RatingKey.of(entry.item))
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.item.seriesName ?? entry.item.title)
                                .font(KanalFont.body(15))
                                .foregroundStyle(KanalColor.primaryText)
                            Text(UIStrings.ratedBadge(entry.rating.badge))
                                .font(KanalFont.caption(11))
                                .foregroundStyle(KanalColor.tertiaryText)
                        }
                        Spacer()
                        Image(
                            systemName: allowedTitleKeys.contains(RatingKey.of(entry.item))
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(
                            allowedTitleKeys.contains(RatingKey.of(entry.item))
                                ? KanalColor.accentSolid : KanalColor.tertiaryText
                        )
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(UIStrings.sectionWithheldByRating)
        } footer: {
            Text(UIStrings.withheldByRatingFooter)
        }
    }

    private func categoryRow(_ name: String, count: Int, isSuggested: Bool) -> some View {
        Button {
            if allowedCategories.contains(name) {
                allowedCategories.remove(name)
            } else {
                allowedCategories.insert(name)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: CategoryLocalizer.display(name))
                        .font(KanalFont.body(15))
                        .foregroundStyle(KanalColor.primaryText)
                    Text(verbatim: count.formatted())
                        .font(KanalFont.caption(11))
                        .foregroundStyle(KanalColor.tertiaryText)
                }
                Spacer()
                if isSuggested, !allowedCategories.contains(name) {
                    Text(UIStrings.suggested)
                        .font(KanalFont.caption(10))
                        .foregroundStyle(KanalColor.accentSolid)
                }
                Image(systemName: allowedCategories.contains(name) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        allowedCategories.contains(name) ? KanalColor.accentSolid : KanalColor.tertiaryText
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        Section {
            Button(String(UIStrings.deleteProfile), role: .destructive) {
                guard let existing else { return }
                Task {
                    await model.deleteProfile(existing)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Data

    private var preview: Profile {
        Profile(
            name: name,
            symbolName: symbolName,
            colorIndex: colorIndex,
            maturity: isChild ? maturity : .adult
        )
    }

    /// What an age rating is currently holding back inside an approved section.
    private var withheld: [(item: MediaItem, rating: MaturityRating)] {
        var draft = existing ?? Profile(name: name)
        draft.maturity = isChild ? maturity : .adult
        draft.allowedCategories = allowedCategories
        draft.allowedTitleKeys = []
        return ContentPolicy(profile: draft, ratings: model.ratings)
            .withheldByRating(in: model.catalogue, limit: 60)
    }

    /// Sections that look like children's television, biggest first.
    private var suggestions: [(name: String, count: Int)] {
        ContentPolicy.suggestedChildCategories(in: model.catalogue)
    }

    /// Everything else the provider ships, minus the adult sections — those are
    /// never offered, because no ticking of a box makes them appropriate for a
    /// profile with an age limit on it.
    private var otherCategories: [(name: String, count: Int)] {
        let suggested = Set(suggestions.map(\.name))
        let buckets = model.catalogue.channelCategories.map { (name: $0.name, count: $0.items.count) }
            + model.catalogue.movieCategories.map { (name: $0.name, count: $0.items.count) }
            + model.catalogue.seriesCategories.map { (name: $0.name, count: $0.items.count) }

        var seen = Set<String>()
        return buckets
            .filter { bucket in
                !suggested.contains(bucket.name)
                    && !AdultContentDetector.isAdult(category: bucket.name)
                    && seen.insert(bucket.name).inserted
            }
            .sorted { $0.count > $1.count }
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let existing else {
            // A new profile defaults to a child's. Someone adding a second
            // profile to a household is far more often adding a child than a
            // second grown-up, and defaulting the other way makes the mistake
            // that matters.
            isChild = true
            symbolName = Profile.avatarSymbols.randomElement() ?? "person.fill"
            colorIndex = Int.random(in: 0..<Profile.avatarColors.count)
            return
        }
        name = existing.name
        symbolName = existing.symbolName
        colorIndex = existing.colorIndex
        isChild = existing.isRestricted
        maturity = existing.isRestricted ? existing.maturity : .six
        allowedCategories = existing.allowedCategories
        allowedTitleKeys = existing.allowedTitleKeys
    }

    private func save() {
        var profile = existing ?? Profile(name: name)
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.symbolName = symbolName
        profile.colorIndex = colorIndex
        profile.maturity = isChild ? maturity : .adult
        profile.allowedCategories = isChild ? allowedCategories : []
        profile.allowedTitleKeys = isChild ? allowedTitleKeys : []

        Task {
            if existing == nil {
                await model.addProfile(profile)
            } else {
                await model.updateProfile(profile)
            }
            dismiss()
        }
    }
}
