#!/usr/bin/env bash
# Generate demo screenshots (PNG) and recordings (GIF) with mock data.
# Requires: cli2png, cli2gif (both in /usr/local/bin)
set -euo pipefail

DEMO_HOME="/tmp/saddle-demo"
DEV_DIR="$DEMO_HOME/Developer"
APP_SUPPORT="$DEMO_HOME/Library/Application Support/com.ansilithic.saddle"
BARE_DIR="$DEMO_HOME/.bare"
FORGE_MOCK="$DEMO_HOME/forge.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
BINARY="$PROJECT_DIR/.build/debug/saddle"
ASSETS_DIR="$PROJECT_DIR/assets"

# Shared measurement state
MEASURED_COLS=0
MEASURED_ROWS=0

# ── Helpers ──────────────────────────────────────────────────────

now=$(date +%s)
iso_hours_ago() { date -u -r $(( now - $1 * 3600 )) "+%Y-%m-%dT%H:%M:%SZ"; }
iso_days_ago()  { date -u -r $(( now - $1 * 86400 )) "+%Y-%m-%dT%H:%M:%SZ"; }
iso_weeks_ago() { date -u -r $(( now - $1 * 604800 )) "+%Y-%m-%dT%H:%M:%SZ"; }

# Measure cols/rows from captured ANSI output.
# Sets MEASURED_COLS and MEASURED_ROWS for the next gen_gif call.
measure() {
    local input="$1"
    local max_width=0
    local line_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        local stripped
        stripped=$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*m//g')
        local width=${#stripped}
        [ "$width" -gt "$max_width" ] && max_width=$width
        line_count=$((line_count + 1))
    done <<< "$input"
    MEASURED_COLS=$((max_width + 2))
    MEASURED_ROWS=$((line_count + 4))
}

# Create a fake git repo with configurable state.
#   create_repo <owner> <name> <commit_date> [dirty] [ahead] [behind]
create_repo() {
    local owner=$1 name=$2 commit_date=$3
    local dirty=${4:-false} ahead=${5:-0} behind=${6:-0}

    local repo_path="$DEV_DIR/$owner/$name"
    local bare_path="$BARE_DIR/$owner/$name.git"
    local remote_url="https://github.com/$owner/$name.git"

    # Create bare origin
    if [ ! -d "$bare_path" ]; then
        mkdir -p "$bare_path"
        git -C "$bare_path" init --bare -b main -q
        local tmp
        tmp=$(mktemp -d)
        git -C "$tmp" init -b main -q
        git -C "$tmp" remote add origin "$bare_path"
        GIT_COMMITTER_DATE="$commit_date" GIT_AUTHOR_DATE="$commit_date" \
            git -C "$tmp" commit --allow-empty -m "initial" -q
        git -C "$tmp" push -u origin main -q 2>/dev/null
        rm -rf "$tmp"
    fi

    # Clone into Developer/
    mkdir -p "$(dirname "$repo_path")"
    git clone -q "$bare_path" "$repo_path" 2>/dev/null

    # Behind: push extra commits to bare origin, then fetch
    if [ "$behind" -gt 0 ]; then
        local tmp
        tmp=$(mktemp -d)
        git clone -q "$bare_path" "$tmp" 2>/dev/null
        for i in $(seq 1 "$behind"); do
            GIT_COMMITTER_DATE="$commit_date" GIT_AUTHOR_DATE="$commit_date" \
                git -C "$tmp" commit --allow-empty -m "upstream $i" -q
        done
        git -C "$tmp" push origin main -q 2>/dev/null
        rm -rf "$tmp"
        git -C "$repo_path" fetch -q 2>/dev/null
    fi

    # Ahead: local commits beyond the tracking ref
    if [ "$ahead" -gt 0 ]; then
        for i in $(seq 1 "$ahead"); do
            GIT_COMMITTER_DATE="$commit_date" GIT_AUTHOR_DATE="$commit_date" \
                git -C "$repo_path" commit --allow-empty -m "local $i" -q
        done
    fi

    # Dirty: uncommitted file
    if [ "$dirty" = "true" ]; then
        echo "work in progress" > "$repo_path/wip.txt"
    fi

    # Repoint origin to GitHub URL for display
    git -C "$repo_path" remote set-url origin "$remote_url"
}

# Create a bare-only repo (remote-only manifest entries cloned during saddle up).
create_bare_only() {
    local owner=$1 name=$2 commit_date=$3
    local bare_path="$BARE_DIR/$owner/$name.git"

    mkdir -p "$bare_path"
    git -C "$bare_path" init --bare -b main -q
    local tmp
    tmp=$(mktemp -d)
    git -C "$tmp" init -b main -q
    git -C "$tmp" remote add origin "$bare_path"
    GIT_COMMITTER_DATE="$commit_date" GIT_AUTHOR_DATE="$commit_date" \
        git -C "$tmp" commit --allow-empty -m "initial" -q
    git -C "$tmp" push -u origin main -q 2>/dev/null
    rm -rf "$tmp"
}

create_hook() {
    local name=$1
    local hook_dir="$APP_SUPPORT/hooks/$name"
    mkdir -p "$hook_dir"
    printf '#!/usr/bin/env bash\ninstall() { :; }\nupdate() { :; }\n' > "$hook_dir/hook.sh"
    chmod +x "$hook_dir/hook.sh"
}

# ── Setup ────────────────────────────────────────────────────────

setup() {
    rm -rf "$DEMO_HOME"
    mkdir -p "$DEV_DIR" "$APP_SUPPORT/hooks" "$BARE_DIR" "$ASSETS_DIR"

    # Git insteadOf — redirects github.com HTTPS URLs to local bare repos
    git config --file "$DEMO_HOME/.gitconfig" \
        url."file://$BARE_DIR/".insteadOf "https://github.com/"

    # Bare repos for remote-only entries (cloned during saddle up)
    create_bare_only neonlabs    sentinel     "$(iso_days_ago 14)"
    create_bare_only pixelforge  rhythm       "$(iso_days_ago 60)"

    # Local repos — owner/name, date, dirty, ahead, behind
    create_repo starloom     orbit           "$(iso_hours_ago 2)"
    create_repo starloom     renderkit       "$(iso_days_ago 3)"    false  0  1
    create_repo starloom     spectrum        "$(iso_weeks_ago 1)"
    create_repo starloom     waveform        "$(iso_hours_ago 5)"   true
    create_repo neonlabs     chronos         "$(iso_days_ago 1)"
    create_repo neonlabs     blueprint       "$(iso_hours_ago 4)"   true   2
    create_repo hexworks     gloomhollow     "$(iso_weeks_ago 2)"
    create_repo jmason       dotfiles        "$(iso_hours_ago 6)"   true
    create_repo jmason       wiki            "$(iso_days_ago 30)"
    create_repo infrakit     gateway         "$(iso_weeks_ago 3)"   false  0  1
    create_repo neonlabs     sandbox         "$(iso_hours_ago 8)"   true          # stray

    # Hooks
    create_hook starloom-orbit
    create_hook neonlabs-chronos
    create_hook jmason-dotfiles
    create_hook hexworks-gloomhollow

    # Manifest
    cat > "$APP_SUPPORT/manifest.toml" <<'MANIFEST'
mount = "~/Developer"
protocol = "https"

[repos]
"github.com/starloom/orbit"
"github.com/starloom/renderkit"
"github.com/starloom/spectrum"
"github.com/starloom/waveform"
"github.com/neonlabs/chronos"
"github.com/neonlabs/blueprint"
"github.com/neonlabs/sentinel"
"github.com/hexworks/gloomhollow"
"github.com/jmason/dotfiles"
"github.com/jmason/wiki"
"github.com/infrakit/gateway"
"github.com/pixelforge/rhythm"
MANIFEST

    # State — recent fetch prevents network calls during status
    cat > "$APP_SUPPORT/state.json" <<STATE
{
    "version": 1,
    "lastRun": "$(date -u "+%Y-%m-%dT%H:%M:%SZ")",
    "lastFetch": "$(date -u "+%Y-%m-%dT%H:%M:%SZ")"
}
STATE

    # Forge mock
    cat > "$FORGE_MOCK" <<FORGE
{
    "repos": {
        "github.com/starloom/orbit": {
            "visibility": "public", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_hours_ago 2)", "language": "Go",
            "description": "Monorepo task orchestrator",
            "stargazers": 47, "isArchived": false
        },
        "github.com/starloom/renderkit": {
            "visibility": "public", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_days_ago 3)", "language": "Go",
            "description": "Shared rendering pipeline",
            "stargazers": 12, "isArchived": false
        },
        "github.com/starloom/spectrum": {
            "visibility": "public", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_weeks_ago 1)", "language": "Go",
            "description": "Terminal color toolkit",
            "stargazers": 31, "isArchived": false
        },
        "github.com/starloom/waveform": {
            "visibility": "public", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_hours_ago 5)", "language": "Rust",
            "description": "Audio visualization engine",
            "stargazers": 9, "isArchived": false
        },
        "github.com/neonlabs/chronos": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_days_ago 1)", "language": "TypeScript",
            "description": "Distributed cron scheduler",
            "stargazers": 0, "isArchived": false
        },
        "github.com/neonlabs/blueprint": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_hours_ago 4)", "language": "Markdown",
            "description": "Architecture decision records",
            "stargazers": 0, "isArchived": false
        },
        "github.com/neonlabs/sentinel": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_days_ago 14)", "language": "Go",
            "description": "Infrastructure health monitor",
            "stargazers": 0, "isArchived": false
        },
        "github.com/hexworks/gloomhollow": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_weeks_ago 2)", "language": "GDScript",
            "description": "2D roguelike dungeon crawler",
            "stargazers": 5, "isArchived": false
        },
        "github.com/jmason/dotfiles": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_hours_ago 6)", "language": "Shell",
            "description": "Personal configuration",
            "stargazers": 0, "isArchived": false
        },
        "github.com/jmason/wiki": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_days_ago 30)", "language": "Markdown",
            "description": "Knowledge base and notes",
            "stargazers": 0, "isArchived": false
        },
        "github.com/infrakit/gateway": {
            "visibility": "public", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_weeks_ago 3)", "language": "Dockerfile",
            "description": "API gateway container",
            "stargazers": 3, "isArchived": false
        },
        "github.com/pixelforge/rhythm": {
            "visibility": "private", "role": "admin", "defaultBranch": "main",
            "pushedAt": "$(iso_days_ago 60)", "language": "Swift",
            "description": "iOS music practice tracker",
            "stargazers": 0, "isArchived": false
        }
    },
    "starred": [
        "github.com/starloom/orbit",
        "github.com/hexworks/gloomhollow"
    ],
    "user": "jmason"
}
FORGE

    # Wrapper binary — clean command name for cli2gif typing animation
    mkdir -p "$DEMO_HOME/bin"
    cat > "$DEMO_HOME/bin/saddle" <<WRAPPER
