import Foundation
import Testing
@testable import KanalCore

@Suite("Title cleaning")
struct TitleCleanerTests {

    @Test("Strips a leading country marker")
    func leadingCountry() {
        let result = TitleCleaner.clean("NO| Viaplay Sport 1")
        #expect(result.title == "Viaplay Sport 1")
        #expect(result.countryCode == "NO")
    }

    @Test("Strips bracketed country markers")
    func bracketedCountry() {
        #expect(TitleCleaner.clean("[SE] SVT1").title == "SVT1")
        #expect(TitleCleaner.clean("(DK) DR1").title == "DR1")
        #expect(TitleCleaner.clean("EN: BBC One").title == "BBC One")
    }

    @Test("Does not mistake a quality tag for a country")
    func qualityIsNotCountry() {
        let result = TitleCleaner.clean("HD | Eurosport 1")
        #expect(result.countryCode == nil)
    }

    @Test("Strips trailing quality tokens")
    func trailingQuality() {
        #expect(TitleCleaner.clean("TV2 Norge FHD").title == "TV2 Norge")
        #expect(TitleCleaner.clean("Discovery 1080p HEVC").title == "Discovery")
    }

    @Test("Extracts season and episode", arguments: [
        ("Breaking Bad S01E04", 1, 4),
        ("Breaking Bad s1e4", 1, 4),
        ("Breaking Bad 1x04", 1, 4),
        ("Breaking Bad Season 2 Episode 11", 2, 11),
    ])
    func episodes(input: String, season: Int, episode: Int) {
        let result = TitleCleaner.clean(input)
        #expect(result.season == season)
        #expect(result.episode == episode)
        #expect(result.seriesName == "Breaking Bad")
    }

    @Test("Combines country, episode and quality")
    func combined() {
        let result = TitleCleaner.clean("EN - Breaking Bad S01E04 1080p")
        #expect(result.seriesName == "Breaking Bad")
        #expect(result.title == "Breaking Bad S01E04")
        #expect(result.countryCode == "EN")
        #expect(result.qualityTag == "1080P")
    }

    @Test("Extracts a trailing year")
    func year() {
        let result = TitleCleaner.clean("Blade Runner 2049 (2017)")
        #expect(result.year == 2017)
        #expect(result.title == "Blade Runner 2049")
    }

    @Test("Never returns an empty title")
    func neverEmpty() {
        #expect(TitleCleaner.clean("HD").title == "HD")
        #expect(TitleCleaner.clean("   ").title == "   ")
    }
}

@Suite("Show names and episode titles")
struct EpisodeNamingTests {

    /// The bug this guards: joining the text on both sides of the code gave
    /// every episode a different show name, so one series became dozens of
    /// one-episode shows.
    @Test("The show is what precedes the code, not what surrounds it")
    func splitsAroundTheCode() {
        let result = TitleCleaner.clean("Breaking Bad S01E01 - Pilot")
        #expect(result.seriesName == "Breaking Bad")
        #expect(result.episodeTitle == "Pilot")
        #expect(result.title == "Breaking Bad S01E01")
    }

    @Test("Every episode of a run shares one show name", arguments: [
        "Breaking Bad S01E01 - Pilot",
        "Breaking Bad S01E02 - Cat's in the Bag",
        "Breaking Bad S02E13 - ABQ",
        "Breaking Bad S05E16 Felina",
    ])
    func oneShowManyEpisodes(raw: String) {
        #expect(TitleCleaner.clean(raw).seriesName == "Breaking Bad")
    }

    @Test("An episode with no title of its own has none invented")
    func noEpisodeTitle() {
        let result = TitleCleaner.clean("Breaking Bad S01E04")
        #expect(result.seriesName == "Breaking Bad")
        #expect(result.episodeTitle == nil)
    }

    @Test("Quality noise after the code is not mistaken for a title")
    func qualityIsNotATitle() {
        let result = TitleCleaner.clean("NO| Breaking Bad S01E04 1080p")
        #expect(result.seriesName == "Breaking Bad")
        #expect(result.episodeTitle == nil)
        #expect(result.qualityTag == "1080P")
    }

    @Test("Grouping folds a whole run into one show")
    func groupsIntoOneShow() {
        let items = (1...6).map { number -> MediaItem in
            let raw = "Breaking Bad S0\(number <= 3 ? 1 : 2)E0\(number) - Episode \(number)"
            let cleaned = TitleCleaner.clean(raw)
            return MediaItem(
                id: raw, kind: .series, title: cleaned.title, rawTitle: raw,
                streamURL: URL(string: "http://p.tv/play/\(number)")!,
                seriesName: cleaned.seriesName, episodeTitle: cleaned.episodeTitle,
                season: cleaned.season, episode: cleaned.episode
            )
        }
        let library = Library(items: items)
        #expect(library.series.count == 1, "a run must not become several shows")
        #expect(library.series.first?.episodes.count == 6)
        #expect(library.series.first?.seasonNumbers == [1, 2])
    }
}

@Suite("Numbers in titles that are not years")
struct TitleYearPlausibilityTests {

    @Test("A number in the future is part of the name, not a release year")
    func futureNumberStaysInTitle() {
        // Read as a year, "Blade Runner 2049" becomes a 2049 film nobody has
        // heard of: no poster, no plot, no cast — and three listings of it
        // stop looking like the same film.
        let result = TitleCleaner.clean("Blade Runner 2049")
        #expect(result.title == "Blade Runner 2049")
        #expect(result.year == nil)
    }

    @Test("Brackets do not make a future number a year either")
    func bracketedFutureNumberStaysInTitle() {
        #expect(TitleCleaner.clean("Blade Runner (2049)").year == nil)
    }

    @Test("A real release year is still read")
    func plausibleYearIsRead() {
        let result = TitleCleaner.clean("Interstellar (2014)")
        #expect(result.title == "Interstellar")
        #expect(result.year == 2014)
    }

    @Test("Next year is a year: providers list titles before they arrive")
    func nextYearIsAllowed() {
        let next = Calendar(identifier: .gregorian).component(.year, from: .now) + 1
        #expect(TitleCleaner.clean("Some Film \(next)").year == next)
    }

    @Test("A title that is only a number keeps it")
    func bareNumberTitle() {
        #expect(TitleCleaner.clean("1917").title == "1917")
    }
}
