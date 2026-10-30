import Foundation
import KanalCore
import SwiftUI

/// The controls, drawn over whichever engine is playing.
///
/// Kanal runs two engines — AVFoundation for live TV and MP4, VLC for the
/// Matroska that makes up nearly every film — and Apple's own player chrome
/// cannot be restyled. Mimicking it would leave the two paths *nearly* alike,
/// which is the version that looks broken. So both wear this instead, and they
/// match because they are the same view rather than two good imitations.
/// Walking between the streams that carry one channel.
///
/// The system controller does this itself. The alternative engine is handed a
/// single url and has no plan to walk, so when it is the one playing, the
/// screen that owns the plan supplies this instead — and the control looks and
/// behaves identically either way, which is the whole point of one chrome.
public struct SourceControl {
    public let number: Int
    public let count: Int
    public let isSwitching: Bool
    public let onSwitch: () -> Void

    public init(number: Int, count: Int, isSwitching: Bool, onSwitch: @escaping () -> Void) {
        self.number = number
        self.count = count
        self.isSwitching = isSwitching
        self.onSwitch = onSwitch
    }
}

public struct PlayerChrome: View {
    public let controller: any PlaybackControlling
    public let title: String
    public let subtitle: String?
    public let onClose: () -> Void
    /// Only for an engine that cannot walk the plan on its own.
    public var sourceControl: SourceControl?
    /// Supplied only by the engine that can offer them.
    public var sourceAccessory: AnyView?
    public var trailingAccessory: AnyView?
    /// Drawn in the top corner while the controls are *hidden*.
    ///
    /// Owned by the chrome rather than laid over it, because the only corner a
    /// watermark belongs in is the one the controls also want. Handing it to
    /// the view that knows when they are up is how the two never collide.
    public var watermark: AnyView?

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    @State private var showsTracks = false
    #if os(tvOS)
    private enum FocusTarget: Hashable { case surface, close, play, timeline }
    @FocusState private var focusedTarget: FocusTarget?
    @State private var controlsEngaged = false
    @State private var seekState = TelevisionSeekState(duration: 0)
    #endif

    public init(
        controller: any PlaybackControlling,
        title: String,
        subtitle: String? = nil,
        sourceAccessory: AnyView? = nil,
        trailingAccessory: AnyView? = nil,
        watermark: AnyView? = nil,
        sourceControl: SourceControl? = nil,
        onClose: @escaping () -> Void
    ) {
        self.controller = controller
        self.title = title
        self.subtitle = subtitle
        self.sourceAccessory = sourceAccessory
        self.trailingAccessory = trailingAccessory
        self.watermark = watermark
        self.sourceControl = sourceControl
        self.onClose = onClose
    }

    /// Whichever of the two knows about the other feeds.
    private var sources: SourceControl? {
        if let sourceControl { return sourceControl.count > 1 ? sourceControl : nil }
        guard controller.canSwitchSource else { return nil }
        return SourceControl(
            number: controller.sourceNumber,
            count: controller.sourceCount,
            isSwitching: controller.isSwitchingSource,
            onSwitch: { controller.switchSource() }
        )
    }

    public var body: some View {
        ZStack {
            // A tap anywhere brings the controls back, or dismisses them.
            Color.black.opacity(isVisible ? 0.28 : 0.001)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { toggleVisibility() }
                #if os(tvOS)
                .focusable(!isVisible)
                .focused($focusedTarget, equals: .surface)
                .onMoveCommand { _ in
                    guard !isVisible else { return }
                    isVisible = true
                    focusedTarget = .play
                    scheduleHide()
                }
                #endif

            if isVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    transport
                    Spacer(minLength: 0)
                    bottomBar
                }
                #if os(tvOS)
                .focusSection()
                .onMoveCommand { _ in controlsEngaged = true }
                #endif
                .transition(.opacity)
            }

