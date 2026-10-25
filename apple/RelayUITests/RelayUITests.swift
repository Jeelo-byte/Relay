import XCTest

final class RelayUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  private func navigate(_ title: String, in app: XCUIApplication) {
    let button = app.buttons[title].firstMatch
    if button.exists { button.tap() }
    else {
      let sidebarLabel = app.staticTexts[title].firstMatch
      XCTAssertTrue(sidebarLabel.waitForExistence(timeout: 10))
      sidebarLabel.tap()
    }
  }
  func testCleanStartupAndLocalWorkspacePersistWithoutSamples() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    let local = app.buttons["Start on This Device"]
    XCTAssertTrue(local.waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["Explore Sample Workspace"].exists)
    local.tap()
    XCTAssertTrue(app.staticTexts["A little less to catch up on."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["View sample photo collage"].exists)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["A little less to catch up on."].waitForExistence(timeout: 10))
    XCTAssertFalse(local.exists)
    navigate("Messages", in: app)
    XCTAssertFalse(app.staticTexts["Maya Chen"].exists)
  }
  func testCreateAgreementIsInMessageContextMenu() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    navigate("Messages", in: app)
    app.staticTexts["Maya Chen"].firstMatch.tap()
    let message = app.staticTexts["Can you grab my ticket? I'll pay you back $40 by Friday."]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Create Agreement"].exists)
    message.press(forDuration: 1.2)
    let create = app.buttons["Create Agreement"]
    XCTAssertTrue(create.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Copy Message"].exists)
    create.tap()
    XCTAssertTrue(app.buttons["Save Agreement"].waitForExistence(timeout: 5))
  }
  func testRecapPhotosAndSources() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    let collage = app.buttons["View sample photo collage"]
    XCTAssertTrue(collage.waitForExistence(timeout: 15))
    collage.tap()
    XCTAssertTrue(app.staticTexts["1 of 3 · Sample photo"].waitForExistence(timeout: 5))
    app.buttons["Next"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["2 of 3 · Sample photo"].waitForExistence(timeout: 5))
    app.buttons["Close"].tap()
    app.staticTexts["The conversation, remembered."].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Original sources"].waitForExistence(timeout: 5))
  }
  func testSendingRequiresExplicitConfirmation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    navigate("Messages", in: app)
    app.staticTexts["Maya Chen"].firstMatch.tap()
    let composer = app.descendants(matching: .any)["message-composer"].firstMatch
    XCTAssertTrue(composer.waitForExistence(timeout: 5))
    composer.tap(); composer.typeText("Simulator send verification")
    app.buttons["Review Send"].tap()
    XCTAssertTrue(app.buttons["Add Sample Message"].waitForExistence(timeout: 5))
    if app.buttons["Keep Editing"].exists { app.buttons["Keep Editing"].tap() }
    else { app.navigationBars.firstMatch.tap() } // iPad action popovers dismiss on an outside tap.
    XCTAssertTrue(composer.waitForExistence(timeout: 5))
    app.buttons["Review Send"].tap()
    app.buttons["Add Sample Message"].tap()
    XCTAssertTrue(app.staticTexts["Simulator send verification"].waitForExistence(timeout: 5))
  }
  func testChatSearchFindsExactSource() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    navigate("Events", in: app)
    XCTAssertTrue(app.staticTexts["Concert tickets"].waitForExistence(timeout: 15))
    navigate("Messages", in: app)
    app.buttons["Search Chats"].tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap(); search.typeText("poster")
    XCTAssertTrue(app.staticTexts["I'll send you the final poster on Sunday."].waitForExistence(timeout: 5))
    app.buttons["View Source"].tap()
    XCTAssertTrue(app.navigationBars["Studio crew"].waitForExistence(timeout: 5))
  }
  func testReviewFlowAndPersistence() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    navigate("Events", in: app)
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
    navigate("Events", in: app)
    let all = app.buttons["All Agreements"].firstMatch
    for _ in 0..<5 where !all.isHittable { app.swipeUp() }
    all.tap()
    XCTAssertTrue(app.staticTexts["Concert tickets"].waitForExistence(timeout: 10))
  }
  func testCreateAgreementManually() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-demo", "-ui-testing"]
    app.launchEnvironment["RELAY_TEST_NAMESPACE"] = UUID().uuidString
    app.launch()
    navigate("Events", in: app)
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
