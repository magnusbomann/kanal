import Foundation

/// One person who uses this app.
///
/// Modelled on what a household actually is: one or two grown-ups who set
/// things up, and children who only ever see what a grown-up let through.
/// The difference between the two is a single fact — `maturity` — and every
/// restriction in the app is derived from it rather than stored as a pile of
/// independent switches that can disagree with each other.
public struct Profile: Identifiable, Codable, Sendable, Hashable {

    public let id: UUID
    public var name: String
    /// SF Symbol used as the avatar. Symbols rather than photos: no camera
    /// permission, no upload, nothing to sync, and it looks right on a TV.
    public var symbolName: String
    /// Index into `Profile.avatarColors`, kept as a number so the palette can
    /// change without rewriting everyone's saved profile.
    public var colorIndex: Int
    /// The highest age limit this profile may watch. `.adult` means no limit
    /// and marks this as a grown-up's profile.
    public var maturity: MaturityRating
    /// Categories a grown-up has explicitly approved, in the provider's own
    /// spelling — the same key `LibraryFilter` and favourites use, so an
    /// approval survives a change of interface language.
    public var allowedCategories: Set<String>
    /// Individual entries approved one at a time, by stable id.
    public var allowedItemIDs: Set<String>
    /// Entries pulled back out of an approved category.
    public var blockedItemIDs: Set<String>
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "person.fill",
        colorIndex: Int = 0,
        maturity: MaturityRating = .adult,
        allowedCategories: Set<String> = [],
        allowedItemIDs: Set<String> = [],
        blockedItemIDs: Set<String> = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorIndex = colorIndex
        self.maturity = maturity
        self.allowedCategories = allowedCategories
        self.allowedItemIDs = allowedItemIDs
        self.blockedItemIDs = blockedItemIDs
        self.createdAt = createdAt
    }

    /// Decoded field by field so a later addition cannot make an existing
    /// household's profiles unreadable — the same discipline `WatchState` uses,
    /// for the same reason.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "person.fill"
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        // A profile whose age limit failed to decode is treated as a child's,
        // not a grown-up's. Failing safe costs a grown-up one trip to settings.
        maturity = try container.decodeIfPresent(MaturityRating.self, forKey: .maturity) ?? .allAges
        allowedCategories = try container.decodeIfPresent(
            Set<String>.self, forKey: .allowedCategories
        ) ?? []
        allowedItemIDs = try container.decodeIfPresent(
            Set<String>.self, forKey: .allowedItemIDs
        ) ?? []
        blockedItemIDs = try container.decodeIfPresent(
            Set<String>.self, forKey: .blockedItemIDs
        ) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// Whether anything is withheld from this profile.
    public var isRestricted: Bool { maturity != .adult }

    /// Favourites and history are per person, so a child's cartoons never turn
    /// up in a parent's Continue watching — and, more importantly, the reverse.
    public var watchStateFileName: String { "watch-state-\(id.uuidString).json" }

    /// The name shown when a profile was saved with only whitespace.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: CoreStrings.profileUnnamed) : trimmed
    }

    // MARK: - Presets

    /// Avatar colours, as hex so `KanalUI` can resolve them without importing
    /// SwiftUI into the model layer.
    public static let avatarColors: [UInt32] = [
        0xFF7A4D, 0x4DA3FF, 0x39C56B, 0xB579F5, 0xFFC24D, 0xFF5E8A,
    ]

    /// Avatar symbols offered in the editor. Chosen to read at TV distance.
    public static let avatarSymbols: [String] = [
        "person.fill", "face.smiling.inverse", "teddybear.fill", "gamecontroller.fill",
        "star.fill", "bolt.fill", "pawprint.fill", "leaf.fill", "airplane", "guitars.fill",
        "soccerball", "moon.stars.fill",
    ]

    public var avatarColor: UInt32 {
        Self.avatarColors[abs(colorIndex) % Self.avatarColors.count]
    }

    /// The profile created for someone who already had a library before
    /// profiles existed. It is a grown-up's: taking access away from the person
    /// who set the app up would be a bug, not a safety feature.
    public static func makeOwner(named name: String) -> Profile {
        Profile(name: name, symbolName: "person.fill", colorIndex: 0, maturity: .adult)
    }
}
