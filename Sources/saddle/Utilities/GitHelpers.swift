import CLICore
import Foundation

enum GitHelpers {
    struct GitInfo {
        let remoteURL: String?
        let branch: String
        let status: String
        let ahead: Int
        let behind: Int
        let lastCommitTime: String
    }

    static func info(at path: String) -> GitInfo {
        let (rawRemote, remoteRC) = Exec.git("remote", "get-url", "origin", at: path)
        let remoteURL = remoteRC == 0 && !rawRemote.isEmpty ? rawRemote : nil

        let (statusOutput, statusRC) = Exec.git("status", "--porcelain=v2", "--branch", at: path)
        let lines = statusRC == 0 ? statusOutput.components(separatedBy: "\n") : []

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
        if hasChanges {
            status = "uncommitted changes"
        } else if aheadCount > 0 && behindCount > 0 {
            status = "diverged from remote"
        } else if aheadCount > 0 {
            status = "\(aheadCount) commit\(aheadCount == 1 ? "" : "s") ahead"
        } else if behindCount > 0 {
            status = "\(behindCount) commit\(behindCount == 1 ? "" : "s") behind"
        } else if isDetached {
            status = "detached HEAD"
        } else {
            status = "up to date"
        }

        let (logOutput, logRC) = Exec.git("log", "-1", "--format=%cI", at: path)
        let commitTime = logRC == 0 && !logOutput.isEmpty ? logOutput : ""

        return GitInfo(remoteURL: remoteURL, branch: branch, status: status, ahead: aheadCount, behind: behindCount, lastCommitTime: commitTime)
    }
}
