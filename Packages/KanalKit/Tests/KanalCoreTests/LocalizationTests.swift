import Foundation
import Testing
@testable import KanalCore

@Suite("Localization")
struct LocalizationTests {

    /// Runs the repository's localization check as part of the normal test run.
    ///
    /// Keeping it here rather than in a build phase means it gates the same
    /// command everything else does, and a new untranslated string fails
    /// immediately instead of at translation-hand-off time.
    @Test("Every user-facing string is declared and translated")
    func lintPasses() throws {
        let script = repositoryRoot.appending(path: "Scripts/check-localization.py")
        try #require(FileManager.default.fileExists(atPath: script.path))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "\(output)")
    }

    /// Guards the trap that makes a package's strings silently stay English:
    /// resolving against `Bundle.main` instead of `Bundle.module`.
    @Test("Core strings resolve out of the package bundle, not the app's")
    func resolvesFromPackageBundle() {
        let resolved = String(localized: CoreStrings.liveTV)
        #expect(resolved != "kind.liveTV", "String fell back to its key — wrong bundle")
        #expect(!resolved.isEmpty)
    }

    @Test("Plural-aware counts are declared with the number in the key")
    func pluralKeys() {
        // A key without the number cannot carry plural rules at all.
        let one = String(localized: CoreStrings.httpError(1))
        let many = String(localized: CoreStrings.httpError(404))
        #expect(one != many)
    }

    @Test("Metadata languages follow the device, not the developer")
    func metadataLanguagesFollowDevice() {
        let german = PreferredLanguages.codes(for: ["de-DE"])
        #expect(german.first == "de")
        // English is always present: provider listings are written in it.
        #expect(german.contains("en"))

        let norwegian = PreferredLanguages.codes(for: ["nb-NO"])
        #expect(norwegian.first == "nb")
        // Both written forms, because Wikidata labels differ between them.
        #expect(norwegian.contains("nn"))
        #expect(norwegian.contains("en"))
    }

    @Test("A single-language API tag is built from the locale")
    func primaryTag() {
        #expect(PreferredLanguages.primaryTag(for: Locale(identifier: "nb_NO")) == "nb-NO")
        #expect(PreferredLanguages.primaryTag(for: Locale(identifier: "de_DE")) == "de-DE")
    }

    private var repositoryRoot: URL {
        // Tests/KanalCoreTests/…  ->  Packages/KanalKit  ->  Kanal
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
