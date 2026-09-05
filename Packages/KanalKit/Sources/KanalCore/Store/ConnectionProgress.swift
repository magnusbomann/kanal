import Foundation

/// The small number of plain-language steps a person sees while Kanal proves
/// that a TV service works. Protocol names deliberately do not appear here.
public enum ConnectionProgress: String, Codable, Sendable, Equatable, CaseIterable {
    case contacting
    case signingIn
    case loadingContent
    case organising
    case ready
}
