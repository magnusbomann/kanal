import CryptoKit
import Foundation
import Testing
@testable import KanalCore

@Suite("Handoff")
struct PairingTests {

    @Test("An invitation survives the trip through a QR code")
    func invitationRoundTrip() throws {
        let (invitation, _) = Pairing.Invitation.generate()
        let url = try #require(invitation.url)
        let parsed = try #require(Pairing.Invitation(url: url))
        #expect(parsed == invitation)
    }

    @Test("QR invitations preserve their direct LAN fallback")
    func directInvitationRoundTrip() throws {
        var invitation = Pairing.Invitation.generate().invitation
        invitation.host = "192.168.1.42"
        invitation.port = 49152
        #expect(Pairing.Invitation(url: try #require(invitation.url)) == invitation)
        #expect(PairingLANAddress.isPrivateIPv4("192.168.1.42"))
        #expect(PairingLANAddress.isPrivateIPv4("10.0.0.2"))
        #expect(!PairingLANAddress.isPrivateIPv4("8.8.8.8"))
        #expect(!PairingLANAddress.isPrivateIPv4("192.168.1.999"))
        #expect(!PairingLANAddress.isPrivateIPv4("example.com"))
    }

    @Test("Old payloads without a household remain readable")
    func legacyPayload() throws {
        let data = Data(#"{"sources":[],"sentAt":0}"#.utf8)
        let payload = try JSONDecoder().decode(Pairing.Payload.self, from: data)
        #expect(payload.household == nil)
        #expect(payload.localPlaylists == nil)
    }

    @Test("Every invitation gets a fresh key and code")
    func freshEachTime() {
        let first = Pairing.Invitation.generate().invitation
        let second = Pairing.Invitation.generate().invitation
        #expect(first.key != second.key)
        #expect(first.serviceName != second.serviceName)
    }

    @Test("The code is six digits")
    func codeShape() {
        let code = Pairing.Invitation.generate().invitation.code
        #expect(code.count == 6)
        #expect(code.allSatisfy { $0.isNumber })
    }

    @Test("A sealed payload opens with the right key")
    func sealAndOpen() throws {
        let (invitation, key) = Pairing.Invitation.generate()
        let source = PlaylistSource(
            kind: .xtream,
            name: "Provider",
            portalURL: URL(string: "http://example.com:8080"),
            username: "user",
            password: "secret"
        )
        let sealed = try Pairing.seal(Pairing.Payload(sources: [source]), with: key)
        // The credentials must not be readable on the wire.
        #expect(!String(decoding: sealed, as: UTF8.self).contains("secret"))

        let key2 = try #require(invitation.symmetricKey)
        let opened = try Pairing.open(sealed, with: key2)
        #expect(opened.sources.first?.password == "secret")
    }

    @Test("A payload sealed for one TV cannot be opened by another")
    func wrongKey() throws {
        let (_, key) = Pairing.Invitation.generate()
        let (_, otherKey) = Pairing.Invitation.generate()
        let sealed = try Pairing.seal(Pairing.Payload(sources: []), with: key)
        #expect(throws: (any Error).self) {
            try Pairing.open(sealed, with: otherKey)
        }
    }

    @Test("Import receipts authenticate both acceptance and rejection")
    func importReceipts() throws {
        let (_, key) = Pairing.Invitation.generate()
        let (_, wrongKey) = Pairing.Invitation.generate()
        for accepted in [true, false] {
            let receipt = Pairing.Receipt(imported: accepted, sourceCount: 2)
            let sealed = try Pairing.seal(receipt, with: key)
            #expect(try Pairing.openReceipt(sealed, with: key) == receipt)
            #expect(throws: (any Error).self) {
                try Pairing.openReceipt(sealed, with: wrongKey)
            }
            var tampered = sealed
            tampered[tampered.startIndex] ^= 1
            #expect(throws: (any Error).self) {
                try Pairing.openReceipt(tampered, with: key)
            }
        }
    }

    @Test("Framing states its own length")
    func framing() {
        let framed = Pairing.frame(Data(repeating: 7, count: 300))
        #expect(framed.count == 304)
        #expect(Pairing.expectedLength(of: framed) == 300)
    }

    @Test("Nonsense lengths are rejected rather than allocated")
    func rejectsAbsurdLength() {
        #expect(Pairing.expectedLength(of: Data([0xFF, 0xFF, 0xFF, 0xFF])) == nil)
        #expect(Pairing.expectedLength(of: Data([0, 0, 0, 0])) == nil)
        #expect(Pairing.expectedLength(of: Data([0, 0])) == nil)
    }

    @Test("A url that is not a pairing invitation is refused")
    func rejectsOtherURLs() {
        #expect(Pairing.Invitation(url: URL(string: "https://example.com")!) == nil)
        #expect(Pairing.Invitation(url: URL(string: "kanal://pair?n=x")!) == nil)
    }
}
