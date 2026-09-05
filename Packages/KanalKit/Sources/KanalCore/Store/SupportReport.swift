import Foundation

/// A diagnostics snapshot that is safe to paste into a support conversation.
///
/// It intentionally contains no URLs, usernames, passwords, channel names,
/// profile names or playback history. Provider hosts are useful for diagnosing
/// server families, while paths and query strings are where secrets usually
/// live, so only the host and port survive.
public struct SupportReport: Sendable, Equatable {
    public struct SourceSummary: Sendable, Equatable {
        public var id: String
        public var kind: SourceKind
        public var host: String
        public var lastRefreshedAt: Date?
    }

    public var generatedAt: Date
    public var appVersion: String
    public var system: String
    public var phase: String
    public var sourceCount: Int
    public var activeSource: SourceSummary?
    public var channelCount: Int
    public var movieCount: Int
    public var seriesCount: Int
    public var guideProgrammeCount: Int
    public var guideCoveragePercent: Int
    public var guideWasRepaired: Bool
    public var guideIsPartial: Bool
    public var skippedPlaylistLines: Int
    public var timeToFirstPlayableChannel: TimeInterval?

    public init(
        generatedAt: Date = .now,
        appVersion: String,
        system: String,
        phase: String,
        sourceCount: Int,
        activeSource: SourceSummary?,
        channelCount: Int,
        movieCount: Int,
        seriesCount: Int,
        guideProgrammeCount: Int,
        guideCoveragePercent: Int,
        guideWasRepaired: Bool,
        guideIsPartial: Bool,
        skippedPlaylistLines: Int,
        timeToFirstPlayableChannel: TimeInterval? = nil
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.system = system
        self.phase = phase
        self.sourceCount = sourceCount
        self.activeSource = activeSource
        self.channelCount = channelCount
        self.movieCount = movieCount
        self.seriesCount = seriesCount
        self.guideProgrammeCount = guideProgrammeCount
        self.guideCoveragePercent = guideCoveragePercent
        self.guideWasRepaired = guideWasRepaired
        self.guideIsPartial = guideIsPartial
        self.skippedPlaylistLines = skippedPlaylistLines
        self.timeToFirstPlayableChannel = timeToFirstPlayableChannel
    }

    public var text: String {
        let date = generatedAt.formatted(.iso8601)
        let source = activeSource.map {
            "\($0.kind.rawValue) @ \($0.host) [\($0.id)]"
        } ?? "none"
        return """
        Kanal support report
        Generated: \(date)
        App: \(appVersion)
        System: \(system)
        State: \(phase)
        Sources: \(sourceCount)
        Active source: \(source)
        Library: \(channelCount) channels, \(movieCount) films, \(seriesCount) series
        Guide: \(guideProgrammeCount) programmes, \(guideCoveragePercent)% coverage
        Guide repaired: \(guideWasRepaired)
        Guide partial: \(guideIsPartial)
        Skipped playlist lines: \(skippedPlaylistLines)
        Time to first playable channel: \(timeToFirstPlayableChannel.map { String(format: "%.3f s", $0) } ?? "not measured")
        Privacy: no links, credentials, titles, profile names or history included
        """
    }

    public static func sourceSummary(_ source: PlaylistSource) -> SourceSummary {
        let url = source.portalURL ?? source.playlistURL
        let host = [url?.host(), url?.port.map(String.init)]
            .compactMap { $0 }
            .joined(separator: ":")
        return SourceSummary(
            id: String(source.id.uuidString.prefix(8)),
            kind: source.kind,
            host: host.isEmpty ? "local" : host,
            lastRefreshedAt: source.lastRefreshedAt
        )
    }
}
