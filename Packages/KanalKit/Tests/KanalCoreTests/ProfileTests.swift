import Foundation
import Testing
@testable import KanalCore

/// The rules a child's profile is made of.
///
/// Every test here is written from the failure it prevents rather than from the
/// function it calls, because the failure mode of this feature is not a crash
/// or a wrong number on a screen — it is a seven-year-old finding something.
@Suite("Age limits")
struct MaturityTests {

    @Test("A foreign rating rounds up to the nearest step, never down")
    func roundsUp() {
        // German FSK 16 has no Norwegian equivalent. Landing on 15 would let a
        // fifteen-year-old's profile through; landing on 18 costs them a
        // conversation with a parent.
        #expect(MaturityRating.nearest(atLeast: 16) == .adult)
        #expect(MaturityRating.nearest(atLeast: 7) == .nine)
        #expect(MaturityRating.nearest(atLeast: 0) == .allAges)
        #expect(MaturityRating.nearest(atLeast: 99) == .adult)
    }

    @Test("An adult limit is never offered as a child's ceiling")
    func childOptionsExcludeAdult() {
        #expect(!MaturityRating.childOptions.contains(.adult))
    }
}

@Suite("Reading a rating")
struct RatingParserTests {

    @Test("National board codes map onto the Norwegian ladder", arguments: [
        ("PG-13", "US", MaturityRating.twelve),
        ("TV-MA", "US", MaturityRating.adult),
        ("G", "US", MaturityRating.allAges),
        ("15", "NO", MaturityRating.fifteen),
        ("A", "NO", MaturityRating.allAges),
        ("U", "GB", MaturityRating.allAges),
        ("12A", "GB", MaturityRating.twelve),
        // Germany's 16 is where Norway puts 15, not 18 — see the equivalence
        // note in RatingParser. Rounding it up made teenage films adults-only.
        ("16", "DE", MaturityRating.fifteen),
        ("Btl", "SE", MaturityRating.allAges),
    ])
    func boards(code: String, country: String, expected: MaturityRating) {
        #expect(RatingParser.rating(code: code, country: country) == expected)
    }

    /// A letter code only means something to the board that issued it. Guessing
    /// would be a rating the app then presents to a parent as verified.
    @Test("An unknown code is unrated, not permitted")
    func unknownCode() {
        #expect(RatingParser.rating(code: "Kjempebra", country: "NO") == nil)
        #expect(RatingParser.rating(code: "", country: "NO") == nil)
    }

    @Test("Age limits written into free text are read", arguments: [
        ("Action 18+", MaturityRating.adult),
        ("FSK 16", MaturityRating.adult),
        ("Some Film (12)", MaturityRating.twelve),
        ("Aldersgrense 15", MaturityRating.fifteen),
    ])
    func freeText(text: String, expected: MaturityRating) {
        #expect(RatingParser.rating(inText: text) == expected)
    }

    @Test("A year is not an age limit")
    func notAYear() {
        #expect(RatingParser.rating(inText: "Blade Runner 2049") == nil)
        #expect(RatingParser.rating(inText: "1917") == nil)
    }
}

@Suite("Adult material")
struct AdultDetectorTests {

    static func item(_ title: String, group: String? = nil) -> MediaItem {
        MediaItem(
            id: title, kind: .movie, title: title, rawTitle: title,
            streamURL: URL(string: "http://p.tv/x")!, rawGroup: group, category: group
        )
    }

    @Test("The sections every panel ships are caught", arguments: [
        "XXX", "FOR ADULTS 18+", "Adult", "NO | Erotikk", "Brazzers", "VOKSEN",
    ])
    func categories(name: String) {
        #expect(AdultContentDetector.isAdult(category: name))
    }

    /// The words are matched whole. A detector that fires on substrings would
    /// hide Middlesex, Essex and half of Scandinavian television.
    @Test("Ordinary titles are not caught", arguments: [
        "Middlesex", "Sexton Blake", "The Sussex Files", "Kids' Adventure", "Essex Boys",
    ])
    func innocent(name: String) {
        #expect(!AdultContentDetector.isAdult(Self.item(name)))
    }

