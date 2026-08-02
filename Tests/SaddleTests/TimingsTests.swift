import Foundation
import XCTest
@testable import saddle

final class TimingsTests: XCTestCase {
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("saddle-timings-\(UUID().uuidString)")
            .path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    func testLifecycleSamplesAreIsolated() {
        let url = "github.com/example/tool"

        Timings.record(url: url, lifecycle: .health, duration: 0.1, directory: directory)
        Timings.record(url: url, lifecycle: .update, duration: 12, directory: directory)

        XCTAssertEqual(Timings.stats(for: url, lifecycle: .health, directory: directory)?.median, 0.1)
        XCTAssertEqual(Timings.stats(for: url, lifecycle: .update, directory: directory)?.median, 12)
        XCTAssertNotEqual(
            Timings.path(for: url, lifecycle: .health, directory: directory),
            Timings.path(for: url, lifecycle: .update, directory: directory)
        )
    }

    func testRollingWindowAndAdaptiveTimeout() {
        let url = "github.com/example/tool"
        for duration in 1...35 {
            Timings.record(
                url: url,
                lifecycle: .update,
                duration: Double(duration),
                directory: directory
            )
        }

        let stats = Timings.stats(for: url, lifecycle: .update, directory: directory)
        XCTAssertEqual(stats?.count, Timings.windowSize)
        XCTAssertEqual(stats?.last, 35)
        XCTAssertNotNil(Timings.adaptiveTimeout(for: url, lifecycle: .update, directory: directory))
    }

    func testPruneRemovesOnlyUnequippedRepositories() {
        let retained = "github.com/example/retained"
        let removed = "github.com/example/removed"
        Timings.record(url: retained, lifecycle: .health, duration: 1, directory: directory)
        Timings.record(url: removed, lifecycle: .update, duration: 2, directory: directory)

        Timings.prune(keeping: [retained], directory: directory)

        XCTAssertNotNil(Timings.stats(for: retained, lifecycle: .health, directory: directory))
        XCTAssertNil(Timings.stats(for: removed, lifecycle: .update, directory: directory))
    }
}
