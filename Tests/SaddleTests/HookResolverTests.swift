#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import XCTest
@testable import saddle

final class HookResolverTests: XCTestCase {

    private var hooksDir: String!

    override func setUp() {
        super.setUp()
        hooksDir = "/tmp/saddle-test-hooks-\(UUID().uuidString)"
        try! FS.createDirectory(hooksDir)
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
    }

    func testResolveConsolidatedUpdate() {
        createConsolidatedHook(dir: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .update, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
    }

    func testResolveConsolidatedUninstall() {
        createConsolidatedHook(dir: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .uninstall, hooksDir: hooksDir)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.scriptPath.hasSuffix("hook.sh") ?? false)
    }

    func testConsolidatedHealth() {
        createConsolidatedHook(dir: "user-repo")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .health, hooksDir: hooksDir)
        XCTAssertNotNil(result)
    }

    // MARK: - Legacy formats NOT resolved

    func testLegacyDirectoryNotResolved() {
        // Create a legacy directory-style hook (install.sh in dir, no hook.sh)
        let dirPath = "\(hooksDir!)/user-repo"
        try! FS.createDirectory(dirPath)
        try! FS.writeFile("\(dirPath)/install.sh", contents: "#!/bin/sh\n")
        setExecutable("\(dirPath)/install.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNil(result, "Legacy directory format should no longer be resolved")
    }

    func testLegacySingleFileNotResolved() {
        // Create a legacy single-file hook (owner-repo.sh at hooks root)
        try! FS.writeFile("\(hooksDir!)/user-repo.sh", contents: "#!/bin/sh\n")
        setExecutable("\(hooksDir!)/user-repo.sh")

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNil(result, "Legacy single-file format should no longer be resolved")
    }

    func testLegacyDirectoryNotDetectedByHasHook() {
        let dirPath = "\(hooksDir!)/user-repo"
        try! FS.createDirectory(dirPath)
        try! FS.writeFile("\(dirPath)/install.sh", contents: "#!/bin/sh\n")
        setExecutable("\(dirPath)/install.sh")

        XCTAssertFalse(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    func testLegacySingleFileNotDetectedByHasHook() {
        try! FS.writeFile("\(hooksDir!)/user-repo.sh", contents: "#!/bin/sh\n")
        setExecutable("\(hooksDir!)/user-repo.sh")

        XCTAssertFalse(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    // MARK: - No hook

    func testResolveNoHook() {
        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNil(result)
    }

    func testNonExecutableIgnored() {
        let dir = "\(hooksDir!)/user-repo"
        try! FS.createDirectory(dir)
        try! FS.writeFile("\(dir)/hook.sh", contents: "#!/bin/bash\ninstall() { :; }\n")
        // Not chmod +x — should be ignored

        let result = HookResolver.resolve(for: "github.com/user/repo", lifecycle: .install, hooksDir: hooksDir)
        XCTAssertNil(result)
    }

    // MARK: - hasHook

    func testHasHookConsolidated() {
        createConsolidatedHook(dir: "user-repo")
        XCTAssertTrue(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    func testHasNoHook() {
        XCTAssertFalse(HookResolver.hasHook(for: "github.com/user/repo", hooksDir: hooksDir))
    }

    // MARK: - Helpers

    private func createConsolidatedHook(dir: String) {
        let dirPath = "\(hooksDir!)/\(dir)"
        try! FS.createDirectory(dirPath)
        let hookPath = "\(dirPath)/hook.sh"
        try! FS.writeFile(hookPath, contents: "#!/bin/bash\ninstall() { :; }\nupdate() { :; }\nuninstall() { :; }\nhealth() { :; }\n")
        setExecutable(hookPath)
    }

    private func setExecutable(_ path: String) {
        chmod(path, 0o755)
    }
}