    @Test("An adult entry filed inside an ordinary section is still caught")
    func hidingInACleanCategory() {
        #expect(AdultContentDetector.isAdult(Self.item("Playboy TV", group: "Entertainment")))
    }
}

@Suite("What a profile may watch")
struct ContentPolicyTests {

    static func movie(_ title: String, category: String?, year: Int? = 2020) -> MediaItem {
        MediaItem(
            id: title, kind: .movie, title: title, rawTitle: title,
            streamURL: URL(string: "http://p.tv/play/\(abs(title.hashValue))")!,
            rawGroup: category, category: category, year: year
        )
    }

    static func channel(_ title: String, category: String?) -> MediaItem {
        MediaItem(
            id: title, kind: .liveTV, title: title, rawTitle: title,
            streamURL: URL(string: "http://p.tv/live/\(abs(title.hashValue))/m3u8")!,
            rawGroup: category, category: category
        )
    }

    static func episode(_ show: String, category: String?, year: Int? = 1999) -> MediaItem {
        MediaItem(
            id: "\(show) S01E01", kind: .series, title: "\(show) S01E01",
            rawTitle: "\(show) S01E01",
            streamURL: URL(string: "http://p.tv/series/\(abs(show.hashValue))")!,
            rawGroup: category, category: category,
            seriesName: show, season: 1, episode: 1, year: year
        )
    }

    static let library = Library(items: [
        movie("Bamse på tur", category: "Kids"),
        movie("Late Night Horror", category: "Horror"),
        movie("Adults Only Feature", category: "XXX"),
        episode("Bluey", category: "Animation"),
        episode("Family Guy", category: "Animation"),
        channel("NRK Super", category: "Kids"),
        channel("V Sport 1", category: "Sport"),
        channel("Hot TV", category: "Adult"),
    ])

    static func child(_ maturity: MaturityRating = .six, allowing categories: Set<String> = []) -> Profile {
        Profile(name: "Barn", maturity: maturity, allowedCategories: categories)
    }

    // MARK: - The default

    /// The rule the whole feature rests on. An IPTV catalogue carries no age
    /// limits, so "nobody has said this is fine" has to mean no.
    @Test("A child sees nothing until a grown-up says otherwise")
    func deniedByDefault() {
        let policy = ContentPolicy(profile: Self.child(), ratings: RatingIndex())
        #expect(policy.apply(to: Self.library).items.isEmpty)
    }

    @Test("A grown-up's profile is not filtered at all")
    func adultUnfiltered() {
        let policy = ContentPolicy(profile: Profile(name: "Magnus", maturity: .adult), ratings: RatingIndex())
        #expect(policy.isUnrestricted)
        #expect(policy.apply(to: Self.library).items.count == Self.library.items.count)
    }

    // MARK: - Approving

    /// Channels and films are permitted by different things, because only one
    /// of them can carry an age limit at all.
    @Test("An approved section opens its channels, but not its films")
    func approvedCategory() {
        let policy = ContentPolicy(
            profile: Self.child(allowing: ["Kids"]), ratings: RatingIndex()
        )
        let visible = policy.apply(to: Self.library).items.map(\.title).sorted()
        #expect(visible == ["NRK Super"])
    }

