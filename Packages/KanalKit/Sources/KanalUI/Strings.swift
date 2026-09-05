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
    public static let streamPlaying = text("stream.playing", "The active stream")
    public static let streamChoose = text("stream.choose", "Live stream selection and recovery")
    public static let streamLock = text("stream.lock", "Live stream selection and recovery")
    public static let streamLockBody = text("stream.lock.body", "Live stream selection and recovery")
    public static let streamLocked = text("stream.locked", "Live stream selection and recovery")
    public static let streamSelected = text("stream.selected", "Live stream selection and recovery")
    public static let streamWaiting = text("stream.waiting", "Live stream selection and recovery")
    public static let streamWaitingBody = text("stream.waiting.body", "Live stream selection and recovery")
    public static let streamSearchStopped = text("stream.stopped", "Live stream selection and recovery")
    public static let streamSearchStoppedBody = text("stream.stopped.body", "Live stream selection and recovery")
    public static let streamDone = text("stream.done", "Live stream selection and recovery")


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

    // MARK: - Intro

    public static let introOneHeadlineTop = text("intro.1.top", "First intro headline, line one, in capitals")
    public static let introOneHeadlineBottom = text("intro.1.bottom", "First intro headline, line two, shown in grey")
    public static let introOneBody = text("intro.1.body", "Explains what Kanal is and is not")
    public static let introTwoHeadlineTop = text("intro.2.top", "Second intro headline, line one, in capitals")
    public static let introTwoHeadlineBottom = text("intro.2.bottom", "Second intro headline, line two, shown in grey")
    public static let introTwoBody = text("intro.2.body", "Explains where to find the link from your provider")
    public static let introContinue = text("intro.continue", "Advances to the next intro page")
    public static let introSkip = text("intro.skip", "Skips the intro and goes straight to the setup field")
    public static func introStep(_ step: Int, _ total: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "intro.step \(step) \(total)", bundle: bundle,
            comment: "Accessibility description of the page indicator"
        )
    }

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
    public static let welcomePromiseOneLink = text(
        "welcome.promise.oneLink", "Setup reassurance that one link is enough"
    )
    public static let welcomePromiseAutomatic = text(
        "welcome.promise.automatic", "Setup reassurance that Kanal organises everything automatically"
    )
    public static let welcomePromisePrivate = text(
        "welcome.promise.private", "Setup reassurance that the provider details stay private"
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
    public static let detectedReady = text(
        "detect.ready", "Confirms that the pasted setup link is ready without naming its protocol"
    )
    public static let detectedSignInNeeded = text(
        "detect.signInNeeded", "Says the service was found and the supplied sign-in details are needed"
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
    public static let homeQuestion = text(
        "home.question", "Main Home heading asking what the viewer wants to watch"
    )

    public static let shelfContinueWatching = text(
        "shelf.continueWatching", "Row of partly watched films and episodes"
    )
    public static let shelfFavouriteChannels = text("shelf.favouriteChannels", "Row of favourited channels")
    public static let shelfFavouriteSeries = text("shelf.favouriteSeries", "Row of favourited shows")
    public static let shelfNextEpisode = text(
        "shelf.nextEpisode", "Row of episodes that follow recently finished episodes"
    )
    public static let shelfOnNow = text(
        "shelf.onNow", "Row of favourite channels showing what is on and next"
    )
    public static let shelfRecentChannels = text(
        "shelf.recentChannels", "Row of channels watched recently"
    )
    public static let shelfRecentlyAdded = text(
        "shelf.recentlyAdded", "Row of films and shows added by the TV service recently"
    )
    public static let shelfTopMovies = text(
        "shelf.topMovies", "Row of the highest-ranked films available in the viewer's library"
    )
    public static let shelfTopSeries = text(
        "shelf.topSeries", "Row of the highest-ranked shows available in the viewer's library"
    )
    public static let shelfFeaturedMovies = text(
        "shelf.featuredMovies", "Fallback film row when no external popularity ranking is available"
    )
    public static let shelfFeaturedSeries = text(
        "shelf.featuredSeries", "Fallback show row when no external popularity ranking is available"
    )
    public static let shelfNewMovies = text(
        "shelf.newMovies", "Row of recently released films"
    )
    public static let shelfNewSeries = text(
        "shelf.newSeries", "Row of recently released shows"
    )
    public static let shelfFavouriteMovies = text(
        "shelf.favouriteMovies", "Row of favourited films"
    )
    public static func nextProgramme(_ title: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "programme.next \(title)", bundle: bundle,
            comment: "Names the programme airing after the current one. The placeholder is its title."
        )
    }
    public static let seeAll = text("action.seeAll", "Opens the full list for a row")
    public static let libraryEmpty = text("library.empty", "Shown when no library is loaded")

    // MARK: - Recommendations

    public static let shelfTrending = text(
        "shelf.trending", "Row of what is popular this week, filtered to what the viewer's provider carries"
    )
    public static let shelfNewReleases = text(
        "shelf.newReleases", "Row of recently released titles"
    )
    public static func shelfOnService(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "shelf.onService \(name)", bundle: bundle,
            comment: "Row of what is popular on a streaming service. The placeholder is a service name such as Netflix."
        )
    }

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

    // MARK: - Filters

    public static let sortRecommended = text("sort.recommended", "Default ordering: what is popular, then the newest")
    public static let sortNewest = text("sort.newest", "Newest first")
    public static let sortOldest = text("sort.oldest", "Oldest first")
    public static let sortAlphabetical = text("sort.alphabetical", "A to Z")
    public static let filterGenre = text("filter.genre", "Menu label for narrowing by genre")
    public static let filterCountry = text("filter.country", "Menu label for narrowing by country")
    public static let filterDecade = text("filter.decade", "Menu label for narrowing by decade")
    public static let filterClear = text("filter.clear", "Removes every narrowing")
    public static func decadeLabel(_ decade: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "filter.decade.label \(decade)", bundle: bundle,
            comment: "Names a decade. English writes 1990s; other languages do not follow that pattern."
        )
    }
    public static let filterNoResultsTitle = text("filter.noResults.title", "Title when the filters exclude everything")
    public static let filterNoResultsBody = text("filter.noResults.body", "Suggests removing a filter")
    public static let seriesEmptyTitle = text("series.empty.title", "Title when the source carries no series at all")
    public static let seriesEmptyBody = text("series.empty.body", "Explains the playlist simply has no series, no filter to remove")
    public static let moviesEmptyTitle = text("movies.empty.title", "Title when the source carries no films at all")
    public static let moviesEmptyBody = text("movies.empty.body", "Explains the playlist simply has no films, no filter to remove")
    public static let browseMovieCategories = text(
        "browse.movieCategories", "Heading above film rows grouped by genre"
    )
    public static let browseSeriesCategories = text(
        "browse.seriesCategories", "Heading above show rows grouped by genre"
    )
    public static let browseAllMovies = text(
        "browse.allMovies", "Button that opens the complete film library"
    )
    public static let browseAllSeries = text(
        "browse.allSeries", "Button that opens the complete show library"
    )

    // MARK: - Alternative streams

    public static let otherSources = text(
        "sources.action", "Opens the other streams that carry this channel"
    )
    public static let sourcesTitle = text("sources.title", "Heading of the alternative streams sheet, in capitals")
    public static let sourcesHint = text(
        "sources.hint", "Explains that the chosen stream is remembered"
    )
    public static let sourceLastWorked = text(
        "sources.lastWorked", "Marks the stream that played successfully last time"
    )
    public static func sourceCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "sources.count \(count)", bundle: bundle,
            comment: "How many streams carry this channel"
        )
    }
    public static let tryAnotherSource = text(
        "player.switchSource",
        "Button over the picture that gives up on this stream and tries the next one"
    )
    public static let switchingSource = text(
        "player.switchingSource", "Shown while the next stream is being opened"
    )
    public static func sourcePosition(_ number: Int, _ total: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "player.sourcePosition \(number) \(total)", bundle: bundle,
            comment: "Which stream of how many is playing. Spoken, not shown."
        )
    }

    // MARK: - Detail screen

    public static let detailPlay = text("detail.play", "Starts the film")
    public static func detailPlayEpisode(_ code: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "detail.play.episode \(code)", bundle: bundle,
            comment: "Starts a specific episode. The placeholder is a code such as S01E01."
        )
    }
    public static let detailResume = text("detail.resume", "Continues from where it was left")
    public static let detailOverview = text("detail.overview", "Heading above the plot summary")
    public static let detailCast = text("detail.cast", "Heading above the list of actors")
    public static let detailEpisodes = text("detail.episodes", "Heading above the episode list")
    public static let detailNoInfo = text(
        "detail.noInfo", "Shown when nothing is known about a title beyond its name"
    )
    public static func detailRuntime(_ minutes: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "detail.runtime \(minutes)", bundle: bundle,
            comment: "How long a film runs, in minutes"
        )
    }
    public static let personKnownFor = text("person.knownFor", "Heading above a person's best-known work")
    public static let personNotInLibrary = text(
        "person.notInLibrary", "Marks a film or show the viewer's provider does not carry"
    )

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

    // MARK: - TV guide

    public static let guide = text("guide.title", "The TV guide: channels down, time across")
    public static let viewList = text("guide.view.list", "Shows channels as a grid of tiles")
    public static let viewGuide = text("guide.view.guide", "Shows channels as a time-based guide")
    public static let guideMissingTitle = text(
        "guide.missing.title", "Title when no TV guide has been downloaded"
    )
    public static let guideMissingBody = text(
        "guide.missing.body", "Explains that the guide comes from the provider"
    )
    public static let guideNoChannelsTitle = text(
        "guide.noChannels.title", "Title when the guide covers none of the channels"
    )
    public static let guideNoChannelsBody = text(
        "guide.noChannels.body", "Explains that the provider's guide does not match its channels"
    )

    // MARK: - Watching a series through

    public static let nextEpisode = text("player.next.label", "Label above the episode that will play next")
    public static let playNow = text("player.next.playNow", "Starts the next episode immediately")
    public static let stopWatching = text("player.next.stop", "Closes the player instead of continuing")
    public static func playingInSeconds(_ seconds: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "player.next.countdown \(seconds)", bundle: bundle,
            comment: "Counts down to the next episode starting on its own"
        )
    }

    // MARK: - Playback

    public static let buffering = text("player.buffering", "Shown while a stream is loading")
    public static let streamFailedTitle = text("player.failed.title", "Title when a stream will not play")

    public static let playbackUnsupportedTitle = text(
        "player.unsupported.title", "Title when the provider's file format cannot be opened"
    )
    public static func playbackUnsupportedBody(_ container: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "player.unsupported.body \(container)", bundle: bundle,
            comment: "Explains that the provider sends this film in a container Apple cannot open. The placeholder is a file format name such as MKV."
        )
    }
    public static let playbackServerTitle = text(
        "player.server.title", "Title when the provider's server cannot be streamed from"
    )
    public static let playbackServerBody = text(
        "player.server.body", "Explains that the server does not support seeking"
    )
    public static let playbackRejectedTitle = text(
        "player.rejected.title", "Title when the provider refused the request"
    )
    public static let playbackRejectedBody = text(
        "player.rejected.body", "Explains the subscription may have expired or hit its connection limit"
    )
    public static let playbackOfflineTitle = text(
        "player.offline.title", "Title when there is no network"
    )
    public static let playbackOfflineBody = text(
        "player.offline.body", "Explains the device could not reach the provider"
    )

    public static let sectionWithheldByRating = text(
        "profiles.section.withheldByRating",
        "Section listing titles an age rating is holding back from an approved category"
    )
    public static let withheldByRatingFooter = text(
        "profiles.withheldByRating.footer",
        "Explains that a grown-up can let a specific title through anyway"
    )
    public static func ratedBadge(_ badge: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "profiles.ratedBadge \(badge)", bundle: bundle,
            comment: "Shows the age rating a title was given, e.g. \"Rated 12\""
        )
    }

    // MARK: - Parental code

    public static let codeEnterTitle = text("code.enter.title", "Asks for the parental code to unlock")
    public static let codeEnterMessage = text("code.enter.message", "Explains why the code is being asked for")
    public static let codeSetTitle = text("code.set.title", "Asks the adult to choose a new code")
    public static let codeSetMessage = text("code.set.message", "Explains what the code will protect")
    public static let codeConfirmTitle = text("code.confirm.title", "Asks for the new code a second time")
    public static let codeConfirmMessage = text("code.confirm.message", "Explains the second entry guards against typos")
    public static let codeWrong = text("code.wrong", "Shown when the entered code does not match")
    public static func codeDigitsEntered(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "code.digitsEntered \(count)", bundle: bundle,
            comment: "Accessibility description of how many digits have been typed"
        )
    }

    // MARK: - Player controls

    public static let closePlayer = text("player.close", "Leaves the player and returns to browsing")
    public static let play = text("player.play", "Resumes playback")
    public static let pause = text("player.pause", "Pauses playback")
    public static let audioAndSubtitles = text(
        "player.tracks", "Opens the audio and subtitle track picker"
    )
    public static let audioTrack = text("player.audioTrack", "Section heading for audio tracks")
    public static let subtitles = text("player.subtitles", "Section heading for subtitle tracks")
    public static let subtitlesOff = text("player.subtitles.off", "Turns subtitles off")

    // MARK: - Loading and failure

    public static let loadingDetail = text("loading.detail", "Sub-line describing what happens during loading")
    public static let loadFailedTitle = text("load.failed.title", "Title when a playlist could not load")
    public static let connectionContacting = text("connection.contacting", "Setup progress while contacting a TV service")
    public static let connectionSigningIn = text("connection.signingIn", "Setup progress while verifying sign-in details")
    public static let connectionLoadingContent = text("connection.loadingContent", "Setup progress while downloading the library")
    public static let connectionOrganising = text("connection.organising", "Setup progress while organising channels and titles")
    public static let connectionReady = text("connection.ready", "Setup progress when the service is ready")
    public static let connectionProgressDetail = text(
        "connection.detail", "Reassures that setup may take a little while on a large service"
    )

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
    public static let changeTVService = text("source.change", "Repairs a saved TV service with new connection details")
    public static let repairTitle = text("source.repair.title", "Heading when repairing a saved TV service")
    public static let repairBody = text("source.repair.body", "Explains that repair keeps the person's history and favourites")

    public static let sectionSupport = text("settings.section.support", "Settings section for support tools")
    public static let supportTitle = text("support.title", "Title of the support report screen")
    public static let supportIntro = text("support.intro", "Explains what the support report is for")
    public static let supportPrivacy = text("support.privacy", "Explains what private data is excluded from the report")
    public static let supportShare = text("support.share", "Shares the redacted support report")
    public static let supportReportLabel = text("support.report.label", "Heading above the support report text")

    public static let sectionSync = text("settings.section.sync", "Settings section for Apple device sync")
    public static let syncTitle = text("sync.title", "Title for Apple device sync")
    public static let syncBody = text("sync.body", "Explains the private Apple-account sync model")
    public static let syncNow = text("sync.now", "Runs Apple device sync immediately")
    public static let syncWaiting = text("sync.waiting", "Sync has not completed yet")
    public static let syncWorking = text("sync.working", "Sync is currently running")
    public static let syncCurrent = text("sync.current", "Sync completed successfully")
    public static let syncUnavailable = text("sync.unavailable", "iCloud sync is unavailable on this device")
    public static let syncFailed = text("sync.failed", "The most recent sync failed")
    public static func syncLastUpdated(_ relative: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "sync.lastUpdated \(relative)", bundle: bundle,
            comment: "Says when Apple device sync last completed"
        )
    }

    public static let sourceKindXtream = text("source.kind.xtream", "Source type label. A proper noun.")
    public static let sourceKindM3U = text("source.kind.m3u", "Source type label. A proper noun.")
    public static let sourceKindPasted = text("source.kind.pasted", "Source that was pasted as text")
    public static let sourceReady = text("source.ready", "Status for a connected TV service")
    public static func sourceUpdated(_ relative: String) -> LocalizedStringResource {
        LocalizedStringResource("source.updated \(relative)", bundle: bundle, comment: "How long ago a playlist was refreshed")
    }

    public static let rename = text("action.rename", "Renames a playlist")
    public static let save = text("action.save", "Confirms an edit")
    public static let renameTitle = text("rename.title", "Heading of the rename sheet, in capitals")
    public static let renamePrompt = text("rename.prompt", "Placeholder for the playlist name field")
    public static let renameHint = text(
        "rename.hint", "Explains that the detected name is only the provider's hostname"
    )

    // MARK: - Licenses

    public static let licenses = text("licenses.title", "Screen listing the open-source components Kanal is built on")
    public static let licensesIntro = text(
        "licenses.intro", "Explains that Kanal is built on open-source work and credits it"
    )
    public static let licenseLabel = text("licenses.label", "Row label for a component's licence name")
    public static let viewSource = text("licenses.viewSource", "Opens the component's source code in a browser")
    public static let licensesRelink = text(
        "licenses.relink",
        "The LGPL notice: states the viewer's right to obtain and substitute their own build of the library"
    )
    public static let creditVLCPurpose = text(
        "credit.vlc.purpose", "What VLC does inside Kanal"
    )
    public static let creditWikidataPurpose = text(
        "credit.wikidata.purpose", "What Wikidata does inside Kanal"
    )

    // MARK: - Credits

    public static let sectionCredits = text(
        "settings.section.credits", "Section crediting the data sources Kanal uses"
    )
    public static let creditTMDB = text(
        "settings.credit.tmdb",
        "Attribution required by TMDB's terms of use. The wording is theirs — translate it, but do not reword it."
    )
    public static let creditWikidata = text(
        "settings.credit.wikidata", "Credit for Wikidata, whose data is CC0 and needs none"
    )

    // MARK: - Data quality

    public static let sectionDataQuality = text(
        "settings.section.dataQuality", "Section describing problems in the provider's data"
    )
    public static let dataQualityIntro = text(
        "settings.dataQuality.intro",
        "Explains that these are faults in the provider's files, which Kanal worked around"
    )
    public static func skippedLines(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "settings.dataQuality.skippedLines \(count)", bundle: bundle,
            comment: "How many playlist entries could not be read at all"
        )
    }
    public static let guideRepaired = text(
        "settings.dataQuality.guideRepaired", "The TV guide file was malformed and had to be repaired"
    )
    public static let guidePartial = text(
        "settings.dataQuality.guidePartial", "The TV guide file stopped part-way through"
    )
    public static func guideCoverage(_ percent: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "settings.dataQuality.coverage \(percent)", bundle: bundle,
            comment: "What share of channels the TV guide actually covers"
        )
    }
    public static func guideProgrammes(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "settings.dataQuality.programmes \(count)", bundle: bundle,
            comment: "How many programmes the TV guide contains"
        )
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

    // MARK: - Profiles

    public static let whoIsWatching = text(
        "profiles.whoIsWatching", "Headline on the profile picker shown at launch"
    )
    public static let profiles = text("profiles.title", "Screen listing everyone in the household")
    public static let sectionProfiles = text("profiles.section", "Settings section for profiles")
    public static let sectionPeople = text("profiles.section.people", "Section listing each person")
    public static let addProfile = text("profiles.add", "Creates a new profile")
    public static let newProfile = text("profiles.new.title", "Title while creating a profile")
    public static let editProfile = text("profiles.edit.title", "Title while changing a profile")
    public static let manageProfiles = text("profiles.manage", "Opens the profile management screen")
    public static let switchProfile = text("profiles.switch", "Returns to the profile picker")
    public static let deleteProfile = text("profiles.delete", "Removes a profile and its history")
    public static let inUse = text("profiles.inUse", "Marks the profile currently in use")
    public static let cancel = text("action.cancel", "Abandons an edit without saving")
    public static let goBack = text("action.goBack", "Leaves a screen the viewer may not use")
    public static let profileNamePlaceholder = text(
        "profiles.namePlaceholder", "Placeholder in the profile name field"
    )
    public static let profileIsChild = text(
        "profiles.isChild", "Switch that turns a profile into a child's, with an age limit"
    )
    public static let profileChildFooter = text(
        "profiles.isChild.footer",
        "Explains that a child's profile only shows what a grown-up has approved"
    )
    public static let profileAdultFooter = text(
        "profiles.isAdult.footer", "Explains that an adult profile shows the whole library"
    )
    public static let sectionAgeLimit = text("profiles.section.ageLimit", "Section for the age limit")
    public static let ageLimit = text("profiles.ageLimit", "Label on the age limit picker")
    public static let sectionAllowedContent = text(
        "profiles.section.allowed", "Section listing the categories a child may watch"
    )
    public static let allowedContentFooter = text(
        "profiles.allowed.footer",
        "Explains that approved sections are still checked against official age ratings"
    )
    public static let allowedContentFooterNoProvider = text(
        "profiles.allowed.footer.noRatings",
        "Explains that without a ratings source only approved sections are shown"
    )
    public static let allCategories = text(
        "profiles.allCategories", "Expands the full list of provider categories"
    )
    public static let suggested = text(
        "profiles.suggested", "Marks a category Kanal thinks is children's television"
    )
    public static let noCategoriesYet = text(
        "profiles.noCategories", "Shown when the playlist has not loaded yet"
    )
    public static let updatingLibrary = text(
        "profiles.updatingLibrary", "Quiet note that the library is refreshing behind the picker"
    )
    public static let labelAwaitingRating = text(
        "profiles.awaitingRating", "Label for how many titles are still being checked"
    )
    public static func checkingRatings(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "profiles.checkingRatings \(count)", bundle: bundle,
            comment: "Progress note while age ratings are being looked up"
        )
    }
    public static let labelHiddenHere = text(
        "profiles.hiddenCount", "Label for how many entries this profile does not see"
    )
    public static let withheldFooter = text(
        "profiles.hidden.footer", "Explains why the library looks smaller in this profile"
    )

    // MARK: - Parental code

    public static let sectionParentalCode = text(
        "code.section", "Settings section for the four-digit parental code"
    )
    public static let setCode = text("code.set", "Creates a parental code")
    public static let changeCode = text("code.change", "Replaces the parental code")
    public static let removeCode = text("code.remove", "Deletes the parental code")
    public static let codeFooterSet = text(
        "code.footer.set", "Explains what the code currently protects"
    )
    public static let codeFooterUnset = text(
        "code.footer.unset", "Explains that without a code nothing is locked"
    )
    public static let childLibraryEmptyTitle = text(
        "profiles.emptyChild.title", "Title when a child's profile has nothing approved yet"
    )
    public static let childLibraryEmptyBody = text(
        "profiles.emptyChild.body", "Explains that a grown-up decides what appears here"
    )

    // MARK: - Blocked content

    public static let blockedTitle = text(
        "blocked.title", "Title shown when a profile may not watch something"
    )
    public static let blockedMessage = text(
        "blocked.message", "Tells the viewer to ask a grown-up"
    )

    // MARK: - Kanal Pluss

    public static let proHeadlineTop = text(
        "pro.headline.top", "First line of the paywall headline. The brand name, in capitals."
    )
    public static let proHeadlineBottom = text(
        "pro.headline.bottom", "Second line of the paywall headline: the name of the paid tier."
    )
    public static let proBody = text(
        "pro.body", "One sentence saying what the paid tier is"
    )
    public static let proFeatureNoWatermark = text(
        "pro.feature.noWatermark", "Paywall feature: the watermark and the reminders go away"
    )
    public static let proFeatureProfiles = text(
        "pro.feature.profiles", "Paywall feature: profiles and parental controls"
    )
    public static let proFeatureMetadata = text(
        "pro.feature.metadata", "Paywall feature: posters, descriptions and age limits"
    )
    public static let proFeatureHandoff = text(
        "pro.feature.handoff", "Paywall feature: setting up the Apple TV from an iPhone"
    )
    public static let proPlanMonthly = text("pro.plan.monthly", "Name of the monthly price")
    public static let proPlanYearly = text("pro.plan.yearly", "Name of the yearly price")
    public static let proPlanLifetime = text("pro.plan.lifetime", "Name of the one-off price")
    public static let proPlanBest = text(
        "pro.plan.best", "Badge on the recommended price"
    )
    public static func proPlanSave(_ percent: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "pro.plan.save \(percent)", bundle: bundle,
            comment: "Badge on the annual plan. The placeholder is the percentage saved."
        )
    }
    public static func proTrial(_ period: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "pro.trial \(period)", bundle: bundle,
            comment: "Free trial length, e.g. \"7 days free\""
        )
    }
    public static let proActionBuy = text("pro.action.buy", "Primary paywall button")
    public static let proActionTryFree = text(
        "pro.action.tryFree", "Primary paywall button when a free trial is available"
    )
    public static let proActionRestore = text(
        "pro.action.restore", "Restores a purchase made earlier or on another device"
    )
    public static let proActionRetry = text(
        "pro.action.retry", "Tries loading App Store prices again"
    )
    public static let proActionNotNow = text(
        "pro.action.notNow", "Closes the paywall without buying"
    )
    public static let proSmallPrintSubscription = text(
        "pro.smallPrint.subscription", "Small print under a subscription price"
    )
    public static let proSmallPrintLifetime = text(
        "pro.smallPrint.lifetime", "Small print under the one-off price"
    )
    public static let proReassurance = text(
        "pro.reassurance", "Says that the free app keeps working. The most important line on the screen."
    )
    public static let proUnavailable = text(
        "pro.unavailable", "Shown in place of prices when the App Store cannot be reached"
    )
    public static let proLoading = text(
        "pro.loading", "Shown while App Store prices load"
    )
    public static let proPeriodMonth = text(
        "pro.period.month", "Price suffix for a monthly subscription"
    )
    public static let proPeriodYear = text(
        "pro.period.year", "Price suffix for an annual subscription"
    )
    public static let proPeriodOnce = text(
        "pro.period.once", "Price suffix for a one-time purchase"
    )
    public static let proTerms = text(
        "pro.terms", "Link to the terms of use from the purchase screen"
    )
    public static let proPrivacy = text(
        "pro.privacy", "Link to the privacy policy from the purchase screen"
    )
    public static let proWatermark = text(
        "pro.watermark", "The mark drawn over video in the free tier. Tapping it opens the paywall."
    )
    public static let proSettingsSection = text(
        "pro.settings.section", "Settings section for the paid tier"
    )
    public static let proSettingsActive = text(
        "pro.settings.active", "Settings row shown when the paid tier is active"
    )
    public static let proSettingsUpgrade = text(
        "pro.settings.upgrade", "Settings row that opens the paywall"
    )
    public static let proSettingsManage = text(
        "pro.settings.manage", "Settings row that opens the system's subscription management"
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