            if let watermark, !isVisible {
                watermark
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.horizontal, KanalMetrics.lg)
                    .padding(.top, KanalMetrics.md)
                    .transition(.opacity)
            }

            if sources?.isSwitching == true {
                // Named rather than left as a bare spinner. Finding another
                // feed took around four seconds against the measured provider
                // and occasionally much longer, and a wait that says nothing
                // is the one people read as a crash.
                VStack(spacing: KanalMetrics.sm) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(UIStrings.switchingSource)
                        .font(KanalFont.body(13))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            } else if controller.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: controller.isBuffering)
        .animation(.easeInOut(duration: 0.2), value: sources?.isSwitching)
        #if os(tvOS)
        .onPlayPauseCommand {
            controller.togglePlayPause()
            isVisible = true
            focusedTarget = .play
            scheduleHide()
        }
        .onExitCommand {
            if seekState.pending != nil {
                seekState.cancel()
                return
            }
            if isVisible {
                isVisible = false
                focusedTarget = .surface
                hideTask?.cancel()
            } else {
                onClose()
            }
        }
        #endif
        .onAppear {
            #if os(tvOS)
            focusedTarget = .play
            #endif
            scheduleHide(userInitiated: false)
        }
        .onChange(of: controller.isPlaying) { _, playing in
            if playing { scheduleHide(userInitiated: false) }
        }
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
            .buttonStyle(PlayerControlButtonStyle())
            #if os(tvOS)
            .focused($focusedTarget, equals: .close)
            #endif
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

            trailingControls
        }
        .padding(.horizontal, KanalMetrics.md)
        .padding(.top, KanalMetrics.sm)
        #if os(tvOS)
        // A section of its own, so "up" from the transport lands in this row
        // wherever it is pressed — the play button sits under the title, not
        // under anything focusable.
        .focusSection()
        #endif
    }

    /// The buttons in the top right corner.
    ///
    /// On tvOS the focus engine only moves to what lies roughly in the
    /// direction pressed. These sit far off to the right with nothing below
    /// them, and as plain siblings of the close button they could not be
    /// reached from the remote at all. A focus section makes the cluster one
    /// target, reachable from anywhere to its left or below.
    private var trailingControls: some View {
        HStack(alignment: .top, spacing: KanalMetrics.md) {
            // One button, no list. The provider's names for its feeds say
            // which category an entry was filed under, not what the picture
            // looks like, so a menu of them asks the viewer to choose on
            // information they do not have. "Not this one" is the whole
            // question they can actually answer.
            if let sources {
                Button {
                    sources.onSwitch()
                    scheduleHide()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: KanalMetrics.minTarget, height: KanalMetrics.minTarget)
                        .kanalGlassOverVideo(cornerRadius: 100)
                        .contentShape(.circle)
                }
                .buttonStyle(PlayerControlButtonStyle())
                .disabled(sources.isSwitching)
                .accessibilityIdentifier("player.switchSource")
                .accessibilityLabel(Text(UIStrings.tryAnotherSource))
                .accessibilityValue(Text(UIStrings.sourcePosition(
                    sources.number, sources.count
                )))
            }

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
                .buttonStyle(PlayerControlButtonStyle())
                .accessibilityIdentifier("player.tracks")
                .accessibilityLabel(Text(UIStrings.audioAndSubtitles))
            }

            if let sourceAccessory { sourceAccessory }

            if let trailingAccessory {
                trailingAccessory.frame(width: 40, height: 40)
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
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
            .buttonStyle(PlayerControlButtonStyle())
            #if os(tvOS)
            .focused($focusedTarget, equals: .play)
            #endif
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
        .buttonStyle(PlayerControlButtonStyle())
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
                    progress: scrubbing ?? pendingProgress ?? controller.progress,
                    onScrub: { value in
                        scrubbing = value
                        hideTask?.cancel()
                    },
                    onCommit: { value in
                        controller.seek(to: value * controller.duration)
                        scrubbing = nil
                        #if os(tvOS)
                        _ = seekState.commit()
                        #endif
                        scheduleHide()
                    },
                    onNudge: { direction in
                        #if os(tvOS)
                        nudgeSeek(direction)
                        #endif
                    }
                )
                #if os(tvOS)
                .focused($focusedTarget, equals: .timeline)
                .accessibilityIdentifier("player.timeline")
                #endif

                HStack {
                    Text(Self.timeLabel((scrubbing ?? pendingProgress ?? controller.progress) * controller.duration))
                    Spacer()
                    Text("-" + Self.timeLabel(
                        controller.duration - (scrubbing ?? pendingProgress ?? controller.progress) * controller.duration
                    ))
                }
                .font(KanalFont.caption(11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                #if os(tvOS)
                Text(UIStrings.playerSeekHint)
                    .font(KanalFont.caption())
                    .foregroundStyle(.white.opacity(0.85))
                #endif
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
        #if os(tvOS)
        focusedTarget = isVisible ? .play : .surface
        #endif
        if isVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    private var pendingProgress: Double? {
        #if os(tvOS)
        guard let pending = seekState.pending, controller.duration > 0 else { return nil }
        return min(max(pending / controller.duration, 0), 1)
        #else
        return nil
        #endif
    }

    #if os(tvOS)
    private func nudgeSeek(_ direction: TelevisionSeekState.Direction) {
        guard controller.duration > 0 else { return }
        if seekState.duration != controller.duration {
            seekState = TelevisionSeekState(duration: controller.duration)
        }
        controlsEngaged = true
        _ = seekState.nudge(direction, from: controller.position,
                            at: ProcessInfo.processInfo.systemUptime)
        hideTask?.cancel()
    }
    #endif

    /// Controls get out of the way on their own, but never while paused —
    /// nobody wants to hunt for the play button.
    private func scheduleHide(userInitiated: Bool = true) {
        #if os(tvOS)
        if userInitiated { controlsEngaged = true }
        #endif
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, controller.isPlaying else { return }
            #if os(tvOS)
            guard !showsTracks, !controlsEngaged, seekState.pending == nil else { return }
            focusedTarget = .surface
            #endif
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
    var onNudge: ((TelevisionSeekState.Direction) -> Void)? = nil

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            bar(width: proxy.size.width)
        }
        .frame(height: KanalMetrics.minTarget)
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
        Button { onCommit(progress) } label: {
            track.contentShape(.rect)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityIdentifier("player.timeline")
        .accessibilityLabel(Text(UIStrings.playerSeek))
        .accessibilityValue(Text(UIStrings.percentWatched(Int(min(max(progress, 0), 1) * 100))))
        .onMoveCommand { direction in
            guard direction == .left || direction == .right else { return }
            onNudge?(direction == .left ? .backward : .forward)
        }
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

/// Video controls need the same unambiguous focus treatment over every frame.
struct PlayerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ControlBody(configuration: configuration)
    }
    private struct ControlBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            configuration.label
                #if os(tvOS)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(isFocused ? .white : .clear, lineWidth: 4)
                        .padding(-5)
                }
                #endif
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
        }
    }
}
