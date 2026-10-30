import AVFoundation
import Foundation
import KanalFFmpeg
import Network
import UIKit

/// Carries a VLC film to an AirPlay television.
///
/// AirPlay video belongs to `AVPlayer`, which cannot open Matroska — and a
/// real provider's films are almost all Matroska. So when the person picks a
/// television, the film is repackaged on the phone into HLS (picture copied
/// untouched, audio re-encoded only when the television could not take it),
/// served over the local network, and handed to an `AVPlayer` that AirPlays it
/// the ordinary way. The television fetches from the phone; the phone fetches
/// from the provider, which only ever sees the one connection it allows.
///
/// Everything here starts only on that explicit route change, and anything
/// that goes wrong hands the film back to VLC where it was. Ordinary playback
/// never passes through this file.
@MainActor
final class AirPlayRelay {
    enum Outcome {
        /// The television is playing.
        case started
        /// Could not be carried — VLC should take the film back at `position`.
        case failed(position: TimeInterval)
    }

    let player = AVPlayer()
    private(set) var offset: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private let url: URL
    private let userAgent: String
    private var language: String?
    private var session: RemuxSession?
    private let server: HLSServer
    private var onOutcome: ((Outcome) -> Void)?
    private var waitTask: Task<Void, Never>?
    private var hasReportedOutcome = false

    init(url: URL, userAgent: String, language: String?) {
        self.url = url
        self.userAgent = userAgent
        self.language = language
        self.server = HLSServer()
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        // A repackaged stream grows as it is written; waiting to buffer
        // ahead of a file still being produced only adds delay.
        player.automaticallyWaitsToMinimizeStalling = true
    }

    /// Starts at `position`. `outcome` is called once — `.started` when the
    /// first segments are playable, `.failed` otherwise.
    func start(at position: TimeInterval, outcome: @escaping (Outcome) -> Void) {
        onOutcome = outcome
        hasReportedOutcome = false
        begin(at: position)
    }

    /// Current position in the film, in its own seconds.
    var position: TimeInterval {
        let seconds = player.currentTime().seconds
        return offset + (seconds.isFinite ? max(seconds, 0) : 0)
    }

    var isPlaying: Bool { player.rate > 0 }

