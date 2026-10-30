import AVFoundation
import Foundation

/// Why a stream would not play, in words that point at the cause.
///
/// "Cannot Open" is what AVFoundation says whether the file is a container it
/// has never supported, the server refuses range requests, or the provider
/// rejected the credentials. Those need different answers from the viewer, so
/// the raw error is translated into one of them.
public enum PlaybackFailure: Equatable, Sendable {
    /// The container itself is one Apple's player cannot open — usually MKV.
    case unsupportedContainer(String)
    /// The server answered, but not in a way a media player can stream from.
    case serverNotStreamable
    /// The provider refused the request.
    case rejected
    /// Nothing reached us.
    case offline
    /// The feed was accepted but never produced a picture. Distinct from every
    /// other case here because nothing failed: a panel can hold a connection
    /// open indefinitely, which is silence rather than an error.
    case timedOut
    /// The provider's own "this channel is offline" clip, served in place of
    /// the live feed — measured on a real panel as a ten-second playlist that
    /// ends, often while the account's one connection is still counted. It
    /// plays perfectly, which is why it has to be named: otherwise it is
    /// taken for success and the next feed is never tried.
    case providerPlaceholder
    /// Anything else, with whatever the system said.
    case other(String)

    /// Whether another decoder has a meaningful chance of opening the stream.
    ///
    /// Authentication and connectivity failures affect every engine, so a
    /// second attempt would only make the viewer wait for the same answer.
    /// Container, byte-range and otherwise unclassified media failures are
    /// different: VLC may be able to play the exact stream AVFoundation
    /// rejected, and that handoff should happen without asking the viewer to
    /// know why.
    public var shouldTryAlternativeEngine: Bool {
        switch self {
        case .unsupportedContainer, .serverNotStreamable, .other:
            true
        case .rejected, .offline, .timedOut, .providerPlaceholder:
            false
        }
    }

    /// Whether this could be the provider refusing a connection it has not
    /// finished releasing, rather than a stream that is actually broken.
    ///
    /// Panels sell a fixed number of simultaneous connections — the measured
    /// test account allows exactly one — and a request made while the previous
    /// stream is still counted comes back as a redirect to something that is
    /// not media, or as an outright refusal. Both are indistinguishable from a
    /// dead feed at the point AVFoundation reports them, and the difference
    /// only shows up by asking the same feed again a moment later.
    ///
    /// A container the player has never supported is excluded: no amount of
    /// waiting turns Matroska into something AVFoundation opens.
    public var mayBeConnectionLimit: Bool {
        switch self {
        // Silence is the shape a spent connection allowance most often takes:
        // the panel accepts the socket and then sends nothing at all.
        case .rejected, .serverNotStreamable, .other, .timedOut, .providerPlaceholder:
            true
        case .unsupportedContainer, .offline:
            false
        }
    }

    /// - Parameter error: nil when the stream simply never became ready, which
    ///   is how an unplayable container most often behaves.
    public init(error: (any Error)?, url: URL) {
        let nsError = error as NSError?
        let container = url.pathExtension.lowercased()

        guard let nsError else {
            // Timed out with no error at all. If the container is one Apple
            // cannot open, that is why; otherwise the server is at fault.
            self = StreamCandidates.foreign.contains(container)
                ? .unsupportedContainer(container)
                : .serverNotStreamable
            return
        }
        let code = nsError.code

        switch code {
        // -11828 and -11829 are what a container AVFoundation cannot parse
        // produces. Both surface to the viewer as "Cannot Open".
        case -11828, -11829:
            self = .unsupportedContainer(container.isEmpty ? "?" : container)
        // The asset loaded but the server would not serve byte ranges, so
        // there is nothing to seek through.
        case -11850:
            self = .serverNotStreamable
        case -11800 where StreamCandidates.foreign.contains(container):
            self = .unsupportedContainer(container)
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut, -1009, -1005, -1001:
            self = .offline
        case NSURLErrorUserAuthenticationRequired, -1013, 401, 403:
            self = .rejected
        default:
            if StreamCandidates.foreign.contains(container) {
                self = .unsupportedContainer(container)
            } else {
                self = .other(nsError.localizedDescription)
            }
        }
    }
}
