import KanalCore
import SwiftUI

/// The controls, drawn over whichever engine is playing.
///
/// Kanal runs two engines — AVFoundation for live TV and MP4, VLC for the
/// Matroska that makes up nearly every film — and Apple's own player chrome
/// cannot be restyled. Mimicking it would leave the two paths *nearly* alike,
/// which is the version that looks broken. So both wear this instead, and they
/// match because they are the same view rather than two good imitations.
public struct PlayerChrome: View {
    public let controller: any PlaybackControlling
    public let title: String
    public let subtitle: String?
    public let onClose: () -> Void
    /// Supplied only by the engine that can offer them.
    public var sourceAccessory: AnyView?
    public var trailingAccessory: AnyView?

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    @State private var showsTracks = false

    public init(
        controller: any PlaybackControlling,
        title: String,
        subtitle: String? = nil,
        sourceAccessory: AnyView? = nil,
        trailingAccessory: AnyView? = nil,
        onClose: @escaping () -> Void
    ) {
        self.controller = controller
        self.title = title
        self.subtitle = subtitle
        self.sourceAccessory = sourceAccessory
        self.trailingAccessory = trailingAccessory
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            // A tap anywhere brings the controls back, or dismisses them.
            Color.black.opacity(isVisible ? 0.28 : 0.001)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { toggleVisibility() }

            if isVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    transport
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
            }

            if controller.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: controller.isBuffering)
        #if os(tvOS)
        // The remote is the only pointing device here: left and right skip,
        // and the play/pause button does what it says.
        .onMoveCommand { direction in
            isVisible = true
            switch direction {
            case .left: controller.skip(by: -10)
            case .right: controller.skip(by: 10)
            default: break
            }
            scheduleHide()
        }
        .onPlayPauseCommand {
            controller.togglePlayPause()
            isVisible = true
            scheduleHide()
        }
        .onExitCommand { onClose() }
        #endif
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
        .sheet(isPresented: $showsTracks) {
            TrackPickerSheet(controller: controller)
        }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(alignment: .top, spacing: KanalMetrics.md) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
                    .kanalGlassOverVideo(cornerRadius: 100)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.close")
            .accessibilityLabel(Text(UIStrings.closePlayer))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KanalFont.section(16))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(KanalFont.body(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if hasTracks {
                Button {
                    showsTracks = true
                    scheduleHide()
                } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
                        .kanalGlassOverVideo(cornerRadius: 100)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("player.tracks")
                .accessibilityLabel(Text(UIStrings.audioAndSubtitles))
            }

            if let sourceAccessory { sourceAccessory }

            if let trailingAccessory {
                trailingAccessory.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.top, KanalMetrics.sm)
    }

    /// Titles run long and the row is shared with buttons, so the text gets
    /// whatever is left rather than pushing them off screen.

    private var transport: some View {
        HStack(spacing: KanalMetrics.xl) {
            if controller.isScrubbable {
                skipButton(seconds: -10, symbol: "gobackward.10")
            }

            Button {
                controller.togglePlayPause()
                scheduleHide()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .kanalGlassOverVideo(cornerRadius: 100)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.playPause")
            .accessibilityLabel(Text(controller.isPlaying ? UIStrings.pause : UIStrings.play))

            if controller.isScrubbable {
                skipButton(seconds: 10, symbol: "goforward.10")
            }
        }
    }

    private func skipButton(seconds: TimeInterval, symbol: String) -> some View {
        Button {
            controller.skip(by: seconds)
            scheduleHide()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .kanalGlassOverVideo(cornerRadius: 100)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(seconds < 0 ? "player.back" : "player.forward")
    }

    @ViewBuilder
    private var bottomBar: some View {
        if controller.isLive {
            HStack {
                LiveBadge()
                Spacer()
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.bottom, KanalMetrics.lg)
        } else if controller.isScrubbable {
            VStack(spacing: KanalMetrics.xs) {
                Scrubber(
                    progress: scrubbing ?? controller.progress,
                    onScrub: { value in
                        scrubbing = value
                        hideTask?.cancel()
                    },
                    onCommit: { value in
                        controller.seek(to: value * controller.duration)
                        scrubbing = nil
                        scheduleHide()
                    }
                )

                HStack {
                    Text(Self.timeLabel((scrubbing ?? controller.progress) * controller.duration))
                    Spacer()
                    Text("-" + Self.timeLabel(
                        controller.duration - (scrubbing ?? controller.progress) * controller.duration
                    ))
                }
                .font(KanalFont.caption(11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, KanalMetrics.lg)
            .padding(.bottom, KanalMetrics.lg)
        }
    }

    // MARK: Behaviour

    private var hasTracks: Bool {
        controller.audioTracks.count > 1 || !controller.subtitleTracks.isEmpty
    }

    private func toggleVisibility() {
        isVisible.toggle()
        if isVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    /// Controls get out of the way on their own, but never while paused —
    /// nobody wants to hunt for the play button.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, controller.isPlaying else { return }
            isVisible = false
        }
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// The progress bar.
///
/// On touch it is draggable, and grows under the thumb so the target is
/// generous without the resting state being heavy. On tvOS there is nothing to
/// drag with, so it shows position and the remote does the seeking — which is
/// what the platform's own players do too.
struct Scrubber: View {
    let progress: Double
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            bar(width: proxy.size.width)
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private func bar(width: CGFloat) -> some View {
        let track = ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.25))
            Capsule()
                .fill(KanalColor.accent)
                .frame(width: max(width * progress, 0))
        }
        .frame(height: isDragging ? 8 : 4)
        .frame(maxHeight: .infinity, alignment: .center)

        #if os(tvOS)
        track
        #else
        track
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        onScrub(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { value in
                        isDragging = false
                        onCommit(min(max(value.location.x / width, 0), 1))
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        #endif
    }
}
