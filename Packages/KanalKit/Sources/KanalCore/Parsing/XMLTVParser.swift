import Foundation

/// Parses XMLTV guide data.
///
/// Guides run to tens of megabytes, so this uses the event-driven parser and
/// keeps only the fields the UI actually renders — no intermediate DOM.
public final class XMLTVParser: NSObject, XMLParserDelegate {

    public struct Guide: Sendable {
        /// XMLTV channel id → display names declared in the file.
        public var channelNames: [String: String]
        public var channelIcons: [String: URL]
        /// XMLTV channel id → that channel's schedule.
        public var schedules: [String: Schedule]

        public var programmeCount: Int {
            schedules.values.reduce(0) { $0 + $1.count }
        }
    }

    private var channelNames: [String: String] = [:]
    private var channelIcons: [String: URL] = [:]
    private var programmesByChannel: [String: [Programme]] = [:]

    private var currentChannelID: String?
    private var currentElement: String?
    private var textBuffer = ""

    private var pendingChannelID: String?
    private var pendingStart: Date?
    private var pendingStop: Date?
    private var pendingTitle: String?
    private var pendingSubtitle: String?
    private var pendingDescription: String?
    private var pendingCategories: [String] = []
    private var pendingIcon: URL?
    private var pendingEpisodeCode: String?
    private var pendingEpisodeSystem: String?

    /// Only keep programmes inside this window — a full guide is mostly history.
    private let windowStart: Date
    private let windowEnd: Date

    public init(windowStart: Date = .now.addingTimeInterval(-6 * 3600),
                windowEnd: Date = .now.addingTimeInterval(8 * 24 * 3600)) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    /// What a parse produced, and what it took to get there.
    public struct ParseResult: Sendable {
        public var guide: Guide
        /// Repairs the input needed. Empty means it arrived well-formed.
        public var repairs: [XMLRepair.Fix]
        /// True when even the repaired document stopped short. The guide is
        /// then whatever arrived before the break, which is worth showing.
        public var isPartial: Bool

        public var programmeCount: Int { guide.programmeCount }
    }

    public func parse(_ data: Data) -> Guide {
        parseDetailed(data).guide
    }

    /// Parses strictly first, and only repairs when that fails.
    ///
    /// Order matters: a well-formed guide should never pay for the tolerance
    /// the broken ones need, and repaired output is accepted only when it
    /// actually recovers more than the strict attempt did.
    public func parseDetailed(_ data: Data) -> ParseResult {
        let strict = run(on: data)
        if !strict.aborted {
            return ParseResult(guide: strict.guide, repairs: [], isPartial: false)
        }

        guard let repaired = XMLRepair.repair(data) else {
            // Nothing to fix, so the break is structural. Keep what arrived.
            return ParseResult(guide: strict.guide, repairs: [], isPartial: true)
        }

        let second = XMLTVParser(windowStart: windowStart, windowEnd: windowEnd)
        let result = second.run(on: repaired.data)
        guard result.guide.programmeCount >= strict.guide.programmeCount else {
            return ParseResult(guide: strict.guide, repairs: [], isPartial: true)
        }
        return ParseResult(
            guide: result.guide,
            repairs: repaired.fixes,
            isPartial: result.aborted
        )
    }

    private func run(on data: Data) -> (guide: Guide, aborted: Bool) {
        reset()

        let parser = XMLParser(data: data)
        parser.delegate = self
        let succeeded = parser.parse()

        let schedules = programmesByChannel.mapValues { programmes in
            Schedule(channelID: programmes.first?.channelID ?? "", programmes: programmes)
        }
        let guide = Guide(
            channelNames: channelNames,
            channelIcons: channelIcons,
            schedules: schedules
        )
        return (guide, !succeeded)
    }

