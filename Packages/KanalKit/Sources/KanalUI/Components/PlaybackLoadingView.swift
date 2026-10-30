import KanalCore
import SwiftUI

/// What the player is doing before the first frame arrives.
///
/// A bare spinner is the same picture whether a stream is opening normally,
/// has stalled, or is being replaced by another feed — and a wait that says
/// nothing is the one people read as a crash. Naming the stage is what turns
/// thirty seconds of nothing into thirty seconds of something happening.
public enum PlaybackStage: Equatable, Sendable {
    /// The engine has the url and is opening it.
    case connecting
    /// The stream is open and filling its buffer.
    case buffering
    /// Still nothing after long enough that a viewer starts to wonder.
    case slow
    /// This feed was given up on; another one is being tried.
    case switchingSource(number: Int, count: Int)

    var message: LocalizedStringResource {
        switch self {
        case .connecting: UIStrings.playbackStageConnecting
        case .buffering: UIStrings.playbackStageBuffering
        case .slow: UIStrings.playbackStageSlow
        case .switchingSource(let number, let count):
            UIStrings.playbackStageSwitching(number, count)
        }
    }

    /// The second line, when there is something worth adding. A viewer who is
    /// told only "this is slow" cannot tell whether to keep waiting.
    var detail: LocalizedStringResource? {
        switch self {
        case .connecting, .buffering: nil
        case .slow: UIStrings.playbackStageSlowDetail
        case .switchingSource: UIStrings.playbackStageSwitchingDetail
        }
    }
}

/// The screen shown while a film or an episode is opening.
///
/// Built around the poster on purpose: it is the one thing that confirms the
/// right title is loading, which is most of what someone is checking when they
/// stare at a wait.
struct PlaybackLoadingView: View {
    let item: MediaItem
    let subtitle: String?
    let stage: PlaybackStage
    /// The way out. The transport controls are deliberately absent until there
    /// is a picture, so this screen has to carry the escape itself — a wait
    /// nobody can leave is the worst version of a wait.
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            content
                .padding(KanalMetrics.xl)
                .frame(maxWidth: KanalMetrics.playbackPanelWidth)
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
    }

    private var content: some View {
        HStack(spacing: KanalMetrics.lg) {
            poster
            VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                Text(item.title)
                    .font(KanalFont.section(KanalMetrics.scale * 20))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(KanalFont.body(KanalMetrics.scale * 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                status
                    .padding(.top, KanalMetrics.xs)
                Button(String(UIStrings.closePlayer), action: onCancel)
                    .buttonStyle(KanalSecondaryButtonStyle(size: KanalMetrics.scale * 13))
                    .padding(.top, KanalMetrics.sm)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text(stage.message))
    }

    private var poster: some View {
        EnrichedArtwork(item: item, symbol: item.kind.symbolName)
            .kanalArtworkTile(aspect: KanalMetrics.posterAspect)
            .frame(width: posterWidth)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.xs) {
            HStack(spacing: KanalMetrics.sm) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(stage.message)
                    .font(KanalFont.label(KanalMetrics.scale * 14))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let detail = stage.detail {
                Text(detail)
                    .font(KanalFont.body(KanalMetrics.scale * 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .transition(.opacity)
    }

    private var posterWidth: CGFloat {
        #if os(tvOS)
        220
        #else
        110
        #endif
    }
}

/// The same message, compressed, for a stream that has already played and is
/// re-buffering. Covering the picture with the poster again at that point
/// would hide the very thing someone is waiting to see move.
struct PlaybackStallPill: View {
    let stage: PlaybackStage

    var body: some View {
        HStack(spacing: KanalMetrics.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text(stage.message)
                .font(KanalFont.label(KanalMetrics.scale * 13))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.vertical, KanalMetrics.sm)
        .kanalGlassOverVideo(cornerRadius: 100)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
