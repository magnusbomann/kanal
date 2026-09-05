import Foundation

/// Which audio track to start on, when someone has said they want one.
///
/// Off by default, and deliberately so. Most grown-ups watching a foreign film
/// want the language it was made in — switching them to a dub because their
/// phone is set to Norwegian would be the app overruling a taste it was never
/// asked about. A child is the other way round: a seven-year-old cannot follow
/// subtitles, and a Norwegian dub that exists in the file but is not selected
/// is the same to them as no film at all.
///
/// So the preference lives on the profile: set for a child when the profile is
/// made, and something a grown-up turns on for themselves if they want it.
public enum AudioLanguagePreference {

    /// The track to switch to, or nil to leave the stream's own choice alone.
    ///
    /// Nil covers three different "do nothing"s — no preference set, no track
    /// in that language, and a matching track already playing — because the
    /// caller does the same thing in all three, and distinguishing them would
    /// only invite someone to act on the difference.
    public static func track(
        matching preference: String?,
        in tracks: [PlaybackTrack],
        selected: PlaybackTrack.ID?
    ) -> PlaybackTrack? {
        guard let wanted = family(of: preference), !tracks.isEmpty else { return nil }

        // Already right: a file whose default track is the wanted language
        // must not be "corrected" onto a second copy of the same language.
        if let selected, let current = tracks.first(where: { $0.id == selected }),
           family(of: language(of: current)) == wanted, !isSideTrack(current) {
            return nil
        }

        let matching = tracks.filter { family(of: language(of: $0)) == wanted }
        // The ordinary track ahead of a commentary or an audio description —
        // both are in the right language and both are the wrong thing to play.
        return matching.first { !isSideTrack($0) } ?? matching.first
    }

    /// What language a track is in, from whatever the file bothered to say.
    ///
    /// The declared code first. Encoders leave it empty often enough — and VLC
    /// hands back names like "Track 1 - [nor]" or plain "Norwegian" — that the
    /// name is worth reading when the code is missing.
    static func language(of track: PlaybackTrack) -> String? {
        if let code = track.languageCode, !code.isEmpty { return code }
        return languageInName(track.name)
    }

