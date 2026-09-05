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
    @State private var audioLanguage: String?
    @State private var hasLoaded = false
    /// Provider catalogues can contain hundreds of thousands of entries. These
    /// values used to be rebuilt from that catalogue every time focus or one
    /// field changed, which made Settings visibly hitch on both platforms.
    @State private var suggestions: [ProfileCategoryOption] = []
    @State private var otherCategories: [ProfileCategoryOption] = []
    @State private var withheld: [WithheldTitleOption] = []
    @State private var isPreparingAccess = false

    var body: some View {
        List {
            identitySection
            kindSection
            audioSection
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
        .task(id: draft.id) {
            load()
            await prepareCategoryOptions()
        }
        .task(id: accessPolicyKey) {
            guard hasLoaded else { return }
            // Coalesce quick remote-control or segmented-picker changes.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await prepareWithheldTitles()
        }
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

    /// Sound before access, because it applies to both kinds of profile and
    /// the access list below is only ever a child's.
    private var audioSection: some View {
        AudioLanguagePicker(
            selection: $audioLanguage,
            footer: isChild ? UIStrings.audioLanguageChildFooter : UIStrings.audioLanguageFooter
        )
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
            if isPreparingAccess {
                ProgressView().controlSize(.small)
            } else if suggestions.isEmpty && otherCategories.isEmpty {
                Text(UIStrings.noCategoriesYet)
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
            }
            ForEach(suggestions) { suggestion in
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
                    ForEach(otherCategories) { category in
                        categoryRow(category.name, count: category.count, isSuggested: false)
                    }
                }
            }
            if isEditingActiveProfile, model.ratingsPending > 0 {
                // Says out loud why the child's library is still thin. Without
                // this the honest behaviour — hide until checked — is
                // indistinguishable from a broken catalogue, which is exactly
                // how it looked the first time this was tried.
                HStack(spacing: KanalMetrics.sm) {
                    ProgressView().controlSize(.small)
                    Text(UIStrings.checkingRatings(model.ratingsPending))
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
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

    /// Progress only means anything for the profile actually loaded — the
    /// lookups run against that one.
    private var isEditingActiveProfile: Bool {
        existing?.id == model.activeProfileID
    }

    /// Titles an approved section would have shown, held back by an age
    /// rating — and the place a grown-up disagrees with one.
    ///
    /// Identifying a film from a provider's playlist is guesswork often enough
    /// that a rating nobody can see or overrule would eventually hide something
    /// a parent knows is fine, with no way to say so.
    private var withheldSection: some View {
        Section {
            ForEach(withheld) { entry in
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

    private var accessPolicyKey: String {
        "\(isChild)-\(maturity)-\(allowedCategories.sorted().joined(separator: "|"))"
    }

    private func prepareCategoryOptions() async {
        isPreparingAccess = true
        let result = await ProfileEditorDataQueue.shared.categories(in: model.catalogue)
        guard !Task.isCancelled else { return }
        suggestions = result.suggestions
        otherCategories = result.others
        isPreparingAccess = false
        await prepareWithheldTitles()
    }

    private func prepareWithheldTitles() async {
        guard isChild else {
            withheld = []
            return
        }
        var profile = existing ?? Profile(name: name)
        profile.maturity = maturity
        profile.allowedCategories = allowedCategories
        // Existing overrides are precisely what this list lets a parent edit,
        // so the calculation must show every held title before those overrides.
        profile.allowedTitleKeys = []
        let entries = await ProfileEditorDataQueue.shared.withheld(
            in: model.catalogue,
            ratings: model.ratings,
            profile: profile
        )
        guard !Task.isCancelled else { return }
        withheld = entries
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
            // A child starts on the household's own language. See
            // `AudioLanguagePreference` for why a grown-up does not.
            audioLanguage = AudioLanguagePreference.deviceDefault
            return
        }
        name = existing.name
        symbolName = existing.symbolName
        colorIndex = existing.colorIndex
        isChild = existing.isRestricted
        maturity = existing.isRestricted ? existing.maturity : .six
        allowedCategories = existing.allowedCategories
        allowedTitleKeys = existing.allowedTitleKeys
        audioLanguage = existing.preferredAudioLanguage
    }

    private func save() {
        var profile = existing ?? Profile(name: name)
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.symbolName = symbolName
        profile.colorIndex = colorIndex
        profile.maturity = isChild ? maturity : .adult
        profile.allowedCategories = isChild ? allowedCategories : []
        profile.allowedTitleKeys = isChild ? allowedTitleKeys : []
        profile.preferredAudioLanguage = audioLanguage

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

private struct ProfileCategoryOption: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let count: Int
}

private struct WithheldTitleOption: Identifiable, Sendable {
    var id: String { item.id }
    let item: MediaItem
    let rating: MaturityRating
}

/// Serial background worker for the only provider-sized calculations in the
/// editor. SwiftUI receives small immutable arrays and never walks the library.
private actor ProfileEditorDataQueue {
    static let shared = ProfileEditorDataQueue()

    func categories(in library: Library) -> (
        suggestions: [ProfileCategoryOption], others: [ProfileCategoryOption]
    ) {
        let suggestions = ContentPolicy.suggestedChildCategories(in: library)
            .map { ProfileCategoryOption(name: $0.name, count: $0.count) }
        let suggestedNames = Set(suggestions.map(\.name))
        let buckets = library.channelCategories.map { (name: $0.name, count: $0.items.count) }
            + library.movieCategories.map { (name: $0.name, count: $0.items.count) }
            + library.seriesCategories.map { (name: $0.name, count: $0.items.count) }

        var seen = Set<String>()
        let others = buckets
            .filter { bucket in
                !suggestedNames.contains(bucket.name)
                    && !AdultContentDetector.isAdult(category: bucket.name)
                    && seen.insert(bucket.name).inserted
            }
            .sorted { $0.count > $1.count }
            .map { ProfileCategoryOption(name: $0.name, count: $0.count) }
        return (suggestions, others)
    }

    func withheld(
        in library: Library,
        ratings: RatingIndex,
        profile: Profile
    ) -> [WithheldTitleOption] {
        ContentPolicy(profile: profile, ratings: ratings)
            .withheldByRating(in: library, limit: 60)
            .map { WithheldTitleOption(item: $0.item, rating: $0.rating) }
    }
}
