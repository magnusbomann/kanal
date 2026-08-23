import Foundation

/// Spots the part of a provider's catalogue that no restricted profile may
/// ever see, whatever else is configured.
///
/// Every IPTV panel ships an adult section and labels it plainly — the entries
/// are grouped under names like `XXX`, `ADULT`, `FOR ADULTS 18+`. That makes
/// detection reliable in the direction that matters, and this is the one place
/// in Kanal that is allowed to be over-eager: a wrongly hidden channel costs an
/// adult one tap in settings, while a wrongly shown one is the failure the
/// whole feature exists to prevent.
///
/// It is a *floor*, not the policy. Restricted profiles are allowlisted
/// (`ContentPolicy`), so this catches the case where a parent approves a whole
/// category that turns out to have adult entries filed inside it.
public enum AdultContentDetector {

    /// Words that only ever appear on adult material. Matched on word
    /// boundaries against normalised text, so "Sexton" and "Middlesex" are
    /// safe while "SEX" and "XXX" are not.
    private static let words: Set<String> = [
        "xxx", "porn", "porno", "pornhub", "adult", "adults", "erotic", "erotica",
        "erotik", "erotikk", "hardcore", "softcore", "sex", "sexy", "nude", "nudes",
        "playboy", "hustler", "brazzers", "dorcel", "penthouse", "vixen", "blacked",
        "milf", "hentai", "fetish", "bdsm", "voksen", "vuxen", "18plus", "escort",
        "camgirl", "onlyfans", "redtube", "youporn", "xhamster", "xvideos",
    ]

    /// Phrases that need more than one word to be conclusive.
    private static let phrases: [String] = [
        "for adults", "adults only", "kun for voksne", "for voksne", "18 only",
        "18 plus", "adult movies", "adult channels", "red light",
    ]

    /// Whether a provider category is an adult section.
    public static func isAdult(category: String) -> Bool {
        contains(category)
    }

    /// Whether an entry is adult material, judged on everything the playlist
    /// said about it — its own title and the section it arrived in.
    ///
    /// The raw title is used rather than the cleaned one: `TitleCleaner` strips
    /// bracketed markers, and `[XXX]` is exactly such a marker.
    public static func isAdult(_ item: MediaItem) -> Bool {
        contains(item.rawTitle)
            || contains(item.title)
            || item.rawGroup.map(contains) == true
            || item.category.map(contains) == true
    }

    // MARK: - Matching

    private static func contains(_ text: String) -> Bool {
        let normalized = SearchNormalizer.normalize(text)
        guard !normalized.isEmpty else { return false }

        for phrase in phrases where normalized.contains(phrase) { return true }

        for token in normalized.split(separator: " ") {
            if words.contains(String(token)) { return true }
            // "18+" normalises to "18"; on its own that is a section marker.
            if token == "18", normalized.split(separator: " ").count <= 3 { return true }
        }
        return false
    }
}
