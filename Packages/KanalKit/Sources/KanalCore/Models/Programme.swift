import Foundation

/// One entry in a channel's schedule.
public struct Programme: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(channelID)|\(start.timeIntervalSince1970)" }

    public let channelID: String
    public var title: String
    public var subtitle: String?
    public var description: String?
    public var start: Date
    public var stop: Date
    public var categories: [String]
    public var iconURL: URL?
    public var episodeCode: String?

    public init(
        channelID: String,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        start: Date,
        stop: Date,
        categories: [String] = [],
        iconURL: URL? = nil,
        episodeCode: String? = nil
    ) {
        self.channelID = channelID
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.start = start
        self.stop = stop
        self.categories = categories
        self.iconURL = iconURL
        self.episodeCode = episodeCode
    }

    public var duration: TimeInterval { stop.timeIntervalSince(start) }

    public func isOnAir(at date: Date = .now) -> Bool {
        date >= start && date < stop
    }

    /// 0…1 through the programme, for the progress bars on now-playing rows.
    public func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }
}

/// A channel's schedule, kept sorted so lookups can binary-search.
public struct Schedule: Sendable {
    public let channelID: String
    public let programmes: [Programme]

    public init(channelID: String, programmes: [Programme]) {
        self.channelID = channelID
        self.programmes = programmes.sorted { $0.start < $1.start }
    }

    public func programme(at date: Date = .now) -> Programme? {
        var low = 0
        var high = programmes.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = programmes[mid]
            if date < candidate.start {
                high = mid - 1
            } else if date >= candidate.stop {
                low = mid + 1
            } else {
                return candidate
            }
        }
        return nil
    }

    public func upcoming(after date: Date = .now, limit: Int = 4) -> [Programme] {
        programmes.filter { $0.start >= date }.prefix(limit).map { $0 }
    }
}
