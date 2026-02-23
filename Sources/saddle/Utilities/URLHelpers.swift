import Foundation

enum URLHelpers {
    /// Normalize a git URL for comparison.
    /// git@github.com:user/repo.git -> github.com/user/repo
    /// https://github.com/user/repo.git -> github.com/user/repo
    static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.hasPrefix("git@") {
            s = String(s.dropFirst(4))
            if let colonIdx = s.firstIndex(of: ":") {
                s = s[s.startIndex..<colonIdx] + "/" + s[s.index(after: colonIdx)...]
                s = String(s)
            }
        }
        if s.hasPrefix("https://") { s = String(s.dropFirst(8)) }
        if s.hasPrefix("http://") { s = String(s.dropFirst(7)) }
        return s.lowercased()
    }

    /// Derive a repo name from a URL.
    static func repoName(from url: String) -> String {
        let lastComponent = url.split(separator: "/").last.map(String.init) ?? url
        if lastComponent.hasSuffix(".git") {
            return String(lastComponent.dropLast(4))
        }
        return lastComponent
    }

    /// Derive the owner/org from a URL.
    static func owner(from url: String) -> String {
        let normalized = normalize(url)
        let parts = normalized.split(separator: "/")
        guard parts.count >= 3 else { return "" }
        return String(parts[parts.count - 2])
    }

    /// Extract the hostname from a normalized URL.
    static func host(from url: String) -> String {
        let normalized = normalize(url)
        return String(normalized.split(separator: "/").first ?? "")
    }

    /// Extract the path after the hostname from a normalized URL.
    static func pathAfterHost(from url: String) -> String {
        let normalized = normalize(url)
        guard let slashIdx = normalized.firstIndex(of: "/") else { return normalized }
        return String(normalized[normalized.index(after: slashIdx)...])
    }

    /// Convert a normalized URL to a cloneable SSH URL.
    /// github.com/user/repo -> git@github.com:user/repo.git
    static func sshURL(from normalized: String) -> String {
        let parts = normalized.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return normalized }
        return "git@\(parts[0]):\(parts[1]).git"
    }

    /// Convert a normalized URL to a cloneable HTTPS URL.
    /// github.com/user/repo -> https://github.com/user/repo.git
    static func httpsURL(from normalized: String) -> String {
        return "https://\(normalized).git"
    }

    /// Convert a normalized URL to a cloneable URL using the given protocol.
    static func cloneURL(from normalized: String, protocol proto: Manifest.CloneProtocol) -> String {
        switch proto {
        case .ssh: return sshURL(from: normalized)
        case .https: return httpsURL(from: normalized)
        }
    }

    /// Derive a hook base name from a URL (owner-repo, no extension).
    /// The result is sanitized to only contain `[a-zA-Z0-9._-]` characters
    /// to prevent path traversal or shell injection when used in file paths
    /// and bash commands.
    static func hookBaseName(from url: String) -> String {
        let normalized = normalize(url)
        let parts = normalized.split(separator: "/")
        let raw: String
        if parts.count >= 3 {
            raw = "\(parts[parts.count - 2])-\(parts[parts.count - 1])"
        } else {
            raw = repoName(from: url)
        }
        return sanitizeHookName(raw)
    }

    /// Strip characters outside `[a-zA-Z0-9._-]` from a hook name.
    static func sanitizeHookName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(name.unicodeScalars.filter { allowed.contains($0) })
    }
}
