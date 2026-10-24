import XCTest
@testable import RelayKit
final class RelayKitTests: XCTestCase { func testSchema() { XCTAssertEqual(Party.me.display_name_snapshot,"You") } }
