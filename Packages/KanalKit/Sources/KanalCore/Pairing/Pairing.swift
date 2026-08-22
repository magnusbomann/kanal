import CryptoKit
import Foundation

/// Handing a playlist from a phone to an Apple TV.
///
/// Typing a provider URL with a remote is the worst minute in any TV app, so
/// Kanal does not ask anyone to. The TV shows a code, the phone sends the
/// playlist over the local network, and nothing ever leaves the house — no
/// account, no server, and no running cost to carry.
public enum Pairing {

    /// The Bonjour service the TV advertises and the phone looks for.
    public static let serviceType = "_kanal-pair._tcp"

    /// What the QR code on the TV encodes.
    public struct Invitation: Codable, Sendable, Hashable {
        /// Bonjour instance name, so the phone can find this exact TV.
        public var serviceName: String
        /// Symmetric key, base64. Fresh for every pairing session.
        public var key: String
        /// Short human code, for when a camera is not available.
        public var code: String

        public init(serviceName: String, key: String, code: String) {
            self.serviceName = serviceName
            self.key = key
            self.code = code
        }

        /// Encoded into the QR image, and parsed back on the phone.
        public var url: URL? {
            var components = URLComponents()
            components.scheme = "kanal"
            components.host = "pair"
            components.queryItems = [
                URLQueryItem(name: "n", value: serviceName),
                URLQueryItem(name: "k", value: key),
                URLQueryItem(name: "c", value: code),
            ]
            return components.url
        }

        public init?(url: URL) {
            guard url.scheme == "kanal", url.host == "pair",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            else { return nil }
            let lookup = Dictionary(
                items.compactMap { item in item.value.map { (item.name, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
            guard let name = lookup["n"], let key = lookup["k"], let code = lookup["c"] else {
                return nil
            }
            self.init(serviceName: name, key: key, code: code)
        }

        /// A fresh invitation, with a key that lives only as long as the screen.
        public static func generate() -> (invitation: Invitation, key: SymmetricKey) {
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            let code = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
            let name = "Kanal-\(code)"
            return (
                Invitation(serviceName: name, key: keyData.base64EncodedString(), code: code),
                key
            )
        }

        public var symmetricKey: SymmetricKey? {
            Data(base64Encoded: key).map { SymmetricKey(data: $0) }
        }
    }

    /// What the phone sends once connected.
    public struct Payload: Codable, Sendable {
        public var sources: [PlaylistSource]
        public var sentAt: Date

        public init(sources: [PlaylistSource], sentAt: Date = .now) {
            self.sources = sources
            self.sentAt = sentAt
        }
    }

    /// Sealed with the key from the QR code, so anything else on the network
    /// sees only ciphertext — and provider credentials travel inside this.
    public static func seal(_ payload: Payload, with key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(payload)
        return try ChaChaPoly.seal(plaintext, using: key).combined
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> Payload {
        let box = try ChaChaPoly.SealedBox(combined: data)
        let plaintext = try ChaChaPoly.open(box, using: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: plaintext)
    }

    /// Length-prefixed framing: one message per connection, but the length
    /// still has to be explicit because TCP does not preserve boundaries.
    public static func frame(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }

    public static func expectedLength(of header: Data) -> Int? {
        guard header.count >= 4 else { return nil }
        let value = header.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        // Playlists are small; anything larger is not one of ours.
        guard value > 0, value <= 4_000_000 else { return nil }
        return Int(value)
    }
}
