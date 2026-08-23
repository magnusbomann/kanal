import Foundation

/// Decides what a profile is allowed to see.
///
/// One rule shapes everything here: **a restricted profile is an allowlist.**
/// Nothing appears in a child's library because it looked harmless — it appears
/// because a national board rated it low enough, or because a grown-up in this
/// household said so. An entry nobody has vouched for is hidden.
///
/// That is stricter than filtering out what looks bad, and it has to be. An
/// IPTV catalogue is four hundred thousand rows a stranger assembled, with no
/// ratings, no genre discipline and an adult section three taps from the front
/// page. There is no honest way to look at that list and decide the unlabelled
/// remainder is fine for a seven-year-old.
///
/// Live TV is where this bites hardest and is also where it is most obviously
/// right: a channel has no age limit, because what it is showing changes every
/// hour. A child gets the channels a grown-up picked, and no others.
public struct ContentPolicy: Sendable {

    /// Why something is not being shown. Carried so the interface can say
    /// "ask a grown-up" rather than pretending the catalogue is small.
    public enum Denial: Sendable, Hashable {
        /// Adult material. Never overridable from a restricted profile.
        case adultContent
        /// Rated above this profile's limit.
        case aboveAgeLimit(MaturityRating)
        /// Nobody has rated or approved it.
        case unrated
        /// A grown-up removed this specific entry.
        case blockedByParent
    }

    public enum Decision: Sendable, Hashable {
        case allowed
        case denied(Denial)

        public var isAllowed: Bool { self == .allowed }
    }

    public let profile: Profile
    public let ratings: RatingIndex

    public init(profile: Profile, ratings: RatingIndex) {
        self.profile = profile
        self.ratings = ratings
    }

    /// A grown-up's profile: nothing is withheld, and no filtering work is done.
    public var isUnrestricted: Bool { !profile.isRestricted }

    // MARK: - Deciding

    public func decision(for item: MediaItem) -> Decision {
        guard profile.isRestricted else { return .allowed }

        // Checked before the allowlists on purpose. Approving a whole category
        // is one tap, and panels do file adult entries inside otherwise
        // ordinary sections; this is the floor under that mistake.
        if AdultContentDetector.isAdult(item) { return .denied(.adultContent) }
        let key = RatingKey.of(item)
        if profile.blockedTitleKeys.contains(key) { return .denied(.blockedByParent) }

        // Three strengths of decision, weakest first: approving a section is
        // broad and casual, a board rating is specific and usually right, and
        // approving one title by name is a grown-up looking straight at that
        // title. So a rating overrules a section, and a named approval
        // overrules the rating.
        //
        // The last step is not a formality. Identifying a title from a
        // provider's playlist is guesswork often enough — "Frost" is Disney's
        // *Frozen* here and a different 2013 film to a search engine — that a
        // rating a parent can see and disagree with is worth more than one
        // they cannot.
        if profile.allowedTitleKeys.contains(key) { return .allowed }

        let rating = ratings[key]
        // Applies whether the rating was verified or is the provider's own
        // marker: both are trusted to withhold, only one is trusted to permit.
        if let rating, rating.rating > profile.maturity {
            return .denied(.aboveAgeLimit(rating.rating))
        }

        // What counts as permission depends on what the thing *is*, because
        // the two kinds differ in whether an age limit can exist at all.
        switch item.kind {
        case .liveTV:
            // No board rates a channel — what it is showing changes every
            // hour — so a grown-up's own approval is the only key there is.
            // Channel sections are small enough to actually read, which is
            // what makes approving one an informed decision.
            return isInApprovedSection(item) ? .allowed : .denied(.unrated)

        case .movie, .series:
            // A section is *where to look*, never permission on its own.
            //
            // This is the correction to the first version of this rule, and
            // Family Guy is why. A provider files it under "Animation", a
            // parent reasonably ticks "Animation" for a nine-year-old, and a
            // section-grants-access rule then shows it — the app having
            // recommended the section itself. Genre is not audience: the same
            // bucket holds Bluey and American Dad.
            //
            // So a film or episode needs a rating of its own. Norway rates
            // Family Guy 15, which is exactly the answer, and an approved
            // section only decides which titles are worth spending a lookup
            // on. Anything still unrated stays out and is counted, so the
            // interface can say "checking" rather than looking broken.
            if let rating, rating.isVerified { return .allowed }
            return .denied(.unrated)
        }
    }

    /// Whether a grown-up approved the section this entry arrived in.
    func isInApprovedSection(_ item: MediaItem) -> Bool {
        if let category = item.category, profile.allowedCategories.contains(category) { return true }
        if let raw = item.rawGroup, profile.allowedCategories.contains(raw) { return true }
        return false
    }

    /// Films and episodes in an approved section that are still waiting on a
    /// rating, in the order they should be looked up.
    ///
    /// This is the pool verification works through. Restricting it to approved
    /// sections is what keeps the job finite: a real catalogue holds thirty
    /// thousand films, and nobody needs an age limit for a film their child
    /// was never going to be offered.
    public func awaitingRating(in catalogue: Library) -> [MediaItem] {
        awaitingRating(among: catalogue.items)
    }

