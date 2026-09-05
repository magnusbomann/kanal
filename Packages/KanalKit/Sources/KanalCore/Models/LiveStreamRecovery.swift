import Foundation

/// One bounded search, shared by every decoder. Retries never erase a lock.
public struct LiveStreamRecovery: Sendable {
    public private(set) var current: String
    public private(set) var attempted: Set<String>
    public private(set) var startedAt: TimeInterval
    public private(set) var lastWorking: String?
    public var locked: Bool
    public let order: [String]
    private var retriedWorking = false

    public init(order: [String], selected: String, locked: Bool, now: TimeInterval) {
        self.order = order
        current = selected
        attempted = [selected]
        startedAt = now
        self.locked = locked
    }

    public func expired(at now: TimeInterval) -> Bool { now - startedAt >= 20 }

    public mutating func played() {
        lastWorking = current
        retriedWorking = false
    }

    /// Starts a new, deliberate attempt or resumes after an actual network outage.
    public mutating func retry(at now: TimeInterval) {
        startedAt = now
        attempted = [current]
        retriedWorking = false
    }

    public mutating func failed(at now: TimeInterval) -> String? {
        // A stream that was playing gets a fresh recovery window and one retry
        // before we consider another source. Repeated failures cannot reset it.
        if lastWorking == current, !retriedWorking {
            retriedWorking = true
            startedAt = now
            attempted = [current]
            return current
        }
        guard !locked, !expired(at: now), attempted.count < 3,
              let next = order.first(where: { !attempted.contains($0) }) else { return nil }
        current = next
        attempted.insert(next)
        return next
    }
}