    var isBuffering: Bool {
        player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    /// Whether the session ended because the film did.
    var hasEnded: Bool {
        guard let session, session.exitCode == Int32(KANAL_REMUX_OK) else { return false }
        guard let item = player.currentItem else { return false }
        let end = item.seekableTimeRanges.last?.timeRangeValue.end.seconds ?? 0
        return end > 0 && player.currentTime().seconds >= end - 0.5
    }

    /// The repackager stopped early and the television has played all it
    /// was given — the provider dropped the film mid-way.
    var hasRunDry: Bool {
        guard let session, let code = session.exitCode,
              code != Int32(KANAL_REMUX_OK), code != Int32(KANAL_REMUX_CANCELLED) else { return false }
        return position >= offset + session.produced - 1
    }

    func togglePlayPause() {
        if player.rate > 0 { player.pause() } else { player.play() }
    }

    /// Seeks within what is already repackaged, and starts again from the
    /// target otherwise — Matroska over HTTP seeks, so that costs a second or
    /// two rather than waiting for the remuxer to catch up.
    func seek(to seconds: TimeInterval) {
        let target = max(seconds, 0)
        let produced = offset + (session?.produced ?? 0)
        if target >= offset, target <= produced - 2 {
            player.seek(to: CMTime(seconds: target - offset, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
        } else {
            restart(at: target)
        }
    }

    /// Another audio track means repackaging from here with that one.
    func selectAudioLanguage(_ code: String?) {
        guard code != language else { return }
        language = code
        restart(at: position)
    }

    func stop() {
        waitTask?.cancel()
        waitTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        session?.cancel()
        session = nil
        server.stop()
        onOutcome = nil
    }

    // MARK: -

    private func restart(at position: TimeInterval) {
        // A restart can fail like the first start can, and must be able to
        // say so — otherwise the television would just stop.
        hasReportedOutcome = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        session?.cancel()
        session = nil
        begin(at: position)
    }

    private func begin(at position: TimeInterval) {
        waitTask?.cancel()
        let session = RemuxSession(url: url, userAgent: userAgent, start: position, language: language)
        self.session = session
        offset = position

        guard let address = server.start(serving: session.directory) else {
            report(.failed(position: position))
            return
        }
        session.start()

        waitTask = Task { [weak self] in
            // The provider can take a while to answer; the remuxer has its
            // own network timeout, so this is only a backstop.
            let deadline = Date.now.addingTimeInterval(45)
            while !Task.isCancelled, Date.now < deadline {
                if session.exitCode != nil, !session.isPlayable {
                    break
                }
                if session.isPlayable {
                    guard let self else { return }
                    if session.duration > 0 { self.duration = session.duration }
                    // The film resumes from the keyframe before the position
                    // asked for, so the clock is set from where it really is.
                    self.offset = max(session.origin, 0)
                    let item = AVPlayerItem(url: address.appendingPathComponent("index.m3u8"))
                    self.player.replaceCurrentItem(with: item)
                    // A playlist still being written opens at its live edge,
                    // seconds into the film, and a seek before the item is
                    // ready is ignored. So: wait for ready, then go to the start.
                    while item.status == .unknown, !Task.isCancelled, Date.now < deadline {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    guard !Task.isCancelled else { return }
                    guard item.status == .readyToPlay else { break }
                    await self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    guard !Task.isCancelled else { return }
                    self.player.play()
                    self.report(.started)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, let self else { return }
            self.report(.failed(position: position))
        }
    }

    private func report(_ outcome: Outcome) {
        guard !hasReportedOutcome else { return }
        hasReportedOutcome = true
        if case .failed = outcome {
            session?.cancel()
            session = nil
            server.stop()
        }
        onOutcome?(outcome)
    }

    /// The AirPlay receiver the sound is going to, if any — which is what
    /// choosing a television in the route picker changes first.
    static var airPlayRouteID: String? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first { $0.portType == .airPlay }?.uid
    }
}

/// One run of the repackager, on a thread of its own.
final class RemuxSession: @unchecked Sendable {
    let directory: URL
    private let url: URL
    private let userAgent: String
    private let startPosition: TimeInterval
    private let language: String?
    private let state: UnsafeMutablePointer<kanal_remux_state>
    private let lock = NSLock()
    private var _exitCode: Int32?
    private var cancelled = false
    private var cleaned = false

    init(url: URL, userAgent: String, start: TimeInterval, language: String?) {
        self.url = url
        self.userAgent = userAgent
        self.startPosition = start
        self.language = language
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("airplay-\(UUID().uuidString)", isDirectory: true)
        state = .allocate(capacity: 1)
        state.initialize(to: kanal_remux_state())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func start() {
        let thread = Thread { [self] in
            let code = kanal_remux_run(
                url.isFileURL ? url.path : url.absoluteString, userAgent, startPosition,
                language, directory.path, state
            )
            lock.lock()
            _exitCode = code
            let wasCancelled = cancelled
            lock.unlock()
            // The thread is the last user of the state, so it frees it — the
            // caller may cancel and walk away long before this returns.
            if wasCancelled { cleanUp() }
        }
        thread.qualityOfService = .userInitiated
        thread.name = "Kanal AirPlay remux"
        thread.start()
    }

    var exitCode: Int32? {
        lock.lock(); defer { lock.unlock() }
        return _exitCode
    }

    var produced: TimeInterval { read { $0.produced } }
    var duration: TimeInterval { read { $0.duration } }
    var origin: TimeInterval { read { $0.origin } }

    private func read(_ field: (kanal_remux_state) -> Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        return cleaned ? 0 : field(state.pointee)
    }

    /// Two whole segments listed is enough for AVPlayer to start and keep
    /// going while the rest is written.
    var isPlayable: Bool {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("index.m3u8"), encoding: .utf8)
        else { return false }
        let segments = text.components(separatedBy: "#EXTINF").count - 1
        return segments >= 2 || (segments >= 1 && text.contains("#EXT-X-ENDLIST"))
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { return lock.unlock() }
        cancelled = true
        let finished = _exitCode != nil
        if !finished { state.pointee.cancel = 1 }
        lock.unlock()
        if finished { cleanUp() }
    }

    private func cleanUp() {
        lock.lock()
        guard !cleaned else { return lock.unlock() }
        cleaned = true
        // Freed only here, after the remuxer has returned for good.
        state.deallocate()
        lock.unlock()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Serves one directory over HTTP to the local network, for as long as one
/// film is being carried. Paths carry a random token, so nothing else on the
/// network can guess its way to the files.
final class HLSServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "Kanal AirPlay server")
    private let lock = NSLock()
    private var root: URL?
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    /// Returns the base URL the television should use, or nil without a
    /// local network address to offer it.
    func start(serving directory: URL) -> URL? {
        lock.lock()
        root = directory
        lock.unlock()
        guard let host = LocalAddress.privateIPv4() else { return nil }
        if listener == nil {
            guard let listener = try? NWListener(using: .tcp, on: .any) else { return nil }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: ready.signal()
                default: break
                }
            }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 3)
            listener.stateUpdateHandler = nil
            guard let port = listener.port?.rawValue else {
                listener.cancel()
                return nil
            }
            self.listener = listener
            _ = port
        }
        guard let port = listener?.port?.rawValue else { return nil }
        return URL(string: "http://\(host):\(port)/\(token)/")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.respond(to: request, on: connection)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            return send(status: "405 Method Not Allowed", on: connection)
        }
        let isHead = parts[0] == "HEAD"
        let components = parts[1].split(separator: "/").map(String.init)
        lock.lock()
        let root = self.root
        lock.unlock()
        // Exactly /<token>/<file>, and the file name plain — nothing outside
        // the one directory can be reached.
        guard components.count == 2, components[0] == token,
              let name = components.last?.split(separator: "?").first.map(String.init),
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }),
              !name.hasPrefix("."), let root,
              let body = try? Data(contentsOf: root.appendingPathComponent(name), options: .mappedIfSafe)
        else {
            return send(status: "404 Not Found", on: connection)
        }

