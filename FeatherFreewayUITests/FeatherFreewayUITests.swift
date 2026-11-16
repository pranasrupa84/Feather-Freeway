import XCTest

/// Identifiers mirrored from the app's `AccessibilityID`.
private enum ID {
    static let toast = "toast"
    static let corn = "corn.balance"
    static let back = "nav.back"
    static let roadside = "screen.roadside"
    static let play = "home.play"
    static let routeMap = "home.routeMap"
    static let errands = "home.errands"
    static let records = "home.records"
    static let settings = "home.settings"
    static let laneGarage = "lane.garage"
    static let laneRoadside = "lane.roadside"
    static let laneCoop = "lane.coop"
    static let garage = "screen.garage"
    static let coop = "screen.coop"
    static let errandsSheet = "screen.errands"
    static let routeScreen = "screen.routeMap"
    static let ticket = "route.ticket"
    static let start = "route.start"
    static let glovebox = "screen.glovebox"
    static let settingsScreen = "screen.settings"
    static let reset = "settings.reset"
    static let resetConfirm = "settings.reset.confirm"
    static let guide = "screen.guide"
    static let guideNext = "guide.next"
    static let guideDone = "guide.done"
    static let game = "screen.game"
    static let go = "game.go"
    static let pause = "game.pause"
    static let resume = "game.resume"
    static let quit = "game.quit"
    static let citation = "game.citation"
    static let home = "game.home"
    static let eggExpress = "home.eggExpress"
    static let deliveryShortcut = "game.delivery.shortcut"
    static let deliveryPath = "game.delivery.path"
    static let deliveryCargo = "game.delivery.cargo"
    static func buy(_ kind: String) -> String { "garage.buy.\(kind)" }
    static func level(_ kind: String) -> String { "garage.level.\(kind)" }
    static func coopAction(_ breed: String) -> String { "coop.action.\(breed)" }
    static func marker(_ i: Int) -> String { "route.marker.\(i)" }
}

