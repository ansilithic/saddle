# saddle

Repository orchestrator for `~/Developer/`. Discovers all git repos, shows their status, syncs from a manifest, and runs post-sync hooks.

## Install

```sh
brew tap ansilithic/tap
brew install saddle
```

Or build from source:

```sh
make build && make install
```

## Usage

```
USAGE: saddle <subcommand>

SUBCOMMANDS:
  status (default)    Show git status of all repos in ~/Developer.
  up                  Clone missing repos and pull latest changes.
  remote              List GitHub repos not cloned locally.

OPTIONS:
  --version           Show the version.
  -h, --help          Show help information.
```

### Commands

**`saddle status`** (default) - Scan `~/Developer/` and display a table of all repos with branch, visibility, local status, and last commit time. Repos in the manifest are marked as "saddled."

**`saddle up`** - Read the manifest, clone any missing repos, pull updates for clean repos, and run configured hooks.

**`saddle remote`** - Query GitHub for all your repos (owned + collaborator) and show which ones aren't cloned locally.

## Configuration

Config lives at `~/.config/saddle/`:

- **`manifest.txt`** - One repo URL per line. Optional root path (e.g. `~/Developer`). Lines starting with `#` are comments.
- **`hooks/`** - Executable scripts named `owner-repo.sh` that run after sync.

State lives at `~/.local/state/saddle/`:

- **`state.json`** - Last run timestamp
- **`saddle.log`** - Error log
- **`hooks/`** - Per-hook output logs

## Requirements

- macOS 14+ (Sonoma)
- Swift 6.0
- `gh` CLI (for `remote` command and visibility detection)

## License

MIT