    /// The bug this rule exists for, in full.
    ///
    /// A provider files Family Guy under "Animation". Kanal itself used to
    /// suggest "Animation" as a children's section, a parent reasonably ticked
    /// it for a nine-year-old, and the section then granted access — so an
    /// adult cartoon appeared in a child's profile on the app's own
    /// recommendation. Two things had to change, and both are asserted here.
    @Test("Ticking an animation section does not hand a child Family Guy")
    func animationSectionIsNotAPass() {
        let profile = Self.child(.nine, allowing: ["Animation"])
        var ratings = RatingIndex()
        // Norway rates Family Guy 15, which is what TMDB actually answers.
        ratings.record(
            ContentRating(rating: .fifteen, source: .board, country: "NO"),
            for: RatingKey.make(title: "Family Guy", year: nil)
        )
        let policy = ContentPolicy(profile: profile, ratings: ratings)

        #expect(!policy.allows(Self.episode("Family Guy", category: "Animation")))
        // And Bluey, which nobody has rated yet, is not smuggled in either —
        // it waits for its own answer rather than riding the section.
        #expect(!policy.allows(Self.episode("Bluey", category: "Animation")))

        // Once rated, it appears on its own merit.
        ratings.record(
            ContentRating(rating: .allAges, source: .board, country: "NO"),
            for: RatingKey.make(title: "Bluey", year: nil)
        )
        #expect(ContentPolicy(profile: profile, ratings: ratings)
            .allows(Self.episode("Bluey", category: "Animation")))
    }

    /// Genre words name a shelf, not an audience.
    @Test("Genre and broadcaster names are never suggested as children's", arguments: [
        "Animation", "Cartoons", "Tegnefilm", "Family", "Familie",
        "Disney", "Disney Plus", "Nickelodeon", "Anime", "Comedy",
    ])
    func genresAreNotAudiences(name: String) {
        #expect(!ContentPolicy.looksLikeChildren(name))
    }

    @Test("Names that really do mean children still are", arguments: [
        "Kids", "NO | Barn", "Barne-TV", "Disney Junior", "Nick Jr",
        "CBeebies", "Children", "Kinder", "Enfants",
    ])
    func audiencesAreRecognised(name: String) {
        #expect(ContentPolicy.looksLikeChildren(name))
    }

    /// What the verification pass works through: the approved sections, from
    /// the whole catalogue rather than from what is already on screen.
    @Test("Unrated titles in approved sections are queued for checking")
    func poolIsTheApprovedSections() {
        let policy = ContentPolicy(
            profile: Self.child(.nine, allowing: ["Animation"]), ratings: RatingIndex()
        )
        let waiting = policy.awaitingRating(in: Self.library).map { $0.seriesName ?? $0.title }
        #expect(Set(waiting) == ["Bluey", "Family Guy"])
    }

    /// Live channels have no age limit — what they are showing changes every
    /// hour — so they are only ever a grown-up's decision.
    @Test("A channel nobody approved stays out, whatever else is allowed")
    func channelsNeedApproval() {
        let policy = ContentPolicy(
            profile: Self.child(allowing: ["Kids"]), ratings: RatingIndex()
        )
        #expect(!policy.allows(Self.channel("V Sport 1", category: "Sport")))
    }

    @Test("Approving the adult section does not open it")
    func adultCategoryCannotBeApproved() {
        let policy = ContentPolicy(
            profile: Self.child(allowing: ["XXX", "Adult"]), ratings: RatingIndex()
        )
        #expect(policy.apply(to: Self.library).items.isEmpty)
    }

    // MARK: - Ratings

    @Test("A board rating above the limit removes a film from an approved section")
    func ratingOverrulesCategory() {
        var ratings = RatingIndex()
        ratings.record(
            ContentRating(rating: .fifteen, source: .board, country: "NO"),
            for: RatingKey.make(title: "Bamse på tur", year: 2020)
        )
        let policy = ContentPolicy(profile: Self.child(allowing: ["Kids"]), ratings: ratings)
        #expect(!policy.allows(Self.movie("Bamse på tur", category: "Kids")))
        // The channel in the same approved section is unaffected: no board
        // rates a channel, so a grown-up's approval is all there ever is.
        #expect(policy.allows(Self.channel("NRK Super", category: "Kids")))
    }

    @Test("A board rating at or below the limit is enough on its own")
    func verifiedRatingOpensWithoutApproval() {
        var ratings = RatingIndex()
        ratings.record(
            ContentRating(rating: .six, source: .board, country: "NO"),
            for: RatingKey.make(title: "Late Night Horror", year: 2020)
        )
        let policy = ContentPolicy(profile: Self.child(), ratings: ratings)
        #expect(policy.allows(Self.movie("Late Night Horror", category: "Horror")))
    }

    /// The asymmetry that keeps this honest: a panel's own marker is a reliable
    /// warning and a worthless endorsement. Panels label the adult section and
    /// label nothing else.
    @Test("A provider's own marker can deny but never permit")
    func providerMarkersAreOneWay() {
        var low = RatingIndex()
        low.record(
            ContentRating(rating: .allAges, source: .provider),
            for: RatingKey.make(title: "Late Night Horror", year: 2020)
        )
        #expect(!ContentPolicy(profile: Self.child(), ratings: low)
            .allows(Self.movie("Late Night Horror", category: "Horror")))

        var high = RatingIndex()
        high.record(
            ContentRating(rating: .adult, source: .provider),
            for: RatingKey.make(title: "Bamse på tur", year: 2020)
        )
        #expect(!ContentPolicy(profile: Self.child(allowing: ["Kids"]), ratings: high)
            .allows(Self.movie("Bamse på tur", category: "Kids")))
    }

    @Test("A grown-up's own decision outranks a board")
    func parentOutranksBoard() {
        var ratings = RatingIndex()
        let key = RatingKey.make(title: "Late Night Horror", year: 2020)
        ratings.record(ContentRating(rating: .fifteen, source: .board, country: "NO"), for: key)
        ratings.record(ContentRating(rating: .six, source: .parent), for: key)
        #expect(ratings[key]?.rating == .six)
        #expect(ratings[key]?.source == .parent)
    }

    @Test("Between two equal sources the stricter one wins")
    func stricterWinsAmongEquals() {
        var ratings = RatingIndex()
        let key = "x"
        ratings.record(ContentRating(rating: .twelve, source: .board), for: key)
        ratings.record(ContentRating(rating: .fifteen, source: .board), for: key)
        ratings.record(ContentRating(rating: .six, source: .board), for: key)
        #expect(ratings[key]?.rating == .fifteen)
    }

    // MARK: - Suggestions

    @Test("Children's sections are suggested, adult and genre ones never are")
    func suggestions() {
        let names = ContentPolicy.suggestedChildCategories(in: Self.library).map(\.name)
        #expect(names.contains("Kids"))
        #expect(!names.contains("Horror"))
        #expect(!names.contains("XXX"))
        #expect(!names.contains("Adult"))
        #expect(!names.contains("Animation"))
    }
}

