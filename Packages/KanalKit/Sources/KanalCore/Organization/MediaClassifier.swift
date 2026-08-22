import Foundation

/// Decides whether an entry is live TV, a movie, or a series episode.
///
/// Providers never label this consistently, so we vote across three signals:
/// the stream URL, the provider's group name, and the title itself.
public enum MediaClassifier {

    private static let vodFileExtensions: Set<String> = [
        "mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "mpg", "mpeg", "webm",
    ]

    /// Extensions that only ever appear on a continuous stream.
    private static let liveExtensions: Set<String> = ["m3u8", "ts", "mpd"]

    /// The same names, used as a trailing path segment instead of a suffix.
    ///
    /// Real panels write live streams as `/play/<token>/m3u8` — the format is
    /// a path component, so `pathExtension` is empty and an extension check
    /// alone reads every channel as something else entirely.
    private static let liveSegments: Set<String> = ["m3u8", "ts", "hls", "mpd", "index"]

    private static let movieGroupHints = [
        "vod", "movie", "movies", "film", "filme", "filmer", "cinema", "kino", "peliculas",
    ]

    private static let seriesGroupHints = [
        "series", "serie", "serier", "tv show", "tvshow", "shows", "staffel", "season",
    ]

    public static func classify(
        title: String,
        streamURL: URL,
        group: String?,
        hasEpisodeMarker: Bool
    ) -> MediaKind {
        let path = streamURL.path.lowercased()

        // Xtream Codes uses literal /movie/ and /series/ path segments.
        if path.contains("/series/") { return .series }
        if path.contains("/movie/") || path.contains("/vod/") {
            return hasEpisodeMarker ? .series : .movie
        }

        let ext = streamURL.pathExtension.lowercased()
        let lastSegment = path.split(separator: "/").last.map(String.init) ?? ""

        // A live-looking URL settles it before any group name gets a say.
        // Free directories use genre names like "Series" and "Movies" for live
        // channels, and trusting those would file MTV under television drama.
        let looksLive = liveExtensions.contains(ext)
            || liveSegments.contains(lastSegment)
            || path.contains("/live/")
        if !hasEpisodeMarker, looksLive { return .liveTV }

        let group = (group ?? "").lowercased()
        let isSeriesGroup = seriesGroupHints.contains { group.contains($0) }
        let isMovieGroup = movieGroupHints.contains { group.contains($0) }

        // A file extension on the path means it is a stored file, not a live feed.
        if vodFileExtensions.contains(ext) {
            return hasEpisodeMarker || isSeriesGroup ? .series : .movie
        }

        if hasEpisodeMarker && (isSeriesGroup || isMovieGroup) { return .series }
        if isSeriesGroup { return .series }
        if isMovieGroup { return .movie }

        // Episode markers alone are enough — no live channel is called S01E04.
        if hasEpisodeMarker { return .series }

        // An opaque token at the end of the path is a stored file behind a
        // one-off link. Live streams are addressed by something a human could
        // have written — a channel number, a name, a format. Without this,
        // a catalogue of a few hundred thousand films reads as live TV,
        // because nothing else in the url says otherwise.
        if isOpaqueToken(lastSegment) { return .movie }

        return .liveTV
    }

    /// Long, random-looking, and mixing letters with digits: a generated
    /// identifier rather than anything a person chose.
    static func isOpaqueToken(_ segment: String) -> Bool {
        guard segment.count >= 16 else { return false }
        let hasLetter = segment.contains(where: \.isLetter)
        let hasDigit = segment.contains(where: \.isNumber)
        return hasLetter && hasDigit
    }
}

/// Turns provider group names into categories a person would recognize.
///
/// `"NO| VIAPLAY SPORT ᴴᴰ"` and `"|NO| Viaplay Sport"` should land in the
/// same bucket, so we strip markers, fold case, and title-case the result.
public enum CategoryNormalizer {

    /// Compiled once, for the same reason the title patterns are.
    private static let bracketedMarker = try! NSRegularExpression(
        pattern: #"[\[\(\|]\s*[A-Za-z]{2,3}\s*[\]\)\|]"#
    )
    private static let leadingMarker = try! NSRegularExpression(
        pattern: #"^\s*[A-Za-z]{2,3}\s*[:\-–—\|]\s*"#
    )

    private static let noiseTokens: Set<String> = [
        "vod", "live", "channels", "channel", "tv", "hd", "fhd", "sd", "uhd", "4k",
    ]

    public static func normalize(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        // Drop bracketed/piped country markers anywhere in the string.
        value = bracketedMarker.stringByReplacingMatches(
            in: value, range: NSRange(value.startIndex..., in: value), withTemplate: " "
        )
        // Leading "NO -" / "NO:" style markers.
        value = leadingMarker.stringByReplacingMatches(
            in: value, range: NSRange(value.startIndex..., in: value), withTemplate: ""
        )
        value = value.replacingOccurrences(of: "_", with: " ")
        value = TitleCleaner.normalizeWhitespace(value)

        // Directories pack several genres into one field ("Animation;comedy").
        // Render them as a phrase rather than leaving the delimiter on screen.
        let segments = value
            .split(whereSeparator: { $0 == ";" || $0 == "/" || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if segments.count > 1 {
            let named = segments.prefix(2).map { titleCased($0) }
            return named.joined(separator: " & ")
        }
        value = segments.first ?? value

        let words = value.split(separator: " ").filter { word in
            !noiseTokens.contains(word.lowercased()) || value.split(separator: " ").count == 1
        }
        guard !words.isEmpty else { return nil }

        return words.map { titleCasedWord(String($0)) }.joined(separator: " ")
    }

    static func titleCased(_ value: String) -> String {
        value.split(separator: " ").map { titleCasedWord(String($0)) }.joined(separator: " ")
    }

    /// Keeps short all-caps words as acronyms; sentence-cases everything else.
    private static func titleCasedWord(_ word: String) -> String {
        if word.count <= 4, word == word.uppercased(),
           word.rangeOfCharacter(from: .decimalDigits) == nil {
            return word
        }
        let lower = word.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
