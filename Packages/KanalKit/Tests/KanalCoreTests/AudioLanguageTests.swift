import Foundation
import Testing
@testable import KanalCore

/// Starting a child's film in a language they can follow.
///
/// The failure this guards against is quiet in both directions: a Norwegian
/// dub that exists but is never selected leaves a five-year-old watching a
/// film in English, and a preference applied to a grown-up turns a foreign
/// film into a dub nobody asked for.
@Suite("Choosing the audio language")
struct AudioLanguagePreferenceTests {

    static func track(_ id: String, _ name: String, _ code: String? = nil) -> PlaybackTrack {
        PlaybackTrack(id: id, name: name, languageCode: code)
    }

    static let dubbed = [
        track("1", "English", "en"),
        track("2", "Norwegian", "nb"),
        track("3", "Swedish", "sv"),
    ]

    @Test("A Norwegian profile gets the Norwegian track")
    func picksTheDub() {
        let chosen = AudioLanguagePreference.track(
            matching: "nb", in: Self.dubbed, selected: "1"
        )
        #expect(chosen?.id == "2")
    }

    /// The default, and the one most grown-ups want.
    @Test("No preference changes nothing")
    func noPreference() {
        #expect(AudioLanguagePreference.track(
            matching: nil, in: Self.dubbed, selected: "1"
        ) == nil)
    }

    @Test("A film without the language is left exactly as it is")
    func noSuchTrack() {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", "German", "de")]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    /// A file whose own default is already Norwegian must not be nudged onto a
    /// second Norwegian track — the switch would be visible and pointless.
    @Test("A correct track already playing is left alone")
    func alreadyCorrect() {
        let tracks = [Self.track("1", "Norsk", "nb"), Self.track("2", "Norwegian", "nor")]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    /// Providers label the same dub `nor`, `no`, `nb` or `nn` more or less at
    /// random, and all four mean "this is in Norwegian" to the person watching.
    @Test("Every spelling of Norwegian counts", arguments: ["nor", "no", "nb", "nn", "nb-NO"])
    func norwegianFamily(code: String) {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", "Dub", code)]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "2")
    }

    /// Norwegian is the only family the app folds. Danish and Swedish are
    /// close enough to read but not close enough to substitute.
    @Test("Neighbouring languages are not substituted", arguments: ["da", "sv", "is"])
    func neighboursAreNotNorwegian(code: String) {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", "Nordic", code)]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    /// The bibliographic codes an old encoder writes. Foundation knows these;
    /// a hand-written table in this file would not.
    @Test("Three-letter codes are understood", arguments: [
        ("ger", "de"), ("fre", "fr"), ("dut", "nl"), ("swe", "sv"), ("spa", "es"),
    ])
    func bibliographicCodes(raw: String, expected: String) {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", "Dub", raw)]
        #expect(
            AudioLanguagePreference.track(matching: expected, in: tracks, selected: "1")?.id == "2"
        )
    }

    /// Encoders leave the language field empty often enough that the name is
    /// worth reading — VLC in particular hands back only a name.
    @Test("A language written into the name is read", arguments: [
        "Norwegian", "Norsk", "Track 2 - [nor]", "Audio: Norwegian (dub)",
    ])
    func readsTheName(name: String) {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", name, nil)]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "2")
    }

    /// The trap in reading names: a substring match would find "no" inside
    /// "Nordic" and hand a child a language nobody asked for.
    @Test("A name that merely contains the letters is not a match", arguments: [
        "Nordic Commentary", "Nothing", "Snowboarding",
    ])
    func refusesSubstrings(name: String) {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", name, nil)]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    @Test("An empty track list is not an error")
    func noTracks() {
        #expect(AudioLanguagePreference.track(matching: "nb", in: [], selected: nil) == nil)
    }

    /// Undetermined is what a file says when it does not know, and it is not
    /// an invitation to guess.
    @Test("Undetermined tracks are never chosen")
    func undetermined() {
        let tracks = [Self.track("1", "English", "en"), Self.track("2", "Track 2", "und")]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    @Test("The offered list leads with the languages the app speaks")
    func offered() {
        let codes = AudioLanguagePreference.offered(first: ["nb-NO", "en-GB"])
        #expect(codes.prefix(2) == ["nb", "en"])
        #expect(Set(codes).count == codes.count, "no language is offered twice")
        #expect(codes.allSatisfy { $0.count == 2 })
    }
}

/// A child's profile arrives with the sound already set; a grown-up's does not.
@Suite("Which profiles get a language by default")
struct ProfileAudioDefaultTests {

    @Test("A new child's profile starts on the household's language")
    func childHasOne() {
        let child = Profile.makeChild(named: "Barn", maturity: .nine)
        #expect(child.isRestricted)
        #expect(child.preferredAudioLanguage == AudioLanguagePreference.deviceDefault)
    }

    /// Most grown-ups want the language the film was made in, so nothing is
    /// chosen for them.
    @Test("A grown-up's profile does not")
    func grownUpHasNone() {
        #expect(Profile(name: "Meg", maturity: .adult).preferredAudioLanguage == nil)
        #expect(Profile.makeOwner(named: "Meg").preferredAudioLanguage == nil)
    }

    /// A household that already had children's profiles before this existed
    /// is the case the feature is *for*. Leaving those on the original
    /// language would mean the setting only ever reached profiles made after
    /// the update.
    @Test("A child's profile saved before this existed gets the language")
    func migratesOlderChild() throws {
        let json = Data("""
        {"id":"9E3C0A6C-1D2E-4F5A-9B8C-0D1E2F3A4B5C","name":"Barn","maturity":9,
         "allowedCategories":["Kids"],"allowedTitleKeys":[],"blockedTitleKeys":[]}
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.maturity == .nine)
        #expect(profile.preferredAudioLanguage == AudioLanguagePreference.deviceDefault)
    }

    @Test("A grown-up's older profile is left on the original language")
    func doesNotMigrateGrownUps() throws {
        let json = Data("""
        {"id":"1E3C0A6C-1D2E-4F5A-9B8C-0D1E2F3A4B5C","name":"Meg","maturity":18,
         "allowedCategories":[],"allowedTitleKeys":[],"blockedTitleKeys":[]}
        """.utf8)
        #expect(try JSONDecoder().decode(Profile.self, from: json)
            .preferredAudioLanguage == nil)
    }

    /// The distinction the custom encoder exists to preserve: a parent who
    /// deliberately picks "original language" for their child must not have
    /// that undone by the migration on the next launch.
    @Test("Choosing the original language for a child sticks")
    func explicitOriginalSurvives() throws {
        var child = Profile.makeChild(named: "Barn", maturity: .six)
        child.preferredAudioLanguage = nil
        let data = try JSONEncoder().encode(child)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("preferredAudioLanguage"), "the choice must be written down")
        #expect(try JSONDecoder().decode(Profile.self, from: data)
            .preferredAudioLanguage == nil)
    }

    @Test("The choice survives a round trip")
    func roundTrip() throws {
        var profile = Profile.makeChild(named: "Barn", maturity: .six)
        profile.preferredAudioLanguage = "nb"
        let decoded = try JSONDecoder().decode(
            Profile.self, from: JSONEncoder().encode(profile)
        )
        #expect(decoded.preferredAudioLanguage == "nb")
    }
}

/// Editing a profile is cheap or very expensive depending on what changed, and
/// the difference has to be decided by the model rather than by each caller.
@Suite("Which edits narrow the library")
struct ProfileNarrowingTests {

    static let child = Profile.makeChild(named: "Barn", maturity: .nine)

    @Test("Cosmetic edits change nothing that must be recomputed")
    func cosmeticEdits() {
        var renamed = Self.child
        renamed.name = "Ola"
        renamed.symbolName = "star.fill"
        renamed.colorIndex = 4
        renamed.preferredAudioLanguage = "sv"
        #expect(!Self.child.narrows(differentlyThan: renamed))
    }

    @Test("A tightened age limit does")
    func ageLimit() {
        var stricter = Self.child
        stricter.maturity = .six
        #expect(Self.child.narrows(differentlyThan: stricter))
    }

    @Test("So does every change to what a grown-up let through")
    func approvals() {
        var withCategory = Self.child
        withCategory.allowedCategories.insert("Kids")
        #expect(Self.child.narrows(differentlyThan: withCategory))

        var withTitle = Self.child
        withTitle.allowedTitleKeys.insert("bluey|2018")
        #expect(Self.child.narrows(differentlyThan: withTitle))

        var withBlock = Self.child
        withBlock.blockedTitleKeys.insert("bluey|2018")
        #expect(Self.child.narrows(differentlyThan: withBlock))
    }
}

/// Every audio track name a real provider actually served.
///
/// Taken verbatim from fourteen children's films on Magnus's own panel, probed
/// 2026-08-30. The point of this suite is that the shapes are not consistent
/// even within one provider's Disney catalogue, so nothing here is invented.
@Suite("Track names a real provider serves")
struct RealTrackNameTests {

    static func track(_ id: String, _ name: String, _ code: String?) -> PlaybackTrack {
        PlaybackTrack(id: id, name: name, languageCode: code)
    }

    /// Elio, Camp Rock 3, Toy Story, Coco — the English-name shape.
    @Test("Elio and Camp Rock 3 name their tracks in English")
    func englishNames() {
        let tracks = [
            Self.track("1", "English", "eng"),
            Self.track("2", "Danish", "dan"),
            Self.track("3", "German", "ger"),
            Self.track("4", "Finnish", "fin"),
            Self.track("5", "Norwegian", "nor"),
            Self.track("6", "Polish", "pol"),
            Self.track("7", "Swedish", "swe"),
            Self.track("8", "Turkish", "tur"),
        ]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "5")
        #expect(AudioLanguagePreference.track(matching: "de", in: tracks, selected: "1")?.id == "3")
        #expect(AudioLanguagePreference.track(matching: "pl", in: tracks, selected: "1")?.id == "6")
    }

    /// Camp Rock, Moana, Encanto, Zootopia, Wish, Turning Red, Paddington 2 —
    /// each language named in itself.
    @Test("Moana and Encanto name them in their own language")
    func nativeNames() {
        let tracks = [
            Self.track("1", "English", "eng"),
            Self.track("2", "Dansk", "dan"),
            Self.track("3", "Suomi", "fin"),
            Self.track("4", "Íslenska", "ice"),
            Self.track("5", "Norsk", "nor"),
            Self.track("6", "Svenska", "swe"),
            Self.track("7", "Türkçe", "tur"),
        ]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "5")
        #expect(AudioLanguagePreference.track(matching: "is", in: tracks, selected: "1")?.id == "4")
        #expect(AudioLanguagePreference.track(matching: "tr", in: tracks, selected: "1")?.id == "7")
    }

    /// The same names with the language field empty, which is what an encoder
    /// that only filled in the title leaves behind.
    @Test("The names alone are enough when no code was declared", arguments: [
        ("Norwegian", "nb"), ("Norsk", "nb"), ("Dansk", "da"), ("Svenska", "sv"),
        ("Suomi", "fi"), ("Íslenska", "is"), ("Türkçe", "tr"), ("Polski", "pl"),
    ])
    func namesWithoutCodes(name: String, expected: String) {
        let tracks = [Self.track("1", "English", "eng"), Self.track("2", name, nil)]
        #expect(
            AudioLanguagePreference.track(matching: expected, in: tracks, selected: "1")?.id == "2"
        )
    }

    /// Paddington 2 and Shaun the Sheep label the English track with a locale
    /// tag rather than a name.
    @Test("A locale tag is read as a language")
    func localeTag() {
        let tracks = [Self.track("1", "en-GB", nil), Self.track("2", "Norsk", nil)]
        #expect(AudioLanguagePreference.track(matching: "en", in: tracks, selected: "2")?.id == "1")
    }

    /// The Lion King and Inside Out 2: every track is called "Stereo". The
    /// name carries nothing, and the declared code is all there is.
    @Test("A film that names no language at all still works from its codes")
    func stereoTitles() {
        let tracks = [
            Self.track("1", "Stereo", "dan"),
            Self.track("2", "Stereo", "eng"),
            Self.track("3", "Stereo", "fin"),
            Self.track("4", "Stereo", "nor"),
            Self.track("5", "Stereo", "swe"),
        ]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "2")?.id == "4")
    }

    /// And the same film with the codes stripped is genuinely unanswerable —
    /// which must read as "leave it alone", never as a guess.
    @Test("With neither codes nor names, nothing is chosen")
    func stereoWithoutCodes() {
        let tracks = (1...5).map { Self.track("\($0)", "Stereo", nil) }
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    /// Shaun the Sheep Movie carries one English track and nothing else. The
    /// commonest outcome, and it has to be silent.
    @Test("A film with only English is left as it is")
    func onlyEnglish() {
        let tracks = [Self.track("1", "en-GB", "eng")]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    /// Not from this provider, but the shapes other panels use.
    @Test("Codes and extras around the name do not hide it", arguments: [
        "Norwegian [nor]", "Track 5 - [nor]", "Norsk AC3 5.1", "5.1 Norwegian",
        "Norwegian (Dolby Digital)", "nor", "NO", "Audio - Norsk",
    ])
    func decoratedNames(name: String) {
        let tracks = [Self.track("1", "English", "eng"), Self.track("2", name, nil)]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "2")
    }

    /// The other half: names that look close and are not.
    @Test("Names that only resemble a language are refused", arguments: [
        "Stereo", "Nordic", "Nordic Mix", "Commentary", "Original", "Dolby Atmos",
        "Track 2", "Descriptive Audio", "5.1", "Snowboarding",
    ])
    func refusedNames(name: String) {
        let tracks = [Self.track("1", "English", "eng"), Self.track("2", name, nil)]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1") == nil)
    }

    /// A commentary is in the language it is in, and is still not the track a
    /// child should land on.
    @Test("The plain track wins over a commentary in the same language")
    func plainBeforeCommentary() {
        let tracks = [
            Self.track("1", "English", "eng"),
            Self.track("2", "Norwegian Commentary", "nor"),
            Self.track("3", "Norwegian", "nor"),
        ]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "3")
    }

    @Test("An audio description is treated the same way")
    func plainBeforeAudioDescription() {
        let tracks = [
            Self.track("1", "English", "eng"),
            Self.track("2", "Norsk syntolkning", "nor"),
            Self.track("3", "Norsk", "nor"),
        ]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "3")
    }

    /// If the only Norwegian there is happens to be a commentary, it is still
    /// closer to what was asked for than leaving the film in English.
    @Test("A commentary is used only when it is the sole match")
    func commentaryAsLastResort() {
        let tracks = [Self.track("1", "English", "eng"), Self.track("2", "Norsk kommentar", "nor")]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "2")
    }

    /// And a viewer already parked on a Norwegian commentary is nudged onto
    /// the plain track, because they did not choose it — the file did.
    @Test("A side track playing by default is corrected")
    func correctsADefaultedSideTrack() {
        let tracks = [
            Self.track("1", "Norwegian Commentary", "nor"),
            Self.track("2", "Norwegian", "nor"),
        ]
        #expect(AudioLanguagePreference.track(matching: "nb", in: tracks, selected: "1")?.id == "2")
    }
}
