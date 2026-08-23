import Foundation

/// Pulls a human title out of the noise providers put in `tvg-name`.
///
/// Playlist titles look like `NO| Viaplay Sport 1 FHD` or
/// `EN - Breaking Bad S01E04 [1080p]`. Everything here is about getting to
/// "Viaplay Sport 1" and "Breaking Bad" without asking the user to fix it.
public enum TitleCleaner {

    public struct Result: Sendable, Equatable {
        public var title: String
        public var seriesName: String?
        /// The episode's own title, when the provider wrote one after the code.
        public var episodeTitle: String?
        public var season: Int?
        public var episode: Int?
        public var year: Int?
        public var qualityTag: String?
        public var countryCode: String?
    }

    /// Two-to-three letter prefix codes seen at the head of playlist titles.
    private static let qualityTokens: Set<String> = [
        "fhd", "hd", "sd", "uhd", "4k", "8k", "hq", "lq",
        "1080p", "1080i", "720p", "576p", "480p", "2160p",
        "hevc", "h264", "h265", "x264", "x265", "raw", "vip", "multi",
    ]

    private static let separators = CharacterSet(charactersIn: " |-–—:•·_.")

    /// Compiled once.
    ///
    /// These ran per entry, and a real catalogue is four hundred thousand of
    /// them — around two million `NSRegularExpression` constructions per load,
    /// which was most of the time spent parsing.
    private static let countryPattern = try! NSRegularExpression(
        pattern: #"^\s*[\[\(\|]?\s*([A-Za-z]{2,3})\s*[\]\)\|:\-–—]+\s*"#
    )
    private static let episodePatterns: [NSRegularExpression] = [
        #"[\s\-–—_\[\(]*[Ss](\d{1,2})\s*[EeXx]\s*(\d{1,3})[\s\]\)]*"#,
        #"[\s\-–—_\[\(]*(\d{1,2})\s*[xX]\s*(\d{1,3})\b[\s\]\)]*"#,
        #"[\s\-–—_]*[Ss]eason\s*(\d{1,2})\s*[\-–—_]?\s*[Ee]pisode\s*(\d{1,3})"#,
    ].map { try! NSRegularExpression(pattern: $0) }
    private static let yearPattern = try! NSRegularExpression(
        pattern: #"[\s\[\(]+((?:19|20)\d{2})[\s\]\)]*$"#
    )

