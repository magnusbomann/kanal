import XCTest

/// Tests that the player can actually be operated.
///
/// These exist because of a bug the unit tests could never have caught: the
/// close button was a `Button` whose label was an `Image`, so only the glyph
/// itself was tappable and the circle drawn around it was not. Every control
/// looked right in a screenshot and the one you needed most did nothing —
/// leaving force-quitting the app as the only way to stop watching.
final class PlayerControlTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchIntoPlayer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-kanal-source", ProcessInfo.processInfo.environment["KANAL_TEST_PLAYLIST"]
                ?? "http://127.0.0.1:8733/films3.m3u",
            "-kanal-play-movie", "0",
            "-AppleLanguages", "(en)",
        ]
        app.launch()
        return app
    }

    func testCloseButtonLeavesThePlayer() {
        let app = launchIntoPlayer()

        let close = app.buttons["player.close"]
        XCTAssertTrue(
            close.waitForExistence(timeout: 30),
            "the player never opened, so the close button was never reachable"
        )

        close.tap()

        // Back in the library: the player's controls are gone.
        XCTAssertTrue(
            close.waitForNonExistence(timeout: 10),
            "tapping close left the player on screen"
        )
    }

    func testTransportControlsAreReachable() {
        let app = launchIntoPlayer()

        let playPause = app.buttons["player.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 30))

        // Every control must be hittable, not merely present — that distinction
        // is exactly what the close button failed.
        for identifier in ["player.close", "player.playPause", "player.back", "player.forward"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, "\(identifier) is missing")
            XCTAssertTrue(control.isHittable, "\(identifier) is drawn but cannot be tapped")
        }
    }
}

extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !exists
    }
}
