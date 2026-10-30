import KanalCore
import SwiftUI

/// One control that covers the whole life of a download.
///
/// Download, waiting, downloading, done and failed are five states of the same
/// thing, and a viewer should never have to hunt for a second control to undo
/// what the first one started — so the button changes what it says rather than
/// appearing beside another button.
public struct DownloadButton: View {
    @Environment(AppModel.self) private var model
    @Environment(DownloadStore.self) private var downloads: DownloadStore?

    public let item: MediaItem
    /// `menu` is a row inside a context menu; `action` is a button on a screen.
    public var style: Style = .action

    public enum Style { case action, menu }

    public init(item: MediaItem, style: Style = .action) {
        self.item = item
        self.style = style
    }

    public var body: some View {
        // Live TV has no end to download, and a store the app has not wired up
        // means the feature is simply not present here.
        if let downloads, item.kind != .liveTV {
            let record = downloads.download(for: item.id, sourceID: model.activeSourceID)
            switch style {
            case .menu:
                Button(role: record == nil ? nil : .destructive) {
                    act(on: record, in: downloads)
                } label: {
                    Label(title(for: record), systemImage: symbol(for: record))
                }
            case .action:
                Button {
                    act(on: record, in: downloads)
                } label: {
                    Label(title(for: record), systemImage: symbol(for: record))
                        .labelStyle(.titleAndIcon)
                }
                // Full width on touch, where it is a row of its own; sized like
                // its neighbours on TV, where the actions sit side by side.
                #if os(tvOS)
                .buttonStyle(KanalSecondaryButtonStyle(size: 16))
                #else
                .buttonStyle(KanalSecondaryButtonStyle(fullWidth: true, size: 13))
                #endif
            }
        }
    }

    private func act(on record: Download?, in downloads: DownloadStore) {
        guard let record else {
            downloads.add(item, sourceID: model.activeSourceID)
            return
        }
        switch record.state {
        case .waiting, .downloading: downloads.cancel(record.id)
        case .finished: downloads.remove(record.id)
        case .failed: downloads.add(item, sourceID: model.activeSourceID)
        }
    }

    private func title(for record: Download?) -> String {
        guard let record else { return String(UIStrings.downloadAction) }
        return switch record.state {
        case .waiting, .downloading: String(UIStrings.downloadCancel)
        case .finished: String(UIStrings.downloadRemove)
        case .failed: String(UIStrings.downloadRetry)
        }
    }

    private func symbol(for record: Download?) -> String {
        guard let record else { return "arrow.down.circle" }
        return switch record.state {
        case .waiting, .downloading: "stop.circle"
        case .finished: "trash"
        case .failed: "arrow.clockwise"
        }
    }
}

/// The small mark saying a title is already on the device.
///
/// Sits where the live badge sits on a channel, and says the same kind of
/// thing: this one will start immediately.
public struct DownloadedBadge: View {
    public init() {}

    public var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(KanalColor.primaryText)
            .padding(6)
            .background(.ultraThinMaterial, in: .circle)
            .accessibilityLabel(Text(UIStrings.downloadedBadge))
    }
}

/// Where one download has got to, as a line of plain language rather than a
/// percentage on its own — "38 % of what?" is a question a size answers.
public enum DownloadSummary {
    public static func text(_ record: Download) -> String {
        switch record.state {
        case .waiting:
            String(UIStrings.downloadWaiting)
        case .downloading:
            if let fraction = record.fraction {
                "\(String(UIStrings.downloadRunning)) · \(fraction.formatted(.percent.precision(.fractionLength(0))))"
            } else {
                "\(String(UIStrings.downloadRunning)) · \(DownloadSize.text(record.byteCount))"
            }
        case .finished:
            DownloadSize.text(record.byteCount)
        case .failed(let message):
            message
        }
    }
}


public enum DownloadSize {
    /// Formatted the way the Settings app formats storage, so the number here
    /// and the number there are comparable.
    public static func text(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
