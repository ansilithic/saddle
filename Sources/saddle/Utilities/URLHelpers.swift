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

    /// Derive a hook name from a URL (owner-repo.sh).
    static func hookName(from url: String) -> String {
        let normalized = normalize(url)
        let parts = normalized.split(separator: "/")
        guard parts.count >= 3 else { return "\(repoName(from: url)).sh" }
        return "\(parts[parts.count - 2])-\(parts[parts.count - 1]).sh"
    }
}
