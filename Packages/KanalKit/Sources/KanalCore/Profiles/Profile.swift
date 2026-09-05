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
    /// Individual titles a grown-up approved one at a time.
    ///
    /// Keyed by `RatingKey`, not by entry id. An entry's id is built from its
    /// stream URL and panels reissue those, so a token rotation would silently
    /// drop every decision a parent had made. The title and year do not rotate.
    public var allowedTitleKeys: Set<String>
    /// Titles pulled back out of an approved category.
    public var blockedTitleKeys: Set<String>
    /// Language to start the sound in, when the file offers it. Nil means the
    /// one the film was made in — see `AudioLanguagePreference` for why that
    /// is the default for a grown-up and not for a child.
    public var preferredAudioLanguage: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "person.fill",
        colorIndex: Int = 0,
        maturity: MaturityRating = .adult,
        allowedCategories: Set<String> = [],
        allowedTitleKeys: Set<String> = [],
        blockedTitleKeys: Set<String> = [],
        preferredAudioLanguage: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorIndex = colorIndex
        self.maturity = maturity
        self.allowedCategories = allowedCategories
        self.allowedTitleKeys = allowedTitleKeys
        self.blockedTitleKeys = blockedTitleKeys
        self.preferredAudioLanguage = preferredAudioLanguage
        self.createdAt = createdAt
    }

    /// A child's profile, with the sound already set to the language the
    /// household reads the app in.
    ///
    /// Chosen here rather than left to the editor because it is the thing a
    /// parent would never think to look for and would notice immediately if it
    /// were missing: a five-year-old cannot read subtitles, so a film that
    /// starts in English is a film they cannot watch. A grown-up creating the
    /// profile can still change it, and a title with no such track is left
    /// exactly as the file intended.
    public static func makeChild(
        named name: String,
        maturity: MaturityRating,
        symbolName: String = "teddybear.fill",
        colorIndex: Int = 0
    ) -> Profile {
        Profile(
            name: name,
            symbolName: symbolName,
            colorIndex: colorIndex,
            maturity: maturity,
            preferredAudioLanguage: AudioLanguagePreference.deviceDefault
        )
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
        allowedTitleKeys = try container.decodeIfPresent(
            Set<String>.self, forKey: .allowedTitleKeys
        ) ?? []
        blockedTitleKeys = try container.decodeIfPresent(
            Set<String>.self, forKey: .blockedTitleKeys
        ) ?? []
        // Key presence, not value, because the two nils mean opposite things.
        //
        // A profile saved before this field existed has made no choice, and a
        // child who has made no choice should get the household's language —
        // that is the whole point of the feature, and it must reach the
        // children who already have profiles. A parent who has since picked
        // "original language" stores an explicit null, which the custom
        // encoder below guarantees is written, and that choice is kept.
        if container.contains(.preferredAudioLanguage) {
            preferredAudioLanguage = try container.decodeIfPresent(
                String.self, forKey: .preferredAudioLanguage
            )
        } else {
            preferredAudioLanguage = maturity == .adult
                ? nil
                : AudioLanguagePreference.deviceDefault
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// Spelled out because both `init(from:)` and `encode(to:)` are written by
    /// hand, which stops Swift synthesising them.
    private enum CodingKeys: String, CodingKey {
        case id, name, symbolName, colorIndex, maturity
        case allowedCategories, allowedTitleKeys, blockedTitleKeys
        case preferredAudioLanguage, createdAt
    }

    /// Written field by field so the audio choice is always present on disk.
    ///
    /// The synthesised encoder omits a nil optional, which would make "the
    /// parent chose the original language" indistinguishable from "this
    /// profile predates the setting" — and the decoder treats those two
    /// differently on purpose.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(colorIndex, forKey: .colorIndex)
        try container.encode(maturity, forKey: .maturity)
        try container.encode(allowedCategories, forKey: .allowedCategories)
        try container.encode(allowedTitleKeys, forKey: .allowedTitleKeys)
        try container.encode(blockedTitleKeys, forKey: .blockedTitleKeys)
        try container.encode(preferredAudioLanguage, forKey: .preferredAudioLanguage)
        try container.encode(createdAt, forKey: .createdAt)
    }

    /// Whether two versions of a profile would show a different library.
    ///
    /// A name, an avatar colour or an audio language changes nothing about
    /// what may be watched, and treating every edit as though it did meant
    /// renaming a profile re-filtered the whole catalogue and threw away a
    /// rating sweep that was part way through.
    public func narrows(differentlyThan other: Profile) -> Bool {
        maturity != other.maturity
            || allowedCategories != other.allowedCategories
            || allowedTitleKeys != other.allowedTitleKeys
            || blockedTitleKeys != other.blockedTitleKeys
    }

    /// Whether anything is withheld from this profile.
    public var isRestricted: Bool { maturity != .adult }

    /// The launch picker has no outgoing profile to protect. Gate the target
    /// as well, otherwise restarting the app bypasses a child's parental lock.
    public func requiresCodeForSelection(parentalCodeIsSet: Bool) -> Bool {
        parentalCodeIsSet && !isRestricted
    }

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
