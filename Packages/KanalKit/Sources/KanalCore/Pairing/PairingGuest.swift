import CryptoKit
import Foundation
import Network
import Observation

/// The sending half, run by the phone.
///
/// Finds the TV that is showing the code, opens one connection, sends one
/// sealed message, and hangs up.
@MainActor
@Observable
public final class PairingGuest {

    public enum State: Equatable {
        case idle
        case searching
        case connecting
        case transmitting
        case awaitingReceipt
        case sent
        case failed(String)
    }

    public private(set) var state: State = .idle

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var timeout: Task<Void, Never>?
    private var receiptTimeout: Task<Void, Never>?
    private var discoveryFallback: Task<Void, Never>?
    private var receiptBuffer = Data()
    private var generation = 0

    public init() {}

    public func send(_ payload: Pairing.Payload, to invitation: Pairing.Invitation) {
        beginSend(payload, to: invitation)
    }

    /// Sends the given sources to whichever TV is advertising this invitation.
    public func send(_ sources: [PlaylistSource], to invitation: Pairing.Invitation) {
        beginSend(Pairing.Payload(sources: sources), to: invitation)
    }

    private func beginSend(_ payload: Pairing.Payload, to invitation: Pairing.Invitation) {
        guard let key = invitation.symmetricKey else {
            state = .failed(String(localized: CoreStrings.pairingUnreadableCode))
            return
        }
        cancel()
        self.generation &+= 1
        let generation = self.generation
        state = .searching

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: Pairing.serviceType, domain: nil),
            using: parameters
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.generation == generation, case .searching = self.state else { return }
                let match = results.first { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return name == invitation.serviceName
                    }
                    return false
                }
                guard let match else { return }
                self.connect(to: match.endpoint, payload: payload, key: key, generation: generation)
            }
        }
        browser.stateUpdateHandler = { [weak self] browserState in
            guard case .failed = browserState else { return }
            Task { @MainActor in
                guard let self, self.generation == generation, case .searching = self.state else { return }
                self.connectDirectIfAvailable(invitation, payload: payload, key: key, generation: generation)
            }
        }
        browser.start(queue: .main)

        // Without this a TV that went to sleep leaves the phone spinning.
        discoveryFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == generation, case .searching = self.state else { return }
                self.connectDirectIfAvailable(invitation, payload: payload, key: key, generation: generation)
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                guard let self else { return }
                guard self.generation == generation, self.state == .searching || self.state == .connecting else { return }
                self.state = .failed(String(localized: CoreStrings.pairingNotFound))
                self.cancel()
            }
        }
    }

    public func cancel() {
        timeout?.cancel()
        receiptTimeout?.cancel()
        discoveryFallback?.cancel()
        browser?.cancel()
        connection?.cancel()
        browser = nil
        connection = nil
        receiptBuffer.removeAll(keepingCapacity: false)
        generation &+= 1
    }

    private func connect(to endpoint: NWEndpoint, payload: Pairing.Payload, key: SymmetricKey, generation: Int) {
        state = .connecting
        browser?.cancel()
        browser = nil

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                guard self.connection === connection else { return }
                switch state {
                case .ready:
                    self.transmit(payload, over: connection, key: key, generation: generation)
                case .failed(let error):
                    self.state = .failed(error.localizedDescription)
                    self.resetConnection()
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func connectDirectIfAvailable(_ invitation: Pairing.Invitation, payload: Pairing.Payload, key: SymmetricKey, generation: Int) {
        guard case .searching = state,
              let host = invitation.host, PairingLANAddress.isPrivateIPv4(host), let rawPort = invitation.port,
              let port = NWEndpoint.Port(rawValue: rawPort) else { return }
        browser?.cancel()
        browser = nil
        connect(to: .hostPort(host: NWEndpoint.Host(host), port: port), payload: payload, key: key, generation: generation)
    }

    private func transmit(_ payload: Pairing.Payload, over connection: NWConnection, key: SymmetricKey, generation: Int) {
        do {
            state = .transmitting
            let sealed = try Pairing.seal(payload, with: key)
            receiptTimeout?.cancel()
            receiptTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.generation == generation, self.connection === connection else { return }
                    self.state = .failed(String(localized: CoreStrings.pairingMismatch))
                    self.resetConnection()
                }
            }
            connection.send(
                content: Pairing.frame(sealed),
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.generation == generation else { return }
                        if let error {
                            self.state = .failed(error.localizedDescription)
                            self.resetConnection()
                        } else {
                            self.state = .awaitingReceipt
                            self.receiptTimeout?.cancel()
                            self.receiptTimeout = Task { [weak self] in
                                try? await Task.sleep(for: .seconds(150))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    guard let self, self.generation == generation, self.connection === connection else { return }
                                    self.state = .failed(String(localized: CoreStrings.pairingNotFound))
                                    self.resetConnection()
                                }
                            }
                            self.receiveReceipt(on: connection, key: key)
                        }
                    }
                }
            )
        } catch {
            state = .failed(error.localizedDescription)
            resetConnection()
        }
    }

    private func receiveReceipt(on connection: NWConnection, key: SymmetricKey) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.connection === connection else { return }
                if let error { self.state = .failed(error.localizedDescription); self.resetConnection(); return }
                if let data { self.receiptBuffer.append(data) }
                guard !self.receiptBuffer.isEmpty else {
                    if isComplete { self.state = .failed(String(localized: CoreStrings.pairingMismatch)); self.resetConnection() }
                    else { self.receiveReceipt(on: connection, key: key) }
                    return
                }
                do {
                    guard let length = Pairing.expectedLength(of: self.receiptBuffer) else {
                        if self.receiptBuffer.count < 4 && !isComplete { self.receiveReceipt(on: connection, key: key); return }
                        throw NSError(domain: "KanalPairing", code: 1)
                    }
                    guard self.receiptBuffer.count >= 4 + length else {
                        if !isComplete { self.receiveReceipt(on: connection, key: key); return }
                        throw NSError(domain: "KanalPairing", code: 1)
                    }
                    guard self.receiptBuffer.count == 4 + length else { throw NSError(domain: "KanalPairing", code: 1) }
                    let receipt = try Pairing.openReceipt(Data(self.receiptBuffer.dropFirst(4)), with: key)
                    guard receipt.imported else { throw NSError(domain: "KanalPairing", code: 2) }
                    self.state = .sent
                    self.timeout?.cancel()
                    self.receiptTimeout?.cancel()
                } catch {
                    self.state = .failed(String(localized: CoreStrings.pairingMismatch))
                }
                connection.cancel()
                self.resetConnection(keepState: self.state == .sent)
            }
        }
    }

    private func resetConnection(keepState: Bool = false) {
        connection?.cancel()
        connection = nil
        receiptBuffer.removeAll(keepingCapacity: false)
        if !keepState { receiptTimeout?.cancel() }
    }
}
