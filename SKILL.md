# Saddle — Agent Skill

Instructions for AI coding agents using saddle to manage local git repositories.

## What saddle does

Saddle provides visibility into every git repo in a local development directory and syncs repos from a declared manifest. It complements `gh` — where `gh` handles remote operations (PRs, issues, API calls), saddle covers the local side.

## When to use saddle vs gh

| Task | Tool |
|------|------|
| See what repos are cloned locally | `saddle` |
| Check which repos have uncommitted changes | `saddle --dirty` |
| Find repos not yet cloned | `saddle --all` |
| Clone and set up a repo from the manifest | `saddle up` |
| Add a repo to the manifest | Edit `manifest.toml` or `saddle equip <url>` |
| Create a PR, view issues, call GitHub API | `gh` |

## Commands

### `saddle` (status)

Default command. Scans the development directory and shows every repo's state.

```sh
saddle                  # local repos (default)
saddle --all            # all repos including remote-only
saddle --dirty          # repos with uncommitted changes
saddle --equipped       # repos tracked in the manifest
saddle --stray          # cloned but not in manifest
saddle --owner <name>   # filter by org/owner
```

Output columns: manifest status, local path, visibility, origin URL, sync state (dirty/ahead/behind), last commit time, description.

### `saddle up`

Sync all manifest repos. Clones missing repos, pulls clean repos, runs install hooks.

```sh
saddle up               # sync everything
saddle up --no-hooks    # sync without running hooks
```

### `saddle equip <repo>`

Add a repo to the manifest. If a URL is provided, clones it. If run inside a repo directory, adds the current repo.

```sh
saddle equip https://github.com/org/repo
saddle equip            # adds current directory's repo
```

### `saddle unequip <repo>`

Remove a repo from the manifest and run its uninstall hook if one exists.

### `saddle info`

Show saddle configuration: manifest path, mount directory, hook directory, authenticated forges.

## Configuration paths

| Path | Purpose |
|------|---------|
| `~/.config/saddle/manifest.toml` | Repo manifest |
| `~/.config/saddle/hooks/` | Per-repo hook scripts (`hook.sh` with functions) |
| `~/.local/state/saddle/` | Logs and state |

## Tips for agents

- Run `saddle` at the start of a session to understand what's on the machine.
- Use `saddle --dirty` to find repos with uncommitted work before making changes.
- Use `saddle --stray` to find repos that exist locally but aren't tracked.
- Saddle reads auth from `gh auth token` — if `gh` is authenticated, saddle gets GitHub data automatically.
- Editing `manifest.toml` directly is fine. `saddle equip` and `saddle unequip` are conveniences for interactive use.
- Hook scripts are optional. Most repos don't need them.