#!/bin/sh
export HOME="$DEMO_HOME"
export SADDLE_FORGE_MOCK="$FORGE_MOCK"
exec "$BINARY" "\$@"
WRAPPER
    chmod +x "$DEMO_HOME/bin/saddle"
}

# ── Generate ─────────────────────────────────────────────────────

gen_png() {
    local name=$1 cmd=$2
    local output
    output=$(eval "$cmd" 2>/dev/null)
    measure "$output"
    printf '%s\n' "$output" | cli2png -o "$ASSETS_DIR/$name.png" -p "$cmd" --width "$MEASURED_COLS" --height "$MEASURED_ROWS"
    echo "  $name.png  ${MEASURED_COLS}x${MEASURED_ROWS}"
}

gen_gif() {
    local name=$1 cmd=$2
    cli2gif "$cmd" -o "$ASSETS_DIR/$name.gif" --cols "$MEASURED_COLS" --rows "$MEASURED_ROWS" --prompt
    echo "  $name.gif  ${MEASURED_COLS}x${MEASURED_ROWS}"
}

gen() {
    gen_png "$1" "$2"
    gen_gif "$1" "$2"
}

generate() {
    export PATH="$DEMO_HOME/bin:$PATH"

    echo "Generating assets..."

    # help — stateless
    gen "help" "saddle --help"

    # status — reads state but doesn't mutate
    gen "status" "saddle status"

    # up — mutates state (clones, pulls), needs reset between PNG and GIF
    gen_png "up" "saddle up"
    setup
    export PATH="$DEMO_HOME/bin:$PATH"
    gen_gif "up" "saddle up"

    echo "Done. Assets in $ASSETS_DIR/"
}

# ── Teardown ─────────────────────────────────────────────────────

teardown() {
    rm -rf "$DEMO_HOME"
}

# ── Main ─────────────────────────────────────────────────────────

for tool in cli2png cli2gif; do
    if ! command -v "$tool" &>/dev/null; then
        echo "Error: $tool not found" >&2
        exit 1
    fi
done

if [ ! -f "$BINARY" ]; then
    echo "Error: debug binary not found at $BINARY" >&2
    echo "Run 'make build-debug' first." >&2
    exit 1
fi

setup
generate
teardown
