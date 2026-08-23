import KanalCore
import SwiftUI

/// A live channel tile: logo on a dark plate, with what's on right now beneath.
public struct ChannelCard: View {
    public let channel: MediaItem
    public var nowPlaying: Programme?
    public var isFavorite: Bool
    /// How many streams carry this channel. One is drawn plainly.
    public var sourceCount: Int
    public var action: () -> Void

    public init(
        channel: MediaItem,
        nowPlaying: Programme? = nil,
        isFavorite: Bool = false,
        sourceCount: Int = 1,
        action: @escaping () -> Void
    ) {
        self.channel = channel
        self.nowPlaying = nowPlaying
        self.isFavorite = isFavorite
        self.sourceCount = sourceCount
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                logoPlate
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(KanalFont.section(15))
                        .foregroundStyle(KanalColor.primaryText)
                        .lineLimit(1)
                    Text(nowPlaying?.title ?? channel.category.map(CategoryLocalizer.display) ?? " ")
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(KanalCardButtonStyle())
        .accessibilityLabel(accessibilityText)
    }

    private var logoPlate: some View {
        ZStack {
            // Most provider logos ship with a baked-in white background, so the
            // plate matches the scheme's card colour instead of forcing dark —
            // that way the logo's own edges disappear into the tile.
            RoundedRectangle(cornerRadius: KanalMetrics.cardRadius, style: .continuous)
                .fill(KanalColor.surface)
            Artwork(url: channel.logoURL, title: channel.title, symbol: "tv", contentMode: .fit)
                .padding(KanalMetrics.sm)
                .clipped()
        }
        .kanalArtworkTile(aspect: KanalMetrics.backdropAspect)
        .overlay(alignment: .topLeading) {
            if let nowPlaying, nowPlaying.isOnAir() {
                LiveBadge().padding(KanalMetrics.sm)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KanalColor.accentSolid)
                    .padding(6)
                    .background(.ultraThinMaterial, in: .circle)
                    .padding(KanalMetrics.sm)
            }
        }
        .overlay(alignment: .bottom) {
            if let nowPlaying {
                ProgressLine(fraction: nowPlaying.progress())
                    .padding(.horizontal, KanalMetrics.sm)
                    .padding(.bottom, KanalMetrics.sm)
            }
        }
    }

    /// Channel and programme names come from the provider, so this reads as
    /// a list rather than a sentence — there is no grammar to get wrong.
    private var accessibilityText: String {
        [channel.title, nowPlaying?.title].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A 2:3 poster for a movie or a show.
public struct PosterCard: View {
    public let title: String
    public let artworkURL: URL?
    public var subtitle: String?
    public var progressFraction: Double?
    /// When set, the poster is upgraded to real artwork once the title is
    /// identified. Left nil for anything we cannot look up, such as a channel.
    public var enrich: MediaItem?
    public var action: () -> Void

    public init(
        title: String,
        artworkURL: URL?,
        subtitle: String? = nil,
        progressFraction: Double? = nil,
        enrich: MediaItem? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.artworkURL = artworkURL
        self.subtitle = subtitle
        self.progressFraction = progressFraction
        self.enrich = enrich
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                artwork

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KanalFont.section(15))
                        .foregroundStyle(KanalColor.primaryText)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(KanalFont.body(12))
                            .foregroundStyle(KanalColor.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(KanalCardButtonStyle())
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let enrich {
                EnrichedArtwork(item: enrich, symbol: "film")
            } else {
                Artwork(url: artworkURL, title: title, symbol: "film")
            }
        }
        .kanalArtworkTile(aspect: KanalMetrics.posterAspect)
        .overlay(alignment: .bottom) {
            if let progressFraction {
                ProgressLine(fraction: progressFraction)
                    .padding(.horizontal, KanalMetrics.sm)
                    .padding(.bottom, KanalMetrics.sm)
            }
        }
    }
}

/// A wide 16:9 card, used for "Continue watching".
public struct ResumeCard: View {
    public let item: MediaItem
    public let progress: WatchProgress
    public var action: () -> Void

    public init(item: MediaItem, progress: WatchProgress, action: @escaping () -> Void) {
        self.item = item
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                Group {
                    if item.kind == .liveTV {
                        Artwork(url: item.logoURL, title: item.title, symbol: item.kind.symbolName)
                    } else {
                        EnrichedArtwork(item: item)
                    }
                }
                    .kanalArtworkTile(aspect: KanalMetrics.backdropAspect)
                    .overlay(alignment: .center) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)
                            .padding(14)
                            .kanalGlassOverVideo(cornerRadius: 100)
                    }
                    .overlay(alignment: .bottom) {
                        ProgressLine(fraction: progress.fraction)
                            .padding(.horizontal, KanalMetrics.sm)
                            .padding(.bottom, KanalMetrics.sm)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(KanalFont.section(15))
                        .foregroundStyle(KanalColor.primaryText)
                        .lineLimit(1)
                    Text(remainingText)
                        .font(KanalFont.body(12))
                        .foregroundStyle(KanalColor.secondaryText)
                }
            }
        }
        .buttonStyle(KanalCardButtonStyle())
    }

    private var remainingText: String {
        let minutes = Int(progress.remaining / 60)
        guard minutes >= 1 else { return String(UIStrings.nearlyFinished) }
        return String(UIStrings.minutesLeft(minutes))
    }
}

/// Card press and focus behaviour, shared so every tile reacts identically.
///
/// On tvOS the focused card is the entire interface — it is how you know where
/// you are from across a room — so it lifts, brightens and casts a shadow. On
/// touch there is no focus, and a press just needs to feel like a press.
public struct KanalCardButtonStyle: ButtonStyle {

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration)
    }

    private struct CardBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .contentShape(.rect)
                .scaleEffect(scale)
                .shadow(
                    color: .black.opacity(isFocused ? 0.35 : 0),
                    radius: isFocused ? 28 : 0,
                    y: isFocused ? 14 : 0
                )
                .brightness(isFocused ? 0.04 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.75), value: isFocused)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
                .zIndex(isFocused ? 1 : 0)
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.96 }
            #if os(tvOS)
            return isFocused ? 1.08 : 1
            #else
            return 1
            #endif
        }
    }
}
