import Foundation

/// Where one download has got to.
///
/// `failed` carries the reason as text because the causes are not a fixed set:
/// a panel that answers 302 forever, a disk that filled up and a link that
/// expired all end here, and only the first is worth retrying.
public enum DownloadState: Codable, Sendable, Hashable {
    /// In the queue, waiting for the one slot.
    case waiting
    case downloading
    case finished
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .waiting, .downloading: true
        case .finished, .failed: false
        }
    }
}

/// One title kept on the device.
///
/// The `item` is stored whole rather than as an id. A provider rewrites its
/// catalogue between refreshes — signed urls rotate, films disappear — and a
/// file already on the disk must survive that, otherwise the one copy that
/// cannot go away is the one the app forgets how to name.
public struct Download: Codable, Sendable, Hashable, Identifiable {
    /// Source-scoped, so two providers carrying the same numeric id are two
    /// different downloads.
    public let id: String
    public var item: MediaItem
    public var sourceID: UUID?
    /// Name inside the downloads directory. Unique, generated once.
    public let fileName: String
    public var state: DownloadState
    /// Bytes on disk so far, or the finished size.
    public var byteCount: Int64
    /// What the server said it would be, when it said anything. Zero means
    /// unknown, which is common: panels stream without a content length.
    public var expectedByteCount: Int64
    public var addedAt: Date
    public var finishedAt: Date?

    public init(
        id: String,
        item: MediaItem,
        sourceID: UUID?,
        fileName: String,
        state: DownloadState = .waiting,
        byteCount: Int64 = 0,
        expectedByteCount: Int64 = 0,
        addedAt: Date = .now,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.item = item
        self.sourceID = sourceID
        self.fileName = fileName
        self.state = state
        self.byteCount = byteCount
        self.expectedByteCount = expectedByteCount
        self.addedAt = addedAt
        self.finishedAt = finishedAt
    }

    /// Nil while the size is unknown, so the interface can show an indeterminate
    /// bar rather than a progress ring frozen at zero.
    public var fraction: Double? {
        guard expectedByteCount > 0 else { return nil }
        return min(max(Double(byteCount) / Double(expectedByteCount), 0), 1)
    }

    public var isFinished: Bool { state == .finished }

    /// How this download is titled and grouped in the library. An episode
    /// belongs under its show; everything else stands for itself.
    public var groupingTitle: String {
        item.seriesName ?? item.title
    }

    /// Scoping key, matching how watch history is keyed to a service.
    public static func key(itemID: String, sourceID: UUID?) -> String {
        guard let sourceID else { return itemID }
        return "\(sourceID.uuidString)|\(itemID)"
    }

    /// The container to save as.
    ///
    /// A provider url usually carries no extension at all, and what comes back
    /// is Matroska whatever was asked for. Guessing `.mkv` in that case is not
    /// a shot in the dark: it is what this catalogue measurably serves, and it
    /// routes the file straight to the engine that can open it.
    public static func fileExtension(for item: MediaItem) -> String {
        let ext = item.streamURL.pathExtension.lowercased()
        if StreamCandidates.native.contains(ext) || StreamCandidates.foreign.contains(ext) {
            return ext
        }
        return "mkv"
    }
}
