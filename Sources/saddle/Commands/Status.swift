import ArgumentParser
import CLICore
import Foundation

struct Status: ParsableCommand {
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

    @Flag(name: .long, help: "Show the status legend.")
    var showLegend = false

    @Option(help: "Show only repos owned by <owner>.")
    var owner: String?

    private struct PartialInfo {
        let relativePath: String
        let fullPath: String
        let git: GitHelpers.GitInfo
        let saddled: Bool
        let hasHook: Bool
    }

    func run() {
        let spinner = BrailleSpinner(label: "Scanning repos\u{2026}")
        spinner.start()

        let manifest: Manifest?
        let path = Config.manifestPath
        if FS.exists(path) {
            manifest = Parser.parseOrNil(at: path)
        } else {
            manifest = nil
        }

        let devDir = manifest?.mount ?? FS.expandPath(Parser.defaultMount)
        let declaredURLs = manifest?.repos ?? []

        let (allRepos, _, forgeResult) = gatherRepos(manifest: manifest, devDir: devDir, declaredURLs: declaredURLs)

        spinner.stop()

        let repos = applyFilters(allRepos)

        if showLegend {
            printLegend(repos: repos)
        } else {
            print()
        }

        if !repos.isEmpty {
            printReposSection(repos, forge: forgeResult, mountDir: devDir)
        } else {
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
        if archived { filters.append("archived") }
        if active { filters.append("active") }
        if all { filters.append("all") }
        else if !hasAnyFilter && owner == nil { filters.append("equipped (default)") }
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

    private func printLegend(repos: [RepoInfo]) {
        print()
        let publicCount = repos.filter { $0.visibility == "public" }.count
        let dirtyCount = repos.filter { $0.localStatus == "dirty" }.count
        let saddledCount = repos.filter(\.saddled).count
        let hookedCount = repos.filter(\.hasHook).count
        let archivedCount = repos.filter(\.isArchived).count
        let starredCount = repos.filter(\.isStarred).count

        let indicators: [(color: Color, count: Int, label: String)] = [
            (.red, publicCount, "public"),
            (.yellow, dirtyCount, "dirty"),
            (.cyan, saddledCount, "equipped"),
            (.magenta, hookedCount, "hooked"),
            (.gray, archivedCount, "archived"),
            (.yellow, starredCount, "starred"),
        ]

        for (i, ind) in indicators.enumerated() {
            var prefix = ""
            for c in 0..<6 {
                if c == i {
                    prefix += "\u{250C}"
                } else if c < i {
                    prefix += "\u{2502}"
                } else {
                    prefix += "\u{2500}"
                }
            }
            prefix += "\u{2500}"
            let symbol = ind.label == "starred" ? "\u{2605}" : "\u{25CF}"
            print(styled(prefix, .dim) + " " + styled(symbol, ind.color) + " " + styled("\(ind.label)", ind.color) + " " + styled("(\(ind.count))", .dim))
        }

        print(styled("\u{2502}\u{2502}\u{2502}\u{2502}\u{2502}\u{2502}", .dim))
    }

    private var hasAnyFilter: Bool {
        `public` || `private` || clean || dirty || equipped || unequipped
            || hooked || unhooked || starred || unstarred || archived || active || owner != nil
    }

    private func applyFilters(_ repos: [RepoInfo]) -> [RepoInfo] {
        let defaultEquipped = !all && !hasAnyFilter

        return repos.filter { repo in
            if defaultEquipped && !repo.saddled { return false }
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

    private func gatherRepos(manifest: Manifest?, devDir: String, declaredURLs: [String]) -> (repos: [RepoInfo], missingURLs: [String], forge: ForgeResult) {
        let normalizedDeclared = Set(declaredURLs.map { URLHelpers.normalize($0) })

        var forgeResult = ForgeResult()
        let visGroup = DispatchGroup()
        visGroup.enter()
        DispatchQueue.global().async {
            forgeResult = Forge.fetchAllRepos()
            visGroup.leave()
        }

        let discoveredPaths = FS.findRepos(in: devDir)
        let repoCount = discoveredPaths.count

        let emptyGit = GitHelpers.GitInfo(remoteURL: nil, branch: "", status: "", lastCommitTime: "")
        var partials = Array(repeating: PartialInfo(relativePath: "", fullPath: "", git: emptyGit, saddled: false, hasHook: false), count: repoCount)

        partials.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: repoCount) { i in
                let repoPath = discoveredPaths[i]
                let relativePath = String(repoPath.dropFirst(devDir.count + 1))
                let git = GitHelpers.info(at: repoPath)
                let normalized = git.remoteURL.map { URLHelpers.normalize($0) }
                let saddled = normalized.map { normalizedDeclared.contains($0) } ?? false
                let hasHook = git.remoteURL.map { Sync.findHook(for: $0) != nil } ?? false
                buffer[i] = PartialInfo(relativePath: relativePath, fullPath: repoPath, git: git, saddled: saddled, hasHook: hasHook)
            }
        }

        visGroup.wait()

        var repos: [RepoInfo] = []
        var localNormalized = Set<String>()
        var matchedNormalized = Set<String>()
        for p in partials {
            let normalized = p.git.remoteURL.map { URLHelpers.normalize($0) }
            let ghInfo = normalized.flatMap { forgeResult.repos[$0] }

            let visibility = ghInfo?.visibility ?? "\u{2014}"
            let role = ghInfo?.role ?? (p.git.remoteURL != nil ? "\u{2014}" : "local")
            let language = ghInfo?.language ?? ""
            let description = ghInfo?.description ?? ""
            let stargazers = ghInfo?.stargazers ?? 0
            let isArchived = ghInfo?.isArchived ?? false

            let localStatus: String
            let localStatusColor: Color
            if p.git.status == "uncommitted changes" {
                (localStatus, localStatusColor) = ("dirty", .yellow)
            } else {
                (localStatus, localStatusColor) = ("clean", .green)
            }

            let owner = p.git.remoteURL.map { URLHelpers.owner(from: $0) } ?? "local"
            let isStarred = normalized.map { forgeResult.starredURLs.contains($0) } ?? false
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

        let remoteOnly = forgeResult.repos
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
                saddled: normalizedDeclared.contains(normalizedURL),
                hasHook: false,
                isStarred: forgeResult.starredURLs.contains(normalizedURL),
                remoteOnly: true
            ))
        }

        let missingWithNoForgeData = normalizedDeclared.subtracting(localNormalized).subtracting(remoteOnlyNormalized)
        for normalizedURL in missingWithNoForgeData.sorted() {
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
                saddled: true,
                hasHook: false,
                isStarred: forgeResult.starredURLs.contains(normalizedURL),
                remoteOnly: true
            ))
        }

        return (repos, [], forgeResult)
    }

    // MARK: - Display

    private static let colPadding = 2
    private static let minDescLen = 10

    private static var terminalWidth: Int {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0, w.ws_col > 0 {
            return Int(w.ws_col)
        }
        return 120
    }

    private func printReposSection(_ repos: [RepoInfo], forge: ForgeResult, mountDir: String) {
        let p = Self.colPadding
        let termWidth = Self.terminalWidth
        let rowIndent = 8

        let mountLabel = FS.shortenPath(mountDir)
        let localPathHeaderWidth = "Local Path (\(mountLabel))".count
        let headValues = repos.map { $0.remoteURL ?? "no origin" }
        let pathValues = repos.map { $0.remoteOnly ? "" : $0.relativePath }
        let idealHead = max("Origin".count, headValues.map { $0.count }.max() ?? 0) + p
        let idealPath = max(localPathHeaderWidth, pathValues.map { $0.count }.max() ?? 0) + p
        let colUpdated = max("Last Commit".count, 14) + p

        let budget = termWidth - rowIndent - colUpdated - Self.minDescLen
        let colHead: Int
        let colPath: Int
        if idealHead + idealPath <= budget {
            colHead = idealHead
            colPath = idealPath
        } else {
            let total = idealHead + idealPath
            colHead = max("Origin".count + p, idealHead * budget / total)
            colPath = max(localPathHeaderWidth + p, budget - colHead)
        }

        let fixedWidth = rowIndent + colHead + colPath + colUpdated
        let descWidth = max(Self.minDescLen, termWidth - fixedWidth)

        let sorted = repos.sorted { a, b in
            if (a.remoteURL == nil) != (b.remoteURL == nil) { return b.remoteURL == nil }
            let aOrigin = (a.remoteURL ?? a.relativePath).lowercased()
            let bOrigin = (b.remoteURL ?? b.relativePath).lowercased()
            return aOrigin < bOrigin
        }

        let dotColors: [Color] = [.red, .yellow, .cyan, .magenta, .gray, .yellow]
        let dots = dotColors.enumerated().map { i, c in
            styled(i == dotColors.count - 1 ? "\u{2605}" : "\u{25CF}", c)
        }.joined()
        let localPathCol = styled("Local Path", .dim) + " " + styled("(\(mountLabel))", .darkGray)
            + String(repeating: " ", count: max(0, colPath - localPathHeaderWidth))
        let header = dots + styled("  ", .dim)
            + styled("Origin".padding(toLength: colHead, withPad: " ", startingAt: 0), .dim)
            + localPathCol
            + styled("Last Commit".padding(toLength: colUpdated, withPad: " ", startingAt: 0), .dim)
            + styled("Description", .dim)
        print(header)
        print(styled("\u{2500}".repeating(termWidth), .dim))

        for repo in sorted {
            printRepoRow(repo, colHead: colHead, colPath: colPath, colUpdated: colUpdated, colDesc: descWidth)
        }
    }

    private func printRepoRow(_ repo: RepoInfo, colHead: Int, colPath: Int, colUpdated: Int, colDesc: Int) {
        let p = Self.colPadding
        let s1 = repo.visibility == "public" ? styled("\u{25CF}", .red) : " "
        let s2 = repo.localStatus == "dirty" ? styled("\u{25CF}", .yellow) : " "
        let s3 = repo.saddled ? styled("\u{25CF}", .cyan) : " "
        let s4 = repo.hasHook ? styled("\u{25CF}", .magenta) : " "
        let s5 = repo.isArchived ? styled("\u{25CF}", .gray) : " "
        let s6 = repo.isStarred ? styled("\u{2605}", .yellow) : " "
        let prefix = s1 + s2 + s3 + s4 + s5 + s6 + "  "
        let missing = repo.saddled && repo.remoteOnly
        let stray = !repo.remoteOnly && !repo.saddled
        let dim = repo.remoteOnly || !repo.saddled

        let headRaw = repo.remoteURL ?? "no origin"
        let headTrunc = truncate(headRaw, to: colHead - p)
        let headPad = String(repeating: " ", count: max(0, colHead - headTrunc.count))
        let headCol: String
        if repo.remoteURL == nil {
            headCol = styled(headTrunc, .dim, .red) + headPad
        } else if missing {
            let name = URLHelpers.repoName(from: headRaw)
            if let range = headRaw.range(of: name, options: .backwards) {
                let nameStart = headRaw.distance(from: headRaw.startIndex, to: range.lowerBound)
                let nameEnd = headRaw.distance(from: headRaw.startIndex, to: range.upperBound)
                let len = headTrunc.count
                let before = String(headTrunc.prefix(min(nameStart, len)))
                let mid = nameStart < len ? String(headTrunc.dropFirst(nameStart).prefix(min(nameEnd, len) - nameStart)) : ""
                let after = nameEnd < len ? String(headTrunc.dropFirst(nameEnd)) : ""
                headCol = styled(before, .darkGray) + styled(mid, .orange) + styled(after, .darkGray) + headPad
            } else {
                headCol = styled(headTrunc, .orange) + headPad
            }
        } else {
            let name = URLHelpers.repoName(from: headRaw)
            if let range = headRaw.range(of: name, options: .backwards) {
                let nameStart = headRaw.distance(from: headRaw.startIndex, to: range.lowerBound)
                let nameEnd = headRaw.distance(from: headRaw.startIndex, to: range.upperBound)
                let len = headTrunc.count
                let before = String(headTrunc.prefix(min(nameStart, len)))
                let mid = nameStart < len ? String(headTrunc.dropFirst(nameStart).prefix(min(nameEnd, len) - nameStart)) : ""
                let after = nameEnd < len ? String(headTrunc.dropFirst(nameEnd)) : ""
                if dim {
                    headCol = styled(before, .dim) + styled(mid, .dim) + styled(after, .dim) + headPad
                } else {
                    headCol = styled(before, .darkGray) + mid + styled(after, .darkGray) + headPad
                }
            } else {
                headCol = (dim ? styled(headTrunc, .dim) : styled(headTrunc, .darkGray)) + headPad
            }
        }

        let pathRaw = repo.remoteOnly ? "\u{2014}" : repo.relativePath
        let pathText = truncate(pathRaw, to: colPath - p).padding(toLength: colPath, withPad: " ", startingAt: 0)

        let timeStr = repo.lastPushTime
        let timeColor = timeStr.isEmpty ? Color.dim : pushTimeColor(timeStr)
        let updatedText = truncate(timeStr.isEmpty ? "\u{2014}" : timeStr, to: colUpdated - p).padding(toLength: colUpdated, withPad: " ", startingAt: 0)

        let descCol: String
        if !repo.description.isEmpty {
            let desc = truncate(repo.description, to: colDesc)
            descCol = styled(desc, .dim, .green)
        } else {
            descCol = ""
        }

        let pathCol = stray ? styled(pathText, .blue) : (dim ? styled(pathText, .dim) : styled(pathText, .darkGray))
        let timeCol = dim ? styled(updatedText, .dim, timeColor) : styled(updatedText, timeColor)
        print("\(prefix)\(headCol)\(pathCol)\(timeCol)\(descCol)")
    }

    private func truncate(_ text: String, to maxLen: Int) -> String {
        guard maxLen > 0 else { return "" }
        if text.count <= maxLen { return text }
        return String(text.prefix(maxLen - 1)) + "\u{2026}"
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
        if days < 30 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        let months = days / 30
        if months < 12 { return "\(months) month\(months == 1 ? "" : "s") ago" }
        let years = months / 12
        return "\(years) year\(years == 1 ? "" : "s") ago"
    }

    private func pushTimeColor(_ time: String) -> Color {
        if time.contains("hour") || time.contains("minute") || time.contains("second") { return .green }
        if time.hasSuffix("days ago"), let n = Int(time.split(separator: " ").first ?? ""), n <= 7 { return .cyan }
        if time.contains("day") { return .yellow }
        if time.contains("week") { return .yellow }
        if time.contains("month") { return .orange }
        return .dim
    }

}