        let type = name.hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : "video/mp4"
        var status = "200 OK"
        var slice = body
        var extra = ""
        if let range = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let bounds = Self.byteRange(range, length: body.count) {
            slice = body.subdata(in: bounds)
            status = "206 Partial Content"
            extra = "Content-Range: bytes \(bounds.lowerBound)-\(bounds.upperBound - 1)/\(body.count)\r\n"
        }
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(slice.count)\r\n"
            + "Accept-Ranges: bytes\r\n\(extra)Cache-Control: no-cache\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        if !isHead { response.append(slice) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func send(status: String, on connection: NWConnection) {
        let response = Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// "Range: bytes=a-b" or "bytes=a-", clamped to the file.
    static func byteRange(_ header: String, length: Int) -> Range<Int>? {
        guard let spec = header.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) else { return nil }
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let lower = Int(bounds[0]), lower < length else { return nil }
        let upper = Int(bounds[1]).map { min($0, length - 1) } ?? length - 1
        guard upper >= lower else { return nil }
        return lower..<(upper + 1)
    }
}

/// The phone's address on the home network, which is what the television
/// fetches from. Wi-Fi only: AirPlay does not run over anything else.
enum LocalAddress {
    static func privateIPv4() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }
        for cursor in sequence(first: interfaces, next: { $0?.pointee.ifa_next }) {
            guard let cursor, (cursor.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  let address = cursor.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: cursor.pointee.ifa_name).hasPrefix("en")
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let octets = value.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { continue }
            if octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
                || (octets[0] == 192 && octets[1] == 168) {
                return value
            }
        }
        return nil
    }
}
