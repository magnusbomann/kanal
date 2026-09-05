import Foundation

/// The remote seek policy used by the tvOS player chrome.
///
/// Keeping this independent of SwiftUI makes the edge cases (reversal,
/// pauses, clamping and cancellation) deterministic and shared by both
/// playback engines.
public struct TelevisionSeekState: Sendable, Equatable {
    public enum Direction: Sendable, Equatable { case backward, forward }

    public let duration: TimeInterval
    public private(set) var pending: TimeInterval?

    private var lastDirection: Direction?
    private var lastNudgeAt: TimeInterval?
    private var nudgeCount = 0

    public init(duration: TimeInterval, pending: TimeInterval? = nil) {
        let clampedDuration = max(duration.isFinite ? duration : 0, 0)
        self.duration = clampedDuration
        self.pending = pending.map { min(max($0, 0), clampedDuration) }
    }

    @discardableResult
    public mutating func nudge(_ direction: Direction, from position: TimeInterval, at time: TimeInterval) -> TimeInterval {
        let reversed = lastDirection != nil && lastDirection != direction
        let paused = lastNudgeAt.map { time - $0 > 0.7 } ?? false
        if reversed || paused { nudgeCount = 0 }

        let step: TimeInterval
        switch min(nudgeCount / 4, 5) {
        case 0: step = 10
        case 1: step = 20
        case 2: step = 40
        case 3: step = 80
        case 4: step = 160
        default: step = 300
        }
        let base = pending ?? position
        let delta = direction == .forward ? step : -step
        pending = min(max(base + delta, 0), duration)
        lastDirection = direction
        lastNudgeAt = time
        nudgeCount += 1
        return pending ?? 0
    }

    /// Commits the preview position, if any, and clears the pending state.
    public mutating func commit() -> TimeInterval? {
        defer { reset() }
        return pending
    }

    /// Drops the preview without changing the underlying playback position.
    public mutating func cancel() { reset() }

    private mutating func reset() {
        pending = nil
        lastDirection = nil
        lastNudgeAt = nil
        nudgeCount = 0
    }
}
