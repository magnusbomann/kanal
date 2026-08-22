import Foundation
import Testing
@testable import KanalCore

/// The malformations real IPTV panels emit. Every case here killed a strict
/// parser before the repair ladder existed.
@Suite("Malformed provider XML")
struct XMLRepairTests {

    static func guide(body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="a"><display-name>\(body)</display-name></channel>
          <programme start="20260101120000 +0000" stop="20260101130000 +0000" channel="a">
            <title>\(body)</title>
          </programme>
        </tv>
        """.utf8)
    }

    func parse(_ data: Data) -> XMLTVParser.ParseResult {
        XMLTVParser(
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 4_000_000_000)
        ).parseDetailed(data)
    }

    @Test("A strict parser really does reject each of these", arguments: [
        "Cops & Robbers",
        "Cops&nbsp;and Robbers",
        "Am&eacute;lie",
        "5 < 6",
    ])
    func inputsAreGenuinelyBroken(body: String) {
        #expect(XMLParser(data: Self.guide(body: body)).parse() == false)
    }

    @Test("Recovers a bare ampersand")
    func bareAmpersand() {
        let result = parse(Self.guide(body: "Cops & Robbers"))
        #expect(result.programmeCount == 1)
        #expect(result.repairs.contains(.bareAmpersands))
        #expect(result.guide.schedules["a"]?.programmes.first?.title == "Cops & Robbers")
    }

    @Test("Turns HTML entities into the characters they mean")
    func htmlEntities() {
        let result = parse(Self.guide(body: "Am&eacute;lie"))
        #expect(result.programmeCount == 1)
        #expect(result.repairs.contains(.undefinedEntities))
        #expect(result.guide.schedules["a"]?.programmes.first?.title == "Amélie")
    }

    @Test("Keeps the text of an entity it does not recognise")
    func unknownEntity() {
        let result = parse(Self.guide(body: "A &weirdthing; B"))
        let title = result.guide.schedules["a"]?.programmes.first?.title
        #expect(title == "A &weirdthing; B")
    }

    @Test("Escapes a stray less-than sign")
    func strayAngleBracket() {
        let result = parse(Self.guide(body: "5 < 6"))
        #expect(result.programmeCount == 1)
        #expect(result.repairs.contains(.strayAngleBrackets))
    }

    @Test("Strips control characters XML forbids")
    func controlCharacters() {
        var data = Self.guide(body: "AB")
        // Splice an illegal 0x1F into the title.
        if let range = data.range(of: Data("AB".utf8)) {
            data.replaceSubrange(range, with: Data([0x41, 0x1F, 0x42]))
        }
        let result = parse(data)
        #expect(result.programmeCount == 1)
        #expect(result.repairs.contains(.controlCharacters))
    }

    @Test("Reads Latin-1 that claims to be UTF-8")
    func mislabelledEncoding() {
        var data = Data(#"<?xml version="1.0" encoding="UTF-8"?><tv><channel id="a"><display-name>Am"#.utf8)
        data.append(0xE9) // é in Latin-1, invalid on its own in UTF-8
        data.append(contentsOf: Data("""
        lie</display-name></channel>
        <programme start="20260101120000 +0000" stop="20260101130000 +0000" channel="a"><title>X</title></programme>
        </tv>
        """.utf8))

        let result = parse(data)
        #expect(result.programmeCount == 1)
        #expect(result.repairs.contains(.encoding))
        #expect(result.guide.channelNames["a"] == "Amélie")
    }

    @Test("Recovers everything before a truncated download stops")
    func truncated() {
        let data = Data("""
        <tv>
          <channel id="a"><display-name>A</display-name></channel>
          <programme start="20260101120000 +0000" stop="20260101130000 +0000" channel="a">
            <title>Complete</title>
          </programme>
          <programme start="20260101130000 +0000" stop="2026010
        """.utf8)

        let result = parse(data)
        #expect(result.repairs.contains(.truncation))
        #expect(result.programmeCount == 1, "the complete programme should survive")
        #expect(result.guide.schedules["a"]?.programmes.first?.title == "Complete")
    }

    @Test("A clean guide is never touched")
    func cleanInputUntouched() {
        let result = parse(Self.guide(body: "Nothing wrong here"))
        #expect(result.repairs.isEmpty)
        #expect(result.isPartial == false)
        #expect(XMLRepair.repair(Self.guide(body: "Nothing wrong here")) == nil)
    }

    @Test("Valid entities and numeric references survive")
    func validEntitiesSurvive() {
        let (text, fix) = XMLRepair.repairEntities("A &amp; B &#233; C &#x2014; D")
        #expect(fix == nil)
        #expect(text == "A &amp; B &#233; C &#x2014; D")
    }

    @Test("Parsing twice on one instance does not double up")
    func noStateLeak() {
        let parser = XMLTVParser(
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 4_000_000_000)
        )
        let data = Self.guide(body: "Fine")
        #expect(parser.parse(data).programmeCount == 1)
        #expect(parser.parse(data).programmeCount == 1)
    }
}

@Suite("Reporting bad provider data")
struct DiagnosticsTests {

    @Test("A clean load reports nothing")
    func cleanLoadIsSilent() {
        var diagnostics = SourceDiagnostics()
        diagnostics.guideProgrammes = 500
        diagnostics.channelsWithID = 100
        diagnostics.guideChannelsMatched = 95
        #expect(diagnostics.hasFindings == false)
    }

    @Test("Skipped playlist entries are reported")
    func skippedLines() {
        var diagnostics = SourceDiagnostics()
        diagnostics.skippedPlaylistLines = 3
        #expect(diagnostics.hasFindings)
    }

    @Test("A repaired guide is reported rather than passed off as clean")
    func repairIsReported() {
        var diagnostics = SourceDiagnostics()
        diagnostics.guideRepairs = [.bareAmpersands]
        #expect(diagnostics.hasFindings)
    }

    @Test("A truncated guide is reported")
    func partialIsReported() {
        var diagnostics = SourceDiagnostics()
        diagnostics.guideIsPartial = true
        #expect(diagnostics.hasFindings)
    }

    /// The failure that is otherwise invisible: a guide that parsed perfectly
    /// but describes channels nobody has.
    @Test("Poor coverage is reported even when nothing failed")
    func poorCoverage() {
        var diagnostics = SourceDiagnostics()
        diagnostics.guideProgrammes = 900
        diagnostics.channelsWithID = 100
        diagnostics.guideChannelsMatched = 12
        #expect(diagnostics.hasFindings)
        #expect(Int(diagnostics.guideCoverage * 100) == 12)
    }

    @Test("Coverage is zero rather than undefined without channel ids")
    func noChannelIDs() {
        #expect(SourceDiagnostics().guideCoverage == 0)
    }
}
