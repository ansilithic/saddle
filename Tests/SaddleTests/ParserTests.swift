import XCTest
@testable import saddle

final class ParserTests: XCTestCase {

    func testParseURLs() throws {
        let content = """
            git@github.com:user/dotfiles.git
            git@github.com:user/lab.git
            """
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.urls.count, 2)
        XCTAssertEqual(manifest.urls[0], "git@github.com:user/dotfiles.git")
        XCTAssertEqual(manifest.urls[1], "git@github.com:user/lab.git")
    }

    func testDefaultRoot() throws {
        let content = "git@github.com:user/repo.git\n"
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertTrue(manifest.root.hasSuffix("/Developer"))
    }

    func testCustomRoot() throws {
        let content = """
            /Users/test/Projects

            git@github.com:user/repo.git
            """
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.root, "/Users/test/Projects")
        XCTAssertEqual(manifest.urls.count, 1)
    }

    func testTildeRoot() throws {
        let content = "~/Projects\n"
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertFalse(manifest.root.hasPrefix("~"))
        XCTAssertTrue(manifest.root.hasSuffix("/Projects"))
    }

    func testParseSkipsComments() throws {
        let content = """
            # This is a comment
            git@github.com:user/dotfiles.git
            # Another comment
            """
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.urls.count, 1)
    }

    func testParseSkipsBlankLines() throws {
        let content = """
            git@github.com:user/a.git

            git@github.com:user/b.git

            """
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.urls.count, 2)
    }

    func testParseEmptyFile() throws {
        let content = "# Just comments\n"
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(try Parser.parse(at: path))
    }

    func testRootOnlyIsValid() throws {
        let content = "~/Developer\n"
        let path = "/tmp/saddle-test-\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertTrue(manifest.urls.isEmpty)
    }

    func testParseFileNotFound() throws {
        XCTAssertThrowsError(try Parser.parse(at: "/tmp/nonexistent-saddle-file"))
    }

    func testNormalizeSSHUrl() {
        XCTAssertEqual(
            URLHelpers.normalize("git@github.com:user/repo.git"),
            "github.com/user/repo"
        )
    }

    func testNormalizeHTTPSUrl() {
        XCTAssertEqual(
            URLHelpers.normalize("https://github.com/user/repo.git"),
            "github.com/user/repo"
        )
    }

    func testNormalizeMatchesAcrossProtocols() {
        let ssh = URLHelpers.normalize("git@github.com:user/repo.git")
        let https = URLHelpers.normalize("https://github.com/user/repo.git")
        XCTAssertEqual(ssh, https)
    }

    func testRepoNameFromSSH() {
        XCTAssertEqual(URLHelpers.repoName(from: "git@github.com:user/my-project.git"), "my-project")
    }

    func testRepoNameFromHTTPS() {
        XCTAssertEqual(URLHelpers.repoName(from: "https://github.com/user/my-project.git"), "my-project")
    }

    func testHookNameFromSSH() {
        XCTAssertEqual(URLHelpers.hookName(from: "git@github.com:user/my-project.git"), "user-my-project.sh")
    }

    func testHookNameFromHTTPS() {
        XCTAssertEqual(URLHelpers.hookName(from: "https://github.com/user/my-project.git"), "user-my-project.sh")
    }

    func testHookNameMatchesAcrossProtocols() {
        let ssh = URLHelpers.hookName(from: "git@github.com:user/repo.git")
        let https = URLHelpers.hookName(from: "https://github.com/user/repo.git")
        XCTAssertEqual(ssh, https)
    }
}
