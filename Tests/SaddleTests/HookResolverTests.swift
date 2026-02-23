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

    // MARK: - Consolidated format (hook.sh)

    func testResolveConsolidatedInstall() {
        createConsolidatedHook(dir: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hookName, "user-repo")
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    func testResolveConsolidatedUpdate() {
        createConsolidatedHook(dir: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    func testResolveConsolidatedUninstall() {
        createConsolidatedHook(dir: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .uninstall, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    func testConsolidatedHealthReturnsNil() {
        createConsolidatedHook(dir: "user-repo")

        // Health lifecycle is supported by consolidated format (unlike legacy directory)
        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .health, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    // MARK: - Legacy directory format

    func testResolveDirectoryInstall() {
        createHook(dir: "user-repo", script: "install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hookName, "user-repo")
        XCTAssertTrue(result?.isLegacy ?? false)
    }

    func testResolveDirectoryUpdate() {
        createHook(dir: "user-repo", script: "update.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("update.sh") ?? false)
        XCTAssertTrue(result?.isLegacy ?? false)
    }

    func testResolveDirectoryUninstall() {
        createHook(dir: "user-repo", script: "uninstall.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .uninstall, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("uninstall.sh") ?? false)
        XCTAssertTrue(result?.isLegacy ?? false)
    }

    func testDirectoryHealthReturnsNil() {
        createHook(dir: "user-repo", script: "install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .health, hooksDir: hooksDir)
        XCTAssertNil(result)
    }

    // MARK: - Update fallback to install

    func testUpdateFallsBackToInstall() {
        createHook(dir: "user-repo", script: "install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("install.sh") ?? false)
        XCTAssertTrue(result?.isLegacy ?? false)
    }

    func testUpdatePrefersUpdateOverInstall() {
        createHook(dir: "user-repo", script: "install.sh")
        createHook(dir: "user-repo", script: "update.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("update.sh") ?? false)
        XCTAssertTrue(result?.isLegacy ?? false)
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

    // MARK: - Format precedence

    func testConsolidatedPreferredOverLegacyDirectory() {
        createConsolidatedHook(dir: "user-repo")
        createHook(dir: "user-repo", script: "install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    func testConsolidatedPreferredOverLegacySingleFile() {
        createConsolidatedHook(dir: "user-repo")
        createLegacyHook(name: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
        XCTAssertFalse(result?.isLegacy ?? true)
    }

    func testDirectoryPreferredOverLegacySingleFile() {
        createHook(dir: "user-repo", script: "install.sh")
        createLegacyHook(name: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("install.sh") ?? false)
        XCTAssertTrue(result?.isLegacy ?? false)
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

    private func createConsolidatedHook(dir: String) {
        let dirPath = "\(hooksDir!)/\(dir)"
        _ = FS.createDirectory(dirPath)
        let hookPath = "\(dirPath)/hook.sh"
        _ = FS.writeFile(hookPath, contents: "#!/bin/bash\ninstall() { :; }\nupdate() { :; }\nuninstall() { :; }\nhealth() { :; }\n")
        chmod(hookPath, 0o755)
    }

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
