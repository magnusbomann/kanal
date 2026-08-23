import KanalCore
import SwiftUI

/// What happens when an episode ends.
///
/// Watching a series is watching a sequence. Stopping dead at every credit
/// roll makes the viewer do the sequencing by hand, so the next episode starts
/// itself — but visibly, and with a way out, because the other failure is an
/// app that keeps playing at someone who fell asleep.
public struct NextEpisodeOverlay: View {
    public let episode: MediaItem
    public let secondsRemaining: Int
    public let onPlayNow: () -> Void
    public let onStop: () -> Void

    public init(
        episode: MediaItem,
        secondsRemaining: Int,
        onPlayNow: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.episode = episode
        self.secondsRemaining = secondsRemaining
        self.onPlayNow = onPlayNow
        self.onStop = onStop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            Text(UIStrings.nextEpisode)
                .kanalLabel(11)
                .foregroundStyle(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                if let code = episode.episodeCode {
                    Text(code)
                        .kanalLabel(12)
                        .foregroundStyle(KanalColor.accentSolid)
                }
                Text(episode.episodeTitle ?? episode.title)
                    .font(KanalFont.section(18))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: KanalMetrics.sm) {
                Button(action: onPlayNow) {
                    Label(String(UIStrings.playNow), systemImage: "play.fill")
                }
                .buttonStyle(KanalPrimaryButtonStyle(size: 14))

                Button(String(UIStrings.stopWatching), action: onStop)
                    .buttonStyle(KanalSecondaryButtonStyle(size: 14))
            }

            // The count is the promise being kept, so it is stated plainly
            // rather than left as a shrinking ring nobody can read.
            Text(UIStrings.playingInSeconds(secondsRemaining))
                .font(KanalFont.body(12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(KanalMetrics.lg)
        .frame(maxWidth: 420, alignment: .leading)
        .kanalGlassPanel()
        .accessibilityElement(children: .contain)
    }
}
