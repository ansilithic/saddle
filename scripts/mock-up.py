#!/usr/bin/env python3
"""Generate mock saddle up output with proper ANSI codes."""

ESC = "\033"
RESET = f"{ESC}[0m"
BOLD = f"{ESC}[1m"
DIM = f"{ESC}[2m"

def rgb(r, g, b):
    return f"{ESC}[38;2;{r};{g};{b}m"

BLUE = rgb(97, 175, 239)
YELLOW = rgb(229, 192, 123)
RED = rgb(224, 108, 117)
GREEN = rgb(57, 255, 20)  # neon green (saddle text)
GREEN_OK = rgb(152, 195, 121)  # One Dark green
DARK_GRAY = rgb(51, 56, 66)
GRAY = rgb(107, 114, 128)

# Box drawing
TLCR = "\u250c"  # ┌
PIPE = "\u2502"  # │
DASH = "\u2500"  # ─
DOT = "\u25cf"   # ●
MDASH = "\u2014"  # —

def styled(text, color):
    return f"{color}{text}{RESET}"

def dim(text):
    return f"{DIM}{text}{RESET}"

def bold(text):
    return f"{BOLD}{text}{RESET}"

def repo_path(org, name):
    return f"{DARK_GRAY}{org}/{RESET}{GREEN}{name}{RESET}"

ELLIPSIS = "\u2026"

lines = []
a = lines.append

# Header
a("")
a(f"  {bold('Reading manifest' + ELLIPSIS)}  {dim('~/.config/saddle/manifest.toml')}")
a(f"  {dim('7 repos declared, mount at ~/Developer')}")
a("")
a(f"  {bold('Scanning' + ELLIPSIS)}  {dim('~/Developer')}")
a(f"  {dim('7 found, 1 untracked')}")
a("")
a(f"  {bold('Wrangling' + ELLIPSIS)}  {dim('7 repos')}")
a("")

# Legend
a(f"{dim(TLCR+DASH+DASH+DASH)} {styled(DOT, BLUE)} {styled('synced', BLUE)} {dim('(4)')}")
a(f"{dim(PIPE+TLCR+DASH+DASH)} {styled(DOT, YELLOW)} {styled('skipped (dirty)', YELLOW)} {dim('(2)')}")
a(f"{dim(PIPE+PIPE+TLCR+DASH)} {styled(DOT, RED)} {styled('sync failed', RED)} {dim('(1)')}")
a(f"{dim(PIPE+PIPE+PIPE)}")

# Table header
col_repo = 25
col_hook = 20
a(f"{styled(DOT,BLUE)}{styled(DOT,YELLOW)}{styled(DOT,RED)}  {dim('Repo'+(col_repo-4)*' ')}{dim('Hook'+(col_hook-4)*' ')}{dim('Log')}")
a(dim(DASH * 100))

# Rows: (synced, dirty, failed, org, name, hook_name, hook_ok, log_path)
rows = [
    (True,  False, False, "acmecraft", "deploy-tools",  "deploy-tools", True,  "~/.local/state/saddle/logs/deploy-tools.log"),
    (True,  False, False, "acmecraft", "design-system", None,           None,  None),
    (False, False, True,  "acmecraft", "mobile-app",    None,           None,  None),
    (True,  False, False, "acmecraft", "web-app",       None,           None,  None),
    (False, True,  False, "acmecraft", "api-server",    None,           None,  None),
    (True,  False, False, "jdoe",      "dotfiles",      "dotfiles",     True,  "~/.local/state/saddle/logs/dotfiles.log"),
    (False, True,  False, "jdoe",      "nvim-config",   "nvim-config",  None,  None),
]

for synced, dirty, failed, org, name, hook, hook_ok, log in rows:
    s = styled(DOT, BLUE) if synced else " "
    d = styled(DOT, YELLOW) if dirty else " "
    f_ = styled(DOT, RED) if failed else " "

    rp = repo_path(org, name)
    vis_repo = len(f"{org}/{name}")
    repo_pad = " " * max(1, col_repo - vis_repo)

    if hook and hook_ok is not None:
        hook_text = dim(hook) + " " + styled("ok", GREEN_OK)
        vis_hook = len(hook) + 3
    elif hook and hook_ok is None:
        hook_text = dim(MDASH)
        vis_hook = 1
    else:
        hook_text = dim(MDASH)
        vis_hook = 1
    hook_pad = " " * max(1, col_hook - vis_hook)

    log_text = dim(log) if log else ""

    a(f"{s}{d}{f_}  {rp}{repo_pad}{hook_text}{hook_pad}{log_text}")

a("")
# Summary
a(f"{dim(DASH+DASH+' ')}{styled('4 synced', BLUE)}{dim(', ')}{styled('2 skipped', YELLOW)}{dim(', ')}{styled('1 failed', RED)}{dim(' '+DASH+DASH)}")

print("\n".join(lines))
