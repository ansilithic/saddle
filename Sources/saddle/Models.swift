import CLICore
import Foundation

struct Manifest {
    var root: String
    var urls: [String]
}

enum SyncOutcome {
    case synced
    case unchanged
    case skipped
    case failed(String)
    case wouldSync
}

struct SyncResult {
    var synced = 0
    var unchanged = 0
    var skipped = 0
    var failed = 0
    var wouldSync = 0
    var failures: [(name: String, message: String)] = []

    mutating func record(_ outcome: SyncOutcome, name: String = "") {
        switch outcome {
        case .synced: synced += 1
        case .unchanged: unchanged += 1
        case .skipped: skipped += 1
        case .failed(let msg):
            failed += 1
            if !name.isEmpty { failures.append((name, msg)) }
        case .wouldSync: wouldSync += 1
        }
    }

    var total: Int { synced + unchanged + skipped + failed + wouldSync }
}

struct RepoInfo {
    let relativePath: String
    let fullPath: String
    let remoteURL: String?
    let branch: String
    let status: String
    let statusColor: Color
    let lastCommitTime: String
    let saddled: Bool
    let hasHook: Bool
    let visibility: String
}
