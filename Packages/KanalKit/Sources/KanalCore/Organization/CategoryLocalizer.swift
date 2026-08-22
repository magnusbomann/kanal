import Foundation

/// Translates provider category names for display.
///
/// Category names arrive as provider data, so the instinct is to leave them
/// alone — but they are not arbitrary text. Across every playlist in the wild
/// they are drawn from a small, repeating vocabulary: a few dozen genre words
/// and a list of countries. Both are translatable without asking anyone.
///
/// Two rules keep this honest:
///
/// - **Display only.** Grouping, filtering and favourites all key off the raw
///   name. Translating identity would break a person's filters the moment they
///   changed their phone's language.
/// - **Never guess.** Anything not recognised is passed through exactly as the
///   provider wrote it. A wrong translation of "Sport 1" is worse than English.
public enum CategoryLocalizer {

    /// The name to show. Falls back to `raw` whenever we are not confident.
    public static func display(_ raw: String) -> String {
        let key = SearchNormalizer.normalize(raw)
        guard !key.isEmpty else { return raw }

        if let genre = genreResources[key] {
            return String(localized: genre)
        }
        if let region = regionIndex[key] {
            return region
        }

        // Compound names built by CategoryNormalizer, like "Animation & Comedy".
        if raw.contains(" & ") {
            let parts = raw.components(separatedBy: " & ")
            let translated = parts.map { display($0) }
            if translated != parts {
                return translated.joined(separator: " & ")
            }
        }

        return raw
    }

    /// Whether a name is one we can translate, for diagnostics and tests.
    public static func isRecognized(_ raw: String) -> Bool {
        let key = SearchNormalizer.normalize(raw)
        return genreResources[key] != nil || regionIndex[key] != nil
    }

    // MARK: - Countries

    /// Country names, indexed by how a provider is likely to have written them.
    ///
    /// Built from Foundation's own region data, so every country name Apple
    /// ships is covered in the viewer's language — no list to maintain and no
    /// request to make. Indexed under English, the viewer's own languages, and
    /// the languages IPTV providers serving Europe tend to label in.
    private static let regionIndex: [String: String] = {
        var index: [String: String] = [:]
        let display = Locale.current

        var sourceLocales = ["en"]
        sourceLocales += PreferredLanguages.codes()
        sourceLocales += ["de", "fr", "es", "it", "nl", "sv", "da", "nb", "pl", "pt", "tr", "ar"]

        for identifier in Set(sourceLocales) {
            let source = Locale(identifier: identifier)
            for region in Locale.Region.isoRegions where region.subRegions.isEmpty {
                guard let localized = display.localizedString(forRegionCode: region.identifier),
                      let written = source.localizedString(forRegionCode: region.identifier)
                else { continue }
                index[SearchNormalizer.normalize(written)] = localized
            }
        }

        // Bare ISO codes: a category left as "NO" after marker stripping.
        for region in Locale.Region.isoRegions where region.subRegions.isEmpty {
            guard let localized = display.localizedString(forRegionCode: region.identifier) else {
                continue
            }
            index[SearchNormalizer.normalize(region.identifier)] = localized
        }
        return index
    }()

    // MARK: - Genres

    /// The recurring genre vocabulary, keyed by its normalised English form.
    ///
    /// Every value is a real catalog entry, so these are translated by the same
    /// machinery — and enforced by the same lint — as the rest of the interface.
    private static let genreResources: [String: LocalizedStringResource] = {
        var index: [String: LocalizedStringResource] = [:]
        for (aliases, resource) in genres {
            for alias in aliases {
                index[SearchNormalizer.normalize(alias)] = resource
            }
        }
        return index
    }()

    private static let genres: [([String], LocalizedStringResource)] = [
        (["entertainment"], CoreStrings.genreEntertainment),
        (["comedy", "comedies", "humour", "humor"], CoreStrings.genreComedy),
        (["drama", "dramas"], CoreStrings.genreDrama),
        (["action"], CoreStrings.genreAction),
        (["adventure"], CoreStrings.genreAdventure),
        (["animation", "animated", "cartoon", "cartoons", "anime"], CoreStrings.genreAnimation),
        (["kids", "children", "child", "junior"], CoreStrings.genreKids),
        (["family"], CoreStrings.genreFamily),
        (["documentary", "documentaries", "docu", "docs"], CoreStrings.genreDocumentary),
        (["sport", "sports"], CoreStrings.genreSport),
        (["football", "soccer"], CoreStrings.genreFootball),
        (["news"], CoreStrings.genreNews),
        (["music"], CoreStrings.genreMusic),
        (["movies", "movie", "film", "films", "cinema", "vod"], CoreStrings.movies),
        (["series", "tv shows", "shows", "tvshows"], CoreStrings.series),
        (["lifestyle"], CoreStrings.genreLifestyle),
        (["food", "cooking"], CoreStrings.genreFood),
        (["travel"], CoreStrings.genreTravel),
        (["nature", "wildlife"], CoreStrings.genreNature),
        (["science"], CoreStrings.genreScience),
        (["history"], CoreStrings.genreHistory),
        (["crime"], CoreStrings.genreCrime),
        (["thriller", "thrillers"], CoreStrings.genreThriller),
        (["horror"], CoreStrings.genreHorror),
        (["romance", "romantic"], CoreStrings.genreRomance),
        (["sci fi", "scifi", "science fiction"], CoreStrings.genreSciFi),
        (["fantasy"], CoreStrings.genreFantasy),
        (["western", "westerns"], CoreStrings.genreWestern),
        (["war"], CoreStrings.genreWar),
        (["biography", "biographies"], CoreStrings.genreBiography),
        (["mystery"], CoreStrings.genreMystery),
        (["reality"], CoreStrings.genreReality),
        (["religious", "religion"], CoreStrings.genreReligion),
        (["education", "educational", "learning"], CoreStrings.genreEducation),
        (["health", "fitness"], CoreStrings.genreHealth),
        (["gaming", "games"], CoreStrings.genreGaming),
        (["classic", "classics"], CoreStrings.genreClassics),
        (["adult", "xxx"], CoreStrings.genreAdult),
        (["radio"], CoreStrings.genreRadio),
        (["weather"], CoreStrings.genreWeather),
        (["shopping"], CoreStrings.genreShopping),
        (["events", "event"], CoreStrings.genreEvents),
        (["general"], CoreStrings.genreGeneral),
        (["local"], CoreStrings.genreLocal),
        (["international"], CoreStrings.genreInternational),
        (["premium", "vip"], CoreStrings.genrePremium),
        (["other", "others", "misc", "miscellaneous", "uncategorized", "uncategorised"],
         CoreStrings.otherCategory),
    ]
}
