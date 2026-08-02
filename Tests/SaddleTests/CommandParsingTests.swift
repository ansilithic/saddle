import XCTest
@testable import saddle

final class CommandParsingTests: XCTestCase {
    func testDefaultStatusOwnsStatusFilters() throws {
        let command = try Saddle.parseAsRoot(["--owner", "ansilithic", "--equipped"])
        let status = try XCTUnwrap(command as? Status)

        XCTAssertEqual(status.owner, "ansilithic")
        XCTAssertTrue(status.equipped)
    }

    func testHealthOwnsHealthFilters() throws {
        let command = try Saddle.parseAsRoot(["health", "--owner", "ansilithic", "--unhealthy"])
        let health = try XCTUnwrap(command as? Health)

        XCTAssertEqual(health.owner, "ansilithic")
        XCTAssertTrue(health.unhealthy)
    }
}
