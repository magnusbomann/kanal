import Foundation

/// Everything Kanal knows about age limits, and how it learns more.
///
/// Two sources, and the difference between them is the whole point:
///
/// - **Provider markers** are free, instant and offline. A panel that writes
///   `18+` into a title is telling the truth about that entry, so the marker is
///   trusted to *withhold*. It is never trusted to permit, because the absence
///   of a marker means only that nobody typed one.
/// - **National boards**, via TMDB, are the real thing — the number on the
///   cinema poster. These are what let a child's profile grow past what a
///   grown-up ticked by hand, and they are the only source `ContentPolicy`
///   treats as verification.
///
/// Both are cached permanently. A film's age limit does not change, and paying
/// two network requests per title once is the difference between this being
/// usable and being a reason not to open the app.
public actor RatingService {

    private var index = RatingIndex()
    private let storage: KanalStorage
    private let client: TMDBClient?
    /// Boards to ask, in order. The viewer's own country first — a Norwegian
    /// parent knows what 12 means here and does not know what PG-13 means.
    private let countries: [String]
    /// Titles already looked up and found unrated, so a catalogue full of
    /// obscure entries is not re-fetched on every launch.
    private var knownUnrated: Set<String> = []
    private var isVerifying = false

    /// How many titles one verification pass will fetch.
    ///
    /// Bounded so a pass stays interruptible and one rate-limit reply costs
    /// little. The caller runs passes back to back until the pool is empty, so
    /// this is a step size rather than a ceiling on the work.
    private static let batchLimit = 250

    public init(tmdbAPIKey: String?, storage: KanalStorage = .shared) {
        self.storage = storage
        self.client = tmdbAPIKey.flatMap { $0.isEmpty ? nil : TMDBClient(apiKey: $0) }
        var wanted = [Locale.current.region?.identifier].compactMap { $0 }
        wanted += PreferredLanguages.codes().compactMap { Locale(identifier: $0).region?.identifier }
        wanted += ["NO", "DK", "SE", "FI", "GB", "DE", "US"]
        var seen = Set<String>()
        self.countries = wanted.map { $0.uppercased() }.filter { seen.insert($0).inserted }
    }

    /// Whether board ratings can be fetched at all. Without a key the app still
    /// works — a grown-up's approvals carry the whole load — and the interface
    /// says so rather than leaving a parent wondering why nothing fills in.
    public var canVerifyAutomatically: Bool { client != nil }

    public var current: RatingIndex { index }

    public func load() async {
        index = await storage.load(RatingIndex.self, from: RatingIndex.fileName) ?? RatingIndex()
        knownUnrated = await storage.load(
            Set<String>.self, from: Self.unratedFileName
        ) ?? []
    }

    // MARK: - Provider markers

    /// Reads every age limit the provider wrote into its own data.
    ///
    /// Costs one pass over the catalogue and no network. Runs on whatever
    /// library was just loaded, before any profile is chosen, so a restricted
    /// profile is never briefly permissive while this catches up.
    @discardableResult
    public func seedProviderMarkers(from items: [MediaItem]) -> RatingIndex {
        for item in items {
            guard let found = RatingParser.rating(inText: item.rawTitle)
                ?? item.rawGroup.flatMap(RatingParser.rating(inText:))
            else { continue }
            index.record(ContentRating(rating: found, source: .provider), for: RatingKey.of(item))
        }
        return index
    }

    // MARK: - Boards

    /// How far through the pool this pass got.
    public struct Progress: Sendable {
        /// Titles that gained a rating in this pass.
        public var resolved: Int
        /// Titles in the pool still without an answer.
        public var remaining: Int
        /// Whether the caller needs to rebuild the filtered library.
        public var changed: Bool
        /// Set when the pass stopped early because the service asked us to.
        public var wasRateLimited: Bool
    }

    /// Looks up board ratings for a pool of titles, a batch at a time.
    ///
    /// The pool is whatever the caller decided is worth knowing about — in
    /// practice, the sections a grown-up approved for a child. It is walked in
    /// order and the answers are permanent, so calling this repeatedly works
    /// through the whole pool and picks up where it left off next launch.
    ///
    /// Returns nil only when there is nothing to do at all.
    @discardableResult
    public func verify(_ items: [MediaItem]) async -> Progress? {
        guard let client, !isVerifying else { return nil }
        isVerifying = true
        defer { isVerifying = false }

        // Live channels are skipped: a channel is not a title, and no board
        // rates one. Those are a grown-up's decision by design.
        //
        // Deduplicated through a Set rather than by scanning what has been
        // collected so far. A pool is thousands of episodes of the same few
        // shows, and the scan made this quadratic — seconds of main-thread
        // work before a single request went out.
        var seenKeys = Set<String>()
        var wanted: [(key: String, item: MediaItem)] = []
        var remaining = 0
        for item in items where item.kind != .liveTV {
            let key = RatingKey.of(item)
            guard index[key]?.isVerified != true, !knownUnrated.contains(key),
                  seenKeys.insert(key).inserted
            else { continue }
            remaining += 1
            if wanted.count < Self.batchLimit { wanted.append((key, item)) }
        }

        guard !wanted.isEmpty else {
            return Progress(resolved: 0, remaining: 0, changed: false, wasRateLimited: false)
        }

        var changed = false
        var resolved = 0
        var wasRateLimited = false
        for (key, item) in wanted {
            if Task.isCancelled { break }
            let name = item.seriesName ?? item.title
            let isSeries = item.kind == .series
            do {
                let matches = try await client.search(name, year: item.year, isSeries: isSeries)
                guard let best = Self.confidentMatch(for: name, year: item.year, among: matches) else {
                    knownUnrated.insert(key)
                    continue
                }
                // Every board in preference order, taking the first that
                // yields a number we understand. Norway's answer wins where
                // there is one; a title only the German board rated still gets
                // an answer instead of falling through as unrated.
                let boards = try await client.certifications(
                    id: best.id, isSeries: isSeries, preferring: countries
                )
                let verdict = Self.verdict(from: boards, home: countries.first)

                guard let verdict else {
                    knownUnrated.insert(key)
                    continue
                }
                index.record(
                    ContentRating(rating: verdict.rating, source: .board, country: verdict.country),
                    for: key
                )
                changed = true
                resolved += 1
            } catch TMDBClient.Failure.rateLimited {
                // Stop, and record nothing. Caching "unrated" because the
                // service was busy would hide a children's film permanently —
                // the same mistake the metadata layer already learned once.
                wasRateLimited = true
                break
            } catch {
                continue
            }
        }

        await persist()
        return Progress(
            resolved: resolved,
            remaining: max(remaining - resolved, 0),
            changed: changed,
            wasRateLimited: wasRateLimited
        )
    }

    /// The current index, for a caller that needs to rebuild after a pass.
    public var snapshot: RatingIndex { index }

    /// Which board to believe when they disagree.
    ///
    /// Bob's Burgers is the case that settled this: Finland rates it K7,
    /// Britain 12, Germany 16. Taking whichever board answered first made the
    /// verdict depend on the order of a list, and that order happened to put
    /// the most lenient one in front.
    ///
    /// So: the viewer's own country decides, because that is the number a
    /// parent here recognises and the one their child's school friends go by.
    /// With no answer at home, the strictest of the rest wins — boards
    /// disagreeing by nine years is precisely when to err towards asking a
    /// grown-up, and being one step strict costs a tap while being one step
    /// lenient costs the thing this feature exists for.
    static func verdict(
        from boards: [(code: String, country: String)], home: String?
    ) -> (rating: MaturityRating, country: String)? {
        var readable: [(rating: MaturityRating, country: String)] = []
        for board in boards {
            guard let rating = RatingParser.rating(code: board.code, country: board.country)
            else { continue }
            if let home, board.country.caseInsensitiveCompare(home) == .orderedSame {
                return (rating, board.country)
            }
            readable.append((rating, board.country))
        }
        return readable.max { $0.rating < $1.rating }
    }

    // MARK: - Identifying

    /// The one title this entry certainly is, or nothing.
    ///
    /// Taking the first search result is what a metadata layer does, and it is
    /// the wrong instinct here. Measured against a real playlist: "Frost (2013)"
    /// is Disney's *Frozen* to a Norwegian viewer and a different 2013 film
    /// called *Frost* to TMDB's search, which answered with the latter and its
    /// British 15 certificate. That rating would have pulled a children's film
    /// out of a child's profile on the strength of a coincidence.
    ///
    /// So two entries that both fit is not a tie to break — it is an answer we
    /// do not have. Recording nothing leaves the entry unrated, which costs a
    /// grown-up's approval at worst and never invents a limit.
    static func confidentMatch(
        for name: String, year: Int?, among candidates: [TMDBTitle]
    ) -> TMDBTitle? {
        let needle = SearchNormalizer.normalize(name)
        guard !needle.isEmpty else { return nil }

        var fits: [TMDBTitle] = []
        for candidate in candidates {
            // The name has to be the same name, not merely a close one. A
            // prefix match is good enough to choose a poster and nowhere near
            // good enough to decide what a child may watch.
            guard candidate.allTitles.contains(where: { SearchNormalizer.normalize($0) == needle })
            else { continue }
            // A year that disagrees settles it; a year nobody stated does not.
            if let year, let candidateYear = candidate.year, abs(candidateYear - year) > 1 {
                continue
            }
            fits.append(candidate)
        }

        let unique = Dictionary(grouping: fits, by: \.id).values.compactMap(\.first)
        if unique.count == 1 { return unique.first }
        guard unique.count > 1 else { return nil }

        // Several titles of the same name. When the playlist stated a year,
        // they have all already matched it, and there is genuinely nothing to
        // choose between them — that is the Frost case, and the answer is no
        // answer.
        if year != nil { return nil }

        // With no year, refusing outright was too blunt. TMDB lists two series
        // called "Bluey": the one every four-year-old watches, and an
        // Australian police drama from 1976. Treating that as unanswerable
        // hid the children's programme, which is the failure this feature was
        // supposed to prevent in the other direction.
        //
        // So one candidate may win, but only by a landslide. Anything closer
        // stays unanswered rather than guessed.
        let ranked = unique.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
        guard let leader = ranked.first, let runnerUp = ranked.dropFirst().first else {
            return nil
        }
        let lead = leader.popularity ?? 0
        let next = runnerUp.popularity ?? 0
        guard lead >= 1, lead >= next * 10 else { return nil }
        return leader
    }

    // MARK: - Manual

    /// A grown-up's own decision about a title, which outranks every source.
    public func setParentRating(_ rating: MaturityRating, forKey key: String) async {
        index.record(ContentRating(rating: rating, source: .parent), for: key)
        await persist()
    }

    public func clearRating(forKey key: String) async {
        index.remove(key)
        await persist()
    }

    private static let unratedFileName = "content-ratings-unrated.json"

    private func persist() async {
        await storage.save(index, to: RatingIndex.fileName)
        await storage.save(knownUnrated, to: Self.unratedFileName)
    }
}
