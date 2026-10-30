import Foundation

/// One channel, and every stream that carries it.
///
/// Providers list the same channel many times over. Measured on a real
/// catalogue: 2,047 live entries were 657 actual channels. Most of that is the
/// same stream repeated across categories — "V sport 1" under Norway, Norway
/// Sport, Premier League and All Sport — but not all of it. "V sport 1" also
/// had **seven genuinely different streams** behind those 25 entries.
///
/// So the duplicates are folded away for display and every distinct stream is
/// kept as an alternative. Collapsing to one and picking wrong would throw
/// away six working feeds, and some provider streams are simply dead.
public struct ChannelGroup: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// Distinct streams, most promising first. Never empty.
    public var variants: [MediaItem]
    /// Every category any variant appeared under.
    public var categories: [String]

    public init(id: String, name: String, variants: [MediaItem], categories: [String]) {
        self.id = id
        self.name = name
        self.variants = variants
        self.categories = categories
    }

    public var primary: MediaItem { variants[0] }
    public var hasAlternatives: Bool { variants.count > 1 }
    public var logoURL: URL? { variants.compactMap(\.logoURL).first }
    public var channelID: String? { variants.compactMap(\.channelID).first }
    public var channelNumber: Int? { variants.compactMap(\.channelNumber).first }

    /// The variant to start with: whatever last worked, else the best guess.
    public func preferred(_ rememberedID: String?) -> MediaItem {
        guard let rememberedID,
              let remembered = variants.first(where: { $0.id == rememberedID })
        else { return primary }
        return remembered
    }

    /// Every variant, starting from the remembered one.
    public func ordered(from rememberedID: String?) -> [MediaItem] {
        guard let rememberedID,
              let index = variants.firstIndex(where: { $0.id == rememberedID })
        else { return variants }
        return Array(variants[index...]) + Array(variants[..<index])
    }

    /// Looks through every feed because the best stream and the one carrying
    /// a usable XMLTV id are not necessarily the same provider entry.
    public func programme(in guide: XMLTVParser.Guide, at date: Date = .now) -> Programme? {
        for variant in variants {
            guard let channelID = variant.channelID,
                  let programme = guide.schedules[channelID]?.programme(at: date)
            else { continue }
            return programme
        }
        return nil
    }

    public func upcoming(
        in guide: XMLTVParser.Guide,
        after date: Date = .now,
        limit: Int = 3
    ) -> [Programme] {
        for variant in variants {
            guard let channelID = variant.channelID else { continue }
            let programmes = guide.schedules[channelID]?.upcoming(after: date, limit: limit) ?? []
            if !programmes.isEmpty { return programmes }
        }
        return []
    }
}

/// How promising a stream looks from its name alone.
///
/// Only used to order alternatives, never to discard one — a low-ranked stream
/// is often the only one that works.
enum StreamQuality {

    /// Higher is tried first.
    static func rank(_ item: MediaItem) -> Int {
        let text = (item.qualityTag.map { $0 + " " } ?? "") + item.rawTitle.lowercased()

        var score = 0
        if text.contains("uhd") || text.contains("4k") || text.contains("2160") { score += 40 }
        else if text.contains("fhd") || text.contains("1080") { score += 30 }
        else if text.contains("hd") || text.contains("720") { score += 20 }
        else if text.contains("sd") || text.contains("480") { score -= 10 }

        // Frame rate, once resolution has had its say. A 50fps feed of the
        // same match is the one worth leading with — it is the difference
        // between football that pans and football that stutters — but never
        // enough to put a 50fps SD feed ahead of an ordinary HD one.
        if text.contains("50fps") || text.contains("60fps") { score += 5 }

        // A "raw" feed is an unpackaged source: often higher quality, often
        // less reliable, so it sits behind the ordinary stream rather than
        // being dropped.
        if text.contains("raw") { score -= 5 }
        if text.contains("backup") || text.contains("alt ") { score -= 15 }
        // A low-bandwidth feed is a fallback for a poor connection, never the
        // one to lead with.
        if ChannelNaming.lowBandwidthPhrases.contains(where: text.contains) { score -= 20 }
        return score
    }
}

public extension Library {