    /// Parsing twice on one instance would otherwise accumulate both runs.
    private func reset() {
        channelNames = [:]
        channelIcons = [:]
        programmesByChannel = [:]
        currentChannelID = nil
        currentElement = nil
        textBuffer = ""
        pendingChannelID = nil
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        textBuffer = ""

        switch elementName {
        case "channel":
            currentChannelID = attributes["id"]
        case "programme":
            pendingChannelID = attributes["channel"]
            pendingStart = attributes["start"].flatMap(Self.date(from:))
            pendingStop = attributes["stop"].flatMap(Self.date(from:))
            pendingTitle = nil
            pendingSubtitle = nil
            pendingDescription = nil
            pendingCategories = []
            pendingIcon = nil
            pendingEpisodeCode = nil
        case "icon":
            let url = attributes["src"].flatMap { URL(string: $0) }
            if pendingChannelID != nil {
                pendingIcon = pendingIcon ?? url
            } else if let channelID = currentChannelID, let url {
                channelIcons[channelID] = url
            }
        case "episode-num":
            pendingEpisodeSystem = attributes["system"]
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        textBuffer += String(decoding: CDATABlock, as: UTF8.self)
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        textBuffer = ""

        switch elementName {
        case "display-name":
            if let channelID = currentChannelID, channelNames[channelID] == nil, !text.isEmpty {
                channelNames[channelID] = text
            }
        case "title":
            if pendingChannelID != nil, pendingTitle == nil, !text.isEmpty { pendingTitle = text }
        case "sub-title":
            if pendingChannelID != nil, !text.isEmpty { pendingSubtitle = text }
        case "desc":
            if pendingChannelID != nil, pendingDescription == nil, !text.isEmpty {
                pendingDescription = text
            }
        case "category":
            if pendingChannelID != nil, !text.isEmpty { pendingCategories.append(text) }
        case "episode-num":
            if pendingEpisodeSystem == "onscreen", !text.isEmpty {
                pendingEpisodeCode = text
            } else if pendingEpisodeSystem == "xmltv_ns", pendingEpisodeCode == nil {
                pendingEpisodeCode = Self.onscreenCode(fromXMLTVNS: text)
            }
            pendingEpisodeSystem = nil
        case "channel":
            currentChannelID = nil
        case "programme":
            finishProgramme()
        default:
            break
        }
        currentElement = nil
    }

    private func finishProgramme() {
        defer { pendingChannelID = nil }
        guard let channelID = pendingChannelID,
              let title = pendingTitle,
              let start = pendingStart,
              let stop = pendingStop,
              stop > start,
              stop > windowStart,
              start < windowEnd
        else { return }

        programmesByChannel[channelID, default: []].append(
            Programme(
                channelID: channelID,
                title: title,
                subtitle: pendingSubtitle,
                description: pendingDescription,
                start: start,
                stop: stop,
                categories: pendingCategories,
                iconURL: pendingIcon,
                episodeCode: pendingEpisodeCode
            )
        )
    }

    // MARK: - Dates

    /// XMLTV timestamps: `20240115203000 +0100`, sometimes without the offset.
    static func date(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let stamp = String(parts[0])
        guard stamp.count >= 12, stamp.allSatisfy(\.isNumber) else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            let start = stamp.index(stamp.startIndex, offsetBy: range.lowerBound)
            let end = stamp.index(stamp.startIndex, offsetBy: range.upperBound)
            return Int(stamp[start..<end])
        }

        var components = DateComponents()
        components.year = number(0..<4)
        components.month = number(4..<6)
        components.day = number(6..<8)
        components.hour = number(8..<10)
        components.minute = number(10..<12)
        components.second = stamp.count >= 14 ? number(12..<14) : 0

        var calendar = Calendar(identifier: .gregorian)
        if parts.count == 2, let offset = offsetSeconds(String(parts[1])) {
            calendar.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        } else {
            calendar.timeZone = .gmt
        }
        return calendar.date(from: components)
    }

    static func offsetSeconds(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count == 5 else { return nil }
        let sign: Int = text.hasPrefix("-") ? -1 : 1
        let digits = text.dropFirst()
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2))
        else { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }

    /// `xmltv_ns` counts from zero: "0 . 3 . 0" is S01E04.
    static func onscreenCode(fromXMLTVNS raw: String) -> String? {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let season = Int(parts[0].split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "")
        let episode = Int(parts[1].split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "")
        guard let season, let episode else { return nil }
        return String(format: "S%02dE%02d", season + 1, episode + 1)
    }
}