@Suite("Profiles on disk")
struct ProfileStorageTests {

    /// A profile whose age limit failed to decode must come back as a child's.
    /// Failing the other way would turn a decoding bug into an open library.
    @Test("A profile with no age limit decodes as restricted")
    func missingMaturityFailsSafe() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","name":"Barn"}"#.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.isRestricted)
        #expect(profile.maturity == .allAges)
    }

    @Test("Everyone's history is kept in their own file")
    func watchStateIsPerProfile() {
        let one = Profile(name: "A")
        let two = Profile(name: "B")
        #expect(one.watchStateFileName != two.watchStateFileName)
    }
}

@Suite("Identifying a title before rating it")
struct RatingMatchTests {

    static func candidate(_ id: Int, _ titles: [String], year: Int?) -> TMDBTitle {
        TMDBTitle(
            id: id, isSeries: false,
            localizedTitle: titles[0], originalTitle: titles[0],
            alternateTitles: Array(titles.dropFirst()),
            overview: nil, year: year, posterPath: nil, backdropPath: nil, voteAverage: nil
        )
    }

    @Test("One title with the same name and year is a match")
    func single() {
        let found = RatingService.confidentMatch(
            for: "Løvenes konge", year: 1994,
            among: [Self.candidate(8587, ["Løvenes konge", "The Lion King"], year: 1994)]
        )
        #expect(found?.id == 8587)
    }

