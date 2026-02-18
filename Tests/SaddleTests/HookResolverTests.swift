import XCTest
@testable import saddle

final class HookResolverTests: XCTestCase {

    private var hooksDir: String!

    override func setUp() {
        super.setUp()
        hooksDir = "/tmp/saddle-test-hooks-\(UUID().uuidString)"
        _ = FS.createDirectory(hooksDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: hooksDir)
        super.tearDown()
    }

    // MARK: - Directory format

    func testResolveDirectoryInstall() {
        createHook(dir: "user-repo", script: "install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hookName, "user-repo")
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    func testResolveDirectoryUpdate() {
        createHook(dir: "user-repo", script: "update.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("update.sh") ?? false)
    }

    func testResolveDirectoryUninstall() {
        createHook(dir: "user-repo", script: "uninstall.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .uninstall, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("uninstall.sh") ?? false)
    }

    // MARK: - Update fallback to install

    func testUpdateFallsBackToInstall() {
        createHook(dir: "user-repo", script: "install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("install.sh") ?? false)
    }

    func testUpdatePrefersUpdateOverInstall() {
        createHook(dir: "user-repo", script: "install.sh")
        createHook(dir: "user-repo", script: "update.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("update.sh") ?? false)
    }

    // MARK: - Legacy format

    func testResolveLegacyInstall() {
        createLegacyHook(name: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isLegacy ?? false)
    }

    func testResolveLegacyUpdate() {
        createLegacyHook(name: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isLegacy ?? false)
    }

    func testLegacyNotUsedForUninstall() {
        createLegacyHook(name: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .uninstall, hooksDir: hooksDir)
        XCTAssertNil(result)
    }

    // MARK: - Directory preferred over legacy

    func testDirectoryPreferredOverLegacy() {
        createHook(dir: "user-repo", script: "install.sh")
        createLegacyHook(name: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    // MARK: - No hook

    func testResolveNoHook() {
        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNil(result)
    }

    func testNonExecutableIgnored() {
        let dir = "\(hooksDir!)/user-repo"
        _ = FS.createDirectory(dir)
        _ = FS.writeFile("\(dir)/install.sh", contents: "#!/bin/sh\n")
        // Not chmod +x — should be ignored

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNil(result)
    }

    // MARK: - hasHook

    func testHasHookDirectory() {
        createHook(dir: "user-repo", script: "install.sh")
        XCTAssertTrue(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    func testHasHookLegacy() {
        createLegacyHook(name: "user-repo")
        XCTAssertTrue(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    func testHasNoHook() {
        XCTAssertFalse(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    // MARK: - Helpers

    private func createHook(dir: String, script: String) {
        let dirPath = "\(hooksDir!)/\(dir)"
        _ = FS.createDirectory(dirPath)
        let scriptPath = "\(dirPath)/\(script)"
        _ = FS.writeFile(scriptPath, contents: "#!/bin/sh\n")
        chmod(scriptPath, 0o755)
    }

    private func createLegacyHook(name: String) {
        let path = "\(hooksDir!)/\(name).sh"
        _ = FS.writeFile(path, contents: "#!/bin/sh\n")
        chmod(path, 0o755)
    }

    private func chmod(_ path: String, _ mode: mode_t) {
        Darwin.chmod(path, mode)
    }
}