    static func makeChannelGroups(_ channels: [MediaItem]) -> [ChannelGroup] {
        var buckets: [String: [MediaItem]] = [:]
        var names: [String: String] = [:]

        for (key, channel) in ChannelNaming.countryScopedKeys(for: channels) {
            buckets[key, default: []].append(channel)
            // Keep the shortest name: "V sport 1" over "V sport 1 HD | raw".
            if let existing = names[key] {
                if channel.title.count < existing.count { names[key] = channel.title }
            } else {
                names[key] = channel.title
            }
        }

        return buckets.map { key, members in
            // Entries sharing a url are the same stream listed under several
            // categories; only genuinely distinct streams are alternatives.
            var seenURLs = Set<String>()
            let distinct = members.filter { seenURLs.insert($0.streamURL.absoluteString).inserted }

            return ChannelGroup(
                id: key,
                name: names[key] ?? key,
                variants: distinct.sorted { StreamQuality.rank($0) > StreamQuality.rank($1) },
                categories: Array(Set(members.compactMap(\.category))).sorted()
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.channelNumber, rhs.channelNumber) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.name.lowercased() < rhs.name.lowercased()
            }
        }
    }
}

/// The name two listings of the same channel agree on.
enum ChannelNaming {
    /// Shared with films, which are filed under the same delivery noise —
    /// frame rate included. Without it "V sport Premier League HD | 50FPS"
    /// keys apart from "V sport Premier League HD", and the channel becomes
    /// two cards, each holding a fraction of the streams that carry it: a
    /// failover that should have three feeds to fall through only has two.
    /// Measured on a real catalogue: six channels split this way, every one
    /// of them sport.
    static func groupKey(for item: MediaItem) -> String {
        let key = TitleKey.groupKey(for: item)
        // "NRK1 Lav Internett hastighet" is NRK1 for a slow connection, not a
        // channel of its own: as a second card it pushed NRK2 down the list
        // and left NRK1 with no fallback.
        for phrase in lowBandwidthPhrases where key.hasSuffix(" " + phrase) {
            return String(key.dropLast(phrase.count + 1))
        }
        return key
    }

    /// Normalised, as `SearchNormalizer` leaves them.
    static let lowBandwidthPhrases = [
        "lav internett hastighet", "lav internetthastighet", "lav hastighet", "lav kvalitet",
        "low bandwidth", "low bitrate", "low quality", "lavt bandbredd", "lav bandbredde",
    ]

    /// A shared name is not always a shared channel. Measured on a real
    /// panel: Norway's "TV 2" and Denmark's "TV 2" are listed under exactly
    /// that name, so they folded into one card whose guide interleaved both
    /// schedules and whose failover could land on the Danish feed. A name is
    /// split only when its listings sit under two different countries;
    /// entries filed under no country ("Premier League") stay with the
    /// country most of the listings came from, so sport keeps its feeds.
    static func countryScopedKeys(for channels: [MediaItem]) -> [(String, MediaItem)] {
        let keyed = channels.map { (groupKey(for: $0), $0) }
        var countries: [String: [String: Int]] = [:]
        for (key, channel) in keyed {
            if let country = country(of: channel) { countries[key, default: [:]][country, default: 0] += 1 }
        }
        return keyed.map { key, channel in
            guard let seen = countries[key], seen.count > 1 else { return (key, channel) }
            let dominant = seen.max { ($0.value, $1.key) < ($1.value, $0.key) }!.key
            let country = country(of: channel) ?? dominant
            return (country == dominant ? key : "\(key)|\(country)", channel)
        }
    }

    /// The country a provider category names, if it names one.
    static func country(of item: MediaItem) -> String? {
        guard let category = item.category?.lowercased() else { return nil }
        let words = category.split { !$0.isLetter }.map(String.init)
        for word in words {
            if let code = countryWords[word] { return code }
        }
        return nil
    }

    private static let countryWords: [String: String] = [
        "norway": "no", "norwegian": "no", "norge": "no", "norsk": "no", "no": "no",
        "sweden": "se", "swedish": "se", "sverige": "se", "svensk": "se", "se": "se",
        "denmark": "dk", "danish": "dk", "danmark": "dk", "dansk": "dk", "dk": "dk",
        "finland": "fi", "finnish": "fi", "suomi": "fi", "fi": "fi",
        "germany": "de", "german": "de", "deutschland": "de", "tyskland": "de", "de": "de",
        "uk": "gb", "british": "gb", "england": "gb",
        "usa": "us", "us": "us",
        "netherlands": "nl", "dutch": "nl", "nl": "nl",
        "poland": "pl", "polish": "pl", "pl": "pl",
    ]
}
