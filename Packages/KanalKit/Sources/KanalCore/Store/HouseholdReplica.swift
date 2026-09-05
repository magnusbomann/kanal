import Foundation

/// A deterministic last-writer record. `counter` is local logical time; the
/// device id breaks ties, so merge results do not depend on arrival order.
public struct HouseholdFieldStamp: Codable, Sendable, Hashable, Equatable {
    public var counter: UInt64
    public var deviceID: String
    public var deleted: Bool

    public init(counter: UInt64, deviceID: String, deleted: Bool = false) {
        self.counter = counter
        self.deviceID = deviceID
        self.deleted = deleted
    }

    fileprivate static func newer(_ lhs: HouseholdFieldStamp?, than rhs: HouseholdFieldStamp?) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return (lhs.counter, lhs.deviceID) > (rhs.counter, rhs.deviceID)
    }
}

/// Cloud-safe representation of an on-demand history entry. URLs are replaced
/// by a local-only stub; the receiving device resolves the identity against
/// its current catalogue before playback.
public struct HouseholdHistoryStub: Codable, Sendable, Hashable {
    public let id: String
    public let kind: MediaKind
    public let title: String
    public let rawTitle: String
    public let season: Int?
    public let episode: Int?
    public let providerSeriesID: Int?
    public let seriesName: String?
    public let year: Int?
    public let category: String?
    public let countryCode: String?
    public let language: String?
    public let rawGroup: String?

    public init(item: MediaItem) {
        id = item.id; kind = item.kind; title = item.title; rawTitle = item.rawTitle
        season = item.season; episode = item.episode; providerSeriesID = item.providerSeriesID
        seriesName = item.seriesName; year = item.year; category = item.category
        countryCode = item.countryCode; language = item.language
        rawGroup = item.rawGroup
    }

    public var pendingItem: MediaItem {
        MediaItem(id: id, kind: kind, title: title, rawTitle: rawTitle,
                  streamURL: URL(string: "kanal-history://pending")!, rawGroup: rawGroup, category: category,
                  language: language, countryCode: countryCode, seriesName: seriesName,
                  season: season, episode: episode, providerSeriesID: providerSeriesID, year: year)
    }
}

public enum HouseholdHistorySanitizer {
    public static func stub(_ item: MediaItem) -> HouseholdHistoryStub { HouseholdHistoryStub(item: item) }
}

public extension HouseholdSnapshot {
    /// Returns the transport representation with all cached history media
    /// reduced to identity stubs. Provider source descriptors are already
    /// redacted by their persistence projection.
    func sanitizedForSync() -> HouseholdSnapshot {
        var copy = self
        copy.modifiedAt = Date(timeIntervalSince1970: floor(modifiedAt.timeIntervalSince1970))
        copy.sources = sources.filter { $0.kind != .localFile }.map { source in
            var descriptor = source.redactedForPersistence
            descriptor.lastRefreshedAt = nil
            return descriptor
        }
        copy.watchStates = watchStates.mapValues { state in
            var state = state
            state.recentItems = state.recentItems.mapValues { HouseholdHistorySanitizer.stub($0).pendingItem }
            return state
        }
        return copy
    }
}

/// A persisted replica with logical per-value versions and deletion tombstones.
/// Values travel in the ordinary snapshot; only versions live in syncRecords.
/// An unchanged received value is never stamped as a new local edit.
public struct HouseholdReplica: Codable, Sendable {
    public private(set) var value: HouseholdSnapshot
    public let deviceID: String
    private var clock: UInt64 = 0
    private var observed: HouseholdSnapshot

    public init(
        local: HouseholdSnapshot = .init(modifiedAt: .distantPast, sources: [], profiles: [], watchStates: [:]),
        deviceID: String = UUID().uuidString
    ) {
        self.deviceID = deviceID
        value = .init(modifiedAt: .distantPast, sources: [], profiles: [], watchStates: [:])
        observed = value
        observe(local: local)
    }

    public mutating func observe(local: HouseholdSnapshot) {
        let clean = local.sanitizedForSync()
        let before = Self.fields(observed), after = Self.fields(clean)
        let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        var records = value.syncRecords ?? [:]
        if !changed.isEmpty {
            clock &+= 1
            for key in changed {
                records[key] = .init(counter: clock, deviceID: deviceID, deleted: after[key] == nil)
            }
        }
        let date = changed.isEmpty ? value.modifiedAt : clean.modifiedAt
        value = clean
        value.modifiedAt = date
        value.syncRecords = records
        observed = value
    }

    @discardableResult
    public mutating func merge(remote: HouseholdSnapshot) -> HouseholdSnapshot {
        let incoming = remote.sanitizedForSync()
        let left = Self.fields(value), right = Self.fields(incoming)
        var records = value.syncRecords ?? [:]
        let remoteRecords = incoming.syncRecords ?? [:]
        var fields = left
        let keys = Set(left.keys).union(right.keys).union(records.keys).union(remoteRecords.keys)
        for key in keys {
            let l = records[key], r = remoteRecords[key]
            if Self.wins(r, over: l) || (l == nil && r == nil && left[key] == nil) {
                if let r { records[key] = r }
                fields[key] = r?.deleted == true ? nil : right[key]
            } else if l?.deleted == true {
                fields[key] = nil
            }
        }
        clock = max(clock, remoteRecords.values.map(\.counter).max() ?? 0)
        var merged = Self.materialize(fields)
        merged.modifiedAt = max(value.modifiedAt, incoming.modifiedAt)
        merged.syncRecords = records
        value = merged
        observed = merged
        return merged
    }

