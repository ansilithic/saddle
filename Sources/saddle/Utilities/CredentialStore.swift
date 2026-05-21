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

    private let env = ProcessInfo.processInfo.environment

    // By default saddle stores tokens via the login keychain's default search
    // list. Set SADDLE_KEYCHAIN to an absolute keychain path to instead pin
    // lookups to a dedicated keychain — explicit > implicit, so a later
    // `security list-keychains -s …` change can't silently break saddle's auth,
    // and the token stays out of login.keychain alongside Apple-managed items.
    private var keychain: String? { env["SADDLE_KEYCHAIN"] }

    // A dedicated keychain may be locked in non-GUI sessions (e.g. SSH). If so,
    // saddle can auto-unlock it using a password stored in the login keychain
    // as a generic password; configure that lookup with SADDLE_UNLOCK_SVC and
    // SADDLE_UNLOCK_ACCT. login.keychain auto-unlocks at GUI login; over SSH the
    // user runs `security unlock-keychain ~/Library/Keychains/login.keychain-db`
    // once per session, after which this lookup succeeds.
    //
    // Best-effort: if any of these are unset/locked/missing we skip the unlock
    // and let the subsequent `find-generic-password` return nil. The caller
    // treats nil as "not authenticated."
    private let loginKC = "\(NSHomeDirectory())/Library/Keychains/login.keychain-db"
    private var unlockSvc: String? { env["SADDLE_UNLOCK_SVC"] }
    private var unlockAcct: String? { env["SADDLE_UNLOCK_ACCT"] }

    private func unlockIfNeeded() {
        guard let keychain, let unlockSvc, let unlockAcct else { return }
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
        var args = ["find-generic-password", "-s", service, "-a", account, "-w"]
        if let keychain { args.append(keychain) }
        let (output, rc) = Exec.run("/usr/bin/security", args: args, timeout: 3)
        return rc == 0 && !output.isEmpty ? output : nil
    }

    func set(account: String, token: String) throws {
        unlockIfNeeded()
        // -U updates if exists, adds if not
        var args = ["add-generic-password", "-U", "-s", service, "-a", account, "-w", token]
        if let keychain { args.append(keychain) }
        let (_, rc) = Exec.run("/usr/bin/security", args: args, timeout: 3)
        if rc != 0 {
            throw CredentialError.storeFailed("Keychain write failed (exit \(rc))")
        }
    }

    func delete(account: String) throws {
        unlockIfNeeded()
        var args = ["delete-generic-password", "-s", service, "-a", account]
        if let keychain { args.append(keychain) }
        let (_, rc) = Exec.run("/usr/bin/security", args: args, timeout: 3)
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
