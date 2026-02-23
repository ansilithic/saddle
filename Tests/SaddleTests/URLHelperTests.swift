import XCTest
@testable import saddle

final class URLHelperTests: XCTestCase {

    // MARK: - owner

    func testOwnerFromNormalized() {
        XCTAssertEqual(URLHelpers.owner(from: "github.com/alice/repo"), "alice")
    }

    func testOwnerFromSSH() {
        XCTAssertEqual(URLHelpers.owner(from: "git@github.com:bob/project.git"), "bob")
    }

    func testOwnerFromShortURL() {
        XCTAssertEqual(URLHelpers.owner(from: "repo"), "")
    }

    // MARK: - host

    func testHostFromNormalized() {
        XCTAssertEqual(URLHelpers.host(from: "github.com/user/repo"), "github.com")
    }

    func testHostFromGitLab() {
        XCTAssertEqual(URLHelpers.host(from: "https://gitlab.com/user/repo.git"), "gitlab.com")
    }

    // MARK: - pathAfterHost

    func testPathAfterHost() {
        XCTAssertEqual(URLHelpers.pathAfterHost(from: "github.com/user/repo"), "user/repo")
    }

    func testPathAfterHostFromSSH() {
        XCTAssertEqual(URLHelpers.pathAfterHost(from: "git@github.com:org/project.git"), "org/project")
    }

    func testPathAfterHostNested() {
        XCTAssertEqual(URLHelpers.pathAfterHost(from: "github.com/org/nested/repo"), "org/nested/repo")
    }

    // MARK: - httpsURL

    func testHTTPSURL() {
        XCTAssertEqual(
            URLHelpers.httpsURL(from: "github.com/user/repo"),
            "https://github.com/user/repo.git"
        )
    }

    // MARK: - cloneURL

    func testCloneURLSSH() {
        XCTAssertEqual(
            URLHelpers.cloneURL(from: "github.com/user/repo", protocol: .ssh),
            "git@github.com:user/repo.git"
        )
    }

    func testCloneURLHTTPS() {
        XCTAssertEqual(
            URLHelpers.cloneURL(from: "github.com/user/repo", protocol: .https),
            "https://github.com/user/repo.git"
        )
    }

    // MARK: - hookBaseName

    func testHookBaseName() {
        XCTAssertEqual(URLHelpers.hookBaseName(from: "github.com/user/repo"), "user-repo")
    }

    func testHookBaseNameFromSSH() {
        XCTAssertEqual(URLHelpers.hookBaseName(from: "git@github.com:user/project.git"), "user-project")
    }

    func testHookBaseNameStripsQuotes() {
        XCTAssertEqual(URLHelpers.hookBaseName(from: "github.com/o'malley/repo"), "omalley-repo")
    }

    func testHookBaseNameStripsShellMetachars() {
        XCTAssertEqual(URLHelpers.hookBaseName(from: "github.com/user$(evil)/repo;rm"), "userevil-reporm")
    }

    func testSanitizeHookNamePreservesValid() {
        XCTAssertEqual(URLHelpers.sanitizeHookName("user-repo.v2_test"), "user-repo.v2_test")
    }

    func testSanitizeHookNameStripsInvalid() {
        XCTAssertEqual(URLHelpers.sanitizeHookName("user'repo;echo"), "userrepoecho")
    }

    // MARK: - normalize edge cases

    func testNormalizeCaseInsensitive() {
        XCTAssertEqual(
            URLHelpers.normalize("GitHub.com/User/Repo"),
            "github.com/user/repo"
        )
    }

    func testNormalizeHTTP() {
        XCTAssertEqual(
            URLHelpers.normalize("http://github.com/user/repo"),
            "github.com/user/repo"
        )
    }
}