    /// The case measured against a real playlist: to a Norwegian viewer "Frost"
    /// is Disney's *Frozen*, and TMDB's search answers with a different 2013
    /// film of the same name. A rating taken from the wrong one pulled a
    /// children's film out of a child's profile.
    @Test("Two films of the same name and year is not an answer")
    func ambiguous() {
        let found = RatingService.confidentMatch(
            for: "Frost", year: 2013,
            among: [
                Self.candidate(109445, ["Frost", "Frozen"], year: 2013),
                Self.candidate(222333, ["Frost"], year: 2013),
            ]
        )
        #expect(found == nil)
    }

    @Test("A year that disagrees rules a candidate out")
    func wrongYear() {
        let found = RatingService.confidentMatch(
            for: "Frost", year: 2013,
            among: [Self.candidate(999, ["Frost"], year: 1950)]
        )
        #expect(found == nil)
    }

    /// Good enough to pick a poster, nowhere near good enough to decide what a
    /// child may watch.
    @Test("A name that merely starts the same is not a match")
    func prefixIsNotEnough() {
        let found = RatingService.confidentMatch(
            for: "Frost", year: nil,
            among: [Self.candidate(1, ["Frost Nixon"], year: 2008)]
        )
        #expect(found == nil)
    }
}

@Suite("Overruling a rating")
struct ParentOverrideTests {

    static let film = ContentPolicyTests.movie("Frost", category: "Kids Movies", year: 2013)
    static let library = Library(items: [film])

    static var ratings: RatingIndex {
        var index = RatingIndex()
        index.record(
            ContentRating(rating: .fifteen, source: .board, country: "GB"),
            for: RatingKey.make(title: "Frost", year: 2013)
        )
        return index
    }

    /// Identifying a film from a playlist is guesswork often enough that a
    /// wrong rating has to be something a parent can see and undo.
    @Test("A rating held back inside an approved section is listed for review")
    func listed() {
        let profile = Profile(name: "Emil", maturity: .six, allowedCategories: ["Kids Movies"])
        let withheld = ContentPolicy(profile: profile, ratings: Self.ratings)
            .withheldByRating(in: Self.library)
        #expect(withheld.count == 1)
        #expect(withheld.first?.rating == .fifteen)
    }

    @Test("Approving one title by name beats the rating on it")
    func namedApprovalWins() {
        let profile = Profile(
            name: "Emil", maturity: .six,
            allowedCategories: ["Kids Movies"], allowedTitleKeys: [RatingKey.of(Self.film)]
        )
        #expect(ContentPolicy(profile: profile, ratings: Self.ratings).allows(Self.film))
    }

    /// The order that keeps the override from becoming a hole: a name is a
    /// grown-up looking at that title, a section is not.
    @Test("Approving the section does not beat the rating")
    func sectionApprovalDoesNot() {
        let profile = Profile(name: "Emil", maturity: .six, allowedCategories: ["Kids Movies"])
        #expect(!ContentPolicy(profile: profile, ratings: Self.ratings).allows(Self.film))
    }

    @Test("Adult material is not overridable by name")
    func adultStaysOut() {
        let porn = ContentPolicyTests.movie("Late Night", category: "XXX", year: 2020)
        let profile = Profile(name: "Emil", maturity: .six, allowedTitleKeys: [RatingKey.of(porn)])
        #expect(!ContentPolicy(profile: profile, ratings: RatingIndex()).allows(porn))
    }
}


@Suite("Choosing between boards")
struct RatingVerdictTests {

    typealias Board = (code: String, country: String)

    /// Norway's own answer settles it, wherever it sits in the list.
    @Test("The viewer's own board wins outright")
    func homeBoardWins() {
        let boards: [Board] = [("15", "NO"), ("K7", "FI"), ("16", "DE")]
        let verdict = RatingService.verdict(from: boards, home: "NO")
        #expect(verdict?.rating == .fifteen)
        #expect(verdict?.country == "NO")
    }

    /// Bob's Burgers: Finland K7, Britain 12, Germany 16. Taking whichever
    /// answered first made the verdict depend on list order, and that order
    /// put the most lenient board in front.
    @Test("With no home answer, the strictest board wins")
    func strictestWinsAbroad() {
        let boards: [Board] = [("K7", "FI"), ("12", "GB"), ("16", "DE")]
        let verdict = RatingService.verdict(from: boards, home: "NO")
        #expect(verdict?.rating == .fifteen)
    }

