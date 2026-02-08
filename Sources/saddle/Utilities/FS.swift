import Foundation

struct FS {
    nonisolated(unsafe) static let fm = FileManager.default

    static func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isSymlink(_ path: String) -> Bool {
        do {
            let attrs = try fm.attributesOfItem(atPath: path)
            return attrs[.type] as? FileAttributeType == .typeSymbolicLink
        } catch {
            return false
        }
    }

    static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    static func readFile(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    static func createDirectory(_ path: String) -> Bool {
        do {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    static func isExecutable(_ path: String) -> Bool {
        fm.isExecutableFile(atPath: path)
    }

    static func listDirectory(_ path: String) -> [String] {
        do {
            return try fm.contentsOfDirectory(atPath: path)
        } catch {
            return []
        }
    }

    static func writeFile(_ path: String, contents: String) -> Bool {
        do {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func findRepos(in root: String) -> [String] {
        guard isDirectory(root) else { return [] }

        let skipDirs: Set<String> = [
            ".git", ".build", "node_modules", "__pycache__",
            ".cache", "Pods", "DerivedData", ".swiftpm",
            ".hg", ".svn", "vendor", "target",
        ]

        var repos: [String] = []
        var queue = [root]

        while !queue.isEmpty {
            let dir = queue.removeFirst()
            let entries = listDirectory(dir)

            if entries.contains(".git") {
                repos.append(dir)
            }

            for entry in entries.sorted() {
                guard !skipDirs.contains(entry) else { continue }
                guard !entry.hasPrefix(".") else { continue }
                let fullPath = "\(dir)/\(entry)"
                guard isDirectory(fullPath) && !isSymlink(fullPath) else { continue }
                queue.append(fullPath)
            }
        }

        return repos.sorted()
    }
}
