import Foundation
import Testing
@testable import KanalCore

@Suite("Category names")
struct CategoryLocalizerTests {

    @Test("Recognises the recurring genre vocabulary", arguments: [
        "Entertainment", "entertainment", "ENTERTAINMENT",
        "Comedy", "Comedies", "Documentary", "Documentaries",
        "Sport", "Sports", "Kids", "Children", "News", "Music",
        "Cartoons", "Anime", "Sci-Fi", "Science Fiction",
    ])
    func recognisesGenres(name: String) {
        #expect(CategoryLocalizer.isRecognized(name), "\(name) should be a known genre")
    }

    @Test("Recognises countries by name and by code", arguments: [
        "Norway", "Norge", "Sweden", "Sverige", "Germany", "Deutschland",
        "United Kingdom", "NO", "SE", "DE", "GB",
    ])
    func recognisesCountries(name: String) {
        #expect(CategoryLocalizer.isRecognized(name), "\(name) should be a known country")
    }

    @Test("Passes an unrecognised name through untouched", arguments: [
        "Viaplay Sport 1", "Nordic Premium 4K", "Bein Sports MENA", "Kanal 5 HD",
    ])
    func passesThrough(name: String) {
        #expect(CategoryLocalizer.display(name) == name)
        #expect(!CategoryLocalizer.isRecognized(name))
    }

    /// Asserted against the parts rather than against a literal translation:
    /// the test process resolves its own language, so hardcoding "Animasjon"
    /// would test the runner's locale instead of the code.
    @Test("Translates each half of a packed genre field")
    func compound() {
        // CategoryNormalizer turns "Animation;comedy" into "Animation & Comedy".
        let compound = CategoryLocalizer.display("Animation & Comedy")
        let parts = [
            CategoryLocalizer.display("Animation"),
            CategoryLocalizer.display("Comedy"),
        ]
        #expect(compound == parts.joined(separator: " & "))
    }

    @Test("Unknown halves of a compound are left alone")
    func compoundPartlyUnknown() {
        #expect(CategoryLocalizer.display("Sport & Viasat 4") ==
                CategoryLocalizer.display("Sport") + " & Viasat 4")
    }

    @Test("Never returns an empty name")
    func neverEmpty() {
        #expect(CategoryLocalizer.display("") == "")
        #expect(!CategoryLocalizer.display("Sport").isEmpty)
    }

    /// The property that keeps someone's filters working when they change the
    /// language of their phone.
    @Test("Translation is display-only and does not become identity")
    func displayOnly() {
        let raw = "Entertainment"
        let items = [
            MediaItem(id: "1", kind: .liveTV, title: "A", rawTitle: "A",
                      streamURL: URL(string: "http://a/1.m3u8")!, category: raw),
        ]
        let library = Library(items: items)
        // The bucket is still keyed by what the provider wrote.
        #expect(library.channelCategories.first?.name == raw)
        #expect(library.channels.first?.category == raw)
    }
}
