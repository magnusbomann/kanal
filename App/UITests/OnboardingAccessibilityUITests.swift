import XCTest

final class OnboardingAccessibilityUITests: XCTestCase {
    func testContinueRemainsReachableAtLargestTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let button = app.buttons["onboarding.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable, "Continue must be reachable by scrolling at the largest text size")
        button.tap()
        XCTAssertTrue(app.staticTexts["ONE LINK"].waitForExistence(timeout: 5))
    }
}
