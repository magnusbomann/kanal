import Foundation

/// Every user-facing string in Kanal's interface.
///
/// One file, on purpose. "Have we missed anything?" should be a question you
/// answer by reading a list, not by trusting a grep across sixty files — and a
/// typo in a key here is a compile error rather than a sentence that silently
/// stays English.
///
/// The bundle is baked into every entry. SwiftUI's `Text("...")` looks up
/// `Bundle.main`, which from inside a Swift package resolves to the app and
/// finds nothing, then falls back to the key. That failure is invisible in
/// English and total in every other language.
public enum UIStrings {

    private static var bundle: LocalizedStringResource.BundleDescription {
        .atURL(Bundle.module.bundleURL)
    }

    private static func text(
        _ key: String.LocalizationValue,
        _ comment: StaticString
    ) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: bundle, comment: comment)
    }

    // MARK: - Brand

    public static let appName = text("app.name", "The app's name. Usually left untranslated.")

    // MARK: - Welcome and setup

    public static let welcomeHeadlineTop = text(
        "welcome.headline.top", "First line of the setup headline. Set in heavy condensed capitals."
    )
    public static let welcomeHeadlineBottom = text(
        "welcome.headline.bottom", "Second line of the setup headline, shown in grey."
    )
    public static let welcomeBody = text(
        "welcome.body", "Explains that setup is automatic"
    )
    public static let welcomeFieldPrompt = text(
        "welcome.field.prompt", "Placeholder in the single setup field"
    )
    public static let welcomeContinue = text(
        "welcome.action.continue", "Primary setup button"
    )
    public static let welcomeAddSignIn = text(
        "welcome.action.addSignIn", "Setup button when the provider still needs a username and password"
    )
    public static let welcomeDisclaimer = text(
        "welcome.disclaimer", "Legal note that Kanal provides no channels itself"
    )
    public static let welcomeHandoffAction = text(
        "welcome.handoff.action", "Apple TV button that starts phone handoff"
    )
    public static let welcomeHandoffHint = text(
        "welcome.handoff.hint", "Explains that handoff beats typing with a remote"
    )
    public static let clear = text("action.clear", "Clears the text field")

    // Format chips under the setup field.
    public static let formatM3U = text("format.m3u", "Playlist format name. A proper noun.")
    public static let formatXtream = text("format.xtream", "Provider protocol name. A proper noun.")
    public static let formatGuide = text("format.guide", "Short label for electronic programme guide support")

    // MARK: - Detection feedback

    public static func detectedXtream(host: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "detect.xtream \(host)", bundle: bundle,
            comment: "Confirms an Xtream provider was recognised at a hostname"
        )
    }
    public static func detectedM3U(host: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "detect.m3u \(host)", bundle: bundle,
            comment: "Confirms an M3U playlist was recognised at a hostname"
        )
    }
    public static let detectedFile = text("detect.file", "Confirms a playlist file was recognised")
    public static let detectedPastedText = text(
        "detect.pastedText", "Confirms pasted playlist text was recognised"
    )
    public static func detectedNeedsCredentials(host: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "detect.needsCredentials \(host)", bundle: bundle,
            comment: "Says a host looks like a provider but needs a username and password"
        )
    }
    public static let detectEmpty = text(
        "detect.empty", "Shown when the setup field is empty"
    )
    public static let detectUnusableLink = text(
        "detect.unusable", "Shown when the pasted text is not a link Kanal can open"
    )

    // MARK: - Sign in

    public static let signInTitle = text("signIn.title", "Heading of the sign-in sheet, in capitals")
    public static let signInUsername = text("signIn.username", "Username field label")
    public static let signInPassword = text("signIn.password", "Password field label")
    public static let signInConnect = text("signIn.connect", "Button that connects to the provider")
    public static let signInPrivacy = text(
        "signIn.privacy", "Reassures that credentials stay on the device"
    )

    // MARK: - Home

    public static let greetingNight = text("greeting.night", "Shown between midnight and 6am")
    public static let greetingMorning = text("greeting.morning", "Shown between 6am and noon")
    public static let greetingAfternoon = text("greeting.afternoon", "Shown between noon and 6pm")
    public static let greetingEvening = text("greeting.evening", "Shown after 6pm")

    public static let shelfContinueWatching = text(
        "shelf.continueWatching", "Row of partly watched films and episodes"
    )
    public static let shelfFavouriteChannels = text("shelf.favouriteChannels", "Row of favourited channels")
    public static let shelfFavouriteSeries = text("shelf.favouriteSeries", "Row of favourited shows")
    public static let seeAll = text("action.seeAll", "Opens the full list for a row")
    public static let libraryEmpty = text("library.empty", "Shown when no library is loaded")

    // MARK: - Counts
    //
    // Declared with the number inside the key so the string catalog can carry
    // plural rules. "1 channels" is wrong in English and much worse in
    // languages with more than two plural forms.

    public static func channelCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("count.channels \(count)", bundle: bundle, comment: "Number of live channels")
    }
    public static func filmCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("count.films \(count)", bundle: bundle, comment: "Number of films")
    }
    public static func seriesCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("count.series \(count)", bundle: bundle, comment: "Number of shows")
    }
    public static func episodeCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("count.episodes \(count)", bundle: bundle, comment: "Number of episodes")
    }
    public static func seasonCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("count.seasons \(count)", bundle: bundle, comment: "Number of seasons")
    }
    public static func playlistCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("count.playlists \(count)", bundle: bundle, comment: "Number of playlists received")
    }
    public static func minutesLeft(_ minutes: Int) -> LocalizedStringResource {
        LocalizedStringResource("progress.minutesLeft \(minutes)", bundle: bundle, comment: "Time remaining in something partly watched")
    }
    public static let nearlyFinished = text(
        "progress.nearlyFinished", "Shown instead of a time when under a minute remains"
    )
    public static func percentWatched(_ percent: Int) -> LocalizedStringResource {
        LocalizedStringResource("progress.percentWatched \(percent)", bundle: bundle, comment: "Accessibility description of a progress bar")
    }
    public static func seasonNumber(_ number: Int) -> LocalizedStringResource {
        LocalizedStringResource("season.number \(number)", bundle: bundle, comment: "Name of a season in the season filter")
    }

    // MARK: - Badges and filters

    public static let live = text("badge.live", "Marks a channel that is broadcasting now")
    public static let liveNowAccessibility = text("badge.live.accessibility", "Spoken form of the live badge")
    public static let filterAll = text("filter.all", "Category filter chip that clears the filter")

    // MARK: - Browsing

    public static let seriesNotFound = text("series.notFound", "Title when a show is no longer in the library")
    public static let seriesNotFoundBody = text("series.notFound.body", "Explains a show may have been removed by the provider")
    public static let playFirstEpisode = text("series.playFirst", "Plays the first episode of a show")
    public static let loadingEpisodes = text("series.loadingEpisodes", "Shown while episodes are fetched")
    public static let episodesFailed = text("series.episodesFailed", "Title when episodes could not be fetched")
    public static let noEpisodesListed = text("series.noEpisodes", "Shown when a show has no episodes")
    public static let tryAgain = text("action.tryAgain", "Retries a failed operation")

    // MARK: - Search

    public static let search = text("search.title", "Search screen title")
    public static let searchPrompt = text("search.prompt", "Placeholder in the search field")
    public static let searchEmptyTitle = text("search.empty.title", "Title before anything is typed")
    public static let searchEmptyBody = text(
        "search.empty.body", "Explains that titles in the viewer's own language work too"
    )
    public static let searchNoResultsTitle = text("search.noResults.title", "Title when nothing matched")
    public static let searchNoResultsBody = text(
        "search.noResults.body", "Explains that accents and word order are ignored"
    )
    public static let searchWidening = text(
        "search.widening", "Shown while checking other spellings of the query"
    )
    public static let searchLookingWider = text(
        "search.lookingWider", "Full-screen message while checking other spellings"
    )
    public static func searchMatchedVia(_ title: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "search.matchedVia \(title)", bundle: bundle,
            comment: "Explains a result was found under a different name. The name is shown in bold."
        )
    }

    // MARK: - Playback

    public static let buffering = text("player.buffering", "Shown while a stream is loading")
    public static let streamFailedTitle = text("player.failed.title", "Title when a stream will not play")

    // MARK: - Loading and failure

    public static let loadingDetail = text("loading.detail", "Sub-line describing what happens during loading")
    public static let loadFailedTitle = text("load.failed.title", "Title when a playlist could not load")

    // MARK: - Settings

    public static let settings = text("settings.title", "Settings screen title")
    public static let sectionPlaylists = text("settings.section.playlists", "Section listing the user's playlists")
    public static let sectionAppleTV = text("settings.section.appleTV", "Section for sending a playlist to an Apple TV")
    public static let sectionLibrary = text("settings.section.library", "Section showing what the library contains")
    public static let addPlaylist = text("settings.addPlaylist", "Adds another playlist")
    public static let remove = text("action.remove", "Deletes a playlist")
    public static let refreshNow = text("settings.refreshNow", "Reloads the active playlist immediately")
    public static let labelChannels = text("settings.label.channels", "Row label for the channel count")
    public static let labelFilms = text("settings.label.films", "Row label for the film count")
    public static let labelSeries = text("settings.label.series", "Row label for the series count")
    public static let labelGuide = text("settings.label.guide", "Row label for the TV guide status")
    public static let guideLoaded = text("settings.guide.loaded", "The TV guide has been downloaded")
    public static let guideNotLoaded = text("settings.guide.notLoaded", "The TV guide has not been downloaded")
    public static let settingsDisclaimer = text("settings.disclaimer", "Legal note that Kanal provides no channels")

    public static let sourceKindXtream = text("source.kind.xtream", "Source type label. A proper noun.")
    public static let sourceKindM3U = text("source.kind.m3u", "Source type label. A proper noun.")
    public static let sourceKindPasted = text("source.kind.pasted", "Source that was pasted as text")
    public static func sourceUpdated(_ relative: String) -> LocalizedStringResource {
        LocalizedStringResource("source.updated \(relative)", bundle: bundle, comment: "How long ago a playlist was refreshed")
    }

    // MARK: - Handoff

    public static let handoffTitle = text("handoff.title", "Screen that sends a playlist to an Apple TV")
    public static let handoffAim = text("handoff.aim", "Instruction to point the camera at the TV")
    public static let handoffFinding = text("handoff.finding", "Shown while looking for the Apple TV")
    public static let handoffSending = text("handoff.sending", "Shown while transmitting")
    public static let handoffSent = text("handoff.sent", "Shown when the transfer succeeded")
    public static let handoffSentBody = text("handoff.sent.body", "Explains the TV is now loading the playlist")
    public static let handoffCameraTitle = text("handoff.camera.title", "Title when camera access was refused")
    public static let handoffCameraBody = text("handoff.camera.body", "Explains why the camera is needed")
    public static let openSettings = text("action.openSettings", "Opens the system Settings app")
    public static let done = text("action.done", "Dismisses a completed screen")
    public static let handoffSettingsHint = text(
        "handoff.settingsHint", "Explains handoff in the Settings list"
    )

    // MARK: - Pairing (Apple TV side)

    public static let pairingHeadline = text(
        "pairing.headline", "Headline on the Apple TV pairing screen, in capitals across two lines"
    )
    public static let pairingBody = text("pairing.body", "Step-by-step instruction for the phone")
    public static let pairingWaiting = text("pairing.waiting", "Waiting for a phone to connect")
    public static let pairingReceiving = text("pairing.receiving", "A phone is transmitting")
    public static let pairingPrivacy = text(
        "pairing.privacy", "Reassures that the code is local and short-lived"
    )
    public static let pairingCodeAccessibility = text(
        "pairing.code.accessibility", "Spoken description of the QR code"
    )
}

public extension String {
    /// Resolves a catalog entry for the places that still need a plain `String`
    /// — provider-supplied names and our own text share those parameters, and
    /// a channel called "TV 2 Norge" is not something to translate.
    init(_ resource: LocalizedStringResource) {
        self.init(localized: resource)
    }
}

public extension UIStrings {
    static let addFavourite = LocalizedStringResource(
        "action.addFavourite", bundle: .atURL(Bundle.module.bundleURL),
        comment: "Context menu action that marks something as a favourite"
    )
    static let removeFavourite = LocalizedStringResource(
        "action.removeFavourite", bundle: .atURL(Bundle.module.bundleURL),
        comment: "Context menu action that unmarks a favourite"
    )
}

public extension UIStrings {
    static let tabHome = LocalizedStringResource(
        "tab.home", bundle: .atURL(Bundle.module.bundleURL),
        comment: "First tab, showing shelves of recent and favourite content"
    )
}
