import Foundation

/// Fetching the full record for one title, and for the people in it.
///
/// Separate from the search and discovery calls because it is asked for
/// differently: one title at a time, when someone has actually shown interest,
/// rather than in bulk.
public extension TMDBClient {

    /// Everything the detail screen shows, in one request.
    ///
    /// Series credits come from `aggregate_credits`, which spans the whole run
    /// rather than a single episode — a recurring lead would otherwise be
    /// missing from a show they are in every week.
    func fullDetails(id: Int, isSeries: Bool) async throws -> TitleDetails? {
        let path = isSeries ? "tv/\(id)" : "movie/\(id)"
        let extras = isSeries ? "aggregate_credits" : "credits"

        guard let root = try await json(path: path, query: [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: extras),
        ]) else { return nil }

        var details = Self.details(from: root, id: id, isSeries: isSeries)

        // TMDB has no plot in every language for every title. An empty
        // description is worse than an English one.
        if details?.overview?.isEmpty != false {
            let fallback = try? await json(path: path, query: [
                URLQueryItem(name: "language", value: "en-US"),
            ])
            let english = (fallback?["overview"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            details?.overview = english
        }
        return details
    }

    /// A person, with the work they are best known for.
    func person(id: Int) async throws -> PersonProfile? {
        guard let root = try await json(path: "person/\(id)", query: [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "combined_credits"),
        ]) else { return nil }

        var biography = (root["biography"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if biography == nil {
            let fallback = try? await json(path: "person/\(id)", query: [
                URLQueryItem(name: "language", value: "en-US"),
            ])
            biography = (fallback?["biography"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        let credits = (root["combined_credits"] as? [String: Any])?["cast"] as? [[String: Any]] ?? []
        let known = credits
            .compactMap { row -> KnownRole? in
                guard let id = row["id"] as? Int else { return nil }
                let isSeries = (row["media_type"] as? String) == "tv"
                let title = (row[isSeries ? "name" : "title"] as? String) ?? ""
                guard !title.isEmpty else { return nil }
                return KnownRole(
                    id: id, title: title, isSeries: isSeries,
                    posterPath: row["poster_path"] as? String,
                    popularity: (row["popularity"] as? Double) ?? 0
                )
            }
            .sorted { $0.popularity > $1.popularity }

        // Deduplicated: a person credited twice on one title should appear once.
        var seen = Set<Int>()
        let unique = known.filter { seen.insert($0.id).inserted }

        return PersonProfile(
            id: id,
            name: (root["name"] as? String) ?? "",
            biography: biography,
            profilePath: root["profile_path"] as? String,
            knownFor: Array(unique.prefix(12))
        )
    }

    // MARK: - Parsing

    static func details(from root: [String: Any], id: Int, isSeries: Bool) -> TitleDetails? {
        let title = (root[isSeries ? "name" : "title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }

        let dateKey = isSeries ? "first_air_date" : "release_date"
        let voteCount = (root["vote_count"] as? Int) ?? 0
        let average = root["vote_average"] as? Double

        // A score from a handful of votes is noise dressed as information.
        let rating = (voteCount >= 20 && (average ?? 0) > 0) ? average : nil

        let runtime = (root["runtime"] as? Int)
            ?? (root["episode_run_time"] as? [Int])?.first

        return TitleDetails(
            id: id,
            isSeries: isSeries,
            title: title,
            overview: (root["overview"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            year: (root[dateKey] as? String).flatMap { Int($0.prefix(4)) },
            genres: (root["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? [],
            rating: rating,
            runtimeMinutes: runtime.flatMap { $0 > 0 ? $0 : nil },
            seasonCount: root["number_of_seasons"] as? Int,
            episodeCount: root["number_of_episodes"] as? Int,
            posterPath: root["poster_path"] as? String,
            backdropPath: root["backdrop_path"] as? String,
            cast: castMembers(from: root, isSeries: isSeries)
        )
    }

    static func castMembers(from root: [String: Any], isSeries: Bool) -> [CastMember] {
        let container = (root["aggregate_credits"] as? [String: Any])
            ?? (root["credits"] as? [String: Any])
        guard let rows = container?["cast"] as? [[String: Any]] else { return [] }

        return rows.prefix(20).compactMap { row in
            guard let id = row["id"] as? Int,
                  let name = row["name"] as? String, !name.isEmpty
            else { return nil }

            // Films give one character; series give a list of roles.
            let role = (row["character"] as? String)
                ?? ((row["roles"] as? [[String: Any]])?.first?["character"] as? String)

            return CastMember(
                id: id, name: name,
                role: role.flatMap { $0.isEmpty ? nil : $0 },
                profilePath: row["profile_path"] as? String
            )
        }
    }
}
