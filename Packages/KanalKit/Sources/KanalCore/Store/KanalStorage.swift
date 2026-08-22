import Foundation

/// On-disk state.
///
/// Plain JSON files rather than a database: the whole model is a handful of
/// arrays, and a corrupt cache should cost a refresh, never a crash.
public actor KanalStorage {

    public static let shared = KanalStorage()

    private let directory: URL
    /// Caches live where the system may reclaim them under pressure. A
    /// catalogue can be hundreds of megabytes, and losing it costs a refresh.
    private let cacheDirectory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.directory = base.appending(path: "Kanal", directoryHint: .isDirectory)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        self.cacheDirectory = (caches ?? self.directory)
            .appending(path: "Kanal", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Caches

    public func loadCache(_ name: String) -> Data? {
        try? Data(contentsOf: cacheDirectory.appending(path: name))
    }

    public func saveCache(_ data: Data, to name: String) {
        try? data.write(to: cacheDirectory.appending(path: name), options: .atomic)
    }

    public func removeCache(_ name: String) {
        try? FileManager.default.removeItem(at: cacheDirectory.appending(path: name))
    }

    public func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        let url = directory.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    public func save(_ value: some Encodable, to name: String) {
        let url = directory.appending(path: name)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
}