    /// One board writing something we cannot read must not end the lookup —
    /// this is what left Bob's Burgers unrated entirely.
    @Test("An unreadable code is skipped, not fatal")
    func unreadableCodeIsSkipped() {
        let boards: [Board] = [("Ukjent", "NO"), ("12", "GB")]
        #expect(RatingService.verdict(from: boards, home: "NO")?.rating == .twelve)
    }

    @Test("Nothing readable at all is no answer")
    func nothingReadable() {
        #expect(RatingService.verdict(from: [("???", "NO")], home: "NO") == nil)
        #expect(RatingService.verdict(from: [], home: "NO") == nil)
    }

    /// A 16 is the foreign equivalent of Norway's 15, not of 18. Rounding it
    /// up made ordinary teenage films adults-only.
    @Test("A foreign 16 lands on fifteen", arguments: ["DE", "FI", "NL", "FR", "ES"])
    func sixteenIsFifteen(country: String) {
        let code = country == "FI" ? "K16" : "16"
        #expect(RatingParser.rating(code: code, country: country) == .fifteen)
    }

    @Test("Board notation that is not a bare number still reads", arguments: [
        ("K7", "FI", MaturityRating.nine),
        ("Från 15 år", "SE", MaturityRating.fifteen),
        ("Btl", "SE", MaturityRating.allAges),
        ("B-15", "MX", MaturityRating.fifteen),
        // India is not a board we carry, so its notation is read for the age
        // it states and rounded up. The 16-means-15 equivalence applies only
        // where we actually know the scale — guessing at an unfamiliar one is
        // how a limit gets invented.
        ("U/A 16+", "IN", MaturityRating.adult),
    ])
    func notationIsRead(code: String, country: String, expected: MaturityRating) {
        #expect(RatingParser.rating(code: code, country: country) == expected)
    }
}

@Suite("Identifying which title this is")
struct ConfidentMatchTests {

    static func title(_ id: Int, _ name: String, year: Int?, popularity: Double) -> TMDBTitle {
        TMDBTitle(
            id: id, isSeries: true, localizedTitle: name, originalTitle: name,
            alternateTitles: [], year: year, popularity: popularity
        )
    }

    /// TMDB lists two series called "Bluey": the one every four-year-old
    /// watches, and an Australian police drama from 1976. Refusing to choose
    /// hid the children's programme — the failure this feature exists to
    /// prevent, pointing the other way.
    @Test("A landslide favourite wins when no year was stated")
    func famousTitleWins() {
        let match = RatingService.confidentMatch(for: "Bluey", year: nil, among: [
            Self.title(1, "Bluey", year: 1976, popularity: 0.6),
            Self.title(2, "Bluey", year: 2018, popularity: 480),
        ])
        #expect(match?.id == 2)
    }

    /// The Frost case: two 2013 films of the same name, neither obviously the
    /// one meant. A wrong answer here invents an age limit, so there is none.
    @Test("Two comparable titles remain unanswered")
    func ambiguityStaysUnanswered() {
        #expect(RatingService.confidentMatch(for: "Frost", year: nil, among: [
            Self.title(1, "Frost", year: 2013, popularity: 12),
            Self.title(2, "Frost", year: 2013, popularity: 9),
        ]) == nil)
    }

    @Test("A stated year that both candidates fit is still no answer")
    func statedYearDoesNotBreakTies() {
        #expect(RatingService.confidentMatch(for: "Frost", year: 2013, among: [
            Self.title(1, "Frost", year: 2013, popularity: 900),
            Self.title(2, "Frost", year: 2013, popularity: 3),
        ]) == nil)
    }

    @Test("A name that merely starts the same is not a match")
    func prefixIsNotAMatch() {
        #expect(RatingService.confidentMatch(for: "Bluey", year: nil, among: [
            Self.title(1, "Bluey Minisodes", year: 2024, popularity: 40),
        ]) == nil)
    }
}