    /// The same question asked of a list that is already narrowed — used to
    /// thin the pool between passes without walking the catalogue again.
    public func awaitingRating(among items: [MediaItem]) -> [MediaItem] {
        guard profile.isRestricted else { return [] }
        return items.filter { item in
            guard item.kind != .liveTV else { return false }
            guard isInApprovedSection(item) else { return false }
            guard !AdultContentDetector.isAdult(item) else { return false }
            let key = RatingKey.of(item)
            guard !profile.allowedTitleKeys.contains(key) else { return false }
            return ratings[key]?.isVerified != true
        }
    }

    public func allows(_ item: MediaItem) -> Bool { decision(for: item).isAllowed }

    /// A show is reachable when any of its episodes is. Episodes are filtered
    /// individually as well, so approving a show never smuggles one through.
    public func allows(_ group: SeriesGroup) -> Bool {
        guard profile.isRestricted else { return true }
        return group.episodes.contains(where: allows)
    }

    /// A channel is reachable when any of its streams is. Variants of one
    /// channel are the same content on different feeds, so a grown-up
    /// approving the channel means all of them.
    public func allows(_ group: ChannelGroup) -> Bool {
        guard profile.isRestricted else { return true }
        return group.variants.contains(where: allows)
    }

    // MARK: - Applying

    /// The library this profile actually has.
    ///
    /// Rebuilt rather than filtered per screen, so every list, shelf, search
    /// result and deep link in the app is narrowed by construction. Forgetting
    /// to filter one screen is exactly the kind of mistake that would only be
    /// noticed by a child finding it.
    public func apply(to library: Library) -> Library {
        guard profile.isRestricted else { return library }
        return Library(items: library.items.filter(allows))
    }

    /// Titles an approved section would have shown, held back by a rating.
    ///
    /// This list is the reason a rating is allowed to overrule an approval at
    /// all. A parent who ticked "Kids Movies" and then cannot find a film they
    /// know is fine needs somewhere to look, see why, and disagree — otherwise
    /// the safe behaviour is indistinguishable from a broken catalogue.
    public func withheldByRating(
        in library: Library, limit: Int = 200
    ) -> [(item: MediaItem, rating: MaturityRating)] {
        guard profile.isRestricted else { return [] }
        var found: [(item: MediaItem, rating: MaturityRating)] = []
        for item in library.items {
            guard found.count < limit else { break }
            guard !AdultContentDetector.isAdult(item) else { continue }
            guard isInApprovedSection(item) else { continue }
            guard case .denied(.aboveAgeLimit(let rating)) = decision(for: item) else { continue }
            found.append((item, rating))
        }
        return found
    }

    /// Categories worth offering a grown-up when they set up a child.
    ///
    /// Suggestions only: nothing here is approved until it is tapped. The
    /// signal is the provider's own section name, which is the only thing in
    /// the catalogue that describes a whole group honestly.
    public static func suggestedChildCategories(
        in library: Library, limit: Int = 12
    ) -> [(name: String, count: Int)] {
        let buckets = library.channelCategories + library.movieCategories.map {
            (name: $0.name, items: $0.items)
        }
        var seen = Set<String>()
        var found: [(name: String, count: Int)] = []

        for bucket in buckets where !seen.contains(bucket.name) {
            guard looksLikeChildren(bucket.name), !AdultContentDetector.isAdult(category: bucket.name)
            else { continue }
            seen.insert(bucket.name)
            found.append((bucket.name, bucket.items.count))
        }
        for bucket in library.seriesCategories where !seen.contains(bucket.name) {
            guard looksLikeChildren(bucket.name), !AdultContentDetector.isAdult(category: bucket.name)
            else { continue }
            seen.insert(bucket.name)
            found.append((bucket.name, bucket.items.count))
        }
        return Array(found.sorted { $0.count > $1.count }.prefix(limit))
    }

    /// Words that name an **audience**, in the languages IPTV panels are
    /// written in.
    ///
    /// The distinction this list turns on, learned the hard way: a genre is not
    /// an audience. "Animation", "Cartoons", "Tegnefilm" and "Family" all had
    /// to come out, because the bucket that holds Bluey also holds Family Guy,
    /// South Park and Rick and Morty — and a suggestion a parent is likely to
    /// trust must not need vetting.
    ///
    /// Broadcaster names came out for the same reason. "Disney" is Disney+,
    /// which carries FX; "Nickelodeon" and "Nick" are the general channels.
    /// Only their explicitly junior feeds are unambiguous, and those are
    /// matched as phrases below.
    private static let childHints: Set<String> = [
        // "barne" and "børne" are the Nordic compound stems: a provider writing
        // "Barne-TV" leaves that token behind once punctuation is stripped.
        "kids", "kid", "children", "child", "barn", "barne", "barnas", "børn",
        "børne", "barnekanaler", "barnetv", "barneserier", "barnefilm",
        "barnefilmer", "junior",
        "cbeebies", "cbbc", "babytv", "kika", "niños", "infantil", "enfants",
        "kinder", "bambini", "boomerang", "preschool", "førskole",
    ]

    /// Multi-word names that are unambiguous only together.
    private static let childPhrases: [String] = [
        "disney junior", "disney jr", "nick jr", "nickelodeon junior",
        "cartoon network kids", "kids tv", "tv for kids", "for barn",
    ]

    static func looksLikeChildren(_ category: String) -> Bool {
        let normalized = SearchNormalizer.normalize(category)
        guard !normalized.isEmpty else { return false }
        if childPhrases.contains(where: normalized.contains) { return true }
        return normalized.split(separator: " ").contains { childHints.contains(String($0)) }
    }
}
