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

    func get(account: String) -> String? {
        let (output, rc) = Exec.run("/usr/bin/security", args: [
            "find-generic-password", "-s", service, "-a", account, "-w"
        ], timeout: 3)
        return rc == 0 && !output.isEmpty ? output : nil
    }

    func set(account: String, token: String) throws {
        // -U updates if exists, adds if not
        let (_, rc) = Exec.run("/usr/bin/security", args: [
            "add-generic-password", "-U", "-s", service, "-a", account, "-w", token
        ], timeout: 3)
        if rc != 0 {
            throw CredentialError.storeFailed("Keychain write failed (exit \(rc))")
        }
    }

    func delete(account: String) throws {
        let (_, rc) = Exec.run("/usr/bin/security", args: [
            "delete-generic-password", "-s", service, "-a", account
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
