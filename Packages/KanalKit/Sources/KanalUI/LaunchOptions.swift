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
    #endif
}
