import Foundation
import Testing
@testable import KanalCore

@Suite("TV guide parsing")
struct XMLTVTests {

    static func guideXML(badAmpersand: Bool) -> Data {
        let title = badAmpersand ? "Cops & Robbers" : "Cops and Robbers"
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="tv2.no"><display-name>\(title)</display-name></channel>
          <channel id="nrk1.no"><display-name>NRK 1</display-name></channel>
          <programme start="\(stamp(-1)) +0000" stop="\(stamp(1)) +0000" channel="tv2.no">
            <title>On now</title><desc>Currently airing.</desc>
          </programme>
          <programme start="\(stamp(1)) +0000" stop="\(stamp(2)) +0000" channel="tv2.no">
            <title>Up next</title>
          </programme>
          <programme start="\(stamp(-1)) +0000" stop="\(stamp(1)) +0000" channel="nrk1.no">
            <title>Also on now</title>
          </programme>
        </tv>
        """.utf8)
    }

    static func stamp(_ hoursFromNow: Double) -> String {
        let date = Date.now.addingTimeInterval(hoursFromNow * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = .gmt
        return formatter.string(from: date)
    }

    @Test("Reads channels and programmes")
    func wellFormed() {
        let guide = XMLTVParser().parse(Self.guideXML(badAmpersand: false))
        #expect(guide.schedules.count == 2)
        #expect(guide.programmeCount == 3)
        #expect(guide.schedules["tv2.no"]?.programme()?.title == "On now")
    }

    /// The failure that costs an entire schedule: `<programme>` elements come
    /// after every `<channel>`, so one bad character early on takes everything
    /// with it.
    @Test("Recovers a guide broken by an unescaped ampersand")
    func repairsBareAmpersand() {
        let broken = Self.guideXML(badAmpersand: true)

        // Confirm the input really is fatal to a strict parser.
        let strict = XMLParser(data: broken)
        #expect(strict.parse() == false)

        let guide = XMLTVParser().parse(broken)
        #expect(guide.programmeCount == 3, "repair should recover every programme")
        #expect(guide.schedules["nrk1.no"]?.programme()?.title == "Also on now")
    }

    @Test("Parses XMLTV timestamps with and without an offset")
    func timestamps() throws {
        let withOffset = try #require(XMLTVParser.date(from: "20260115203000 +0100"))
        let asUTC = try #require(XMLTVParser.date(from: "20260115193000"))
        #expect(withOffset == asUTC)
    }

    @Test("Converts xmltv_ns episode numbering to onscreen form")
    func episodeNumbering() {
        #expect(XMLTVParser.onscreenCode(fromXMLTVNS: "0 . 3 . 0") == "S01E04")
        #expect(XMLTVParser.onscreenCode(fromXMLTVNS: "1 . 0 .") == "S02E01")
    }
}
