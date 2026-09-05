import Foundation

/// Who the recommendations are being fetched for.
///
/// Discovery only ever *orders* a library someone already has, so it was built
/// once and shared. Measured against a real provider, that made a child's Home
/// almost empty: of TMDB's twenty trending films, four were in the catalogue
/// and **none** were rated for a nine-year-old; trending shows managed none
/// either. Every row fell below its minimum and collapsed to the fallback,
/// which is the catalogue in whatever order the panel sent it — the "random
/// films" a parent actually sees.
///
/// Asking the kid-shaped question instead of filtering the grown-up answer
/// turned that into fifteen films and ten new ones from the same catalogue.
/// So the audience is part of the request, not a filter applied afterwards.
///
/// This changes **what is suggested first**, never what is permitted.
/// `ContentPolicy` remains the only thing that decides whether a title may be
/// seen, and it is applied to the library these rows are matched against.
public enum DiscoveryAudience: Sendable, Hashable, Codable {
    case everyone
    /// A restricted profile, carrying its own ceiling.
    case children(MaturityRating)

    public init(profile: Profile?) {
        guard let profile, profile.isRestricted else {
            self = .everyone
            return
        }
        self = .children(profile.maturity)
    }

    public var isChildren: Bool {
        if case .children = self { return true }
        return false
    }

    /// Distinguishes one audience's cached rows from another's. A profile
    /// switch must not serve a nine-year-old the grown-up cache saved an hour
    /// ago, and the two ceilings do not ask TMDB the same question either.
    public var cacheScope: String {
        switch self {
        case .everyone: "all"
        case .children(let ceiling): "kids\(ceiling.rawValue)"
        }
    }

    // MARK: - What to ask TMDB for

    /// Film genres worth asking for, as TMDB's `with_genres` expression.
    ///
    /// Animation and Family, joined by `|` so either qualifies. Nil for a
    /// grown-up, who gets the unfiltered popularity list as before.
    public var movieGenres: String? {
        isChildren ? "16|10751" : nil
    }

    /// Show genres. **Kids** (10762) and Family, deliberately not Animation.
    ///
    /// Animation is a technique, not an audience — filtering shows by it
    /// returns Family Guy and South Park alongside Paw Patrol. Measured on the
    /// same catalogue: Animation alone yielded two usable shows for a
    /// nine-year-old, Kids-and-Family yielded seven. This is the same mistake
    /// the profile suggestions made once already, and it is worth not making
    /// twice in a different file.
    public var seriesGenres: String? {
        isChildren ? "10762|10751" : nil
    }

    /// A board ceiling TMDB itself can filter on, as (country, code).
    ///
    /// The American board is used because it is the one TMDB has near-complete
    /// coverage for — a Norwegian ceiling would silently exclude most of the
    /// catalogue for want of a certificate rather than for being unsuitable.
    /// `RatingParser` already maps these codes onto Medietilsynet's ladder, so
    /// the two agree about what a `PG` means.
    ///
    /// Films only: TMDB's `discover/tv` has no certification filter, which is
    /// why shows lean on the audience genre and on the policy behind it.
    public var movieCertification: (country: String, code: String)? {
        guard case .children(let ceiling) = self else { return nil }
        // US has no six-year step; its next rung up is PG, which maps to nine.
        // Asking for G there is the strict reading, and the right one.
        let code = switch ceiling {
        case .allAges, .six: "G"
        case .nine: "PG"
        case .twelve: "PG-13"
        case .fifteen, .adult: "R"
        }
        return ("US", code)
    }

    /// Services to lead with, matched by name against what TMDB says is
    /// available in the region.
    ///
    /// For a child that is Disney first — measured on the same catalogue it
    /// carried seventeen usable films against Netflix's twelve, and it is the
    /// one a parent would look for. For everyone else the existing order is
    /// kept, because it was chosen for the same reason.
    public var preferredServices: [String] {
        isChildren ? ["disney"] : []
    }
}
