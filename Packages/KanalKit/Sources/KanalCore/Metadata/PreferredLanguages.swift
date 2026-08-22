import Foundation

/// Which languages to ask metadata providers for.
///
/// This is not interface text — it is what makes the *search* work in someone's
/// own language. A Norwegian typing "Løvenes konge" and a German typing "Der
/// König der Löwen" are asking the same question, and both must be answered
/// against a provider list that is almost certainly written in English.
public enum PreferredLanguages {

    /// Language codes to query, most preferred first.
    ///
    /// English is always appended: IPTV listings are overwhelmingly English
    /// regardless of who is watching, so it is the language the *answer* has to
    /// come back in even when the question was asked in another.
    public static func codes(
        for preferred: [String] = Locale.preferredLanguages,
        limit: Int = 4
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for identifier in preferred {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier else {
                continue
            }
            if seen.insert(code).inserted { result.append(code) }
            // Norwegian is written two ways and Wikidata labels differ between
            // them, so someone reading one should still find the other.
            for sibling in siblings[code] ?? [] where seen.insert(sibling).inserted {
                result.append(sibling)
            }
            if result.count >= limit { break }
        }

        if seen.insert("en").inserted { result.append("en") }
        return result
    }

    /// A single BCP-47 tag, for APIs that accept only one — "nb-NO", "de-DE".
    public static func primaryTag(for locale: Locale = .current) -> String {
        guard let code = locale.language.languageCode?.identifier else { return "en-US" }
        guard let region = locale.language.region?.identifier else { return code }
        return "\(code)-\(region)"
    }

    private static let siblings: [String: [String]] = [
        "nb": ["nn"],
        "nn": ["nb"],
        "no": ["nb", "nn"],
    ]
}
