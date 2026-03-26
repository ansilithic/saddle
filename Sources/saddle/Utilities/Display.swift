import CLICore

/// Style a repo path: dim the prefix (owner/), bold the repo name.
func styledRepoPath(_ path: String) -> String {
    guard let lastSlash = path.lastIndex(of: "/") else {
        return styled(path, .bold)
    }
    let before = String(path[path.startIndex...lastSlash])
    let name = String(path[path.index(after: lastSlash)...])
    return styled(before, .darkGray) + styled(name, .bold)
}
