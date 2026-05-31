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
    // list. Set KEYCHAIN_PATH to an absolute keychain path to instead pin
    // lookups to a dedicated keychain — explicit > implicit, so a later
    // `security list-keychains -s …` change can't silently break saddle's auth,
    // and the token stays out of login.keychain alongside Apple-managed items.
    private var keychain: String? { env["KEYCHAIN_PATH"] }

    // A dedicated keychain may be locked in non-GUI sessions (e.g. SSH). If so,
    // saddle auto-unlocks it using a password stored as a generic password;
    // configure that lookup with KEYCHAIN_UNLOCK_SVC and KEYCHAIN_UNLOCK_ACCT.
    //
    // The unlock password is read from the System keychain — machine-domain,
    // auto-unlocked at boot from the root-only /var/db/SystemKey, with no session
    // or GUI login required (so it works headless and across SSH sessions); access
    // is still gated by the item's ACL. This is the single supported source: no
    // env-var or login-keychain fallbacks. On a desktop where the dedicated
    // keychain is already unlocked at GUI login the unlock is simply a no-op and
    // the subsequent read succeeds regardless.
    //
    // Best-effort: if any of these are unset/missing we skip the unlock and let
    // the subsequent `find-generic-password` return nil. The caller treats nil
    // as "not authenticated."
    private let unlockPwKeychain = "/Library/Keychains/System.keychain"
    private var unlockSvc: String? { env["KEYCHAIN_UNLOCK_SVC"] }
    private var unlockAcct: String? { env["KEYCHAIN_UNLOCK_ACCT"] }

    private func unlockIfNeeded() {
        guard let keychain, let unlockSvc, let unlockAcct else { return }
        let (output, rc) = Exec.run("/usr/bin/security", args: [
            "find-generic-password", "-s", unlockSvc, "-a", unlockAcct, "-w", unlockPwKeychain
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
