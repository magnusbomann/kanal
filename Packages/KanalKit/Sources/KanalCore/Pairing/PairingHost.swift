import CryptoKit
import Foundation
import Network
import Observation

/// The receiving half, run by the Apple TV.
///
/// Listens on the local network under a one-off Bonjour name, accepts a single
/// sealed payload, and stops. Short-lived by design: the window is open only
/// while the pairing screen is on screen.
@MainActor
@Observable
public final class PairingHost {

    public enum State: Equatable {
        case idle
        case waiting
        case receiving
        case received(Int)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var invitation: Pairing.Invitation?

    private var listener: NWListener?
    private var connection: NWConnection?
    private var key: SymmetricKey?
    private var buffer = Data()
    private var expectedLength: Int?

    /// Called with the sources the phone sent.
    private let onReceive: ([PlaylistSource]) -> Void

    public init(onReceive: @escaping ([PlaylistSource]) -> Void) {
        self.onReceive = onReceive
    }

    public func start() {
        guard listener == nil else { return }

        let (invitation, key) = Pairing.Invitation.generate()
        self.invitation = invitation
        self.key = key

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: invitation.serviceName,
                type: Pairing.serviceType
            )
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .failed(let error) = state {
                        self?.state = .failed(error.localizedDescription)
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            state = .waiting
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        buffer = Data()
        expectedLength = nil
        if case .received = state {} else { state = .idle }
    }

    private func accept(_ incoming: NWConnection) {
        // One phone at a time; a second caller is ignored rather than queued.
        guard connection == nil else {
            incoming.cancel()
            return
        }
        connection = incoming
        state = .receiving
        incoming.start(queue: .main)
        receive(on: incoming)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drainBuffer()
                }
                if isComplete {
                    self.drainBuffer()
                } else if case .receiving = self.state {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func drainBuffer() {
        if expectedLength == nil {
            guard let length = Pairing.expectedLength(of: buffer) else { return }
            expectedLength = length
            buffer.removeFirst(4)
        }
        guard let expectedLength, buffer.count >= expectedLength, let key else { return }

        let sealed = buffer.prefix(expectedLength)
        do {
            let payload = try Pairing.open(Data(sealed), with: key)
            state = .received(payload.sources.count)
            onReceive(payload.sources)
        } catch {
            // A failure here means the key did not match — someone else's
            // traffic, or a stale QR code.
            state = .failed(String(localized: CoreStrings.pairingMismatch))
        }
        connection?.cancel()
        connection = nil
    }
}