    public func snapshot() -> HouseholdSnapshot { value }

    private static func wins(_ incoming: HouseholdFieldStamp?, over current: HouseholdFieldStamp?) -> Bool {
        guard let incoming else { return false }
        guard let current else { return true }
        if incoming.counter != current.counter { return incoming.counter > current.counter }
        if incoming.deleted != current.deleted { return incoming.deleted }
        return incoming.deviceID > current.deviceID
    }

    private static let memberships: Set<String> = [
        "favoriteIDs", "hiddenCategoryNames", "allowedCategories", "allowedTitleKeys", "blockedTitleKeys",
        "recentIDs", "recentChannelGroupIDs"
    ]
    private static func escape(_ key: String) -> String {
        key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }
    private static func unescape(_ key: String) -> String {
        key.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
    }
    private static func fields(_ snapshot: HouseholdSnapshot) -> [String: Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        object.removeValue(forKey: "modifiedAt")
        object.removeValue(forKey: "syncRecords")
        for group in ["sources", "profiles"] {
            let entries = object[group] as? [[String: Any]] ?? []
            var keyed: [String: Any] = [:]
            for var entry in entries {
                guard let id = entry["id"] as? String else { continue }
                entry["_present"] = true
                keyed[id] = entry
            }
            object[group] = keyed
        }
        var result: [String: Data] = [:]
        func walk(_ node: Any, at path: [String]) {
            if let object = node as? [String: Any] {
                for (key, value) in object { walk(value, at: path + [key]) }
            } else if let array = node as? [String], let name = path.last, memberships.contains(name) {
                for (index, key) in array.enumerated() {
                    let rank = name.hasPrefix("recent") ? index : 0
                    walk(rank, at: path + [key])
                }
            } else if let data = try? JSONSerialization.data(withJSONObject: node, options: [.fragmentsAllowed, .sortedKeys]) {
                result[path.map(escape).joined(separator: "/")] = data
            }
        }
        walk(object, at: [])
        return result
    }

    private static func materialize(_ fields: [String: Data]) -> HouseholdSnapshot {
        var root: [String: Any] = [:]
        func insert(_ value: Any, path: ArraySlice<String>, into object: inout [String: Any]) {
            guard let first = path.first else { return }
            if path.count == 1 { object[first] = value; return }
            var child = object[first] as? [String: Any] ?? [:]
            insert(value, path: path.dropFirst(), into: &child)
            object[first] = child
        }
        for (path, data) in fields {
            guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            let components = path.split(separator: "/", omittingEmptySubsequences: false).map { unescape(String($0)) }
            insert(value, path: components[...], into: &root)
        }
        func restore(_ node: [String: Any]) -> [String: Any] {
            var result = node
            for (key, value) in node {
                if memberships.contains(key), let members = value as? [String: Any] {
                    result[key] = members.keys.sorted { a, b in
                        let x = members[a] as? Int ?? 0, y = members[b] as? Int ?? 0
                        return x == y ? a < b : x < y
                    }
                } else if let child = value as? [String: Any] { result[key] = restore(child) }
            }
            return result
        }
        root = restore(root)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func decode<T: Decodable>(_ object: Any, as type: T.Type) -> T? {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? decoder.decode(type, from: data)
        }
        // Decode entries independently: one malformed legacy entry must not
        // discard the rest of a household. Presence tombstones dominate fields.
        let sources = (root["sources"] as? [String: [String: Any]] ?? [:]).values.compactMap { entry -> PlaylistSource? in
            guard entry["_present"] as? Bool == true else { return nil }
            return decode(entry, as: PlaylistSource.self)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let profiles = (root["profiles"] as? [String: [String: Any]] ?? [:]).values.compactMap { entry -> Profile? in
            guard entry["_present"] as? Bool == true else { return nil }
            return decode(entry, as: Profile.self)
        }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        var states: [String: WatchState] = [:]
        let rawStates = root["watchStates"] as? [String: Any] ?? [:]
        for profile in profiles {
            let key = profile.id.uuidString
            guard let object = rawStates[key], var state = decode(object, as: WatchState.self) else { continue }
            state.recentIDs = Array(state.recentIDs.sorted {
                let a = state.progress[$0]?.updatedAt ?? .distantPast
                let b = state.progress[$1]?.updatedAt ?? .distantPast
                return a == b ? $0 < $1 : a > b
            }.prefix(200))
            state.recentChannelGroupIDs = Array(state.recentChannelGroupIDs.prefix(50))
            state.recentItems = state.recentItems.filter { state.recentIDs.contains($0.key) }
            states[key] = state
        }
        return .init(modifiedAt: .distantPast, sources: sources, profiles: profiles, watchStates: states)
    }
}
