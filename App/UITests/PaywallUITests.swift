import XCTest

/// Offline layout and selection checks. These never make a StoreKit purchase.
final class PaywallUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kanal-paywall", "-kanal-pro", "0", "-AppleLanguages", "(en)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if !extra.isEmpty {
            if extra.contains("-UIPreferredContentSizeCategoryName") { app.launchArguments.removeLast(2) }
            app.launchArguments += extra
        }
        app.launch()
        XCTAssertTrue(app.buttons["pro.purchase"].waitForExistence(timeout: 15))
        return app
    }

    func testSelectionUpdatesTheActualChargeAndTrialAction() {
        let app = launch()
        let buy = app.buttons["pro.purchase"]
        let billing = app.staticTexts["pro.billing"]
        XCTAssertTrue(buy.isHittable, "The purchase action should be visible on opening")
        XCTAssertTrue(buy.label.contains("Start free trial"))
        XCTAssertTrue(billing.label.contains("249,00"))
        XCTAssertTrue(billing.label.contains("per year"))
        XCTAssertTrue(app.buttons["pro.plan.yearly"].isSelected)
        snapshot(app, "Annual trial")

        app.buttons["pro.plan.monthly"].tap()
        XCTAssertTrue(app.buttons["pro.plan.monthly"].isSelected)
        XCTAssertFalse(buy.label.contains("trial"))
        XCTAssertTrue(billing.label.contains("39,00"))
        XCTAssertTrue(billing.label.contains("per month"))

        let lifetime = app.buttons["pro.plan.lifetime"]
        if !lifetime.isHittable { app.swipeUp() }
        lifetime.tap()
        XCTAssertTrue(lifetime.isSelected)
        XCTAssertTrue(billing.label.contains("599,00"))
        XCTAssertTrue(billing.label.contains("once"))
        XCTAssertFalse(buy.label.contains("trial"))
        snapshot(app, "One-time purchase")
    }

    func testIneligibleCustomerIsNeverPromisedAFreeTrial() {
        let app = launch(["-kanal-paywall-no-trial"])
        XCTAssertFalse(app.buttons["pro.purchase"].label.contains("trial"))
        XCTAssertFalse(app.staticTexts["pro.billing"].label.contains("free"))
        XCTAssertTrue(app.staticTexts["pro.billing"].label.contains("249,00"))
    }

    func testUnavailablePricesHaveRecoveryAndCannotBePurchased() {
        let app = launch(["-kanal-paywall-unavailable"])
        XCTAssertFalse(app.buttons["pro.purchase"].isEnabled)
        XCTAssertTrue(app.buttons["pro.retry"].exists)
        app.buttons["pro.retry"].tap()
        XCTAssertTrue(app.buttons["pro.retry"].exists)
        app.buttons["pro.close"].tap()
        XCTAssertTrue(app.buttons["pro.purchase"].waitForNonExistence(timeout: 5))
    }

    func testLoadingPricesCannotBePurchased() {
        let app = launch(["-kanal-paywall-loading"])
        XCTAssertFalse(app.buttons["pro.purchase"].isEnabled)
        XCTAssertTrue(app.staticTexts["Loading App Store prices…"].exists)
        app.buttons["pro.close"].tap()
        XCTAssertTrue(app.buttons["pro.purchase"].waitForNonExistence(timeout: 5))
    }

    func testPendingApprovalExplainsWhyPurchaseIsDisabled() {
        let app = launch(["-kanal-paywall-pending"])
        XCTAssertFalse(app.buttons["pro.purchase"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["pro.pending"].firstMatch.exists)
        XCTAssertFalse(app.buttons["pro.plan.monthly"].isEnabled)
        snapshot(app, "Awaiting approval")
    }

    func testLargeTextKeepsPurchaseAndFreeExitReachable() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let buy = app.buttons["pro.purchase"]
        for _ in 0..<12 {
            if buy.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(buy.isHittable)
        snapshot(app, "Accessibility text")
        let free = app.buttons["pro.continueFree"]
        for _ in 0..<8 {
            if free.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(free.isHittable)
        free.tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 5))
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
