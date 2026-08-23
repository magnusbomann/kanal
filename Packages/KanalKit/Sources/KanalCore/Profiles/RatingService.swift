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
    /// TMDB's rate limit is generous but not infinite, and a real catalogue has
    /// thirty thousand films. Bounded work per pass, resumed next launch, keeps
    /// this off the critical path forever.
    private static let batchLimit = 120

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

    /// Looks up board ratings for titles a restricted profile can currently
    /// reach, so anything rated above the limit falls back out of an approved
    /// category on its own.
    ///
    /// Returns the index only when something changed, so callers can skip a
    /// rebuild of the filtered library in the common case of nothing new.
    @discardableResult
    public func verify(_ items: [MediaItem]) async -> RatingIndex? {
        guard let client, !isVerifying else { return nil }
        isVerifying = true
        defer { isVerifying = false }

        // Live channels are skipped: a channel is not a title, and no board
        // rates one. Those are a grown-up's decision by design.
        let wanted = items
            .filter { $0.kind != .liveTV }
            .reduce(into: [(key: String, item: MediaItem)]()) { found, item in
                let key = RatingKey.of(item)
                guard index[key] == nil, !knownUnrated.contains(key),
                      !found.contains(where: { $0.key == key })
                else { return }
                found.append((key, item))
            }
            .prefix(Self.batchLimit)

        guard !wanted.isEmpty else { return nil }

        var changed = false
        for (key, item) in wanted {
            if Task.isCancelled { break }
            let name = item.seriesName ?? item.title
            let isSeries = item.kind == .series
            do {
                let matches = try await client.search(name, year: item.year, isSeries: isSeries)
                guard let best = matches.first else {
                    knownUnrated.insert(key)
                    continue
                }
                let found = try await client.certification(
                    id: best.id, isSeries: isSeries, preferring: countries
                )
                guard let found,
                      let rating = RatingParser.rating(code: found.code, country: found.country)
                else {
                    knownUnrated.insert(key)
                    continue
                }
                index.record(
                    ContentRating(rating: rating, source: .board, country: found.country),
                    for: key
                )
                changed = true
            } catch TMDBClient.Failure.rateLimited {
                // Stop, and record nothing. Caching "unrated" because the
                // service was busy would hide a children's film permanently —
                // the same mistake the metadata layer already learned once.
                break
            } catch {
                continue
            }
        }

        await persist()
        return changed ? index : nil
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
