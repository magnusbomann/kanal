import Foundation

/// What a playlist entry actually is. Kanal derives this automatically —
/// the user is never asked to sort their own playlist.
public enum MediaKind: String, Codable, Sendable, CaseIterable, Hashable {
    case liveTV
    case movie
    case series

    public var displayName: String {
        String(localized: displayNameResource)
    }

    public var displayNameResource: LocalizedStringResource {
        switch self {
        case .liveTV: CoreStrings.liveTV
        case .movie: CoreStrings.movies
        case .series: CoreStrings.series
        }
    }

    public var symbolName: String {
        switch self {
        case .liveTV: "dot.radiowaves.left.and.right"
        case .movie: "film.stack"
        case .series: "rectangle.stack"
        }
    }
}
