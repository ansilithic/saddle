import ArgumentParser
import CLICore
import Foundation

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show status of all repos in the developer directory."
    )

    @Flag(help: "Show all repos, including archived.")
    var all = false

    @Flag(help: "Show only public repos.")
    var `public` = false

    @Flag(help: "Show only private repos.")
    var `private` = false

    @Flag(help: "Show only clean repos.")
    var clean = false

    @Flag(help: "Show only dirty repos.")
    var dirty = false

    @Flag(help: "Show only equipped repos.")
    var equipped = false

    @Flag(help: "Show only unequipped repos.")
    var unequipped = false

    @Flag(help: "Show only stray repos (local but not in manifest).")
    var stray = false

    @Flag(help: "Show only local repos (equipped + stray).")
    var local = false

    @Flag(help: "Show only hooked repos.")
    var hooked = false

    @Flag(help: "Show only unhooked repos.")
    var unhooked = false

    @Flag(help: "Show only starred repos.")
    var starred = false

    @Flag(help: "Show only unstarred repos.")
    var unstarred = false

    @Flag(help: "Show only archived repos.")
    var archived = false

    @Flag(help: "Show only active (non-archived) repos.")
    var active = false

    @Flag(name: .long, help: "Fetch all remotes regardless of cache age.")
    var forceFetch = false

    @Option(help: "Show only repos owned by <owner>.")
    var owner: String?

    private struct PartialInfo {
        let relativePath: String
        let fullPath: String
        let git: GitHelpers.GitInfo
        let saddled: Bool
        let hasHook: Bool
    }

    func run() async {
        let spinner = ProgressSpinner()
        spinner.label = styled("Scanning\u{2026}", .dim)
        spinner.start()

        let (manifest, devDir, declaredURLs) = Parser.loadManifest()

        let shouldFetch = forceFetch || State.shouldFetch()
        let (allRepos, _, hostResult) = await gatherRepos(manifest: manifest, devDir: devDir, declaredURLs: declaredURLs, spinner: spinner, fetch: shouldFetch, forceHost: forceFetch)

        spinner.stop()

        let repos = applyFilters(allRepos)

        if !repos.isEmpty {
            printReposSection(repos, host: hostResult, mountDir: devDir)
        } else {
            print()
            print()
            print(styled("No git repos found in \(FS.shortenPath(devDir))", .dim))
        }

        printFilterLine(repos: repos)
    }

    // MARK: - Filtering

    private var activeFilters: [String] {
        var filters: [String] = []
        if `public` && !`private` { filters.append("public") }
        if `private` && !`public` { filters.append("private") }
        if clean && !dirty { filters.append("clean") }
        if dirty && !clean { filters.append("dirty") }
        if equipped && !unequipped { filters.append("equipped") }
        if unequipped && !equipped { filters.append("unequipped") }
        if hooked && !unhooked { filters.append("hooked") }
        if unhooked && !hooked { filters.append("unhooked") }
        if starred && !unstarred { filters.append("starred") }
        if unstarred && !starred { filters.append("unstarred") }
        if stray { filters.append("stray") }
        if local { filters.append("local") }
        if archived { filters.append("archived") }
        if active { filters.append("active") }
        if all { filters.append("all") }
        else if !hasAnyFilter && owner == nil { filters.append("local (default)") }
        if let owner { filters.append("owner: \(owner)") }
        return filters
    }

    private func printFilterLine(repos: [RepoInfo]) {
        let filters = activeFilters
        let filterText = filters.isEmpty
            ? styled("none", .dim)
            : styled(filters.joined(separator: ", "), .cyan)
        print()
        print(styled("  \u{25BC} Filters applied:", .dim) + " " + filterText + " " + styled("(\(repos.count) repos)", .darkGray))
    }

    private var hasAnyFilter: Bool {
        `public` || `private` || clean || dirty || equipped || unequipped || stray || local
            || hooked || unhooked || starred || unstarred || archived || active || owner != nil
    }

    private func applyFilters(_ repos: [RepoInfo]) -> [RepoInfo] {
        let defaultLocal = !all && !hasAnyFilter

        return repos.filter { repo in
            if defaultLocal && !repo.saddled && repo.remoteOnly { return false }
            if `public` != `private` {
                if `public` && repo.visibility != "public" { return false }
                if `private` && repo.visibility != "private" { return false }
            }
            if clean != dirty {
                if clean && repo.localStatus != "clean" { return false }
                if dirty && repo.localStatus != "dirty" { return false }
            }
            if equipped != unequipped {
                if equipped && !repo.saddled { return false }
                if unequipped && repo.saddled { return false }
            }
            if stray && (repo.saddled || repo.remoteOnly) { return false }
            if local && repo.remoteOnly { return false }
            if hooked != unhooked {
                if hooked && !repo.hasHook { return false }
                if unhooked && repo.hasHook { return false }
            }
            if archived != active {
                if archived && !repo.isArchived { return false }
                if active && repo.isArchived { return false }
            }
            if starred != unstarred {
                if starred && !repo.isStarred { return false }
                if unstarred && repo.isStarred { return false }
            }
            if let owner {
                if repo.owner.lowercased() != owner.lowercased() { return false }
            }
            return true
        }
    }

    // MARK: - Data Gathering

    private func gatherRepos(manifest: Manifest?, devDir: String, declaredURLs: [String], spinner: ProgressSpinner, fetch: Bool, forceHost: Bool = false) async -> (repos: [RepoInfo], missingURLs: [String], host: HostResult) {
        let normalizedDeclared = Set(declaredURLs.map { URLHelpers.normalize($0) })

        async let hostResultTask = Host.fetchAllRepos(declaredURLs: declaredURLs, forceRefresh: forceHost)

        let discoveredPaths = FS.findRepos(in: devDir)
        let repoCount = discoveredPaths.count

        // Phase 1: scan local state (no network)
        let emptyGit = GitHelpers.GitInfo(remoteURL: nil, branch: "", status: "", ahead: 0, behind: 0, lastCommitTime: "")
        var partials = Array(repeating: PartialInfo(relativePath: "", fullPath: "", git: emptyGit, saddled: false, hasHook: false), count: repoCount)

        let scanLock = NSLock()
        nonisolated(unsafe) var scanned = 0

        partials.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            DispatchQueue.concurrentPerform(iterations: repoCount) { i in
                let repoPath = discoveredPaths[i]
                let relativePath = String(repoPath.dropFirst(devDir.count + 1))
                let git = GitHelpers.info(at: repoPath)
                let normalized = git.remoteURL.map { URLHelpers.normalize($0) }
                let saddled = normalized.map { normalizedDeclared.contains($0) } ?? false
                let hasHook = git.remoteURL.map { HookResolver.hasHook(for: $0) } ?? false

                buffer[i] = PartialInfo(relativePath: relativePath, fullPath: repoPath, git: git, saddled: saddled, hasHook: hasHook)

                scanLock.lock()
                scanned += 1
                spinner.status = styled("[\(scanned)/\(repoCount)]", .dim)
                scanLock.unlock()
            }
        }

        // Phase 2: fetch remotes (network)
        if fetch {
            let fetchLock = NSLock()
            nonisolated(unsafe) var fetched = 0
            nonisolated(unsafe) var failedCount = 0
            let fetchable = partials.enumerated().filter { $0.element.git.remoteURL != nil }
            let fetchCount = fetchable.count

            spinner.label = styled("Fetching\u{2026}", .bold) + "  " + styled("\(fetchCount) repos", .dim)
            spinner.status = styled("[0/\(fetchCount)]", .dim)

            partials.withUnsafeMutableBufferPointer { buf in
                nonisolated(unsafe) let buffer = buf
                DispatchQueue.concurrentPerform(iterations: fetchCount) { fi in
                    let (i, partial) = fetchable[fi]
                    let repoPath = discoveredPaths[i]

                    spinner.activate("\(fi)", name: partial.relativePath)

                    let (fetchOutput, fetchExit) = Exec.git("fetch", at: repoPath, timeout: 30)

                    if fetchExit == 0 {
                        let git = GitHelpers.info(at: repoPath)
                        let normalized = git.remoteURL.map { URLHelpers.normalize($0) }
                        let saddled = normalized.map { normalizedDeclared.contains($0) } ?? false
                        let hasHook = git.remoteURL.map { HookResolver.hasHook(for: $0) } ?? false
                        let relativePath = String(repoPath.dropFirst(devDir.count + 1))
                        buffer[i] = PartialInfo(relativePath: relativePath, fullPath: repoPath, git: git, saddled: saddled, hasHook: hasHook)
                    }

                    fetchLock.lock()
                    fetched += 1
                    if fetchExit != 0 {
                        failedCount += 1
                        spinner.fail("\(fi)", reason: fetchOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        spinner.complete("\(fi)")
                    }
                    let failStr = failedCount > 0 ? "  " + styled("\(failedCount) failed", .red) : ""
                    spinner.status = styled("[\(fetched)/\(fetchCount)]", .dim) + failStr
                    fetchLock.unlock()
                }
            }

            State.touchLastFetch()
        }

        let hostResult = await hostResultTask

        var repos: [RepoInfo] = []
        var localNormalized = Set<String>()
        var matchedNormalized = Set<String>()
        for p in partials {
            let normalized = p.git.remoteURL.map { URLHelpers.normalize($0) }
            let ghInfo = normalized.flatMap { hostResult.repos[$0] }

            let visibility = ghInfo?.visibility ?? "\u{2014}"
            let role = ghInfo?.role ?? (p.git.remoteURL != nil ? "\u{2014}" : "local")
            let language = ghInfo?.language ?? ""
            let description = ghInfo?.description ?? ""
            let stargazers = ghInfo?.stargazers ?? 0
            let isArchived = ghInfo?.isArchived ?? false

            let localStatus: String
            let localStatusColor: Color
            if p.git.status == "uncommitted changes" {
                (localStatus, localStatusColor) = ("dirty", .red)
            } else {
                (localStatus, localStatusColor) = ("clean", .green)
            }

            let owner = p.git.remoteURL.map { URLHelpers.owner(from: $0) } ?? "local"
            let isStarred = normalized.map { hostResult.starredURLs.contains($0) } ?? false
            let repo = RepoInfo(
                relativePath: p.relativePath,
                fullPath: p.fullPath,
                remoteURL: p.git.remoteURL.map { URLHelpers.normalize($0) },
                owner: owner.isEmpty ? "local" : owner,
                branch: p.git.branch,
                localStatus: localStatus,
                localStatusColor: localStatusColor,
                visibility: visibility,
                role: role,
                isArchived: isArchived,
                language: language,
                description: description,
                stargazers: stargazers,
                lastPushTime: Self.relativeTime(from: p.git.lastCommitTime),
                ahead: p.git.ahead,
                behind: p.git.behind,
                saddled: p.saddled,
                hasHook: p.hasHook,
                isStarred: isStarred,
                remoteOnly: false
            )
            repos.append(repo)
            if let url = p.git.remoteURL {
                localNormalized.insert(URLHelpers.normalize(url))
            }
            if p.saddled, let url = p.git.remoteURL {
                matchedNormalized.insert(URLHelpers.normalize(url))
            }
        }

        let remoteOnly = hostResult.repos
            .filter { !localNormalized.contains($0.key) }
            .sorted { $0.key < $1.key }

        var remoteOnlyNormalized = Set<String>()
        for (normalizedURL, info) in remoteOnly {
            remoteOnlyNormalized.insert(normalizedURL)
            let name = URLHelpers.pathAfterHost(from: normalizedURL)
            let owner = URLHelpers.owner(from: normalizedURL)
            let host = URLHelpers.host(from: normalizedURL)
            let pushedTime = Self.relativeTime(from: info.pushedAt)
            repos.append(RepoInfo(
                relativePath: name,
                fullPath: "",
                remoteURL: normalizedURL,
                owner: owner.isEmpty ? host : owner,
                branch: info.defaultBranch,
                localStatus: "not cloned",
                localStatusColor: .cyan,
                visibility: info.visibility,
                role: info.role,
                isArchived: info.isArchived,
                language: info.language,
                description: info.description,
                stargazers: info.stargazers,
                lastPushTime: pushedTime,
                ahead: 0,
                behind: 0,
                saddled: normalizedDeclared.contains(normalizedURL),
                hasHook: false,
                isStarred: hostResult.starredURLs.contains(normalizedURL),
                remoteOnly: true
            ))
        }

        let missingWithNoHostData = normalizedDeclared.subtracting(localNormalized).subtracting(remoteOnlyNormalized)
        for normalizedURL in missingWithNoHostData.sorted() {
            let name = URLHelpers.pathAfterHost(from: normalizedURL)
            let owner = URLHelpers.owner(from: normalizedURL)
            let host = URLHelpers.host(from: normalizedURL)
            repos.append(RepoInfo(
                relativePath: name,
                fullPath: "",
                remoteURL: normalizedURL,
                owner: owner.isEmpty ? host : owner,
                branch: "",
                localStatus: "not cloned",
                localStatusColor: .cyan,
                visibility: "\u{2014}",
                role: "\u{2014}",
                isArchived: false,
                language: "",
                description: "",
                stargazers: 0,
                lastPushTime: "",
                ahead: 0,
                behind: 0,
                saddled: true,
                hasHook: false,
                isStarred: hostResult.starredURLs.contains(normalizedURL),
                remoteOnly: true
            ))
        }

        return (repos, [], hostResult)
    }

    // MARK: - Display

    private func printReposSection(_ repos: [RepoInfo], host: HostResult, mountDir: String) {
        let termWidth = terminalWidth()
        let mountLabel = FS.shortenPath(mountDir)

        let table = TrafficLightTable(segments: [
            .indicators([
                Indicator("equipped (in manifest)", color: .custom(RGB(hex: "4A9EC2").fg)),
                Indicator("stray (not in manifest)", color: .custom(RGB(hex: "C85A6A").fg)),
                Indicator("hooked", color: .custom(RGB(hex: "7B2FBE").fg)),
            ]),
            .column(TextColumn("Local Repository (\(mountLabel))", sizing: .auto())),
            .indicators([
                Indicator("private", color: .custom(RGB(hex: "1EA00C").fg)),
                Indicator("public", color: .custom(RGB(hex: "F97316").fg)),
                Indicator("starred", color: .custom(RGB(hex: "FFE500").fg)),
            ]),
            .column(TextColumn("Origin", sizing: .auto())),
            .indicators([
                Indicator("dirty", color: .custom(RGB(hex: "EF4444").fg)),
                Indicator("ahead", color: .custom(RGB(hex: "22D3EE").fg)),
                Indicator("behind", color: .custom(RGB(hex: "A855F7").fg)),
            ]),
            .column(TextColumn("Last Commit", sizing: .fixed(14))),
            .column(TextColumn("Description", sizing: .flexible(minWidth: 10))),
        ])

        let sorted = repos.sorted { a, b in
            if (a.remoteURL == nil) != (b.remoteURL == nil) { return b.remoteURL == nil }
            let aOrigin = (a.remoteURL ?? a.relativePath).lowercased()
            let bOrigin = (b.remoteURL ?? b.relativePath).lowercased()
            return aOrigin < bOrigin
        }

        let rows = sorted.map { buildRow(repo: $0) }
        let counts: [[Int]]? = legendCounts(repos: repos)

        print(table.render(rows: rows, counts: counts, terminalWidth: termWidth), terminator: "")
    }

    private func buildRow(repo: RepoInfo) -> TrafficLightRow {
        let originStates: [IndicatorState] = [
            repo.visibility == "private" ? .on : .off,
            repo.visibility == "public" ? .on : .off,
            repo.isStarred ? .on : .off,
        ]

        let isStray = !repo.remoteOnly && !repo.saddled

        let localStates: [IndicatorState] = [
            repo.saddled ? .on : .off,
            isStray ? .on : .off,
            repo.hasHook ? .on : .off,
        ]

        let statusStates: [IndicatorState] = [
            repo.localStatus == "dirty" ? .on : .off,
            repo.ahead > 0 ? .on : .off,
            repo.behind > 0 ? .on : .off,
        ]

        let missing = repo.saddled && repo.remoteOnly
        let dim = repo.remoteOnly || !repo.saddled

        let originCol = styleOrigin(repo)
        let pathCol = stylePath(repo)

        let timeStr = repo.lastPushTime
        let timeColor = timeStr.isEmpty ? Color.dim : pushTimeColor(timeStr)
        let timeRaw = timeStr.isEmpty ? "\u{2014}" : timeStr
        let timeCol = missing ? styled(timeRaw, .dim, .red) : (dim ? styled(timeRaw, .dim, timeColor) : styled(timeRaw, timeColor))

        let descCol = repo.description.isEmpty ? "" : (missing ? styled(repo.description, .dim, .red) : styled(repo.description, .dim, .green))

        return TrafficLightRow(
            indicators: [localStates, originStates, statusStates],
            values: [pathCol, originCol, timeCol, descCol]
        )
    }

    private func originIndicatorColors(repo: RepoInfo) -> [(r: Int, g: Int, b: Int)] {
        var colors: [(r: Int, g: Int, b: Int)] = []
        if repo.visibility == "private" { colors.append((30, 160, 12)) }
        if repo.visibility == "public"  { colors.append((249, 115, 22)) }
        if repo.isStarred               { colors.append((255, 229, 0)) }
        return colors
    }

    private func styleOrigin(_ repo: RepoInfo) -> String {
        let headRaw = repo.remoteURL ?? "no origin"
        if repo.remoteURL == nil {
            return styled(headRaw, .dim, .red)
        }

        let missing = repo.saddled && repo.remoteOnly

        let name = URLHelpers.repoName(from: headRaw)
        guard let range = headRaw.range(of: name, options: .backwards) else {
            if missing { return styled(headRaw, .dim, .red) }
            return styled(headRaw, .darkGray)
        }

        let before = String(headRaw[headRaw.startIndex..<range.lowerBound])
        let mid = String(headRaw[range])
        let after = String(headRaw[range.upperBound...])

        if missing {
            return styled(before, .dim, .red) + styled(mid, .dim, .red) + styled(after, .dim, .red)
        }

        let colors = originIndicatorColors(repo: repo)
        let styledMid = colors.isEmpty
            ? styled(mid, .darkGray)
            : blendedString(mid, colors: colors)
        return styled(before, .darkGray) + styledMid + styled(after, .darkGray)
    }

    private func stylePath(_ repo: RepoInfo) -> String {
        if repo.remoteOnly {
            let missing = repo.saddled
            return missing ? styled("\u{2014}", .dim, .red) : styled("\u{2014}", .dim)
        }
        return styledRepoPath(repo.relativePath)
    }

    private func blendedString(_ text: String, colors: [(r: Int, g: Int, b: Int)]) -> String {
        guard !colors.isEmpty else { return text }
        let r = colors.map(\.r).reduce(0, +) / colors.count
        let g = colors.map(\.g).reduce(0, +) / colors.count
        let b = colors.map(\.b).reduce(0, +) / colors.count
        return "\u{1B}[38;2;\(r);\(g);\(b)m\(text)\(Color.reset.rawValue)"
    }

    private func legendCounts(repos: [RepoInfo]) -> [[Int]] {
        [
            [
                repos.filter(\.saddled).count,
                repos.filter { !$0.remoteOnly && !$0.saddled }.count,
                repos.filter(\.hasHook).count,
            ],
            [
                repos.filter { $0.visibility == "private" }.count,
                repos.filter { $0.visibility == "public" }.count,
                repos.filter(\.isStarred).count,
            ],
            [
                repos.filter { $0.localStatus == "dirty" }.count,
                repos.filter { $0.ahead > 0 }.count,
                repos.filter { $0.behind > 0 }.count,
            ],
        ]
    }

    static func relativeTime(from iso8601: String) -> String {
        guard !iso8601.isEmpty else { return "" }
        let date = DateFormatting.iso8601WithFractionalSeconds.date(from: iso8601)
            ?? DateFormatting.iso8601.date(from: iso8601)
        guard let d = date else { return "" }
        let seconds = Int(-d.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds) seconds ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        let days = hours / 24
        if days < 7 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        let weeks = days / 7
        if days < 30 { return "\(weeks) week\(weeks == 1 ? "" : "s") ago" }
        let months = days / 30
        if months < 12 { return "\(months) month\(months == 1 ? "" : "s") ago" }
        let years = months / 12
        return "\(years) year\(years == 1 ? "" : "s") ago"
    }

    private func pushTimeColor(_ time: String) -> Color {
        if time.contains("hour") || time.contains("minute") || time.contains("second") { return .green }
        if time.contains("day"), let n = Int(time.split(separator: " ").first ?? ""), n <= 7 { return .cyan }
        if time.contains("week") { return .yellow }
        if time.contains("month") { return .orange }
        return .dim
    }

}
