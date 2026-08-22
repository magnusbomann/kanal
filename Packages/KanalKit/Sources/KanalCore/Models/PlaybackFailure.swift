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
    /// Anything else, with whatever the system said.
    case other(String)

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
