import CryptoKit
import Foundation
import Security

public struct HouseholdSnapshot: Codable, Sendable, Equatable {
    public var modifiedAt: Date
    public var sources: [PlaylistSource]
    public var profiles: [Profile]
    public var watchStates: [String: WatchState]
    /// Per-entry version records used to merge edits made on different devices.
    /// Nil keeps snapshots written by older builds decodable.
    public var syncRecords: [String: HouseholdFieldStamp]?

    public init(
        modifiedAt: Date = .now,
        sources: [PlaylistSource],
        profiles: [Profile],
        watchStates: [String: WatchState],
        syncRecords: [String: HouseholdFieldStamp]? = nil
    ) {
        self.modifiedAt = modifiedAt
        self.sources = sources
        self.profiles = profiles
        self.watchStates = watchStates
        self.syncRecords = syncRecords
    }
}

public protocol HouseholdSyncing: Sendable {
    func pull() async throws -> HouseholdSnapshot?
    func push(_ snapshot: HouseholdSnapshot) async throws
    func externalChanges() async -> AsyncStream<Void>
}

public extension HouseholdSyncing {
    func externalChanges() async -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

public enum HouseholdSyncState: Sendable, Equatable {
    case waiting
    case syncing
    case current(Date)
    case unavailable
    case failed(String)
}

public actor NoopHouseholdSync: HouseholdSyncing {
    public init() {}
    public func pull() -> HouseholdSnapshot? { nil }
    public func push(_ snapshot: HouseholdSnapshot) {}
}

public actor MemoryHouseholdSync: HouseholdSyncing {
    public var snapshot: HouseholdSnapshot?
    public init(snapshot: HouseholdSnapshot? = nil) { self.snapshot = snapshot }
    public func pull() -> HouseholdSnapshot? { snapshot }
    public func push(_ snapshot: HouseholdSnapshot) { self.snapshot = snapshot }
}

/// A compact household snapshot in this app's private iCloud key-value store.
///
/// The payload deliberately contains no provider URL or credential. Those live
/// in a synchronisable Keychain item and are end-to-end encrypted by Apple.
/// Keeping the non-secret descriptor here avoids a second synchronised AES key:
/// two newly configured devices could previously create different keys and
/// make the same iCloud snapshot permanently unreadable to each other.
public actor ICloudHouseholdSync: HouseholdSyncing {
    private let store: NSUbiquitousKeyValueStore
    private let keyStore = HouseholdKeyStore()
    private let valueKey = "household.v3"
    private let previousValueKey = "household.v2"
    private let legacyValueKey = "household.v1.encrypted"
    private let maximumPayloadBytes = 900_000
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func externalChanges() -> AsyncStream<Void> {
        let store = self.store
        return AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                queue: nil
            ) { _ in
                continuation.yield()
            }
            let lifetime = NotificationObserverLifetime(observer)
            continuation.onTermination = { _ in
                lifetime.cancel()
            }
        }
    }

    public func pull() throws -> HouseholdSnapshot? {
        store.synchronize()
        if let payload = store.data(forKey: valueKey) {
            return try decoder.decode(HouseholdSnapshot.self, from: payload)
        }
        if let payload = store.data(forKey: previousValueKey) {
            // AppModel migrates any old portal descriptor into Keychain
            // before publishing the sanitized v3 snapshot.
            return try decoder.decode(HouseholdSnapshot.self, from: payload)
        }

        // One-way migration from builds that sealed the descriptor with a
        // synchronisable app-created key. Never delete it until v2 is safely
        // accepted by iCloud, so a late-arriving Keychain item can retry.
        guard let sealed = store.data(forKey: legacyValueKey) else { return nil }
        guard let key = try keyStore.load() else { throw SyncError.keyNotAvailable }
        let box = try AES.GCM.SealedBox(combined: sealed)
        let clear = try AES.GCM.open(box, using: key)
        let snapshot = try decoder.decode(HouseholdSnapshot.self, from: clear)
        return snapshot
    }

    public func push(_ snapshot: HouseholdSnapshot) throws {
        try write(snapshot)
    }

    private func write(_ snapshot: HouseholdSnapshot) throws {
        let payload = try encoder.encode(snapshot.sanitizedForSync())
        guard payload.count <= maximumPayloadBytes else {
            throw SyncError.payloadTooLarge
        }
        store.set(payload, forKey: valueKey)
        store.removeObject(forKey: previousValueKey)
        store.removeObject(forKey: legacyValueKey)
        guard store.synchronize() else { throw SyncError.unavailable }
    }
}

private final class NotificationObserverLifetime: @unchecked Sendable {
    private let observer: NSObjectProtocol
    private let lock = NSLock()
    private var isCancelled = false

    init(_ observer: NSObjectProtocol) {
        self.observer = observer
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true
        NotificationCenter.default.removeObserver(observer)
    }

    deinit { cancel() }
}

public enum SyncError: LocalizedError, Sendable {
    case unavailable
    case keyNotAvailable
    case couldNotSeal
    case payloadTooLarge

    public var errorDescription: String? {
        switch self {
        case .unavailable: "iCloud is not available."
        case .keyNotAvailable: "The iCloud Keychain sync key has not arrived yet."
        case .couldNotSeal: "The household data could not be encrypted."
        case .payloadTooLarge: "The household data is too large for iCloud key-value storage."
        }
    }
}

private struct HouseholdKeyStore: Sendable {
    private let service = "com.bomann.kanal.household-sync-key"
    private let account = "primary"

    func load() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status)
        }
        return SymmetricKey(data: data)
    }

    func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = true
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
        return key
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
