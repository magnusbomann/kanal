import Foundation

/// One selectable audio or subtitle track.
///
/// Matroska files routinely carry several of each — an original-language track
/// beside a dubbed one, forced subtitles beside full ones — and picking between
/// them is most of what a person does in a player after pressing play.
public struct PlaybackTrack: Identifiable, Sendable, Hashable {
    public let id: String
    /// What the file calls it, cleaned up for display.
    public let name: String
    /// BCP-47 code when the file declares one.
    public let languageCode: String?

    public init(id: String, name: String, languageCode: String? = nil) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
    }

    /// The name to show, preferring the language over whatever the encoder
    /// typed. "Norsk" beats "Track 2 [nor]".
    public var displayName: String {
        guard let languageCode,
              let localized = Locale.current.localizedString(forLanguageCode: languageCode),
              !localized.isEmpty
        else { return name }

        // Keep any extra detail the file offered, like "Commentary".
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        if cleaned.localizedCaseInsensitiveContains(localized) || cleaned.count < 3 {
            return localized.localizedCapitalized
        }
        return "\(localized.localizedCapitalized) · \(cleaned)"
    }
}
