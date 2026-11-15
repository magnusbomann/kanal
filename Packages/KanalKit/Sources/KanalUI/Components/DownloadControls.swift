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
    @Environment(Navigator.self) private var navigator
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
            let record = downloads.download(
                forAnyOf: model.downloadVariants(for: item), sourceID: model.activeSourceID
            )
            switch style {
            case .menu:
                Button(role: record == nil ? nil : .destructive) {
                    act(on: record, in: downloads)
                } label: {
                    Label(title(for: record), systemImage: symbol(for: record))
                }
            case .action:
                VStack(alignment: .leading, spacing: KanalMetrics.xs) {
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

                    // Where it has got to, right under the button that started
                    // it. Only the library said so before, and nobody goes
                    // there to find out whether the film they just tapped is
                    // coming.
                    if let record, record.state.isActive {
                        DownloadProgressLine(record: record)
                    }
                }
            }
        }
    }

    private func act(on record: Download?, in downloads: DownloadStore) {
        guard let record else {
            // Several versions: ask which. One: nothing to ask.
            if model.downloadVariants(for: item).count > 1 {
                navigator.choosingDownload = item
            } else {
                downloads.add(item, sourceID: model.activeSourceID)
            }
            return
        }
        switch record.state {
        case .waiting, .downloading: downloads.cancel(record.id)
        case .finished: downloads.remove(record.id)
        // The version chosen last time, again.
        case .failed: downloads.add(record.item, sourceID: model.activeSourceID)
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

/// A bar and the same words the library uses: percent when the provider says
/// how big the file is, the amount so far when it does not.
struct DownloadProgressLine: View {
    let record: Download
    @Environment(DownloadStore.self) private var downloads: DownloadStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if record.state == .downloading, let fraction = record.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(DownloadSummary.text(record, secondsRemaining: downloads?.secondsRemaining(for: record)))
                .font(KanalFont.caption())
                .foregroundStyle(KanalColor.secondaryText)
                .monospacedDigit()
        }
        .tint(KanalColor.accentSolid)
        .accessibilityElement(children: .combine)
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
    public static func text(_ record: Download, secondsRemaining: TimeInterval? = nil) -> String {
        switch record.state {
        case .waiting:
            String(UIStrings.downloadWaiting)
        case .downloading:
            if let fraction = record.fraction {
                // "38 % · 1,2 GB / 3,1 GB · About 4 minutes remaining": how far,
                // of how much, and how long — a percentage alone answers none
                // of the questions people actually have.
                [
                    "\(String(UIStrings.downloadRunning)) · \(fraction.formatted(.percent.precision(.fractionLength(0))))",
                    "\(DownloadSize.text(record.byteCount)) / \(DownloadSize.text(record.expectedByteCount))",
                    secondsRemaining.flatMap(timeLeft),
                ].compactMap { $0 }.joined(separator: " · ")
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


extension DownloadSummary {
    /// Worded by the system in the person's own language — "About 4 minutes
    /// remaining" — so there is nothing here to translate.
    static func timeLeft(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : (seconds >= 60 ? [.minute] : [.second])
        formatter.includesApproximationPhrase = true
        formatter.includesTimeRemainingPhrase = true
        return formatter.string(from: seconds)
    }
}

/// The versions of a film, with what each would cost to keep.
struct DownloadVersionSheet: View {
    let item: MediaItem
    @Environment(AppModel.self) private var model
    @Environment(DownloadStore.self) private var downloads: DownloadStore?
    @Environment(\.dismiss) private var dismiss
    @State private var options: [DownloadOption]?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let options {
                        ForEach(options) { option in
                            Button {
                                downloads?.add(option.item, sourceID: model.activeSourceID)
                                dismiss()
                            } label: {
                                row(option)
                            }
                            .accessibilityIdentifier("download.version")
                        }
                    } else {
                        // The panel answers in a moment; the versions are
                        // known already, only their sizes are on the way.
                        ForEach(model.downloadVariants(for: item)) { variant in
                            row(DownloadOption(item: variant), loading: true)
                        }
                    }
                } footer: {
                    Text(UIStrings.downloadVersionHint)
                }
            }
            .navigationTitle(Text(UIStrings.downloadVersionTitle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(UIStrings.cancel)) { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .task {
            let loaded = await model.downloadOptions(for: item)
            // Smallest first: the reason anyone opens this is to save space.
            options = loaded.sorted { ($0.estimatedBytes ?? .max) < ($1.estimatedBytes ?? .max) }
        }
    }

    private func row(_ option: DownloadOption, loading: Bool = false) -> some View {
        HStack(spacing: KanalMetrics.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.quality ?? String(UIStrings.downloadVersionStandard))
                    .font(KanalFont.section(16))
                    .foregroundStyle(KanalColor.primaryText)
                Group {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else if let bytes = option.estimatedBytes {
                        Text(verbatim: "≈ " + DownloadSize.text(bytes))
                    } else {
                        Text(UIStrings.downloadVersionUnknownSize)
                    }
                }
                .font(KanalFont.caption())
                .foregroundStyle(KanalColor.secondaryText)
                .monospacedDigit()
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(KanalColor.accentSolid)
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
    }
}

public enum DownloadSize {
    /// Formatted the way the Settings app formats storage, so the number here
    /// and the number there are comparable.
    public static func text(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
