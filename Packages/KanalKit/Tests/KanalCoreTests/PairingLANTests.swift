import Foundation
import Testing
@testable import KanalCore

/// This test deliberately exercises a real TCP loopback/LAN path. It is opt-in
/// because CI and ordinary package test runs must not depend on network policy.
@Suite("Pairing LAN", .serialized)
@MainActor
struct PairingLANTests {
    @Test("Direct LAN fallback transfers the complete payload after host teardown")
    func directFallback() async throws {
        guard ProcessInfo.processInfo.environment["KANAL_PAIRING_LAN_TEST"] == "1" else { return }

        let source = PlaylistSource(
            kind: .xtream,
            name: "LAN test provider",
            portalURL: URL(string: "http://example.test:8080"),
            username: "lan-user",
            password: "lan-password"
        )
        let payload = Pairing.Payload(
            sources: [source],
            sentAt: Date(timeIntervalSince1970: 123),
            household: HouseholdSnapshot(
                sources: [source],
                profiles: [Profile(name: "LAN test profile")],
                watchStates: [:]
            ),
            activeSourceID: source.id,
            localPlaylists: ["fixture": "#EXTM3U"]
        )
        var received: Pairing.Payload?
        var host: PairingHost?
        host = PairingHost { incoming in
            received = incoming
            // The setup screen may disappear while import is still running.
            host?.stop()
            try? await Task.sleep(for: .milliseconds(100))
            return incoming.sources.count == 1 && incoming.sources.first?.password == "lan-password"
        }
        let activeHost = try #require(host)
        defer { activeHost.stop() }
        activeHost.start()

        let invitation = try await waitForInvitation(activeHost)
        let directHost = try #require(invitation.host)
        let directPort = try #require(invitation.port)
        var directInvitation = invitation
        directInvitation.serviceName += "-bonjour-disabled"
        directInvitation.host = directHost
        directInvitation.port = directPort

        let guest = PairingGuest()
        defer { guest.cancel() }
        guest.send(payload, to: directInvitation)
        try await waitUntil(timeout: 20) { guest.state == .sent }
        #expect(guest.state == .sent)
        #expect(received?.sources.first?.id == payload.sources.first?.id)
        #expect(received?.sources.first?.name == payload.sources.first?.name)
        #expect(received?.sources.first?.password == payload.sources.first?.password)
        #expect(received?.activeSourceID == payload.activeSourceID)
        #expect(received?.localPlaylists == payload.localPlaylists)
        #expect(received?.household?.profiles.first?.name == "LAN test profile")
        #expect(activeHost.state == .received(1))
    }

    private func waitForInvitation(_ host: PairingHost) async throws -> Pairing.Invitation {
        try await waitUntil(timeout: 5) { host.invitation != nil }
        return try #require(host.invitation)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { throw NSError(domain: "KanalPairingLANTests", code: 1) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
