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
        case sent
        case failed(String)
    }

    public private(set) var state: State = .idle

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var timeout: Task<Void, Never>?

    public init() {}

    /// Sends the given sources to whichever TV is advertising this invitation.
    public func send(_ sources: [PlaylistSource], to invitation: Pairing.Invitation) {
        guard let key = invitation.symmetricKey else {
            state = .failed(String(localized: CoreStrings.pairingUnreadableCode))
            return
        }
        cancel()
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
                guard let self, case .searching = self.state else { return }
                let match = results.first { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return name == invitation.serviceName
                    }
                    return false
                }
                guard let match else { return }
                self.connect(to: match.endpoint, sources: sources, key: key)
            }
        }
        browser.start(queue: .main)

        // Without this a TV that went to sleep leaves the phone spinning.
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, case .searching = self.state else { return }
                self.state = .failed(String(localized: CoreStrings.pairingNotFound))
                self.cancel()
            }
        }
    }

    public func cancel() {
        timeout?.cancel()
        browser?.cancel()
        connection?.cancel()
        browser = nil
        connection = nil
    }

    private func connect(to endpoint: NWEndpoint, sources: [PlaylistSource], key: SymmetricKey) {
        state = .connecting
        browser?.cancel()
        browser = nil

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.transmit(sources, over: connection, key: key)
                case .failed(let error):
                    self.state = .failed(error.localizedDescription)
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func transmit(_ sources: [PlaylistSource], over connection: NWConnection, key: SymmetricKey) {
        do {
            let sealed = try Pairing.seal(Pairing.Payload(sources: sources), with: key)
            connection.send(
                content: Pairing.frame(sealed),
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.state = .failed(error.localizedDescription)
                        } else {
                            self.state = .sent
                        }
                        self.timeout?.cancel()
                        connection.cancel()
                    }
                }
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
