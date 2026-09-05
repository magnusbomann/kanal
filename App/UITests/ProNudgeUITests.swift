import XCTest

/// That closing a stream actually lands on the offer.
///
/// `ProNudge` decides *when* to ask and is covered by unit tests. What those
/// cannot see is the wiring: the player reporting whether anything played, the
/// shell noticing the cover has gone, and a sheet coming up after a full-screen
/// cover has come down — the one SwiftUI arrangement in this app that has to be
/// sequenced rather than merely declared.
final class ProNudgeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(resettingNudge: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-kanal-source", ProcessInfo.processInfo.environment["KANAL_TEST_PLAYLIST"]
                ?? "http://127.0.0.1:8733/films3.m3u",
            "-kanal-play-channel", "0",
            "-AppleLanguages", "(en)",
        ]
        if resettingNudge { app.launchArguments.append("-kanal-reset-nudge") }
        app.launch()
        return app
    }

    /// Watch and close four streams. The first three are the app proving it
    /// works; the fourth is the first time it is allowed to ask for anything.
    func testTheOfferArrivesAfterTheAppHasProvedItself() {
        var app = launch(resettingNudge: true)
        let paywall = app.otherElements["pro.screen"]

        for round in 1...4 {
            let close = app.buttons["player.close"]
            XCTAssertTrue(
                close.waitForExistence(timeout: 30),
                "the player never opened on round \(round)"
            )
            // Give the stream a moment to actually reach the screen — a
            // playback that never started is deliberately never sold to.
            RunLoop.current.run(until: Date().addingTimeInterval(4))
            close.tap()

            if round < 4 {
                XCTAssertFalse(
                    paywall.waitForExistence(timeout: 3),
                    "the offer appeared on round \(round), before the app had shown it works"
                )
                app.terminate()
                app = launch(resettingNudge: false)
            }
        }

        XCTAssertTrue(
            paywall.waitForExistence(timeout: 10),
            "closing the fourth stream did not bring up the offer"
        )
    }

    /// A visible capsule is the button. Tapping beside its text must still
    /// stop playback and remove the full-screen player.
    func testFailureCloseButtonUsesItsWholeVisibleArea() {
        let app = launch(resettingNudge: false)
        let close = app.buttons["player.failure.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 30))

        close.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()

        XCTAssertFalse(
            close.waitForExistence(timeout: 5),
            "the failure panel remained after tapping inside the close capsule"
        )
        XCTAssertFalse(app.buttons["player.close"].exists, "the player remained presented")
    }
}
