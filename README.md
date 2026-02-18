# saddle

![saddle status](assets/status.png)

A private package manager designed to facilitate rapid development and distribution for humans and agents, built directly on top of git and designed exclusively for macOS.

Enables key insights at a glance:
- How many repos do I have set up right now?
- Are there any uncommited changes anywhere?
- Which ones are public?

Also enables one-liner setup for any new machine via manifest list and hook scripts. The manifest declares which repos should be cloned locally and keeps them up to date. The script hooks define how the code in these repos should be installed locally, if at all. One command to do it all:

```sh
saddle up
```

## Install

### Homebrew

```sh
brew install ansilithic/tap/saddle
```

### From source

```sh
git clone https://github.com/ansilithic/saddle.git
cd saddle
make build && make install
```

Requires macOS 14+ (Sonoma), Swift 6.0, and the [`gh` CLI](https://cli.github.com/) for GitHub integration.

## Quick start guide

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

![saddle help](assets/help.png)

### Hooks

Optional per-repo scripts that run during sync. The script's working directory is the repo itself, wherever it may be.

**Directory format** (recommended):

```
~/.config/saddle/hooks/you-dotfiles/
  install.sh     # first clone
  update.sh      # subsequent syncs (falls back to install.sh)
  uninstall.sh   # saddle unequip
  check.sh       # saddle status (exit 0 = healthy)
```

**Single-file format:**

```
~/.config/saddle/hooks/you-dotfiles.sh
```

Hook names are derived from the repo URL: `github.com/you/dotfiles` becomes `you-dotfiles`. All scripts must be executable. Output is logged to `~/.local/state/saddle/hooks/`.

## GitHub and GitLab Integration

Saddle delegates authentication to the [`gh`](https://cli.github.com/) and [`glab`](https://gitlab.com/gitlab-org/cli) CLIs. If the user is authenticated to these tools, saddle will show repo visibility, list all remote repos, and display any starred repos too.

## AI agent usage

Saddle pairs with `gh` to give AI agents full local + remote repo visibility. See [`SKILL.md`](SKILL.md) for agent-specific instructions — what commands to run, how to interpret output, and when to use saddle vs gh.

## License

MIT
