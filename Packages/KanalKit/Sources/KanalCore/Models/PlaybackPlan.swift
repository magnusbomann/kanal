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
    /// Present for grouped channels, so the successful stream can lead the
    /// next time this same channel is opened.
    public let groupID: String?

    public init(
        item: MediaItem,
        candidates: [URL],
        owners: [String],
        groupID: String? = nil
    ) {
        self.item = item
        self.candidates = candidates
        self.owners = owners
        self.groupID = groupID
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

    /// A film, with every other listing of it behind the one that plays.
    ///
    /// The same fallback channels get. A provider lists one film several times
    /// and the streams behind those listings are not equally alive, so a dead
    /// one costs a moment rather than the film.
    public init(movie: MovieGroup, remembered: String? = nil) {
        // Titled and identified by the film, not by whichever listing ends up
        // playing: the resume position belongs to the film, and a viewer who
        // fell through to the third stream should not find their progress
        // filed under it.
        self.init(
            id: movie.id,
            ordered: movie.ordered(from: remembered),
            fallback: movie.representative,
            shownAs: movie.representative
        )
    }

    private init(group: ChannelGroup, ordered: [MediaItem]) {
        self.init(id: group.id, ordered: ordered, fallback: group.primary)
    }

    private init(
        id: String, ordered: [MediaItem], fallback: MediaItem, shownAs: MediaItem? = nil
    ) {
        var candidates: [URL] = []
        var owners: [String] = []

        for variant in ordered {
            for url in StreamCandidates.candidates(for: variant) {
                candidates.append(url)
                owners.append(variant.id)
            }
        }

        let leading = shownAs ?? ordered.first ?? fallback
        self.init(
            item: leading,
            candidates: candidates.isEmpty ? [leading.streamURL] : candidates,
            owners: owners.isEmpty ? [leading.id] : owners,
            groupID: id
        )
    }

    public func owner(at index: Int) -> String? {
        owners.indices.contains(index) ? owners[index] : nil
    }

    // MARK: Variants
    //
    // A candidate list mixes two different kinds of step. Moving from
    // `film.mkv` to `film.mp4` asks the same stream for another container and
    // costs nothing. Moving to the next variant asks the provider for a
    // different feed — a new connection, on an account that may only be
    // allowed one at a time. The two need different patience and different
    // words on screen, so the boundary between them has to be visible.

    /// Where each variant's run of candidates begins, in order.
    public var variantStarts: [Int] {
        var starts: [Int] = []
        var previous: String?
        for index in candidates.indices {
            let owner = owner(at: index)
            if owner != previous { starts.append(index) }
            previous = owner
        }
        return starts
    }

    /// How many distinct streams carry this. One for anything ungrouped.
    public var variantCount: Int { variantStarts.count }

    /// True when this candidate is the first request made to its feed, and so
    /// the one that has to wait for a connection rather than reuse one.
    public func isVariantStart(_ index: Int) -> Bool {
        guard candidates.indices.contains(index) else { return false }
        return index == 0 || owner(at: index) != owner(at: index - 1)
    }

    /// Which stream a candidate belongs to, counting from one — "source 2 of 5"
    /// as a viewer would count them.
    public func variantNumber(at index: Int) -> Int {
        let starts = variantStarts
        guard let position = starts.lastIndex(where: { $0 <= index }) else { return 1 }
        return position + 1
    }

    /// The first candidate of the next stream, or nil when this is the last.
    public func nextVariantStart(after index: Int) -> Int? {
        variantStarts.first { $0 > index }
    }

    /// True when advancing past `index` means opening a different feed rather
    /// than re-asking the same one for another container.
    public func crossesVariant(advancingFrom index: Int) -> Bool {
        guard candidates.indices.contains(index + 1) else { return false }
        return owner(at: index) != owner(at: index + 1)
    }

    /// Whether this index is the provider's own url for the last variant —
    /// the point past which there is nothing left to try.
    public func isLast(_ index: Int) -> Bool {
        index >= candidates.count - 1
    }

    /// The order a decoder with broad format support should use.
    ///
    /// AVFoundation asks for guessed Apple-friendly extensions before the URL
    /// the provider actually published. VLC can open those original formats,
    /// so each variant's real URL leads here; extension guesses remain as a
    /// final fallback rather than delaying every MKV film.
    public var alternativeCandidateIndices: [Int] {
        guard !candidates.isEmpty else { return [] }

        var ownerOrder: [String] = []
        var lastIndexByOwner: [String: Int] = [:]
        for index in candidates.indices {
            let owner = owner(at: index) ?? "candidate-\(index)"
            if lastIndexByOwner[owner] == nil { ownerOrder.append(owner) }
            lastIndexByOwner[owner] = index
        }

        let originals = ownerOrder.compactMap { lastIndexByOwner[$0] }
        let originalSet = Set(originals)
        return originals + candidates.indices.filter { !originalSet.contains($0) }
    }
}
