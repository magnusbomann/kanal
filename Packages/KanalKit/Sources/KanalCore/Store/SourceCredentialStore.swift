import Foundation
import Security

/// The secret half of a TV service. The public descriptor stays in JSON and
/// iCloud; this half lives only in synchronisable Keychain.
public struct SourceCredentials: Codable, Sendable, Equatable {
    public var portalURL: URL?
    public var playlistURL: URL?
    public var epgURL: URL?
    public var username: String?
    public var password: String?

    public init(source: PlaylistSource) {
        portalURL = source.portalURL
        playlistURL = source.kind == .m3u ? source.playlistURL : nil
        epgURL = source.epgURL
        username = source.username
        password = source.password
    }

    public var isEmpty: Bool {
        portalURL == nil && playlistURL == nil && epgURL == nil
            && username?.isEmpty != false && password?.isEmpty != false
    }
}

public protocol SourceCredentialStoring: Sendable {
    func load(for sourceID: UUID) async throws -> SourceCredentials?
    func save(_ credentials: SourceCredentials, for sourceID: UUID) async throws
    func remove(for sourceID: UUID) async throws
}

/// iCloud Keychain-backed service secrets. `synchronizable` is the important
/// bit: Apple moves the encrypted item between a person's devices; Kanal never
/// operates a credential server and never receives a recoverable copy.
public actor KeychainSourceCredentialStore: SourceCredentialStoring {
    private let service = "com.bomann.kanal.tv-service"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func load(for sourceID: UUID) throws -> SourceCredentials? {
        var query = baseQuery(sourceID)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status)
        }
        return try decoder.decode(SourceCredentials.self, from: data)
    }

    public func save(_ credentials: SourceCredentials, for sourceID: UUID) throws {
        guard !credentials.isEmpty else {
            try remove(for: sourceID)
            return
        }
        let data = try encoder.encode(credentials)
        var existing = baseQuery(sourceID)
        existing[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let updateStatus = SecItemUpdate(
            existing as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(updateStatus) }

        var add = baseQuery(sourceID)
        // iCloud Keychain synchronisation is not provided on tvOS. A QR
        // import still carries the credentials to the TV, so keep those
        // credentials in its local Keychain instead of creating an item that
        // appears synchronisable but can never arrive or be read back there.
        add[kSecAttrSynchronizable as String] = Self.shouldSynchronize
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func remove(for sourceID: UUID) throws {
        var query = baseQuery(sourceID)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
    }

    private func baseQuery(_ sourceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString,
        ]
    }

    private static var shouldSynchronize: Bool {
        #if os(tvOS)
        false
        #else
        true
        #endif
    }
}

public struct KeychainError: LocalizedError, Sendable {
    public let status: OSStatus
    public init(_ status: OSStatus) { self.status = status }
    public var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

/// Deterministic test and preview store; deliberately public so a caller can
/// verify migrations without touching the developer's real Keychain.
public actor MemorySourceCredentialStore: SourceCredentialStoring {
    private var values: [UUID: SourceCredentials] = [:]
    public init() {}
    public func load(for sourceID: UUID) -> SourceCredentials? { values[sourceID] }
    public func save(_ credentials: SourceCredentials, for sourceID: UUID) {
        values[sourceID] = credentials
    }
    public func remove(for sourceID: UUID) { values[sourceID] = nil }
}

public extension PlaylistSource {
    /// Removes everything that can contain provider credentials before the
    /// descriptor is written to JSON or iCloud.
    var redactedForPersistence: PlaylistSource {
        var copy = self
        copy.username = nil
        copy.password = nil
        copy.epgURL = nil
        copy.portalURL = nil
        if kind == .m3u { copy.playlistURL = nil }
        return copy
    }

    func applying(_ credentials: SourceCredentials?) -> PlaylistSource {
        guard let credentials else { return self }
        var copy = self
        copy.portalURL = credentials.portalURL ?? copy.portalURL
        if kind == .m3u { copy.playlistURL = credentials.playlistURL }
        copy.epgURL = credentials.epgURL
        copy.username = credentials.username
        copy.password = credentials.password
        return copy
    }
}
