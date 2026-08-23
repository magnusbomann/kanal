import Foundation

/// An age limit, on the ladder Norwegian viewers already know.
///
/// Medietilsynet's own steps — A, 6, 9, 12, 15, 18 — rather than a scheme
/// invented here. Every other country's system is *mapped onto* this one by
/// `RatingParser`, so the app has exactly one scale to compare against and a
/// parent only ever sees numbers they recognise from a cinema poster.
///
/// The raw value is the minimum age, which makes "is this allowed?" an integer
/// comparison and makes the JSON on disk readable.
public enum MaturityRating: Int, Codable, Sendable, CaseIterable, Comparable, Hashable {
    /// Medietilsynet's "A": permitted for all.
    case allAges = 0
    case six = 6
    case nine = 9
    case twelve = 12
    case fifteen = 15
    /// Adults only. Never selectable as a *child* profile's ceiling.
    case adult = 18

    public static func < (lhs: MaturityRating, rhs: MaturityRating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The badge shown on a poster: "A", "6", "9", "12", "15", "18".
    public var badge: String {
        self == .allAges ? String(localized: CoreStrings.ratingAllAges) : String(rawValue)
    }

    /// What a parent picks from in the profile editor.
    public var displayNameResource: LocalizedStringResource {
        switch self {
        case .allAges: CoreStrings.maturityAllAges
        case .six: CoreStrings.maturitySix
        case .nine: CoreStrings.maturityNine
        case .twelve: CoreStrings.maturityTwelve
        case .fifteen: CoreStrings.maturityFifteen
        case .adult: CoreStrings.maturityAdult
        }
    }

    public var displayName: String { String(localized: displayNameResource) }

    /// The limits offered when creating a restricted profile. `adult` is absent
    /// on purpose: an adult profile is a different thing, not the top of this
    /// list, and offering it here would let someone build a "child" profile
    /// with no limit at all.
    public static let childOptions: [MaturityRating] = [.allAges, .six, .nine, .twelve, .fifteen]

    /// Rounds a foreign rating up to the nearest step we carry.
    ///
    /// Up, never down. A German FSK 16 becomes 18 rather than 15 — the cost of
    /// being one step strict is a film a fifteen-year-old has to ask for; the
    /// cost of being one step lenient is the thing this whole feature exists
    /// to prevent.
    public static func nearest(atLeast age: Int) -> MaturityRating {
        allCases.first { $0.rawValue >= age } ?? .adult
    }
}
