import Foundation
import Observation

/// Films and episodes kept on the device.
///
/// Three facts about a real provider shape everything here:
///
/// 1. **One connection at a time.** The measured panel allows a single
///    concurrent stream, so downloads run strictly one after another and stand
///    aside entirely while someone is watching. A download that quietly steals
///    the slot would look like the app breaking playback.
/// 2. **The catalogue is not stable.** Records keep a whole `MediaItem`, so a
///    file on the disk is still nameable after the provider drops the title.
/// 3. **Nothing arrives with an extension.** Saved as Matroska unless the url
///    says otherwise, which is also what routes it to the engine that opens it.
@MainActor
@Observable
public final class DownloadStore {

    /// Newest first, in the order the library shows them.
    public private(set) var downloads: [Download] = []
    /// Set while a stream is on screen. The queue is held back until it clears.
    public private(set) var isHeldForPlayback = false

    @ObservationIgnored private let storage: KanalStorage
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let makeSession: (URLSessionDelegate) -> URLSession

    public static let fileName = "downloads.json"

    public init(
        storage: KanalStorage = .shared,
        directory: URL? = nil,
        makeSession: ((URLSessionDelegate) -> URLSession)? = nil
    ) {
        self.storage = storage
        self.directory = directory ?? Self.defaultDirectory()
        self.makeSession = makeSession ?? { delegate in
            #if os(macOS)
            let configuration = URLSessionConfiguration.default
            #else
            // Keeps going while the app is in the background, and picks up
            // where it left off the next time the app runs.
            let configuration = URLSessionConfiguration.background(
                withIdentifier: "com.bomann.kanal.downloads"
            )
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = false
            #endif
            // The provider allows one connection; asking for more poisons the
            // account into redirect loops for minutes.
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.timeoutIntervalForResource = 60 * 60 * 12
            return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// tvOS has no durable place for large files: everything an app writes
    /// outside the caches directory is size-limited, so downloads there are
    /// explicitly a cache the system may reclaim, and the library screen says so.
    private static func defaultDirectory() -> URL {
        #if os(tvOS)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        return (base ?? FileManager.default.temporaryDirectory)
            .appending(path: "Kanal", directoryHint: .isDirectory)
            .appending(path: "Downloads", directoryHint: .isDirectory)
    }

    // MARK: Lifecycle

    /// Reads the index and reconciles it with what is actually on the disk and
    /// what the background session is still carrying.
    public func start() async {
        downloads = await storage.load([Download].self, from: Self.fileName) ?? []
        let session = makeSession(makeDelegate())
        self.session = session

        let live = await session.allTasks.compactMap { $0 as? URLSessionDownloadTask }
        for task in live {
            guard let name = task.taskDescription,
                  let record = downloads.first(where: { $0.fileName == name }),
                  record.state.isActive
            else {
                task.cancel()
                continue
            }
            tasks[record.id] = task
        }

        // A record left mid-flight by a crash or a force-quit has no task to
        // come back to. Put it back in the queue rather than leaving a row
        // that says "downloading" forever.
        for index in downloads.indices where downloads[index].state == .downloading {
            if tasks[downloads[index].id] == nil { downloads[index].state = .waiting }
        }
        // A finished record whose file is gone — a purged tvOS cache, a restore
        // from backup — is not finished.
        for index in downloads.indices where downloads[index].isFinished {
            if !FileManager.default.fileExists(atPath: fileURL(downloads[index]).path) {
                downloads[index].state = .failed(CoreStrings.downloadFileMissing.resolved)
            }
        }
        persist()
        pump()
    }

    // MARK: Queries

    public func download(for itemID: String, sourceID: UUID?) -> Download? {
        let key = Download.key(itemID: itemID, sourceID: sourceID)
        return downloads.first { $0.id == key }
    }

    /// The local file to play instead of going to the provider, when there is
    /// one. Everything else in the app routes through this.
    public func playableFile(for item: MediaItem, sourceID: UUID?) -> URL? {
        guard let record = download(for: item.id, sourceID: sourceID), record.isFinished else {
            return nil
        }
        let url = fileURL(record)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public var finished: [Download] { downloads.filter(\.isFinished) }
    public var inProgress: [Download] { downloads.filter { $0.state.isActive } }

    public var totalByteCount: Int64 {
        downloads.reduce(0) { $0 + $1.byteCount }
    }

    public func fileURL(_ record: Download) -> URL {
        directory.appending(path: record.fileName)
    }

    // MARK: Commands

    /// Queues a title. Live TV is refused: there is no end to download.
    @discardableResult
    public func add(_ item: MediaItem, sourceID: UUID?) -> Download? {
        guard item.kind != .liveTV else { return nil }
        let key = Download.key(itemID: item.id, sourceID: sourceID)
        if let existing = downloads.first(where: { $0.id == key }) {
            // A failed attempt is retried in place rather than duplicated.
            guard case .failed = existing.state else { return existing }
            update(key) { record in
                record.item = item
                record.state = .waiting
                record.byteCount = 0
            }
            pump()
            return download(for: item.id, sourceID: sourceID)
        }
        let record = Download(
            id: key,
            item: item,
            sourceID: sourceID,
            fileName: "\(UUID().uuidString).\(Download.fileExtension(for: item))"
        )
        downloads.insert(record, at: 0)
        persist()
        pump()
        return record
    }

    /// Stops a download and forgets it. The partial file goes with it — half a
    /// film is not something anyone wants to find later.
    public func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        remove(id)
    }

    /// Deletes the file and the record.
    public func remove(_ id: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let record = downloads.remove(at: index)
        tasks[id]?.cancel()
        tasks[id] = nil
        try? FileManager.default.removeItem(at: fileURL(record))
        persist()
        pump()
    }

    public func removeAll() {
        for record in downloads {
            tasks[record.id]?.cancel()
            try? FileManager.default.removeItem(at: fileURL(record))
        }
        tasks.removeAll()
        downloads.removeAll()
        persist()
    }

    /// Everything belonging to a service that has been deleted.
    public func removeAll(forSource sourceID: UUID) {
        for record in downloads where record.sourceID == sourceID {
            remove(record.id)
        }
    }

    /// Called when playback starts and stops.
    ///
    /// The account allows one connection. A download running underneath a film
    /// does not merely slow it down — it takes the slot, and the film stops.
    public func setPlaybackActive(_ active: Bool) {
        guard isHeldForPlayback != active else { return }
        isHeldForPlayback = active
        if active {
            for task in tasks.values { task.suspend() }
        } else {
            pump()
        }
    }

    // MARK: Queue

    /// Keeps exactly one download running, and only when nothing is playing.
    private func pump() {
        guard let session else { return }
        guard !isHeldForPlayback else { return }
        if let running = downloads.first(where: { $0.state == .downloading }) {
            // Resumes the one that was set aside for playback.
            tasks[running.id]?.resume()
            return
        }
        guard let next = downloads.last(where: { $0.state == .waiting }) else { return }

        let task = session.downloadTask(with: next.item.streamURL)
        task.taskDescription = next.fileName
        tasks[next.id] = task
        update(next.id) { $0.state = .downloading }
        task.resume()
    }

    // MARK: Delegate callbacks

    private func makeDelegate() -> URLSessionDelegate {
        DownloadDelegate(
            directory: directory,
            onProgress: { [weak self] name, written, expected in
                Task { @MainActor in self?.recordProgress(name, written: written, expected: expected) }
            },
            onFinish: { [weak self] name, size in
                Task { @MainActor in self?.recordFinished(name, size: size) }
            },
            onFailure: { [weak self] name, message in
                Task { @MainActor in self?.recordFailure(name, message: message) }
            }
        )
    }

    func recordProgress(_ fileName: String, written: Int64, expected: Int64) {
        guard let record = downloads.first(where: { $0.fileName == fileName }) else { return }
        update(record.id, persisting: false) {
            $0.byteCount = written
            if expected > 0 { $0.expectedByteCount = expected }
        }
    }

    /// Internal rather than private so tests can drive a finished download
    /// without a network.
    func recordFinished(_ fileName: String, size: Int64) {
        guard let record = downloads.first(where: { $0.fileName == fileName }) else { return }
        tasks[record.id] = nil
        update(record.id) {
            $0.state = .finished
            $0.byteCount = size
            $0.expectedByteCount = size
            $0.finishedAt = .now
        }
        pump()
    }

    func recordFailure(_ fileName: String, message: String) {
        guard let record = downloads.first(where: { $0.fileName == fileName }) else { return }
        tasks[record.id] = nil
        try? FileManager.default.removeItem(at: fileURL(record))
        update(record.id) {
            $0.state = .failed(message)
            $0.byteCount = 0
        }
        pump()
    }

    private func update(_ id: String, persisting: Bool = true, _ change: (inout Download) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        change(&downloads[index])
        if persisting { persist() }
    }

    /// Debounced: progress arrives many times a second and the index is the
    /// whole list.
    private func persist() {
        saveTask?.cancel()
        let snapshot = downloads
        saveTask = Task { [storage] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await storage.save(snapshot, to: Self.fileName)
        }
    }

    /// Writes the index now — for app suspension, where a debounce loses.
    public func flush() async {
        saveTask?.cancel()
        await storage.save(downloads, to: Self.fileName)
    }
}

/// `URLSession` calls back on its own queue and `URLSessionDelegate` carries no
/// isolation, so the bridge to the main actor lives here.
///
/// The finished file has to be moved before this method returns — the system
/// deletes the temporary copy immediately afterwards — which is why the
/// destination is computed here rather than asked for across an actor hop.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let directory: URL
    private let onProgress: @Sendable (String, Int64, Int64) -> Void
    private let onFinish: @Sendable (String, Int64) -> Void
    private let onFailure: @Sendable (String, String) -> Void

    init(
        directory: URL,
        onProgress: @escaping @Sendable (String, Int64, Int64) -> Void,
        onFinish: @escaping @Sendable (String, Int64) -> Void,
        onFailure: @escaping @Sendable (String, String) -> Void
    ) {
        self.directory = directory
        self.onProgress = onProgress
        self.onFinish = onFinish
        self.onFailure = onFailure
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let name = downloadTask.taskDescription else { return }
        onProgress(name, totalBytesWritten, max(totalBytesExpectedToWrite, 0))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let name = downloadTask.taskDescription else { return }

        // A panel under load answers with a redirect loop or an error page and
        // the download "succeeds" — a few hundred bytes of HTML that would sit
        // in the library pretending to be a film.
        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode >= 400 {
            onFailure(name, CoreStrings.downloadRefused.resolved)
            return
        }

        let destination = directory.appending(path: name)
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? manager.removeItem(at: destination)
        do {
            try manager.moveItem(at: location, to: destination)
        } catch {
            onFailure(name, error.localizedDescription)
            return
        }

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init) ?? 0
        guard size > 64 * 1024 else {
            try? manager.removeItem(at: destination)
            onFailure(name, CoreStrings.downloadTooSmall.resolved)
            return
        }
        onFinish(name, size)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let name = task.taskDescription, let error else { return }
        // A cancellation is a deletion the person asked for; the record is
        // already gone and there is nothing to report.
        if (error as NSError).code == NSURLErrorCancelled { return }
        onFailure(name, error.localizedDescription)
    }
}
