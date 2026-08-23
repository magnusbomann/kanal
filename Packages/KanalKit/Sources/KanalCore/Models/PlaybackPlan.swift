import Foundation

/// Everything worth trying for one thing the viewer chose, in order.
///
/// Two kinds of fallback stacked together. A channel may be carried by several
/// streams — "V sport 1" had seven on a real provider — and any one of them
/// may be dead. Each stream may in turn be offered in a container the player
/// cannot open, and some panels will serve another if asked by extension.
///
/// Deliberately just a list of URLs: whichever engine ends up playing them,
/// walking a list in order is the whole contract.
public struct PlaybackPlan: Sendable {
    /// What the viewer picked, for titles and resume position.
    public let item: MediaItem
    /// URLs to attempt, best first. Never empty.
    public let candidates: [URL]
    /// Which library entry each candidate came from, so a success can be
    /// remembered against the right variant.
    public let owners: [String]

    public init(item: MediaItem, candidates: [URL], owners: [String]) {
        self.item = item
        self.candidates = candidates
        self.owners = owners
    }

    /// A single entry with no alternatives — films, episodes, one-off streams.
    public init(item: MediaItem) {
        let formats = StreamCandidates.candidates(for: item)
        self.init(
            item: item,
            candidates: formats,
            owners: Array(repeating: item.id, count: formats.count)
        )
    }

    /// A channel, opened normally.
    ///
    /// The variant that last played leads, because a stream that worked
    /// yesterday is the best guess for today. Everything else follows in
    /// quality order, so a dead stream costs a moment rather than the channel.
    public init(group: ChannelGroup, remembered: String? = nil) {
        self.init(group: group, ordered: group.ordered(from: remembered))
    }

    /// A channel opened on a variant the viewer picked themselves.
    ///
    /// Their choice leads even if another one is remembered — they are looking
    /// at the list precisely because the remembered one disappointed them.
    public init(group: ChannelGroup, explicitlyChosen variant: MediaItem) {
        var ordered = group.variants
        if let index = ordered.firstIndex(where: { $0.id == variant.id }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        self.init(group: group, ordered: ordered)
    }

    private init(group: ChannelGroup, ordered: [MediaItem]) {
        var candidates: [URL] = []
        var owners: [String] = []

        for variant in ordered {
            for url in StreamCandidates.candidates(for: variant) {
                candidates.append(url)
                owners.append(variant.id)
            }
        }

        let leading = ordered.first ?? group.primary
        self.init(
            item: leading,
            candidates: candidates.isEmpty ? [leading.streamURL] : candidates,
            owners: owners.isEmpty ? [leading.id] : owners
        )
    }

    public func owner(at index: Int) -> String? {
        owners.indices.contains(index) ? owners[index] : nil
    }

    /// Whether this index is the provider's own url for the last variant —
    /// the point past which there is nothing left to try.
    public func isLast(_ index: Int) -> Bool {
        index >= candidates.count - 1
    }
}
