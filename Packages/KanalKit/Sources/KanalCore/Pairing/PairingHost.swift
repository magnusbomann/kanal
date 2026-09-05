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
    private var importTask: Task<Void, Never>?
    private var generation = 0
    private var receiveTimeout: Task<Void, Never>?

    /// Called with the complete payload the phone sent.
    private let onReceive: @MainActor (Pairing.Payload) async -> Bool

    public init(onReceive: @escaping @MainActor (Pairing.Payload) async -> Bool) {
        self.onReceive = onReceive
    }

    public func start() {
        guard listener == nil else { return }

        generation &+= 1
        let generation = self.generation
        let (pendingInvitation, key) = Pairing.Invitation.generate()
        self.invitation = nil
        self.key = key

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: pendingInvitation.serviceName,
                type: Pairing.serviceType
            )
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == generation, self.listener != nil else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .ready = state, self?.generation == generation,
                       let self, let port = self.listener?.port {
                        var readyInvitation = pendingInvitation
                        readyInvitation.port = port.rawValue
                        readyInvitation.host = PairingLANAddress.privateIPv4Address()
                        self.invitation = readyInvitation
                        self.state = .waiting
                    } else if case .failed(let error) = state, self?.generation == generation {
                        self?.state = .failed(error.localizedDescription)
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .main)
            // Bonjour is not advertised as usable until NWListener reports ready.
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        // Import may itself replace the setup screen. Keep its accepted
        // connection alive until the bounded import has sent its receipt.
        if importTask != nil {
            listener?.cancel()
            listener = nil
            return
        }
        generation &+= 1
        receiveTimeout?.cancel()
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        buffer = Data()
        expectedLength = nil
        key = nil
        invitation = nil
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
        receiveTimeout?.cancel()
        let generation = self.generation
        receiveTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == generation, self.importTask == nil,
                      self.connection === incoming else { return }
                self.state = .failed(String(localized: CoreStrings.pairingMismatch))
                self.resetConnection()
            }
        }
        incoming.start(queue: .main)
        receive(on: incoming)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                if let error {
                    self.state = .failed(error.localizedDescription)
                    self.resetConnection()
                    return
                }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drainBuffer()
                }
                // The complete request has moved to validation and receipt
                // delivery. Further EOF callbacks must not close that reply.
                guard self.importTask == nil else { return }
                if isComplete {
                    self.drainBuffer()
                    if case .receiving = self.state {
                        self.state = .failed(String(localized: CoreStrings.pairingMismatch))
                        self.resetConnection()
                    }
                } else if case .receiving = self.state {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func drainBuffer() {
        guard importTask == nil else { return }
        if expectedLength == nil {
            guard buffer.count >= 4 else { return }
            guard let length = Pairing.expectedLength(of: buffer) else {
                state = .failed(String(localized: CoreStrings.pairingMismatch))
                resetConnection()
                return
            }
            expectedLength = length
            buffer.removeFirst(4)
        }
        guard let expectedLength, buffer.count >= expectedLength, let key,
              let activeConnection = connection else { return }

        let sealed = buffer.prefix(expectedLength)
        do {
            let payload = try Pairing.open(Data(sealed), with: key)
            // Give the app a bounded opportunity to validate and persist the
            // sources, then acknowledge that result over the same connection.
            guard !payload.sources.isEmpty else {
                state = .failed(String(localized: CoreStrings.pairingMismatch))
                resetConnection()
                return
            }
            let callback = onReceive
            let count = payload.sources.count
            let capturedConnection = activeConnection
            let capturedKey = key
            importTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let imported = await Self.withTimeout(seconds: 120) {
                    await callback(payload)
                } ?? false
                guard !Task.isCancelled else { self.importTask = nil; return }
                do {
                    let receipt = try Pairing.seal(Pairing.Receipt(imported: imported, sourceCount: count), with: capturedKey)
                    capturedConnection.send(content: Pairing.frame(receipt), completion: .contentProcessed { [self] error in
                        Task { @MainActor in
                            self.importTask = nil
                            if let error { self.state = .failed(error.localizedDescription) }
                            else if imported { self.state = .received(count) }
                            else { self.state = .failed(String(localized: CoreStrings.pairingMismatch)) }
                            capturedConnection.cancel()
                            self.resetConnection(keepState: true)
                        }
                    })
                } catch {
                    self.state = .failed(error.localizedDescription)
                    capturedConnection.cancel()
                    self.importTask = nil
                    self.resetConnection()
                }
            }
            return
        } catch {
            // A failure here means the key did not match — someone else's
            // traffic, or a stale QR code.
            state = .failed(String(localized: CoreStrings.pairingMismatch))
        }
        resetConnection()
    }

    private func resetConnection(keepState: Bool = false) {
        receiveTimeout?.cancel()
        receiveTimeout = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
        expectedLength = nil
        if !keepState { importTask = nil }
    }

    private static func withTimeout<T: Sendable>(seconds: Int, operation: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { continuation in
            let gate = TimeoutGate<T>(continuation)
            let operationTask = Task {
                gate.resume(await operation())
            }
            let timerTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.timeout()
            }
            gate.install(operation: operationTask, timer: timerTask)
        }
    }

    private final class TimeoutGate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let continuation: CheckedContinuation<T?, Never>
        private var operation: Task<Void, Never>?
        private var timer: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
        func resume(_ value: T) { finish(value) }
        func timeout() { finish(nil) }
        func install(operation: Task<Void, Never>, timer: Task<Void, Never>) {
            lock.lock()
            self.operation = operation
            self.timer = timer
            let done = finished
            lock.unlock()
            if done { operation.cancel(); timer.cancel() }
        }
        private func finish(_ value: T?) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let pendingOperation = operation
            let pendingTimer = timer
            operation = nil
            timer = nil
            lock.unlock()
            if case .none = value { pendingOperation?.cancel() }
            pendingTimer?.cancel()
            continuation.resume(returning: value)
        }
    }
}
