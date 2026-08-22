import Foundation

/// What was wrong with the data a provider sent.
///
/// Kanal repairs what it can, but repairing silently is its own kind of lie: a
/// guide covering a third of the channels looks identical to a guide covering
/// all of them until someone goes looking for a programme that isn't there.
/// This is what lets the app say "loaded, and here is what was off" instead.
public struct SourceDiagnostics: Sendable, Equatable, Codable {

    /// Playlist lines that could not be turned into anything playable.
    public var skippedPlaylistLines: Int = 0

    /// Programmes the guide yielded, after any repair.
    public var guideProgrammes: Int = 0
    /// Repairs the guide needed to parse at all.
    public var guideRepairs: [XMLRepair.Fix] = []
    /// The guide stopped short even after repair — partial, not empty.
    public var guideIsPartial: Bool = false
    /// How many of the library's channels the guide actually covers.
    public var guideChannelsMatched: Int = 0
    /// How many channels carry an id the guide could match against at all.
    public var channelsWithID: Int = 0

    public init() {}

    /// True when there is something worth telling the user about.
    public var hasFindings: Bool {
        skippedPlaylistLines > 0
            || !guideRepairs.isEmpty
            || guideIsPartial
            || (guideProgrammes > 0 && guideCoverage < 0.5)
    }

    /// 0…1 of channels the guide covers. Meaningless without a guide.
    public var guideCoverage: Double {
        guard channelsWithID > 0 else { return 0 }
        return Double(guideChannelsMatched) / Double(channelsWithID)
    }
}
