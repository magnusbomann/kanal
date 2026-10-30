import XCTest

final class PaywallTVUITests: XCTestCase {
    func testRemoteCanChooseEveryPlanAndLeaveWithoutBuying() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-kanal-paywall", "-kanal-pro", "0", "-AppleLanguages", "(en)"]
        app.launch()
        let annual = app.buttons["pro.plan.yearly"]
        XCTAssertTrue(annual.waitForExistence(timeout: 15))
        XCTAssertTrue(annual.hasFocus)
        XCTAssertTrue(annual.isSelected)

        let remote = XCUIRemote.shared
        remote.press(.down)
        let monthly = app.buttons["pro.plan.monthly"]
        XCTAssertTrue(monthly.hasFocus)
        remote.press(.select)
        XCTAssertTrue(monthly.isSelected)
        XCTAssertTrue(app.staticTexts["pro.billing"].label.contains("per month"))

        remote.press(.down)
        let lifetime = app.buttons["pro.plan.lifetime"]
        XCTAssertTrue(lifetime.hasFocus)
        remote.press(.select)
        XCTAssertTrue(lifetime.isSelected)
        XCTAssertTrue(app.staticTexts["pro.billing"].label.contains("once"))

        remote.press(.down)
        XCTAssertTrue(app.buttons["pro.purchase"].hasFocus)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Apple TV purchase action focus"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        remote.press(.menu)
        XCTAssertTrue(app.buttons["pro.purchase"].waitForNonExistence(timeout: 5))
    }
}
