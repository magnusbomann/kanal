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

    /// How many different feeds one search may open.
    public static let maximumSources = 3
    /// The whole search, however many feeds it covers.
    ///
    /// A minute rather than twenty seconds. Each feed is now waited on for as
    /// long as it is still sending something, and against a real provider a
    /// working feed has taken twenty-five seconds to produce a picture — the
    /// old limit ended the search while the answer was still on its way.
    public static let searchWindow: TimeInterval = 60

    public func expired(at now: TimeInterval) -> Bool { now - startedAt >= Self.searchWindow }

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
        guard !locked, !expired(at: now), attempted.count < Self.maximumSources,
              let next = order.first(where: { !attempted.contains($0) }) else { return nil }
        current = next
        attempted.insert(next)
        return next
    }
}
