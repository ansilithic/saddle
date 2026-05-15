import CLICore
import Foundation

/// Topologically orders manifest URLs based on the `[dependencies]`
/// section in the manifest TOML. Repos within a level run in parallel;
/// levels run sequentially. Hard-fail on missing deps, self-deps, cycles.
///
/// The manifest is the single source of truth for dependencies — there
/// is no hook.sh annotation fallback.
enum DependencyResolver {

    enum ResolveError: Error, CustomStringConvertible {
        case missingDep(repo: String, missing: String)
        case cycle(repos: [String])
        case selfDep(repo: String)

        var description: String {
            switch self {
            case .missingDep(let repo, let missing):
                return "\(repo) declares a dependency on \(missing), which is not in the manifest."
            case .cycle(let repos):
                return "Dependency cycle among: \(repos.joined(separator: ", "))"
            case .selfDep(let repo):
                return "\(repo) declares itself as a dependency — not allowed."
            }
        }
    }

    /// Normalize a dep token. Tokens may use short form (`apple/container`)
    /// or full form (`github.com/apple/container` / `git@github.com:...`).
    /// Short two-part names get a `github.com/` host prefix added so they
    /// compare equal to manifest URLs after normalization.
    static func normalizeDep(_ token: String) -> String {
        let n = URLHelpers.normalize(token)
        let parts = n.split(separator: "/")
        if parts.count == 2 {
            return "github.com/\(n)"
        }
        return n
    }

    /// Resolve manifest URLs into topological levels.
    /// Returns levels as arrays of *normalized* URLs and the per-repo
    /// dep map (also normalized) for downstream consumers.
    static func resolveLevels(_ urls: [String], manifestDeps: [String: [String]] = [:]) throws -> (levels: [[String]], deps: [String: [String]]) {
        let normalized = urls.map { URLHelpers.normalize($0) }
        let urlSet = Set(normalized)

        var originalForNormalized: [String: String] = [:]
        for (orig, norm) in zip(urls, normalized) {
            if originalForNormalized[norm] == nil {
                originalForNormalized[norm] = orig
            }
        }

        var deps: [String: [String]] = [:]
        for n in normalized {
            let declared = manifestDeps[n] ?? []
            for d in declared {
                if d == n {
                    throw ResolveError.selfDep(repo: originalForNormalized[n] ?? n)
                }
                if !urlSet.contains(d) {
                    throw ResolveError.missingDep(repo: originalForNormalized[n] ?? n, missing: d)
                }
            }
            deps[n] = declared
        }

        var processed: Set<String> = []
        var levels: [[String]] = []

        while processed.count < normalized.count {
            let ready = normalized.filter { url in
                !processed.contains(url)
                    && (deps[url] ?? []).allSatisfy { processed.contains($0) }
            }
            if ready.isEmpty {
                let cyclic = normalized.filter { !processed.contains($0) }
                let cyclicOriginal = cyclic.map { originalForNormalized[$0] ?? $0 }
                throw ResolveError.cycle(repos: cyclicOriginal)
            }
            levels.append(ready)
            processed.formUnion(ready)
        }
        return (levels, deps)
    }
}
