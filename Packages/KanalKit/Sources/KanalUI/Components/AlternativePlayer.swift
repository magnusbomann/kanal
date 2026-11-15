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
    /// Whether this is a broadcast. Taken from the library entry, because a
    /// stream's own reported length is not a reliable way to tell.
    public let isLive: Bool
    /// Where to resume from, in seconds.
    public let startAt: TimeInterval?
    /// Shown in the chrome, which the engine draws itself so both paths match.
    public let title: String
    public let subtitle: String?
    /// Called once when the decoder has actually opened this candidate.
    public let onReady: @MainActor () -> Void
    /// Called as playback advances, so watch progress still gets recorded.
    public let onProgress: @MainActor (TimeInterval, TimeInterval) -> Void
    public let onFailure: @MainActor (String) -> Void
    /// Called instead of `onReady` when what opened is not the title at all
    /// but the provider's stand-in for a stream it does not have — a short
    /// silent clip saying so. It decodes perfectly, which is why the engine
    /// has to name it: left alone it counts as the film having played.
    public let onPlaceholder: @MainActor () -> Void
    /// The way out. Without it a viewer has to force-quit the app to stop
    /// watching, which is exactly what happened before this existed.
    public let onClose: @MainActor () -> Void

    public init(
        url: URL,
        isLive: Bool = false,
        startAt: TimeInterval?,
        title: String,
        subtitle: String?,
        onReady: @escaping @MainActor () -> Void,
        onProgress: @escaping @MainActor (TimeInterval, TimeInterval) -> Void,
        onFailure: @escaping @MainActor (String) -> Void,
        onPlaceholder: @escaping @MainActor () -> Void = {},
        onClose: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.isLive = isLive
        self.startAt = startAt
        self.title = title
        self.subtitle = subtitle
        self.onReady = onReady
        self.onProgress = onProgress
        self.onFailure = onFailure
        self.onPlaceholder = onPlaceholder
        self.onClose = onClose
    }
}

/// What the app target hands back: the video surface, and something to drive
/// it with.
///
/// Only the surface comes from the engine. The controls are drawn once, by
/// `PlayerView`, so the two paths cannot drift apart in layout — an earlier
/// version let each engine draw its own and the VLC one inherited the video's
/// safe-area insets, clipping the title behind the Dynamic Island.
public struct AlternativePlayerHandle {
    public let surface: AnyView
    public let controller: any PlaybackControlling
    /// The engine's own way to AirPlay, when it has one. The system route
    /// picker cannot send this engine's picture — choosing a television there
    /// moves only the sound — so an engine that can do better says so here
    /// and the chrome shows its button instead of the picker.
    public let airPlay: (@MainActor () -> Void)?

    public init(
        surface: AnyView,
        controller: any PlaybackControlling,
        airPlay: (@MainActor () -> Void)? = nil
    ) {
        self.surface = surface
        self.controller = controller
        self.airPlay = airPlay
    }
}

/// Builds the surface that plays anything the system player cannot.
public typealias AlternativePlayerBuilder = @MainActor (AlternativePlayerRequest) -> AlternativePlayerHandle

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
