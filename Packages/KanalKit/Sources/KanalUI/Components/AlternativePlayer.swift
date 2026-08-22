import Foundation
import SwiftUI

/// What a second playback engine has to report back.
///
/// Kanal's own package deliberately does not link a decoder — that binary is
/// enormous, and the core stays testable without it. The app target supplies
/// one through the environment instead, so `KanalUI` can ask for VLC without
/// knowing VLC exists.
public struct AlternativePlayerRequest {
    public let url: URL
    /// Where to resume from, in seconds.
    public let startAt: TimeInterval?
    /// Called as playback advances, so watch progress still gets recorded.
    public let onProgress: @MainActor (TimeInterval, TimeInterval) -> Void
    public let onFailure: @MainActor (String) -> Void

    public init(
        url: URL,
        startAt: TimeInterval?,
        onProgress: @escaping @MainActor (TimeInterval, TimeInterval) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        self.url = url
        self.startAt = startAt
        self.onProgress = onProgress
        self.onFailure = onFailure
    }
}

/// Builds a view that plays anything the system player cannot.
public typealias AlternativePlayerBuilder = @MainActor (AlternativePlayerRequest) -> AnyView

private struct AlternativePlayerKey: EnvironmentKey {
    static let defaultValue: AlternativePlayerBuilder? = nil
}

public extension EnvironmentValues {
    /// Nil means the app was built without a second engine; playback then
    /// falls back to guessing at formats the system player might accept.
    var alternativePlayer: AlternativePlayerBuilder? {
        get { self[AlternativePlayerKey.self] }
        set { self[AlternativePlayerKey.self] = newValue }
    }
}

public extension View {
    func alternativePlayer(_ builder: @escaping AlternativePlayerBuilder) -> some View {
        environment(\.alternativePlayer, builder)
    }
}