    public static func clean(_ raw: String) -> Result {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var country: String?
        var quality: String?

        // 1. Leading country/language marker: "NO |", "[NO]", "(EN)", "NO:"
        if let (code, rest) = stripLeadingCountry(working) {
            country = code
            working = rest
        }

        // 2. Episode markers, before quality stripping — S01E04 can sit next to 1080p.
        let episodeInfo = extractEpisode(from: working)
        if let info = episodeInfo {
            working = info.remainder
        }

        // 3. Year, either bare (2019) or bracketed.
        let yearInfo = extractYear(from: working)
        if let info = yearInfo {
            working = info.remainder
        }

        // 4. Trailing quality tokens, repeatedly — "Movie 1080p HEVC" drops both.
        while let (token, rest) = stripTrailingQuality(working) {
            quality = quality ?? token.uppercased()
            working = rest
        }

        working = normalizeWhitespace(working)

        // The show is what preceded the marker. Anything after it names this
        // one episode, and must never end up in the show's name.
        let seriesName = episodeInfo.map { info in
            let name = stripQualityWords(info.before)
            return name.isEmpty ? working : name
        }
        let episodeTitle = episodeInfo
            .map { stripQualityWords($0.after) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let title: String
        if let episodeInfo {
            let show = seriesName ?? working
            let code = String(format: "S%02dE%02d", episodeInfo.season, episodeInfo.episode)
            title = show.isEmpty ? code : "\(show) \(code)"
        } else {
            title = working
        }

        return Result(
            title: title.isEmpty ? raw : title,
            seriesName: seriesName?.isEmpty == true ? nil : seriesName,
            episodeTitle: episodeTitle,
            season: episodeInfo?.season,
            episode: episodeInfo?.episode,
            year: yearInfo?.year,
            qualityTag: quality,
            countryCode: country
        )
    }

    // MARK: - Pieces

    private static func stripLeadingCountry(_ input: String) -> (String, String)? {
        // Matches "NO |", "|NO|", "[NO]", "(NOR)", "EN:" at the very start.
        guard let match = countryPattern.firstMatch(
                in: input, range: NSRange(input.startIndex..., in: input)
              ),
              let codeRange = Range(match.range(at: 1), in: input),
              let fullRange = Range(match.range, in: input)
        else { return nil }

        let code = String(input[codeRange]).uppercased()
        // "HD | Something" is a quality tag, not a country.
        guard !qualityTokens.contains(code.lowercased()) else { return nil }

        var rest = String(input[fullRange.upperBound...])
        rest = rest.trimmingCharacters(in: separators)
        guard !rest.isEmpty else { return nil }
        return (code, rest)
    }

    /// What surrounded an episode marker.
    ///
    /// The two halves mean different things and must not be joined. What comes
    /// before "S01E01" is the show; what comes after is that episode's own
    /// title. Treating them as one string names every episode differently and
    /// splits a series into as many one-episode shows.
    struct EpisodeInfo {
        var season: Int
        var episode: Int
        /// The show's name.
        var before: String
        /// This episode's title, when the provider gave one.
        var after: String

        var remainder: String {
            TitleCleaner.normalizeWhitespace(before + " " + after)
        }
    }

    static func extractEpisode(from input: String) -> EpisodeInfo? {
        // S01E04 / s1 e4, then 1x04, then "Season 1 Episode 4".
        for regex in episodePatterns {
            guard let match = regex.firstMatch(
                    in: input, range: NSRange(input.startIndex..., in: input)
                  ),
                  let sRange = Range(match.range(at: 1), in: input),
                  let eRange = Range(match.range(at: 2), in: input),
                  let fullRange = Range(match.range, in: input),
                  let season = Int(input[sRange]),
                  let episode = Int(input[eRange])
            else { continue }

            let before = normalizeWhitespace(String(input[input.startIndex..<fullRange.lowerBound]))
                .trimmingCharacters(in: separators)
            let after = normalizeWhitespace(String(input[fullRange.upperBound...]))
                .trimmingCharacters(in: separators)
            return EpisodeInfo(season: season, episode: episode, before: before, after: after)
        }
        return nil
    }

    struct YearInfo { var year: Int; var remainder: String }

    static func extractYear(from input: String) -> YearInfo? {
        guard let match = yearPattern.firstMatch(
                in: input, range: NSRange(input.startIndex..., in: input)
              ),
              let yearRange = Range(match.range(at: 1), in: input),
              let fullRange = Range(match.range, in: input),
              let year = Int(input[yearRange])
        else { return nil }

        let remainder = String(input[input.startIndex..<fullRange.lowerBound])
            .trimmingCharacters(in: separators)
        return YearInfo(year: year, remainder: remainder)
    }

    private static func stripTrailingQuality(_ input: String) -> (String, String)? {
        let trimmed = input.trimmingCharacters(in: separators)
        guard let lastSpace = trimmed.lastIndex(where: { $0 == " " || $0 == "|" || $0 == "-" }) else {
            return nil
        }
        let tail = String(trimmed[trimmed.index(after: lastSpace)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
        guard qualityTokens.contains(tail.lowercased()) else { return nil }

        let head = String(trimmed[trimmed.startIndex..<lastSpace])
            .trimmingCharacters(in: separators)
        guard !head.isEmpty else { return nil }
        return (tail, head)
    }

    /// Removes quality and language noise from a fragment of a title.
    static func stripQualityWords(_ input: String) -> String {
        let words = input.split(separator: " ").filter { word in
            !qualityTokens.contains(
                word.trimmingCharacters(in: CharacterSet(charactersIn: "[]()")).lowercased()
            )
        }
        return words.joined(separator: " ").trimmingCharacters(in: separators)
    }

    static func normalizeWhitespace(_ input: String) -> String {
        input.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
