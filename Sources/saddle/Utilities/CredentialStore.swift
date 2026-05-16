import Foundation

protocol CredentialStoreProtocol: Sendable {
    func get(account: String) -> String?
    func set(account: String, token: String) throws
    func delete(account: String) throws
}

enum CredentialStore {
    static let platform: any CredentialStoreProtocol = {
        #if os(macOS)
        return KeychainCredentialStore()
        #else
        return FileCredentialStore()
        #endif
    }()
}

#if os(macOS)
struct KeychainCredentialStore: CredentialStoreProtocol {
    private let service = "com.ansilithic.saddle"

    // Pin lookups to the dedicated avranet keychain rather than relying on
    // the user's keychain search list. Explicit > implicit: a future
    // `security list-keychains -s …` change can't silently break saddle's
    // auth, and the user's secret stays out of login.keychain alongside
    // Apple-managed items.
    private let keychain = "\(NSHomeDirectory())/Library/Keychains/avranet.keychain-db"

    // The avranet unlock password lives in login.keychain as a generic
    // password (svce="net.avra.keychain.unlock-password", acct="avranet").
    // login.keychain auto-unlocks at GUI login (HackBookAir's local terminal,
    // launchd-fired tasks). For SSH sessions, login.keychain is locked
    // until the user runs `security unlock-keychain ~/Library/Keychains/
    // login.keychain-db` once per session — at which point this lookup
    // succeeds and we unlock avranet for the rest of the session.
    //
    // Best-effort: if login is locked or the item is missing, we silently
    // skip the unlock attempt and let the subsequent `find-generic-password`
    // call return nil. Caller treats nil as "not authenticated."
    private let loginKC      = "\(NSHomeDirectory())/Library/Keychains/login.keychain-db"
    private let unlockSvc    = "net.avra.keychain.unlock-password"
    private let unlockAcct   = "avranet"

    private func unlockIfNeeded() {
        let (output, rc) = Exec.run("/usr/bin/security", args: [
            "find-generic-password", "-s", unlockSvc, "-a", unlockAcct, "-w", loginKC
        ], timeout: 3)
        guard rc == 0 else { return }
        let pass = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pass.isEmpty else { return }
        _ = Exec.run("/usr/bin/security", args: [
            "unlock-keychain", "-p", pass, keychain
        ], timeout: 3)
    }

    func get(account: String) -> String? {
        unlockIfNeeded()
        let (output, rc) = Exec.run("/usr/bin/security", args: [
            "find-generic-password", "-s", service, "-a", account, "-w", keychain
        ], timeout: 3)
        return rc == 0 && !output.isEmpty ? output : nil
    }

    func set(account: String, token: String) throws {
        unlockIfNeeded()
        // -U updates if exists, adds if not
        let (_, rc) = Exec.run("/usr/bin/security", args: [
            "add-generic-password", "-U", "-s", service, "-a", account, "-w", token, keychain
        ], timeout: 3)
        if rc != 0 {
            throw CredentialError.storeFailed("Keychain write failed (exit \(rc))")
        }
    }

    func delete(account: String) throws {
        unlockIfNeeded()
        let (_, rc) = Exec.run("/usr/bin/security", args: [
            "delete-generic-password", "-s", service, "-a", account, keychain
        ], timeout: 3)
        if rc != 0 {
            throw CredentialError.storeFailed("Keychain delete failed (exit \(rc))")
        }
    }
}
#endif

struct FileCredentialStore: CredentialStoreProtocol {
    private var credentialsPath: String { "\(Paths.dataDir)/credentials" }

    func get(account: String) -> String? {
        guard let contents = try? FS.readFile(credentialsPath),
              let data = contents.data(using: .utf8),
              let creds = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return creds[account]
    }

    func set(account: String, token: String) throws {
        var creds = loadAll()
        creds[account] = token
        try save(creds)
    }

    func delete(account: String) throws {
        var creds = loadAll()
        creds.removeValue(forKey: account)
        try save(creds)
    }

    private func loadAll() -> [String: String] {
        guard let contents = try? FS.readFile(credentialsPath),
              let data = contents.data(using: .utf8),
              let creds = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return creds
    }

    private func save(_ creds: [String: String]) throws {
        let dir = Paths.dataDir
        if !FS.isDirectory(dir) { try FS.createDirectory(dir) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(creds)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try FS.writeFile(credentialsPath, contents: json)
        // Set 0600 permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath)
    }
}

enum CredentialError: Error, CustomStringConvertible {
    case storeFailed(String)

    var description: String {
        switch self {
        case .storeFailed(let msg): return msg
        }
    }
}
