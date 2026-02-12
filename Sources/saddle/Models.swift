import CLICore
import Foundation

struct Manifest {
    var mount: String
    var repos: [String]
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

struct RemoteRepoInfo {
    let visibility: String
    let role: String
    let defaultBranch: String
    let pushedAt: String
    let language: String
    let description: String
    let stargazers: Int
    let isArchived: Bool
}

struct RepoInfo {
    let relativePath: String
    let fullPath: String
    let remoteURL: String?
    let owner: String
    let branch: String
    let localStatus: String
    let localStatusColor: Color
    let visibility: String
    let role: String
    let isArchived: Bool
    let language: String
    let description: String
    let stargazers: Int
    let lastPushTime: String
    let saddled: Bool
    let hasHook: Bool
    let isStarred: Bool
    let remoteOnly: Bool
}
