import XCTest

final class RelayUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  func testReviewFlowAndPersistence() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.staticTexts["Concert tickets"].waitForExistence(timeout: 15))
    app.staticTexts["Concert tickets"].firstMatch.tap()
    let accept = app.buttons["Accept Agreement"]
    XCTAssertTrue(accept.waitForExistence(timeout: 5), "Opening a suggestion must not accept it")
    accept.tap()
    let done = app.buttons["Mark Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5))
    done.tap()
    XCTAssertTrue(app.staticTexts["Done"].firstMatch.waitForExistence(timeout: 5))
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Agreement reviewed and completed"
    shot.lifetime = .keepAlways
    add(shot)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["Concert tickets"].waitForExistence(timeout: 10))
  }
  func testCreateAgreementManually() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    app.buttons["New Agreement"].firstMatch.tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("Demo coffee payment")
    let name = app.textFields["Name"]
    name.tap()
    name.typeText("Taylor")
    let what = app.textFields["What Was Promised?"]
    if what.exists {
      what.tap()
      what.typeText("Pay for coffee")
    }
    app.buttons["Save Agreement"].tap()
    XCTAssertTrue(app.staticTexts["Demo coffee payment"].waitForExistence(timeout: 5))
  }
}
