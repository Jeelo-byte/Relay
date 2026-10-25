import XCTest

@testable import RelayApp

final class ReminderSchedulerTests: XCTestCase {
  @MainActor func testUnbundledLaunchKeepsRemindersUnavailableWithoutCrashing() async throws {
    // This matches `swift run Relay`, which has no macOS application identity.
    guard Bundle.main.bundleURL.pathExtension != "app" else {
      throw XCTSkip("This regression requires the SwiftPM test runner.")
    }
    let scheduler = ReminderScheduler()
    await scheduler.refresh(agreements: [])
    XCTAssertTrue(scheduler.status.contains("app bundle"))
    let enabled = await scheduler.enable(agreements: [])
    XCTAssertFalse(enabled)
    XCTAssertTrue(scheduler.status.contains("Relay.app"))
  }
}
