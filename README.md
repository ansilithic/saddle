# saddle

A personal package manager for your repos.

You build CLI tools, dotfiles, scripts, configs. They live in git repos scattered across GitHub. Saddle tracks them all in one manifest, clones what's missing, pulls what's behind, and runs install hooks — so any machine is one command away from your full environment.

```sh
saddle up
```

## Install

```sh
git clone https://github.com/ansilithic/saddle.git
cd saddle
make build && make install
```

Requires macOS 14+ and Swift 6.0.

## Quick start

Add repos to your manifest:

```sh
saddle equip https://github.com/you/dotfiles.git
saddle equip https://github.com/you/scripts.git
saddle equip https://github.com/you/cool-cli.git
```

Or create the manifest directly:

```toml
# ~/.config/saddle/manifest.toml
mount = "~/Developer"

[repos]
"github.com/you/dotfiles"
"github.com/you/scripts"
"github.com/you/cool-cli"
```

Sync everything:

```sh
saddle up
```

## Commands

| Command | Description |
|---------|-------------|
| `saddle` | Show status of all repos (default) |
| `saddle up` | Clone missing repos, pull updates, run hooks |
| `saddle up --dry-run` | Preview what would happen |
| `saddle equip [repo]` | Add a repo to the manifest |
| `saddle unequip [repo]` | Remove a repo from the manifest |
| `saddle adopt` | Add all untracked local repos to the manifest |

Both `equip` and `unequip` accept a repo URL or detect the repo from the current directory.

### `saddle` (status)

Scans your developer directory and every repo you own on GitHub. Shows branch, visibility, local changes, last commit, starred repos, and whether each repo is tracked in your manifest — all at a glance.

Filter flags: `--public`, `--private`, `--clean`, `--dirty`, `--equipped`, `--unequipped`, `--hooked`, `--unhooked`, `--starred`, `--archived`, `--active`, `--all`, `--owner <name>`.

### `saddle up`

Reads your manifest and syncs:

- **Clones** repos that aren't on disk yet
- **Pulls** latest changes for clean repos (skips dirty ones)
- **Runs hooks** after each sync

## Configuration

Config lives at `~/.config/saddle/`.

### Manifest

`manifest.toml` — lists your repos and where to clone them.

```toml
mount = "~/Developer"

[repos]
"github.com/you/dotfiles"
"github.com/you/scripts"
"github.com/you/cool-cli"
```

The `mount` field sets the root directory (defaults to `~/Developer`). Repos are cloned into subdirectories matching their remote path.

### Hooks

`hooks/` — executable scripts named `owner-repo.sh` that run after each sync. The script's working directory is the repo itself.

```sh
# ~/.config/saddle/hooks/you-dotfiles.sh
#!/bin/sh
make install
```

```sh
chmod +x ~/.config/saddle/hooks/you-dotfiles.sh
```

Hooks are how repos install themselves — symlink configs, compile binaries, run setup scripts.

### State

State lives at `~/.local/state/saddle/`.

| File | Purpose |
|------|---------|
| `state.json` | Last run timestamp |
| `saddle.log` | Error log |
| `hooks/` | Per-hook output logs |

## GitHub integration

With a GitHub token, saddle shows repo visibility, discovers remote repos not cloned locally, and displays your starred repos. Token is resolved from:

1. `gh auth token` (if `gh` CLI is installed)
2. `GITHUB_TOKEN` environment variable
3. `~/.config/saddle/github-token` file

Without a token, everything still works — visibility just shows `—`.

## Requirements

- macOS 14+ (Sonoma)
- Swift 6.0

## License

MIT
