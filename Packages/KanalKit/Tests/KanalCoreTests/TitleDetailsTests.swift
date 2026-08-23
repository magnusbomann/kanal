import Foundation
import Testing
@testable import KanalCore

@Suite("Reading a title's record")
struct TitleDetailsParsingTests {

    /// Shaped like a real `/movie/{id}?append_to_response=credits` response.
    let film: [String: Any] = [
        "title": "Blade Runner 2049",
        "overview": "K oppdager en hemmelighet.",
        "release_date": "2017-10-04",
        "runtime": 164,
        "vote_average": 7.6,
        "vote_count": 12_000,
        "poster_path": "/p.jpg",
        "backdrop_path": "/b.jpg",
        "genres": [["id": 878, "name": "Sci-Fi"], ["id": 18, "name": "Drama"]],
        "credits": [
            "cast": [
                ["id": 1, "name": "Ryan Gosling", "character": "K", "profile_path": "/rg.jpg"],
                ["id": 2, "name": "Harrison Ford", "character": "Deckard"],
            ],
        ],
    ]

    @Test("Reads a film")
    func readsFilm() throws {
        let details = try #require(TMDBClient.details(from: film, id: 335984, isSeries: false))
        #expect(details.title == "Blade Runner 2049")
        #expect(details.year == 2017)
        #expect(details.runtimeMinutes == 164)
        #expect(details.rating == 7.6)
        #expect(details.genres == ["Sci-Fi", "Drama"])
        #expect(details.cast.count == 2)
        #expect(details.cast.first?.role == "K")
        #expect(details.posterURL?.absoluteString.hasSuffix("/p.jpg") == true)
    }

    /// A score from a handful of votes is noise dressed as information.
    @Test("Hides a rating too few people voted on")
    func hidesThinRating() throws {
        var thin = film
        thin["vote_count"] = 3
        #expect(TMDBClient.details(from: thin, id: 1, isSeries: false)?.rating == nil)
    }

    @Test("Hides a rating of zero")
    func hidesZeroRating() throws {
        var none = film
        none["vote_average"] = 0.0
        #expect(TMDBClient.details(from: none, id: 1, isSeries: false)?.rating == nil)
    }

    /// Series credits come from aggregate_credits, and a recurring lead is
    /// listed under `roles` rather than `character`.
    @Test("Reads a series, including its aggregated cast")
    func readsSeries() throws {
        let show: [String: Any] = [
            "name": "Dandadan",
            "first_air_date": "2024-10-04",
            "number_of_seasons": 1,
            "number_of_episodes": 24,
            "episode_run_time": [24],
            "vote_average": 8.5,
            "vote_count": 927,
            "genres": [["name": "Animation"]],
            "aggregate_credits": [
                "cast": [
                    ["id": 9, "name": "Shion Wakayama", "roles": [["character": "Momo Ayase"]]],
                ],
            ],
        ]
        let details = try #require(TMDBClient.details(from: show, id: 240411, isSeries: true))
        #expect(details.title == "Dandadan")
        #expect(details.seasonCount == 1)
        #expect(details.episodeCount == 24)
        #expect(details.runtimeMinutes == 24)
        #expect(details.cast.first?.role == "Momo Ayase")
    }

    @Test("An empty plot is treated as absent, not as an empty paragraph")
    func emptyOverview() throws {
        var blank = film
        blank["overview"] = ""
        #expect(TMDBClient.details(from: blank, id: 1, isSeries: false)?.overview == nil)
    }

    @Test("A record with no name is refused")
    func refusesNameless() {
        #expect(TMDBClient.details(from: ["overview": "x"], id: 1, isSeries: false) == nil)
    }

    @Test("Cast without a photo still appears")
    func castWithoutPhoto() throws {
        let details = try #require(TMDBClient.details(from: film, id: 1, isSeries: false))
        let ford = try #require(details.cast.last)
        #expect(ford.name == "Harrison Ford")
        #expect(ford.profileURL == nil)
    }

    @Test("Knows whether there is enough to be worth showing")
    func substance() {
        let bare = TitleDetails(id: 1, isSeries: false, title: "X")
        #expect(bare.isSubstantial == false)
        let withPlot = TitleDetails(id: 1, isSeries: false, title: "X", overview: "Something")
        #expect(withPlot.isSubstantial)
    }

    @Test("Only TMDB identifiers yield a numeric id")
    func identifierParsing() {
        #expect(MetadataService.tmdbID(from: "tmdb:8587") == 8587)
        #expect(MetadataService.tmdbID(from: "wikidata:Q36479") == nil)
        #expect(MetadataService.tmdbID(from: "bundled:nb:x") == nil)
    }
}
