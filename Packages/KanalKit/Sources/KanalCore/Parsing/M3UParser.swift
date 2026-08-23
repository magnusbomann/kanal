import Foundation

/// Result of parsing an M3U playlist.
public struct M3UPlaylist: Sendable {
    public var items: [MediaItem]
    /// `x-tvg-url` from the header — the EPG we can fetch without asking the user.
    public var epgURL: URL?
    /// Entries we could not turn into a playable item, for diagnostics.
    public var skippedLineCount: Int

    public init(items: [MediaItem], epgURL: URL? = nil, skippedLineCount: Int = 0) {
        self.items = items
        self.epgURL = epgURL
        self.skippedLineCount = skippedLineCount
    }
}

/// Parses extended M3U playlists.
///
/// Written as a single forward pass over the lines: real playlists run to
/// hundreds of thousands of entries and get parsed on every refresh.
public struct M3UParser: Sendable {

    public init() {}

    public func parse(_ text: String) -> M3UPlaylist {
        var items: [MediaItem] = []
        var epgURL: URL?
        var skipped = 0

        var pendingAttributes: [String: String] = [:]
        var pendingDisplayName: String?
        var pendingGroupOverride: String?
        var seenIDs: Set<String> = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTM3U") {
                if let value = Self.attributes(in: line)["x-tvg-url"] ?? Self.attributes(in: line)["url-tvg"] {
                    epgURL = URL(string: value.split(separator: ",").first.map(String.init) ?? value)
                }
                continue
            }

            if line.hasPrefix("#EXTINF") {
                pendingAttributes = Self.attributes(in: line)
                pendingDisplayName = Self.displayName(in: line)
                pendingGroupOverride = nil
                continue
            }

            if line.hasPrefix("#EXTGRP:") {
                pendingGroupOverride = String(line.dropFirst("#EXTGRP:".count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Other directives (#KODIPROP, #EXTVLCOPT, comments) carry no data we use yet.
            if line.hasPrefix("#") { continue }

            guard let url = Self.streamURL(from: line) else {
                skipped += 1
                pendingAttributes = [:]
                pendingDisplayName = nil
                continue
            }

            let rawTitle = pendingDisplayName
                ?? pendingAttributes["tvg-name"]
                ?? url.deletingPathExtension().lastPathComponent
            let group = pendingGroupOverride ?? pendingAttributes["group-title"]

            let cleaned = TitleCleaner.clean(rawTitle)
            let kind = MediaClassifier.classify(
                title: cleaned.title,
                streamURL: url,
                group: group,
                hasEpisodeMarker: cleaned.season != nil
            )

            let identifier = Self.uniqueID(
                preferred: pendingAttributes["tvg-id"],
                url: url,
                rawTitle: rawTitle,
                seen: &seenIDs
            )

            items.append(
                MediaItem(
                    id: identifier,
                    kind: kind,
                    title: cleaned.title,
                    rawTitle: rawTitle,
                    streamURL: url,
                    logoURL: pendingAttributes["tvg-logo"].flatMap { URL(string: $0) },
                    rawGroup: group,
                    category: CategoryNormalizer.normalize(group),
                    channelID: pendingAttributes["tvg-id"].flatMap { $0.isEmpty ? nil : $0 },
                    channelNumber: pendingAttributes["tvg-chno"].flatMap { Int($0) },
                    language: pendingAttributes["tvg-language"],
                    countryCode: pendingAttributes["tvg-country"] ?? cleaned.countryCode,
                    seriesName: kind == .series ? cleaned.seriesName : nil,
                    episodeTitle: kind == .series ? cleaned.episodeTitle : nil,
                    season: kind == .series ? cleaned.season : nil,
                    episode: kind == .series ? cleaned.episode : nil,
                    year: cleaned.year,
                    qualityTag: cleaned.qualityTag
                )
            )

            pendingAttributes = [:]
            pendingDisplayName = nil
            pendingGroupOverride = nil
        }

        return M3UPlaylist(items: items, epgURL: epgURL, skippedLineCount: skipped)
    }

    // MARK: - Line pieces

    /// Pulls `key="value"` pairs out of a directive line.
    static func attributes(in line: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var inQuotes = false
        var readingValue = false

        for character in line {
            if inQuotes {
                if character == "\"" {
                    inQuotes = false
                    readingValue = false
                    let trimmedKey = key.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
                    if !trimmedKey.isEmpty { result[trimmedKey.lowercased()] = value }
                    key = ""
                    value = ""
                } else {
                    value.append(character)
                }
                continue
            }

            switch character {
            case "=":
                readingValue = true
            case "\"":
                if readingValue { inQuotes = true } else { key = "" }
            case ",":
                // Start of the display name — attributes are done.
                if !readingValue { return result }
                key = ""
                readingValue = false
            default:
                guard !readingValue else { break }
                // Keys never contain spaces, so whitespace starts a fresh key.
                // Without this the first attribute on a line would absorb the
                // directive itself ("#EXTINF:-1 tvg-id").
                if character.isWhitespace {
                    key = ""
                } else {
                    key.append(character)
                }
            }
        }
        return result
    }

    /// The text after the last comma on an `#EXTINF` line.
    static func displayName(in line: String) -> String? {
        var inQuotes = false
        var lastCommaIndex: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ",", !inQuotes { lastCommaIndex = index }
            index = line.index(after: index)
        }
        guard let lastCommaIndex else { return nil }
        let name = String(line[line.index(after: lastCommaIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    static func streamURL(from line: String) -> URL? {
        guard let url = URL(string: line), url.scheme != nil else {
            // Percent-encode as a fallback: provider paths often contain spaces.
            guard let encoded = line.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: encoded), url.scheme != nil
            else { return nil }
            return url
        }
        return url
    }

    /// Playlists reuse `tvg-id` across entries, so ids get suffixed on collision.
    static func uniqueID(
        preferred: String?,
        url: URL,
        rawTitle: String,
        seen: inout Set<String>
    ) -> String {
        let base: String
        if let preferred, !preferred.isEmpty {
            base = preferred
        } else {
            base = "\(rawTitle)|\(url.absoluteString)"
        }
        if seen.insert(base).inserted { return base }

        var suffix = 2
        while true {
            let candidate = "\(base)#\(suffix)"
            if seen.insert(candidate).inserted { return candidate }
            suffix += 1
        }
    }
}
