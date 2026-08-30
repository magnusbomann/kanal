import Foundation

/// One film, and every listing of it.
///
/// The same folding channels get, for the same reason. A real provider files
/// one film under several folders — "Interstellar" appeared seven times, once
/// each under Sci-fi, Drama, Eventyr and 4k — and a shelf that shows the same
/// poster seven times in a row is a shelf nobody can read.
///
/// The listings are not always the same stream, so none of them is thrown
/// away: the duplicates fold into one card, and every distinct stream stays
/// behind it as an alternative to fall through to.
public struct MovieGroup: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var year: Int?
    /// Distinct streams, most promising first. Never empty.
    public var variants: [MediaItem]
    /// Every category any listing appeared under.
    public var categories: [String]

    public init(id: String, title: String, year: Int?, variants: [MediaItem], categories: [String]) {
        self.id = id
        self.title = title
        self.year = year
        self.variants = variants
        self.categories = categories
    }

    public var primary: MediaItem { variants[0] }
    public var hasAlternatives: Bool { variants.count > 1 }

    /// Every variant, starting from the one that last played.
    public func ordered(from rememberedID: String?) -> [MediaItem] {
        guard let rememberedID,
              let index = variants.firstIndex(where: { $0.id == rememberedID })
        else { return variants }
        return Array(variants[index...]) + Array(variants[..<index])
    }

    /// The single entry the rest of the app shows and plays.
    ///
    /// A real listing, id and all, so favourites, resume positions and the
    /// detail screen keep working — widened only where the group knows more
    /// than the one listing did.
    public var representative: MediaItem {
        var item = primary
        item.title = title
        item.year = year ?? item.year
        item.logoURL = variants.compactMap(\.logoURL).first
        // A genre if any listing gave one. Sorting alphabetically otherwise
        // puts "4k" ahead of "Science Fiction", and the line under a poster
        // should say what the film is, not what resolution it came in.
        item.category = categories.first { !TitleKey.deliveryWords.contains($0.lowercased()) }
            ?? categories.first
            ?? item.category
        return item
    }
}

public extension Library {

    /// Folds a provider's film listings into one entry per film.
    static func makeMovieGroups(_ movies: [MediaItem]) -> [MovieGroup] {
        var buckets: [String: [MediaItem]] = [:]
        buckets.reserveCapacity(movies.count / 2)
        for movie in movies {
            buckets[TitleKey.groupKey(for: movie), default: []].append(movie)
        }

        var groups: [MovieGroup] = []
        groups.reserveCapacity(buckets.count)
        for (key, members) in buckets {
            for (year, listings) in split(members) {
                let identifier = year.map { "\(key)|\($0)" } ?? key
                groups.append(
                    MovieGroup(
                        id: identifier,
                        // The shortest name of the bunch: "Interstellar" over
                        // "Interstellar 4K Multi".
                        title: listings.map(\.title).min { $0.count < $1.count } ?? key,
                        year: year,
                        variants: distinctStreams(listings),
                        categories: Array(Set(listings.compactMap(\.category))).sorted()
                    )
                )
            }
        }
        return groups
    }

    /// Same name, different films.
    ///
    /// A year is the only evidence a provider gives that two listings are
    /// different films rather than duplicates, so listings that name a year
    /// are grouped by it — The Lion King of 1994 must never fold into the one
    /// from 2019. Listings with no year join the year's group when there is
    /// only one to join; when the name covers two films they stay apart,
    /// because guessing which one they are is how you show somebody the wrong
    /// film.
    private static func split(_ members: [MediaItem]) -> [(Int?, [MediaItem])] {
        let years = Set(members.compactMap(\.year))
        guard years.count > 1 else { return [(years.first, members)] }

        var byYear: [Int: [MediaItem]] = [:]
        var undated: [MediaItem] = []
        for member in members {
            if let year = member.year { byYear[year, default: []].append(member) } else { undated.append(member) }
        }

        var result: [(Int?, [MediaItem])] = byYear
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        if !undated.isEmpty { result.append((nil, undated)) }
        return result
    }

    /// Listings sharing a URL are one stream filed twice; only genuinely
    /// different streams are alternatives.
    private static func distinctStreams(_ members: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return members
            .filter { seen.insert($0.streamURL.absoluteString).inserted }
            .sorted { StreamQuality.rank($0) > StreamQuality.rank($1) }
    }
}

/// The name two listings of the same thing agree on.
enum TitleKey {
    /// Words that describe *how* something is delivered rather than *what* it
    /// is.
    static let deliveryWords: Set<String> = [
        "fhd", "hd", "sd", "uhd", "4k", "8k", "1080p", "1080i", "720p", "576p", "480p",
        "2160p", "hevc", "h264", "h265", "x264", "x265", "raw", "vip", "multi",
        "backup", "alt", "b", "source", "src",
        "25fps", "30fps", "50fps", "60fps", "hdr", "sdr", "hq", "lq",
    ]

    static func groupKey(for item: MediaItem) -> String {
        let words = SearchNormalizer.normalize(item.title)
            .split(separator: " ")
            .map(String.init)
            .filter { !deliveryWords.contains($0) }
        let key = words.joined(separator: " ")
        return key.isEmpty ? SearchNormalizer.normalize(item.title) : key
    }
}
