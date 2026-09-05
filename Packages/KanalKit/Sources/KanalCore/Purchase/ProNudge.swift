import Foundation

/// When the free tier asks for money.
///
/// The model is UHF's, because it works: never take the television away, but
/// let closing a stream land on the offer. That only stays tolerable if the
/// asking is paced, so the whole decision lives here as plain values a test can
/// drive through a week of viewing in a millisecond.
///
/// Four rules, each of which exists because breaking it is a one-star review:
///
///  1. **Not until the app has proven itself.** The first streams someone
///     watches are the ones deciding whether their provider works at all.
///     Asking for money before that is asking them to buy an unknown.
///  2. **Never after a failure.** If the stream never played, they got nothing.
///     A paywall on top of that reads as a toll for a broken app.
///  3. **Never over a child's shoulder.** A restricted profile is a nine-year-
///     old holding the remote; they cannot buy anything and should not be asked.
///  4. **Backs off when refused.** Someone who has said no eight times is not
///     going to say yes on the ninth ask, they are going to leave.
public struct ProNudge: Codable, Sendable, Equatable {

    /// Streams that actually played, ever. Not reset by anything.
    public private(set) var successfulPlaybacks = 0
    /// Times the offer has been shown and closed without a purchase.
    public private(set) var dismissals = 0
    public private(set) var lastShownAt: Date?

    public init() {}

    /// How many streams someone watches before the offer first appears.
    ///
    /// Three, not one: enough for a person to have played live TV, opened a
    /// film, and found out whether both work on their own provider.
    static let playbacksBeforeFirstPrompt = 3

    /// The quiet period after an offer has been shown, which lengthens as it
    /// keeps being refused.
    var cooldown: TimeInterval {
        switch dismissals {
        case ..<5: 15 * 60
        case ..<15: 60 * 60
        default: 6 * 60 * 60
        }
    }

    /// Decides — and records — what happens when the player closes.
    ///
    /// Returns `true` when the Pro screen should come up. Recording lives in
    /// the same call on purpose: a caller that asks and then forgets to tell it
    /// what happened would ask again on the next frame, forever.
    public mutating func playbackClosed(
        didPlay: Bool,
        isPro: Bool,
        isRestricted: Bool,
        now: Date = .now,
        allowsPrompt: Bool = true,
        minimumInterval: TimeInterval = 0
    ) -> Bool {
        guard didPlay else { return false }
        successfulPlaybacks += 1

        guard allowsPrompt, !isPro, !isRestricted else { return false }
        guard successfulPlaybacks > Self.playbacksBeforeFirstPrompt else { return false }
        if let lastShownAt, now.timeIntervalSince(lastShownAt) < max(cooldown, minimumInterval) { return false }

        lastShownAt = now
        return true
    }

    /// Closing the offer without buying. Feeds the back-off.
    public mutating func recordDismissal() {
        dismissals += 1
    }

    /// A purchase resets the counters, so a lapsed subscription starts its
    /// second life with the same patience as its first rather than opening on
    /// a six-hour cooldown nobody can explain.
    public mutating func reset() {
        self = ProNudge()
    }
}
