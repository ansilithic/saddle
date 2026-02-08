import CLICore
import Foundation

enum GitHelpers {
    struct GitInfo {
        let branch: String
        let status: String
        let statusColor: Color
        let lastCommitTime: String
    }

    static func info(at path: String) -> GitInfo {
        let (output, _) = Exec.git("status", "--porcelain=v2", "--branch", at: path)
        let lines = output.components(separatedBy: "\n")

        var hasChanges = false
        var aheadCount = 0
        var behindCount = 0
        var isDetached = false
        var branch = ""

        for line in lines {
            if line.hasPrefix("# branch.head ") {
                let name = String(line.dropFirst("# branch.head ".count))
                if name == "(detached)" {
                    isDetached = true
                    branch = "HEAD"
                } else {
                    branch = name
                }
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    aheadCount = Int(parts[2].dropFirst()) ?? 0
                    behindCount = Int(parts[3].dropFirst()) ?? 0
                }
            } else if !line.hasPrefix("#") && !line.isEmpty {
                hasChanges = true
            }
        }

        let status: String
        let color: Color
        if hasChanges {
            (status, color) = ("uncommitted changes", .yellow)
        } else if aheadCount > 0 && behindCount > 0 {
            (status, color) = ("diverged", .yellow)
        } else if aheadCount > 0 {
            (status, color) = ("\(aheadCount) ahead", .yellow)
        } else if behindCount > 0 {
            (status, color) = ("\(behindCount) behind", .yellow)
        } else if isDetached {
            (status, color) = ("detached", .gray)
        } else {
            (status, color) = ("clean", .green)
        }

        let (logOutput, logRc) = Exec.git("log", "-1", "--format=%cr", at: path)
        let commitTime = (logRc == 0 && !logOutput.isEmpty) ? logOutput : ""

        return GitInfo(branch: branch, status: status, statusColor: color, lastCommitTime: commitTime)
    }

    static func getRemoteURL(at path: String) -> String? {
        let (output, rc) = Exec.git("remote", "get-url", "origin", at: path)
        guard rc == 0, !output.isEmpty else { return nil }
        return output
    }
}
