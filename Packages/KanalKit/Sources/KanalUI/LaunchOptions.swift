import Foundation

/// Debug-only launch arguments, for driving the app from a script.
///
/// Screenshot automation and UI tests need to open a specific screen without a
/// human tapping their way there. Compiled out of release builds entirely, so
/// nothing here can be triggered in a shipped app.
enum LaunchOptions {

    #if DEBUG
    /// `-kanal-tab live` opens straight to a given tab.
    static var startTab: String? {
        value(for: "-kanal-tab")
    }

    /// `-kanal-live-mode guide` opens Live TV showing the guide.
    static var liveMode: String? {
        value(for: "-kanal-live-mode")
    }

    /// `-kanal-settings 1` opens the settings sheet on launch.
    static var opensSettings: Bool {
        ProcessInfo.processInfo.arguments.contains("-kanal-settings")
    }

    /// `-kanal-play-movie 0` starts the nth film, for verifying playback.
    static var autoplayMovieIndex: Int? {
        value(for: "-kanal-play-movie").flatMap(Int.init)
    }

    /// `-kanal-open-series 0` opens the nth show's detail screen.
    static var openSeriesIndex: Int? {
        value(for: "-kanal-open-series").flatMap(Int.init)
    }

    /// `-kanal-details 0` opens the detail screen for the nth film.
    static var detailsMovieIndex: Int? {
        value(for: "-kanal-details").flatMap(Int.init)
    }

    /// `-kanal-source <url>` loads a playlist directly, so a UI test can reach
    /// the player without tapping through setup.
    static var seededSource: URL? {
        value(for: "-kanal-source").flatMap(URL.init(string:))
    }

    private static func value(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }
    #else
    static var startTab: String? { nil }
    static var liveMode: String? { nil }
    static var opensSettings: Bool { false }
    static var autoplayMovieIndex: Int? { nil }
    static var openSeriesIndex: Int? { nil }
    static var detailsMovieIndex: Int? { nil }
    static var seededSource: URL? { nil }
    #endif
}