final class FeatherFreewayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + extra
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitHittable(_ e: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: e)], timeout: timeout) == .completed
    }

    private func tap(_ id: String, timeout: TimeInterval = 8) {
        let e = element(id)
        XCTAssertTrue(waitHittable(e, timeout: timeout), "\(id) not hittable")
        e.tap()
    }

    /// Scrolls the current page up until the element can be tapped, then taps it.
    private func scrollAndTap(_ id: String) {
        let e = element(id)
        for _ in 0..<6 where !(e.exists && e.isHittable) {
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
        tap(id)
    }

    /// Numbers can be grouped with locale separators; compare digits only.
    private func digits(_ s: String) -> Int { Int(s.filter(\.isNumber)) ?? -1 }

    private var cornValue: Int { digits(element(ID.corn).value as? String ?? "") }

    // MARK: - Home and navigation

    func testHomeShowsRoadsideWithMainActions() {
        launch()
        XCTAssertTrue(element(ID.roadside).waitForExistence(timeout: 8))
        XCTAssertTrue(waitHittable(element(ID.play)))
        XCTAssertTrue(element(ID.routeMap).exists)
        XCTAssertTrue(element(ID.errands).exists)
        XCTAssertEqual(cornValue, 5000)
    }

    func testLaneRailSwitchesBetweenGarageRoadsideAndCoop() {
        launch()
        tap(ID.laneGarage)
        XCTAssertTrue(waitHittable(element(ID.buy("rigTime"))))
        tap(ID.laneCoop)
        XCTAssertTrue(waitHittable(element(ID.coopAction("pip"))))
        tap(ID.laneRoadside)
        XCTAssertTrue(waitHittable(element(ID.play)))
    }

    func testSwipingSidewaysChangesHomePage() {
        launch()
        XCTAssertTrue(waitHittable(element(ID.play)))
        app.swipeRight()
        XCTAssertTrue(waitHittable(element(ID.buy("rigTime"))))
        app.swipeLeft()
        app.swipeLeft()
        XCTAssertTrue(waitHittable(element(ID.coopAction("pip"))))
    }

    func testSecondaryScreensOpenAndGoBack() {
        launch()
        tap(ID.records)
        XCTAssertTrue(element(ID.glovebox).waitForExistence(timeout: 5))
        tap(ID.back)
        tap(ID.settings)
        XCTAssertTrue(element(ID.settingsScreen).waitForExistence(timeout: 5))
        tap(ID.back)
        tap(ID.routeMap)
        XCTAssertTrue(element(ID.routeScreen).waitForExistence(timeout: 5))
        tap(ID.back)
        XCTAssertTrue(waitHittable(element(ID.play)))
    }

    func testErrandsSheetOpens() {
        launch()
        tap(ID.errands)
        XCTAssertTrue(element(ID.errandsSheet).waitForExistence(timeout: 5))
        XCTAssertTrue(element("errand.claim.0").exists)
    }

    // MARK: - Garage and Coop

    func testBuyingAGaragePartRaisesItsLevel() {
        launch()
        tap(ID.laneGarage)
        let before = cornValue
        tap(ID.buy("rigTime"))
        let level = element(ID.level("rigTime"))
        let predicate = NSPredicate(format: "value == '1'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: level)], timeout: 5), .completed)
        XCTAssertEqual(cornValue, before - 150)
    }

    func testBuyingWithoutCornIsRefused() {
        launch([ "--freshstart"])
        tap(ID.laneGarage)
        tap(ID.buy("rigTime"))
        let toast = element(ID.toast)
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.hasPrefix("You need"), toast.label)
        XCTAssertEqual(element(ID.level("rigTime")).value as? String, "0")
    }

    func testWelcomingAndChoosingChickens() {
        launch()
        tap(ID.laneCoop)
        tap(ID.coopAction("pip"))
        let toast = element(ID.toast)
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.contains("Welcome"), toast.label)
        XCTAssertEqual(cornValue, 4400)
        tap(ID.coopAction("clover"))
        XCTAssertTrue(element(ID.toast).waitForExistence(timeout: 5))
    }

    // MARK: - Trips

    func testRouteTicketStartPauseResumeQuit() {
        // Autopilot keeps the chicken alive while the test pauses and resumes.
        launch(["--autopilot", "--invincible"])
        tap(ID.routeMap)
        tap(ID.marker(0))
        XCTAssertTrue(element(ID.ticket).waitForExistence(timeout: 5))
        tap(ID.start)
        XCTAssertTrue(element(ID.game).waitForExistence(timeout: 8))
        tap(ID.go)
        // Let the traffic-light countdown finish before pausing.
        sleep(3)
        tap(ID.pause, timeout: 10)
        tap(ID.resume)
        tap(ID.pause, timeout: 10)
        tap(ID.quit)
        XCTAssertTrue(element(ID.routeScreen).waitForExistence(timeout: 8))
    }

    func testNoInputDuringTicketKeepsTheRunWaiting() {
        launch()
        tap(ID.play)
        XCTAssertTrue(waitHittable(element(ID.go)))
        sleep(2)
        XCTAssertTrue(element(ID.go).isHittable, "the trip only starts on GO")
        XCTAssertFalse(element(ID.citation).exists)
    }

    func testAutopilotClearsTheFirstRouteAndShowsTheCitation() {
        launch(["--autopilot"])
        tap(ID.routeMap)
        tap(ID.marker(0))
        tap(ID.start)
        tap(ID.go)
        XCTAssertTrue(element(ID.citation).waitForExistence(timeout: 90))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "citation"
        shot.lifetime = .keepAlways
        add(shot)
        tap(ID.home)
        XCTAssertTrue(element(ID.routeScreen).waitForExistence(timeout: 8))
        XCTAssertGreaterThan(cornValueAfterReturn(), 5000)
    }

    func testEggExpressCanChooseShortcutAndCompleteFirstOrder() {
        launch(["--autopilot", "--invincible"])
        tap(ID.eggExpress)
        tap("delivery.order.0")
        tap(ID.go)

        let shortcut = element(ID.deliveryShortcut)
        XCTAssertTrue(waitHittable(shortcut, timeout: 20), "the delivery fork should offer the shortcut")
        shortcut.tap()

        let selectedPath = element(ID.deliveryPath)
        let shortcutSelected = NSPredicate(format: "label == %@", "Shortcut")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shortcutSelected, object: selectedPath)], timeout: 5), .completed)
        XCTAssertEqual(element(ID.deliveryCargo).label, "CARGO 6/6")
        XCTAssertTrue(app.staticTexts["DELIVERY COMPLETE"].waitForExistence(timeout: 90))
    }

    private func cornValueAfterReturn() -> Int {
        tap(ID.back)
        return cornValue
    }

    func testFirstTripShowsTheGuideFirst() {
        launch(["--freshstart"])
        tap(ID.play)
        XCTAssertTrue(element(ID.guide).waitForExistence(timeout: 5))
        for _ in 0..<12 { tap(ID.guideNext) }
        tap(ID.guideDone)
        XCTAssertTrue(waitHittable(element(ID.go), timeout: 10))
    }

    // MARK: - Settings

    func testResetProgressAfterConfirmation() {
        launch()
        tap(ID.settings)
        tap(ID.reset)
        let confirm = app.buttons["Reset everything"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element(ID.toast).waitForExistence(timeout: 5))
        tap(ID.back)
        XCTAssertEqual(cornValue, 0)
    }

    // MARK: - Tour (also produces the landing-site screenshots)

    func testTourOfEveryScreen() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "phone screenshots")
        launch(["--autopilot"])
        XCTAssertTrue(waitHittable(element(ID.play)))
        attach("shot-home")
        tap(ID.laneGarage); sleep(1); attach("shot-garage")
        tap(ID.laneCoop); sleep(1); attach("shot-coop")
        tap(ID.laneRoadside)
        tap(ID.errands); sleep(1); attach("shot-errands")
        app.swipeDown(velocity: .fast)
        tap(ID.records); sleep(1); attach("shot-glovebox"); tap(ID.back)
        tap(ID.routeMap); sleep(1); attach("shot-routemap")
        tap(ID.marker(0)); sleep(1); attach("shot-ticket")
        tap(ID.start)
        tap(ID.go)
        XCTAssertTrue(element(ID.citation).waitForExistence(timeout: 90))
        sleep(2)
        attach("shot-citation")
        tap(ID.home)
        tap(ID.back)
        tap(ID.play)
        attach("shot-ready")
        tap(ID.go)
        for i in 0..<10 {
            sleep(5)
            if element(ID.citation).exists { break }
            attach("shot-run-\(i)")
        }
    }

    // MARK: - iPad

    func testPadStaysPortraitWhenRotated() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        launch(["--autopilot"])
        XCTAssertTrue(waitHittable(element(ID.play)))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        attach("ipad-rotated")
        // Frames are reported in device coordinates. With the interface locked upright, the lane rail
        // (a horizontal row in the app) runs along the device's long edge vertically.
        let garage = element(ID.laneGarage).frame, coop = element(ID.laneCoop).frame
        XCTAssertGreaterThan(abs(garage.midY - coop.midY), abs(garage.midX - coop.midX), "the interface stays in portrait")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
