import Foundation

/// Every user-facing string produced by KanalCore.
///
/// Centralised for one reason: it makes "did we miss anything?" a question you
/// answer by reading one file rather than by trusting a grep. Strings built at
/// runtime — error messages, counts, kind names — are invisible to Xcode's
/// extractor unless they are declared as literals somewhere, and this is that
/// somewhere.
///
/// The bundle is baked in on purpose. SwiftUI and Foundation both default to
/// `Bundle.main`, which in a Swift package silently resolves to the app and
/// falls back to the key itself — a bug that looks like success in English and
/// like nothing happened in every other language.
public enum CoreStrings {

    static var bundle: LocalizedStringResource.BundleDescription {
        .atURL(Bundle.module.bundleURL)
    }

    private static func resource(
        _ key: String.LocalizationValue,
        _ comment: StaticString
    ) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: bundle, comment: comment)
    }

    // MARK: Kinds

    public static let liveTV = resource("kind.liveTV", "Tab and section name for live television")
    public static let movies = resource("kind.movies", "Tab and section name for films")
    public static let series = resource("kind.series", "Tab and section name for TV series")

    // MARK: Loading failures

    public static let noPlaylistURL = resource(
        "error.noPlaylistLink", "Shown when a saved source has no playlist link"
    )
    public static let emptyPlaylist = resource(
        "error.emptyPlaylist", "Shown when a playlist loads but contains no channels"
    )
    public static func httpError(_ code: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "error.http \(code)", bundle: bundle,
            comment: "Shown when the provider's server returns an HTTP error code"
        )
    }

    // MARK: Provider failures

    public static let badResponse = resource(
        "error.badResponse", "The server answered but not in a format we understand"
    )
    public static let unauthorized = resource(
        "error.unauthorized", "The provider rejected the username or password"
    )
    public static let subscriptionExpired = resource(
        "error.expired", "The provider subscription has expired, date unknown"
    )
    public static func subscriptionExpired(on date: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "error.expiredOn \(date)", bundle: bundle,
            comment: "The provider subscription expired on a known date"
        )
    }
    public static let noAPIKey = resource(
        "error.noMetadataKey", "No metadata provider key is configured"
    )
    public static let rateLimited = resource(
        "error.rateLimited", "A metadata provider asked us to slow down"
    )
    public static let requestFailed = resource(
        "error.requestFailed", "A network request could not be built or sent"
    )

    // MARK: Setup detection

    public static let detectEmpty = resource(
        "detect.empty", "Shown when the setup field is still empty"
    )
    public static let detectUnusable = resource(
        "detect.unusable", "Shown when the pasted text is not a link Kanal can open"
    )

    // MARK: Handoff

    public static let pairingMismatch = resource(
        "pairing.mismatch", "The phone's payload could not be decrypted with this code"
    )
    public static let pairingUnreadableCode = resource(
        "pairing.unreadableCode", "The scanned code was not a valid Kanal invitation"
    )
    public static let pairingNotFound = resource(
        "pairing.notFound", "The Apple TV was not found on the local network"
    )

    // MARK: Loading

    public static func loadingSource(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "loading.source \(name)", bundle: bundle,
            comment: "Shown while a named playlist is loading"
        )
    }


    // MARK: Genres
    //
    // The recurring vocabulary of IPTV category names. Translating these is
    // what stops a Norwegian home screen reading "Entertainment" over one shelf
    // and "Serier" in the tab bar directly below it.

    public static let genreEntertainment = resource(
        "genre.entertainment", "Provider category name"
    )
    public static let genreComedy = resource(
        "genre.comedy", "Provider category name"
    )
    public static let genreDrama = resource(
        "genre.drama", "Provider category name"
    )
    public static let genreAction = resource(
        "genre.action", "Provider category name"
    )
    public static let genreAdventure = resource(
        "genre.adventure", "Provider category name"
    )
    public static let genreAnimation = resource(
        "genre.animation", "Provider category name"
    )
    public static let genreKids = resource(
        "genre.kids", "Provider category name"
    )
    public static let genreFamily = resource(
        "genre.family", "Provider category name"
    )
    public static let genreDocumentary = resource(
        "genre.documentary", "Provider category name"
    )
    public static let genreSport = resource(
        "genre.sport", "Provider category name"
    )
    public static let genreFootball = resource(
        "genre.football", "Provider category name"
    )
    public static let genreNews = resource(
        "genre.news", "Provider category name"
    )
    public static let genreMusic = resource(
        "genre.music", "Provider category name"
    )
    public static let genreLifestyle = resource(
        "genre.lifestyle", "Provider category name"
    )
    public static let genreFood = resource(
        "genre.food", "Provider category name"
    )
    public static let genreTravel = resource(
        "genre.travel", "Provider category name"
    )
    public static let genreNature = resource(
        "genre.nature", "Provider category name"
    )
    public static let genreScience = resource(
        "genre.science", "Provider category name"
    )
    public static let genreHistory = resource(
        "genre.history", "Provider category name"
    )
    public static let genreCrime = resource(
        "genre.crime", "Provider category name"
    )
    public static let genreThriller = resource(
        "genre.thriller", "Provider category name"
    )
    public static let genreHorror = resource(
        "genre.horror", "Provider category name"
    )
    public static let genreRomance = resource(
        "genre.romance", "Provider category name"
    )
    public static let genreSciFi = resource(
        "genre.scifi", "Provider category name"
    )
    public static let genreFantasy = resource(
        "genre.fantasy", "Provider category name"
    )
    public static let genreWestern = resource(
        "genre.western", "Provider category name"
    )
    public static let genreWar = resource(
        "genre.war", "Provider category name"
    )
    public static let genreBiography = resource(
        "genre.biography", "Provider category name"
    )
    public static let genreMystery = resource(
        "genre.mystery", "Provider category name"
    )
    public static let genreReality = resource(
        "genre.reality", "Provider category name"
    )
    public static let genreReligion = resource(
        "genre.religion", "Provider category name"
    )
    public static let genreEducation = resource(
        "genre.education", "Provider category name"
    )
    public static let genreHealth = resource(
        "genre.health", "Provider category name"
    )
    public static let genreGaming = resource(
        "genre.gaming", "Provider category name"
    )
    public static let genreClassics = resource(
        "genre.classics", "Provider category name"
    )
    public static let genreAdult = resource(
        "genre.adult", "Provider category name"
    )
    public static let genreRadio = resource(
        "genre.radio", "Provider category name"
    )
    public static let genreWeather = resource(
        "genre.weather", "Provider category name"
    )
    public static let genreShopping = resource(
        "genre.shopping", "Provider category name"
    )
    public static let genreEvents = resource(
        "genre.events", "Provider category name"
    )
    public static let genreGeneral = resource(
        "genre.general", "Provider category name"
    )
    public static let genreLocal = resource(
        "genre.local", "Provider category name"
    )
    public static let genreInternational = resource(
        "genre.international", "Provider category name"
    )
    public static let genrePremium = resource(
        "genre.premium", "Provider category name"
    )

    // MARK: Categories

    /// The bucket for entries whose provider gave no category.
    public static let otherCategory = resource(
        "category.other", "Fallback name for entries with no provider category"
    )
}

public extension LocalizedStringResource {
    /// Resolves for display in code that needs a plain `String`.
    var resolved: String { String(localized: self) }
}
