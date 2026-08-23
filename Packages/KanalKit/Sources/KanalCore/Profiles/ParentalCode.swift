import CryptoKit
import Foundation
import Security

/// The four digits that stand between a child's profile and everything else.
///
/// Kept in the keychain rather than in `Application Support`, because the JSON
/// files next to it are readable by anyone with the device unlocked and a file
/// browser — which, on a shared iPad, is the exact threat model.
///
/// Stored as a salted SHA-256 digest. There is no server to check against and
/// nothing to recover, so hashing buys only one thing, but it is the thing
/// worth buying: the code a parent probably also uses on their front door never
/// exists on disk in a readable form.
public struct ParentalCode: Sendable {

    /// Four digits. Long enough for a lock screen, short enough to type with a
    /// TV remote on a virtual number pad.
    public static let length = 4

    private static let service = "com.bomann.kanal.parental-code"
    private static let account = "primary"

    public init() {}

    // MARK: - State

    public var isSet: Bool { load() != nil }

    /// Sets or replaces the code. Passing `nil` removes it.
    @discardableResult
    public func set(_ code: String?) -> Bool {
        guard let code, Self.isWellFormed(code) else { return remove() }
        let salt = Self.randomSalt()
        let record = Record(salt: salt, digest: Self.digest(code, salt: salt))
        guard let data = try? JSONEncoder().encode(record) else { return false }
        return store(data)
    }

    /// Whether the typed digits match. Constant-time, out of habit rather than
    /// necessity — an attacker who can time this already has the device.
    public func matches(_ code: String) -> Bool {
        guard let record = load() else { return false }
        let candidate = Self.digest(code, salt: record.salt)
        guard candidate.count == record.digest.count else { return false }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(candidate, record.digest) { difference |= lhs ^ rhs }
        return difference == 0
    }

    public static func isWellFormed(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(\.isNumber)
    }

    // MARK: - Keychain

    private struct Record: Codable {
        var salt: Data
        var digest: Data
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(bytes)
    }

    private static func digest(_ code: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(code.utf8)))
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    private func load() -> Record? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func store(_ data: Data) -> Bool {
        var query = baseQuery
        // This device only, and only while unlocked: a parental code has no
        // business travelling to a restored backup on someone else's hardware.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    private func remove() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
