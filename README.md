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

`manifest.toml` — lists your repos and where to clone them. The format is a minimal TOML subset: key-value pairs and a `[repos]` section of quoted strings. Comments (`#`) and blank lines are supported.

```toml
mount = "~/Developer"

[repos]
"github.com/you/dotfiles"
"github.com/you/scripts"
"github.com/you/cool-cli"
```

The `mount` field sets the root directory (defaults to `~/Developer`). Repos are cloned into `owner/repo` subdirectories matching their remote path.

Set `protocol` to control how repos are cloned (defaults to `ssh`):

```toml
protocol = "https"
```

SSH requires keys configured with your git host. HTTPS works with credential helpers or token-based auth.

### Hooks

`hooks/` — executable scripts that run during sync and lifecycle events. The script's working directory is the repo itself.

Two formats are supported:

**Directory format** (recommended) — separate scripts per lifecycle phase:

```
~/.config/saddle/hooks/you-dotfiles/
  install.sh     # runs on first clone
  update.sh      # runs on subsequent syncs (falls back to install.sh if missing)
  uninstall.sh   # runs during saddle unequip
  check.sh       # runs during saddle status (exit 0 = healthy)
```

**Legacy format** — a single script for install and update:

```
~/.config/saddle/hooks/you-dotfiles.sh
```

All hook scripts must be executable (`chmod +x`). Hook names are derived from the repo URL: `github.com/you/dotfiles` becomes `you-dotfiles`.

Hooks are how repos install themselves — symlink configs, compile binaries, run setup scripts. Output is logged to `~/.local/state/saddle/hooks/`.

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

GitLab is also supported. Token is resolved from:

1. `glab auth token` (if `glab` CLI is installed)
2. `GITLAB_TOKEN` environment variable
3. `~/.config/saddle/gitlab-token` file

Token files should be readable only by you (`chmod 600`). The CLI-based methods (`gh auth token`, `glab auth token`) are preferred as they use the system keychain.

Without a token, everything still works — visibility just shows `—`.

## Shell completions

Zsh completions are installed automatically with `make install`. For bash or fish:

```sh
# Bash
saddle --generate-completion-script bash > ~/.local/share/bash-completion/completions/saddle

# Fish
saddle --generate-completion-script fish > ~/.config/fish/completions/saddle.fish
```

## Requirements

- macOS 14+ (Sonoma)
- Swift 6.0

## License

MIT
