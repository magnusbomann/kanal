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
