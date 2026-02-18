#!/usr/bin/env bash
# Generate a fake saddle environment for demo screenshots.
#
# Usage:
#   ./scripts/demo.sh          # Set up + run saddle status
#   ./scripts/demo.sh setup    # Create the fake environment
#   ./scripts/demo.sh run      # Run saddle status in the fake environment
#   ./scripts/demo.sh run up   # Run saddle up, etc.
#   ./scripts/demo.sh clean    # Remove the fake environment
#
# The script creates fake git repos in /tmp with plausible names,
# a manifest, and hook directories. It overrides HOME so saddle
# reads from the fake config without touching your real setup.
#
# Requires: saddle in PATH (run `make build && make install` first).

set -euo pipefail

DEMO_HOME="/tmp/saddle-demo"
BARE_DIR="/tmp/saddle-demo-bare"
DEV_DIR="$DEMO_HOME/Developer"
CONFIG_DIR="$DEMO_HOME/.config/saddle"
HOOKS_DIR="$CONFIG_DIR/hooks"
STATE_DIR="$DEMO_HOME/.local/state/saddle"

# --- Helpers ---

date_ago() { date -v "$1" "+%Y-%m-%dT%H:%M:%S%z"; }

create_repo() {
  local owner=$1 name=$2 commit_date=$3
  local dirty=${4:-false} ahead=${5:-0} behind=${6:-0}
  local bare="$BARE_DIR/$owner/$name"
  local work="$DEV_DIR/$owner/$name"

  mkdir -p "$bare"
  git init --bare -b main "$bare" -q

  mkdir -p "$work"
  (
    cd "$work"
    git init -b main -q
    git remote add origin "$bare"

    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
      git commit --allow-empty -m "feat: initial setup" -q
    git push -u origin main -q 2>/dev/null

    # Local commits ahead of remote
    for ((i = 0; i < ahead; i++)); do
      GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
        git commit --allow-empty -m "wip: local change" -q
    done

    # Simulate upstream commits (push from a temp clone, then fetch)
    if [ "$behind" -gt 0 ]; then
      local temp="$BARE_DIR/tmp-$owner-$name"
      git clone "$bare" "$temp" -q 2>/dev/null
      (
        cd "$temp"
        for ((i = 0; i < behind; i++)); do
          GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
            git commit --allow-empty -m "upstream: patch" -q
        done
        git push -q origin main 2>/dev/null
      )
      rm -rf "$temp"
      git fetch -q origin 2>/dev/null
    fi

    # Swap remote to fake GitHub URL (tracking ref stays intact)
    git remote set-url origin "git@github.com:$owner/$name.git"

    if [ "$dirty" = "true" ]; then
      echo "TODO: work in progress" > wip.txt
    fi
  )
}

create_hook() {
  local hook_name=$1
  local dir="$HOOKS_DIR/$hook_name"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "Installing..."\n' > "$dir/install.sh"
  chmod +x "$dir/install.sh"
}

# --- Commands ---

setup() {
  echo "Setting up demo environment..."

  rm -rf "$DEMO_HOME" "$BARE_DIR"
  mkdir -p "$DEV_DIR" "$CONFIG_DIR" "$HOOKS_DIR" "$STATE_DIR"

  # Repos: owner, name, date, dirty, ahead, behind
  create_repo acmecraft web-app       "$(date_ago -3H)"  false 2
  create_repo acmecraft api-server    "$(date_ago -2d)"  true
  create_repo acmecraft deploy-tools  "$(date_ago -5H)"  false
  create_repo acmecraft design-system "$(date_ago -28d)" false 0 3
  create_repo jdoe      dotfiles      "$(date_ago -1d)"  false
  create_repo jdoe      nvim-config   "$(date_ago -6H)"  true
  create_repo jdoe      scratch       "$(date_ago -45d)" false  # stray (not in manifest)

  # Manifest — mobile-app is declared but not on disk (shows as "not cloned")
  cat > "$CONFIG_DIR/manifest.toml" << 'EOF'
mount = "/tmp/saddle-demo/Developer"

[repos]
"github.com/acmecraft/web-app"
"github.com/acmecraft/api-server"
"github.com/acmecraft/deploy-tools"
"github.com/acmecraft/design-system"
"github.com/acmecraft/mobile-app"
"github.com/jdoe/dotfiles"
"github.com/jdoe/nvim-config"
EOF

  # Hooks
  create_hook "acmecraft-deploy-tools"
  create_hook "jdoe-dotfiles"
  create_hook "jdoe-nvim-config"

  # Fake gh/glab so real tokens don't leak into demo output
  mkdir -p "$DEMO_HOME/bin"
  printf '#!/bin/sh\nexit 1\n' > "$DEMO_HOME/bin/gh"
  printf '#!/bin/sh\nexit 1\n' > "$DEMO_HOME/bin/glab"
  chmod +x "$DEMO_HOME/bin/gh" "$DEMO_HOME/bin/glab"

  echo "Demo environment ready at $DEMO_HOME"
}

run_saddle() {
  if [ ! -d "$DEMO_HOME" ]; then
    echo "Run '$0 setup' first."
    exit 1
  fi
  PATH="$DEMO_HOME/bin:$PATH" \
  HOME="$DEMO_HOME" \
  GITHUB_TOKEN="" \
  GITLAB_TOKEN="" \
    saddle "$@"
}

clean() {
  rm -rf "$DEMO_HOME" "$BARE_DIR"
  echo "Cleaned up demo environment."
}

# --- Main ---

case "${1:-}" in
  setup) setup ;;
  run)   shift; run_saddle "$@" ;;
  clean) clean ;;
  "")    setup && echo && run_saddle ;;
  *)     echo "Usage: $0 [setup|run [args...]|clean]"; exit 1 ;;
esac
