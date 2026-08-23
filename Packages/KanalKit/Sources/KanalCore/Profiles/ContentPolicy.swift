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
        if profile.blockedItemIDs.contains(item.id) { return .denied(.blockedByParent) }

        let rating = ratings.rating(for: item)
        // A board rating above the limit overrules an approved category — a
        // grown-up ticking "Action" was not agreeing to every film in it.
        if let rating, rating.isVerified, rating.rating > profile.maturity {
            return .denied(.aboveAgeLimit(rating.rating))
        }
        // A provider's own "18+" denies but never permits; see `isVerified`.
        if let rating, !rating.isVerified, rating.rating > profile.maturity {
            return .denied(.aboveAgeLimit(rating.rating))
        }

        if profile.allowedItemIDs.contains(item.id) { return .allowed }
        if let category = item.category, profile.allowedCategories.contains(category) {
            return .allowed
        }
        if let raw = item.rawGroup, profile.allowedCategories.contains(raw) { return .allowed }

        if let rating, rating.isVerified { return .allowed }

        return .denied(.unrated)
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

    /// Section names that mean "children's" across the languages IPTV panels
    /// are written in, plus the children's broadcasters everyone carries.
    private static let childHints: Set<String> = [
        "kids", "kid", "children", "child", "barn", "barnekanaler", "barnetv",
        // "anime" is deliberately absent: the word says nothing about audience,
        // and a suggestion a parent is likely to trust must not need vetting.
        "junior", "cartoon", "cartoons", "tegnefilm", "tecknat", "animation",
        "family", "familie", "familj", "disney", "nickelodeon", "nick",
        "boomerang", "cbeebies", "cbbc", "babytv", "kika", "niños", "infantil",
        "enfants", "kinder", "bambini",
    ]

    static func looksLikeChildren(_ category: String) -> Bool {
        let normalized = SearchNormalizer.normalize(category)
        guard !normalized.isEmpty else { return false }
        return normalized.split(separator: " ").contains { childHints.contains(String($0)) }
    }
}
