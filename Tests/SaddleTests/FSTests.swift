import XCTest
@testable import saddle

final class FSTests: XCTestCase {

    // Atomic writes use rename(2), which replaces a symlink with a regular file.
    // FS.writeFile resolves the symlink first so dotfiles-managed configs survive
    // saddle's manifest mutations (Equip, Unequip).
    func testWriteFilePreservesSymlinks() throws {
        let dir = "/tmp/saddle-fs-test-\(UUID().uuidString)"
        let real = "\(dir)/real.txt"
        let link = "\(dir)/link.txt"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try "original".write(toFile: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)

        try FS.writeFile(link, contents: "rewritten")

        // Symlink survives the write.
        let attrs = try FileManager.default.attributesOfItem(atPath: link)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)

        // Real file received the new content.
        XCTAssertEqual(try String(contentsOfFile: real, encoding: .utf8), "rewritten")
    }
}
