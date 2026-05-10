import CLICore
import Foundation

/// Reads `# saddle:depends ...` annotations from each repo's hook.sh and
/// returns the manifest grouped into topological levels — repos in level N
/// have all dependencies satisfied by levels 0..<N. Within each level,
/// repos appear in their original manifest order.
///
/// Annotation syntax (anywhere in `hook.sh`):
///
///     # saddle:depends apple/container avranet/dns avranet/admin
///
/// Multiple `# saddle:depends` lines are concatenated. Tokens are
/// whitespace-separated and may use any URL form `URLHelpers.normalize`
/// accepts (e.g., `apple/container`, `github.com/apple/container`,
/// `git@github.com:apple/container.git`).
///
/// Hard-fail policy:
///   - Missing dep (declared but not in manifest) → error.
///   - Self-dep → error.
///   - Cycle → error.
///
/// No wildcards. No per-target deps. Keep it simple.
enum DependencyResolver {

    enum ResolveError: Error, CustomStringConvertible {
        case missingDep(repo: String, missing: String)
        case cycle(repos: [String])
        case selfDep(repo: String)

        var description: String {
            switch self {
            case .missingDep(let repo, let missing):
                return "\(repo) declares saddle:depends on \(missing), which is not in the manifest."
            case .cycle(let repos):
                return "Dependency cycle among: \(repos.joined(separator: ", "))"
            case .selfDep(let repo):
                return "\(repo) declares itself as a saddle:depends — not allowed."
            }
        }
    }

    /// Normalize a dep token. Tokens may use short form (`apple/container`)
    /// or full form (`github.com/apple/container` or `git@github.com:...`).
    /// Short-form tokens (just `<owner>/<repo>`) get a `github.com/` host
    /// prefix added so they match manifest URLs after normalization.
    static func normalizeDep(_ token: String) -> String {
        let n = URLHelpers.normalize(token)
        let parts = n.split(separator: "/")
        if parts.count == 2 {
            return "github.com/\(n)"
        }
        return n
    }

    /// Extract dep tokens from a hook.sh by scanning every line for
    /// `# saddle:depends ...`. Returns the raw tokens (no normalization).
    static func parseDeps(hookPath: String) -> [String] {
        guard let contents = try? FS.readFile(hookPath) else { return [] }
        let prefix = "# saddle:depends"
        var deps: [String] = []
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            // Split on whitespace and commas; both feel natural to write.
            let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ","))
            for token in rest.components(separatedBy: separators) where !token.isEmpty {
                deps.append(token)
            }
        }
        return deps
    }

    /// Resolve manifest URLs into topological levels.
    /// Returns levels as arrays of *normalized* URLs.
    static func resolveLevels(_ urls: [String], hooksDir: String = Paths.hooksDir) throws -> [[String]] {
        let normalized = urls.map { URLHelpers.normalize($0) }
        let urlSet = Set(normalized)

        // For error messages, map normalized → original spelling.
        var originalForNormalized: [String: String] = [:]
        for (orig, norm) in zip(urls, normalized) {
            // First occurrence wins; manifest shouldn't have duplicates anyway.
            if originalForNormalized[norm] == nil {
                originalForNormalized[norm] = orig
            }
        }

        // Read deps for each repo.
        var deps: [String: [String]] = [:]
        for (i, url) in urls.enumerated() {
            let n = normalized[i]
            let baseName = URLHelpers.hookBaseName(from: url)
            let hookPath = "\(hooksDir)/\(baseName)/hook.sh"
            guard FS.exists(hookPath) else {
                deps[n] = []
                continue
            }
            var depsList: [String] = []
            for token in parseDeps(hookPath: hookPath) {
                let depNormalized = normalizeDep(token)
                if depNormalized == n {
                    throw ResolveError.selfDep(repo: originalForNormalized[n] ?? url)
                }
                if !urlSet.contains(depNormalized) {
                    throw ResolveError.missingDep(repo: originalForNormalized[n] ?? url, missing: token)
                }
                depsList.append(depNormalized)
            }
            deps[n] = depsList
        }

        // Build levels by repeatedly extracting nodes whose deps are all
        // already processed. Manifest order is preserved within each level
        // (`normalized.filter { ... }` walks the original order).
        var processed: Set<String> = []
        var levels: [[String]] = []

        while processed.count < normalized.count {
            let ready = normalized.filter { url in
                !processed.contains(url)
                    && (deps[url] ?? []).allSatisfy { processed.contains($0) }
            }
            if ready.isEmpty {
                // No progress = cycle. Remaining unprocessed repos form one
                // (or several) — surface them all.
                let cyclic = normalized.filter { !processed.contains($0) }
                let cyclicOriginal = cyclic.map { originalForNormalized[$0] ?? $0 }
                throw ResolveError.cycle(repos: cyclicOriginal)
            }
            levels.append(ready)
            processed.formUnion(ready)
        }
        return levels
    }
}