    /// A language written into a track's name, as a code.
    ///
    /// Measured across fourteen children's films on a real provider, this one
    /// field held four different shapes:
    ///
    /// | what the file said | films |
    /// | --- | --- |
    /// | the English name — `Norwegian`, `Danish` | 6 |
    /// | its own name — `Norsk`, `Svenska`, `Íslenska`, `Türkçe` | 6 |
    /// | a locale tag — `en-GB` | 2 |
    /// | not a language at all — `Stereo` | 2 |
    ///
    /// So all of them are tried. The last row is why this stays a *fallback*:
    /// two of fourteen name no language whatsoever, and only the declared code
    /// saves them.
    static func languageInName(_ name: String) -> String? {
        let cleaned = SearchNormalizer.normalize(name)
        guard !cleaned.isEmpty else { return nil }
        let words = cleaned.split(separator: " ").map(String.init)

        // Names first, and whole words only. A bare code scanned early would
        // read the English word "is" in "Commentary is Norwegian" as Icelandic,
        // and "no" is an ordinary word in several of these languages.
        if let spelled = spellings[cleaned] { return spelled }
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let phrase = words[start..<(start + length)].joined(separator: " ")
                if let spelled = spellings[phrase] { return spelled }
            }
        }

        // Then the title as a locale tag, which is what `en-GB` is.
        if let tag = canonical(name) { return tag }

        // Then a three-letter code standing alone: `nor`, `dan`, `swe`. VLC
        // writes these in brackets, and three letters cannot be mistaken for
        // an ordinary word the way `is` and `no` can.
        for word in words where word.count == 3 {
            if let code = canonical(word) { return code }
        }
        // Two letters only when they are the whole title. Anything looser
        // starts a child's film in a language nobody chose.
        if words.count == 1, words[0].count == 2 { return canonical(words[0]) }
        return nil
    }

    /// Tracks nobody means when they ask for a language.
    ///
    /// A Norwegian audio description *is* in Norwegian and is emphatically not
    /// the track to start a film on — someone talks over it throughout. Same
    /// for a director's commentary. Neither appears in the measured provider's
    /// files, but it costs one comparison to never hand a child one.
    static func isSideTrack(_ track: PlaybackTrack) -> Bool {
        let words = Set(SearchNormalizer.normalize(track.name).split(separator: " ").map(String.init))
        return !words.isDisjoint(with: sideTrackWords)
    }

    private static let sideTrackWords: Set<String> = [
        "commentary", "kommentar", "kommentarspor", "audiodescription",
        "description", "descriptive", "syntolkning", "synstolkning", "beskrivende",
        "narration", "narrated", "ad", "sdh", "karaoke", "instrumental",
    ]

    /// Every language name the app can recognise, mapped to its code.
    ///
    /// Built once. The alternative asked Foundation to spell out several
    /// hundred languages on every track, which is a lot of work to do behind
    /// a play button.
    private static let spellings: [String: String] = {
        var table: [String: String] = [:]
        let english = Locale(identifier: "en")
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            // English, the reader's own language, and — the one that matters
            // most here — the language's name for itself. Six of the fourteen
            // measured films label the track `Norsk`, `Svenska` or `Suomi`,
            // which neither of the first two would find on a phone set to
            // anything else.
            for locale in [english, Locale.current, Locale(identifier: code)] {
                guard let name = locale.localizedString(forLanguageCode: code) else { continue }
                let key = SearchNormalizer.normalize(name)
                // Longer than two letters so a *name* can never collide with a
                // code, and first-wins so the canonical spelling holds.
                guard key.count > 2, table[key] == nil else { continue }
                table[key] = code
            }
        }
        return table
    }()

    /// Folds a language onto the one identifier worth comparing.
    ///
    /// Foundation already knows that `nor`, `no` and `nb-NO` are all Norwegian
    /// bokmål and that the bibliographic `ger` is German, so the mapping is
    /// its job rather than a table here that would go stale.
    static func canonical(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let code = Locale(identifier: raw).language.languageCode?.identifier,
              code.count == 2, code != "un"
        else { return nil }
        return code
    }

    /// Bokmål, nynorsk and plain "Norwegian" are one language to a viewer.
    ///
    /// A provider's Norwegian dub is labelled `nor`, `nb` or `nn` more or less
    /// at random, and refusing one because a profile asked for another would
    /// hide the exact track this feature exists to find. Norwegian is the only
    /// pair the app ships that behaves this way.
    static func family(of raw: String?) -> String? {
        guard let code = canonical(raw) else { return nil }
        return ["nb", "nn", "no"].contains(code) ? "no" : code
    }

    /// Languages worth offering, most likely first.
    ///
    /// The ones the app itself speaks. A list of every language Unicode knows
    /// would be a scrolling exercise, and a track in a language the interface
    /// cannot even name is not one anybody is looking for.
    public static func offered(
        first preferred: [String] = Locale.preferredLanguages
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for identifier in preferred + supported {
            guard let code = canonical(identifier), seen.insert(code).inserted else { continue }
            result.append(code)
        }
        return result
    }

    /// Matches the interface languages Kanal is translated into.
    private static let supported = [
        "nb", "en", "sv", "da", "fi", "de", "nl", "fr", "es", "it", "pt-BR", "pl", "tr", "ar",
    ]

    /// The language a new child's profile starts on: whatever the household
    /// already reads the app in.
    public static var deviceDefault: String? {
        canonical(Locale.preferredLanguages.first) ?? canonical(Locale.current.identifier)
    }

    /// How to name one in a picker.
    public static func displayName(_ code: String, in locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code.uppercased()
    }
}
