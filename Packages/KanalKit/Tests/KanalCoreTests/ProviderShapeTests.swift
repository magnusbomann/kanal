import Foundation
import Testing
@testable import KanalCore

/// The shapes real panels and guides arrive in, which no specification describes.
@Suite("Provider answer shapes")
struct ProviderShapeTests {

    @Test("An empty section is empty, however the panel says it", arguments: ["[]", "{}", "false", "null", "", " \n"])
    func emptySection(body: String) {
        #expect(XtreamClient.entries(in: Data(body.utf8))?.isEmpty == true)
    }

    @Test("One broken entry does not discard the others")
    func strayElement() {
        let entries = XtreamClient.entries(in: Data(#"[{"stream_id":1},null,{"stream_id":2}]"#.utf8))
        #expect(entries?.count == 2)
    }

    @Test("A list keyed by position is still a list")
    func keyedList() {
        let entries = XtreamClient.entries(in: Data(#"{"0":{"stream_id":1},"1":{"stream_id":2}}"#.utf8))
        #expect(entries?.count == 2)
    }

    @Test("An error page or an error object is not an empty section", arguments: [
        "<html><body>502 Bad Gateway</body></html>",
        #"{"user_info":{"auth":0}}"#,
        #"{"error":"rate limited"}"#,
    ])
    func notAList(body: String) {
        #expect(XtreamClient.entries(in: Data(body.utf8)) == nil)
    }

    @Test("A gzipped guide inflates whole, whatever its size")
    func gunzip() throws {
        // 6 MB of repetitive XML compresses far past the old 12× first guess.
        let line = "<programme start=\"20260115203000 +0100\" channel=\"nrk1.no\"><title>Dagsrevyen</title></programme>\n"
        let original = Data(String(repeating: line, count: 60_000).utf8)
        let path = FileManager.default.temporaryDirectory.appending(path: "kanal-gunzip-\(UUID().uuidString).xml")
        try original.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) ; try? FileManager.default.removeItem(at: path.appendingPathExtension("gz")) }

        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = ["-k", path.path]
        try gzip.run()
        gzip.waitUntilExit()

        let compressed = try Data(contentsOf: path.appendingPathExtension("gz"))
        #expect(Gunzip.isGzipped(compressed))
        #expect(Gunzip.decode(compressed) == original)
        // Not gzip at all: handed back untouched.
        #expect(Gunzip.decode(original) == original)
    }
}
