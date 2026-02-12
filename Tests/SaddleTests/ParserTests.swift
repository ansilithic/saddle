import XCTest
@testable import saddle

final class ParserTests: XCTestCase {

    // MARK: - TOML Parsing

    func testParseTOMLRepos() throws {
        let toml = """
            mount = "~/Developer"

            [repos]
            "github.com/user/dotfiles"
            "github.com/user/tools"
            """
        let path = tmpPath()
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.repos.count, 2)
        XCTAssertEqual(manifest.repos[0], "github.com/user/dotfiles")
        XCTAssertEqual(manifest.repos[1], "github.com/user/tools")
    }

    func testDefaultMount() throws {
        let toml = """
            [repos]
            "github.com/user/repo"
            """
        let path = tmpPath()
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertTrue(manifest.mount.hasSuffix("/Developer"))
    }

    func testCustomMount() throws {
        let toml = """
            mount = "/Users/test/Projects"

            [repos]
            "github.com/user/repo"
            """
        let path = tmpPath()
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.mount, "/Users/test/Projects")
        XCTAssertEqual(manifest.repos.count, 1)
    }

    func testTildeMount() throws {
        let toml = """
            mount = "~/Projects"

            [repos]
            """
        let path = tmpPath()
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertFalse(manifest.mount.hasPrefix("~"))
        XCTAssertTrue(manifest.mount.hasSuffix("/Projects"))
    }

    func testParseEmptyRepos() throws {
        let toml = """
            mount = "~/Developer"

            [repos]
            """
        let path = tmpPath()
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertTrue(manifest.repos.isEmpty)
    }

    func testParseComments() throws {
        let toml = """
            # This is the mount point
            mount = "~/Developer"

            [repos]
            # Personal repos
            "github.com/user/dotfiles"
            """
        let path = tmpPath()
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let manifest = try Parser.parse(at: path)
        XCTAssertEqual(manifest.repos.count, 1)
        XCTAssertEqual(manifest.repos[0], "github.com/user/dotfiles")
    }

    func testParseFileNotFound() throws {
        XCTAssertThrowsError(try Parser.parse(at: "/tmp/nonexistent-saddle-file"))
    }

    func testParseEmptyFile() throws {
        let path = tmpPath()
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(try Parser.parse(at: path))
    }

    // MARK: - Save Round-Trip

    func testSaveRoundTrip() throws {
        let manifest = Manifest(
            mount: NSHomeDirectory() + "/Developer",
            repos: ["github.com/user/alpha", "github.com/user/beta"]
        )
        let path = tmpPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try Parser.save(manifest, to: path)
        let loaded = try Parser.parse(at: path)

        XCTAssertEqual(loaded.repos, manifest.repos)
        XCTAssertTrue(loaded.mount.hasSuffix("/Developer"))
    }

    // MARK: - URL Helpers

    func testSSHURLFromNormalized() {
        XCTAssertEqual(
            URLHelpers.sshURL(from: "github.com/user/repo"),
            "git@github.com:user/repo.git"
        )
    }

    func testSSHURLPreservesNestedPath() {
        XCTAssertEqual(
            URLHelpers.sshURL(from: "github.com/org/nested/repo"),
            "git@github.com:org/nested/repo.git"
        )
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

    func testNormalizeAlreadyNormalized() {
        XCTAssertEqual(
            URLHelpers.normalize("github.com/user/repo"),
            "github.com/user/repo"
        )
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

    // MARK: - Helpers

    private func tmpPath() -> String {
        "/tmp/saddle-test-\(UUID().uuidString)"
    }
}
