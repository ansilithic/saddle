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

    @Flag(name: .long, help: "Show the status legend.")
    var showLegend = false

    @Option(help: "Show only repos owned by <owner>.")
    var owner: String?

    private struct PartialInfo {
        let relativePath: String
        let fullPath: String
        let git: GitHelpers.GitInfo
        let saddled: Bool
        let hookHealth: HookHealth
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

        if !repos.isEmpty {
            printReposSection(repos, forge: forgeResult, mountDir: devDir, showLegend: showLegend)
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

    private func printLegend(repos: [RepoInfo], colHead: Int, colPath: Int) {
        print()
        let publicCount = repos.filter { $0.visibility == "public" }.count
        let archivedCount = repos.filter(\.isArchived).count
        let starredCount = repos.filter(\.isStarred).count
        let dirtyCount = repos.filter { $0.localStatus == "dirty" }.count
        let aheadCount = repos.filter { $0.ahead > 0 }.count
        let behindCount = repos.filter { $0.behind > 0 }.count
        let saddledCount = repos.filter { $0.saddled || !$0.remoteOnly }.count
        let hookedCount = repos.filter(\.hasHook).count
        let unhealthyCount = repos.filter { $0.hookHealth == .unhealthy }.count

        struct LegendEntry {
            let slot: Int
            let color: Color
            let count: Int
            let label: String
            let isStar: Bool
        }

        let originEntries: [LegendEntry] = [
            LegendEntry(slot: 0, color: .red, count: publicCount, label: "public", isStar: false),
            LegendEntry(slot: 1, color: .gray, count: archivedCount, label: "archived", isStar: false),
            LegendEntry(slot: 2, color: .yellow, count: starredCount, label: "starred", isStar: true),
        ]

        let localEntries: [LegendEntry] = [
            LegendEntry(slot: 0, color: .cyan, count: saddledCount, label: "equipped", isStar: false),
            LegendEntry(slot: 1, color: .magenta, count: hookedCount, label: "hooked", isStar: false),
            LegendEntry(slot: 2, color: .red, count: unhealthyCount, label: "unhealthy", isStar: false),
        ]

        let statusEntries: [LegendEntry] = [
            LegendEntry(slot: 0, color: .red, count: dirtyCount, label: "dirty", isStar: false),
            LegendEntry(slot: 1, color: .cyan, count: aheadCount, label: "ahead", isStar: false),
            LegendEntry(slot: 2, color: .orange, count: behindCount, label: "behind", isStar: false),
        ]

        let originSlots = 3
        let localSlots = 3
        let statusSlots = 3
        let localOffset = Self.originDotWidth + colHead
        let statusOffset = localOffset + Self.localDotWidth + colPath

        func entryText(_ entry: LegendEntry, slots: Int) -> (styled: String, width: Int) {
            var wiring = ""
            for c in 0..<slots {
                if c == entry.slot {
                    wiring += "\u{250C}"
                } else if c < entry.slot {
                    wiring += "\u{2502}"
                } else {
                    wiring += "\u{2500}"
                }
            }
            wiring += "\u{2500}"
            let symbol = entry.isStar ? "\u{2605}" : "\u{25CF}"
            let countStr = "(\(entry.count))"
            let text = styled(wiring, .dim) + " " + styled(symbol, entry.color) + " " + styled(entry.label, entry.color) + " " + styled(countStr, .dim)
            let width = slots + 1 + 1 + 1 + 1 + entry.label.count + 1 + countStr.count
            return (text, width)
        }

        let originPipes = styled(String(repeating: "\u{2502}", count: originSlots), .dim)
        let localPipes = styled(String(repeating: "\u{2502}", count: localSlots), .dim)
        let statusPipes = styled(String(repeating: "\u{2502}", count: statusSlots), .dim)

        // Entry lines — the longest group determines row count
        let entryCount = max(originEntries.count, max(localEntries.count, statusEntries.count))
        for i in 0..<entryCount {
            let left: String
            let leftWidth: Int
            if i < originEntries.count {
                let entry = entryText(originEntries[i], slots: originSlots)
                left = entry.styled
                leftWidth = entry.width
            } else {
                left = originPipes
                leftWidth = originSlots
            }

            let gap1 = String(repeating: " ", count: max(1, localOffset - leftWidth))

            let middle: String
            let middleWidth: Int
            if i < localEntries.count {
                let entry = entryText(localEntries[i], slots: localSlots)
                middle = entry.styled
                middleWidth = entry.width
            } else {
                middle = localPipes
                middleWidth = localSlots
            }

            let gap2 = String(repeating: " ", count: max(1, statusOffset - localOffset - middleWidth))

            let right: String
            if i < statusEntries.count {
                right = entryText(statusEntries[i], slots: statusSlots).styled
            } else {
                right = statusPipes
            }

            print(left + gap1 + middle + gap2 + right)
        }

        // Footer line — pipes flowing into header dots
        let footerGap1 = String(repeating: " ", count: max(1, localOffset - originSlots))
        let footerGap2 = String(repeating: " ", count: max(1, statusOffset - localOffset - localSlots))
        print(originPipes + footerGap1 + localPipes + footerGap2 + statusPipes)
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

    private func gatherRepos(manifest: Manifest?, devDir: String, declaredURLs: [String]) -> (repos: [RepoInfo], missingURLs: [String], forge: ForgeResult) {
        let normalizedDeclared = Set(declaredURLs.map { URLHelpers.normalize($0) })

        nonisolated(unsafe) var forgeResult = ForgeResult()
        let visGroup = DispatchGroup()
        visGroup.enter()
        DispatchQueue.global().async {
            forgeResult = Forge.fetchAllRepos()
            visGroup.leave()
        }

        let discoveredPaths = FS.findRepos(in: devDir)
        let repoCount = discoveredPaths.count

        let emptyGit = GitHelpers.GitInfo(remoteURL: nil, branch: "", status: "", ahead: 0, behind: 0, lastCommitTime: "")
        var partials = Array(repeating: PartialInfo(relativePath: "", fullPath: "", git: emptyGit, saddled: false, hookHealth: .noHook), count: repoCount)

        partials.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            DispatchQueue.concurrentPerform(iterations: repoCount) { i in
                let repoPath = discoveredPaths[i]
                let relativePath = String(repoPath.dropFirst(devDir.count + 1))
                let git = GitHelpers.info(at: repoPath)
                let normalized = git.remoteURL.map { URLHelpers.normalize($0) }
                let saddled = normalized.map { normalizedDeclared.contains($0) } ?? false

                let hookHealth: HookHealth
                if let url = git.remoteURL, HookResolver.hasHook(for: url) {
                    if let checkResolution = HookResolver.resolve(for: url, lifecycle: .check) {
                        let (_, exitCode) = Exec.run(checkResolution.scriptPath, args: [], cwd: repoPath)
                        hookHealth = exitCode == 0 ? .healthy : .unhealthy
                    } else {
                        hookHealth = .healthy
                    }
                } else {
                    hookHealth = .noHook
                }

                buffer[i] = PartialInfo(relativePath: relativePath, fullPath: repoPath, git: git, saddled: saddled, hookHealth: hookHealth)
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
                (localStatus, localStatusColor) = ("dirty", .red)
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
                ahead: p.git.ahead,
                behind: p.git.behind,
                saddled: p.saddled,
                hookHealth: p.hookHealth,
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
                ahead: 0,
                behind: 0,
                saddled: normalizedDeclared.contains(normalizedURL),
                hookHealth: .noHook,
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
                ahead: 0,
                behind: 0,
                saddled: true,
                hookHealth: .noHook,
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

    private static let originDotWidth = 5  // 3 dots + 2 space separator
    private static let localDotWidth = 4   // 3 dots + 1 space separator
    private static let statusDotWidth = 4  // 3 dots + 1 space separator

    private func printReposSection(_ repos: [RepoInfo], forge: ForgeResult, mountDir: String, showLegend: Bool) {
        let p = Self.colPadding
        let termWidth = Self.terminalWidth
        let fixedDots = Self.originDotWidth + Self.localDotWidth + Self.statusDotWidth

        let mountLabel = FS.shortenPath(mountDir)
        let localPathHeaderWidth = "Local Path (\(mountLabel))".count
        let headValues = repos.map { $0.remoteURL ?? "no origin" }
        let pathValues = repos.map { $0.remoteOnly ? "" : $0.relativePath }
        let idealHead = max("Origin".count, headValues.map { $0.count }.max() ?? 0) + p
        let idealPath = max(localPathHeaderWidth, pathValues.map { $0.count }.max() ?? 0) + p
        let colUpdated = max("Last Commit".count, 14) + p

        let budget = termWidth - fixedDots - colUpdated - Self.minDescLen
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

        let fixedWidth = fixedDots + colHead + colPath + colUpdated
        let descWidth = max(Self.minDescLen, termWidth - fixedWidth)

        let sorted = repos.sorted { a, b in
            if (a.remoteURL == nil) != (b.remoteURL == nil) { return b.remoteURL == nil }
            let aOrigin = (a.remoteURL ?? a.relativePath).lowercased()
            let bOrigin = (b.remoteURL ?? b.relativePath).lowercased()
            return aOrigin < bOrigin
        }

        if showLegend {
            printLegend(repos: repos, colHead: colHead, colPath: colPath)
        } else {
            print()
        }

        // Origin dots: public, archived, starred
        let originDots = styled("\u{25CF}", .red) + styled("\u{25CF}", .gray) + styled("\u{2605}", .yellow)
        // Local dots: equipped, hooked, health
        let localDots = styled("\u{25CF}", .cyan) + styled("\u{25CF}", .magenta) + styled("\u{25CF}", .red)
        // Status dots: dirty, ahead, behind
        let statusDots = styled("\u{25CF}", .red) + styled("\u{25CF}", .cyan) + styled("\u{25CF}", .orange)

        let localPathCol = localDots + " " + styled("Local Path", .dim) + " " + styled("(\(mountLabel))", .darkGray)
            + String(repeating: " ", count: max(0, colPath - localPathHeaderWidth))
        let header = originDots + styled("  ", .dim)
            + styled("Origin".padding(toLength: colHead, withPad: " ", startingAt: 0), .dim)
            + localPathCol
            + statusDots + " " + styled("Last Commit".padding(toLength: colUpdated, withPad: " ", startingAt: 0), .dim)
            + styled("Description", .dim)
        print(header)
        print(styled("\u{2500}".repeating(termWidth), .dim))

        for repo in sorted {
            printRepoRow(repo, colHead: colHead, colPath: colPath, colUpdated: colUpdated, colDesc: descWidth)
        }
    }

    private func printRepoRow(_ repo: RepoInfo, colHead: Int, colPath: Int, colUpdated: Int, colDesc: Int) {
        let p = Self.colPadding

        // Origin dots: public, archived, starred
        let o1 = repo.visibility == "public" ? styled("\u{25CF}", .red) : " "
        let o2 = repo.isArchived ? styled("\u{25CF}", .gray) : " "
        let o3 = repo.isStarred ? styled("\u{2605}", .yellow) : " "
        let originPrefix = o1 + o2 + o3 + "  "

        // Local dots: equipped, hooked, health
        let l1 = repo.saddled ? styled("\u{25CF}", .cyan) : " "
        let l2 = repo.hasHook ? styled("\u{25CF}", .magenta) : " "
        let l3: String
        switch repo.hookHealth {
        case .unhealthy: l3 = styled("\u{25CF}", .red)
        default:         l3 = " "
        }
        let localPrefix = l1 + l2 + l3 + " "

        // Status dots: dirty, ahead, behind
        let s1 = repo.localStatus == "dirty" ? styled("\u{25CF}", .red) : " "
        let s2 = repo.ahead > 0 ? styled("\u{25CF}", .cyan) : " "
        let s3 = repo.behind > 0 ? styled("\u{25CF}", .orange) : " "
        let statusPrefix = s1 + s2 + s3 + " "

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

        let pathCol = stray ? styled(pathText, .dim, .yellow) : (dim ? styled(pathText, .dim) : styled(pathText, .darkGray))
        let timeCol = dim ? styled(updatedText, .dim, timeColor) : styled(updatedText, timeColor)
        print("\(originPrefix)\(headCol)\(localPrefix)\(pathCol)\(statusPrefix)\(timeCol)\(descCol)")
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
