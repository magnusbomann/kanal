import Foundation

/// Turning "what else are they in?" into "what else can I watch?".
///
/// A person's credits come from TMDB, which knows every film ever made; the
/// viewer's provider carries a fraction of it. Every poster on the person
/// sheet is therefore resolved against the library before it is shown, so a
/// tap either opens something or is visibly not an offer.
public extension KnownRole {

    /// The same title, in the shape the library matcher takes.
    var asDiscoveryTitle: DiscoveryTitle {
        DiscoveryTitle(
            id: id,
            names: [title, originalTitle].compactMap { $0 },
            year: year,
            isSeries: isSeries,
            posterPath: posterPath,
            popularity: popularity
        )
    }
}

public extension Library {

    /// The library entry for one credit, or nil if the provider lacks it.
    func item(matching role: KnownRole) -> MediaItem? {
        item(matching: role.asDiscoveryTitle)
    }

    /// Every credit the library carries, keyed by the credit's TMDB id.
    ///
    /// Resolved in one pass because the sheet needs to know what is playable
    /// before it draws anything — a poster that turns out to be tappable a
    /// second after it appears is worse than one that never claimed to be.
    func items(matching roles: [KnownRole]) -> [Int: MediaItem] {
        var found: [Int: MediaItem] = [:]
        for role in roles {
            guard !Task.isCancelled else { break }
            if let item = item(matching: role) { found[role.id] = item }
        }
        return found
    }
}
