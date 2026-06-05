# Source this file to activate the zellij-tmux-shim (fish shell).
# Usage: source activate.fish
#
# This is the fish-native port of activate.sh. fish cannot source the
# bash version, so keep the two in sync when changing activation logic.

# Guard: only activate inside zellij
if test -z "$ZELLIJ"
    echo "zellij-tmux-shim: not inside zellij, skipping activation" >&2
    return 1
end

# Guard: don't double-activate — but always re-ensure PATH priority.
# Child shells inherit ZELLIJ_TMUX_SHIM_ACTIVE but rebuild PATH from
# shell config, pushing the shim behind other entries (brew, cargo, etc.).
if set -q ZELLIJ_TMUX_SHIM_ACTIVE
    set -l _dir
    if set -q ZELLIJ_TMUX_SHIM_DIR
        set _dir "$ZELLIJ_TMUX_SHIM_DIR"
    else if set -q XDG_DATA_HOME
        set _dir "$XDG_DATA_HOME/zellij-tmux-shim"
    else
        set _dir "$HOME/.local/share/zellij-tmux-shim"
    end
    set -gx PATH "$_dir/bin" $PATH
    return 0
end

# XDG-compliant install directory
if set -q XDG_DATA_HOME
    set -gx ZELLIJ_TMUX_SHIM_DIR "$XDG_DATA_HOME/zellij-tmux-shim"
else
    set -gx ZELLIJ_TMUX_SHIM_DIR "$HOME/.local/share/zellij-tmux-shim"
end

# Runtime state goes in an ephemeral, per-user, per-session directory (PIDs, FIFOs, etc.)
# XDG_RUNTIME_DIR is /run/user/UID on systemd Linux; TMPDIR is per-user on macOS.
# Scoped by ZELLIJ_SESSION_NAME so multiple zellij sessions don't collide.
set -l _runtime_base
if set -q XDG_RUNTIME_DIR
    set _runtime_base "$XDG_RUNTIME_DIR"
else if set -q TMPDIR
    set _runtime_base "$TMPDIR"
else
    set _runtime_base /tmp
end
set -l _shim_root "$_runtime_base/zellij-tmux-shim-"(id -u)
if set -q ZELLIJ_SESSION_NAME
    set -gx ZELLIJ_TMUX_SHIM_STATE "$_shim_root/$ZELLIJ_SESSION_NAME"
else
    set -gx ZELLIJ_TMUX_SHIM_STATE "$_shim_root/default"
end

# Save real tmux path before we shadow it
set -gx ZELLIJ_TMUX_SHIM_REAL_TMUX (command -v tmux 2>/dev/null; or true)

# Save original PATH for deactivation (colon-joined, matching the bash port)
set -gx ZELLIJ_TMUX_SHIM_ORIG_PATH (string join ':' $PATH)

# Prepend shim bin to PATH so our tmux shadows the real one
set -gx PATH "$ZELLIJ_TMUX_SHIM_DIR/bin" $PATH

# Set fake tmux env vars so Claude Code thinks it's inside tmux
set -gx TMUX "zellij-shim:/tmp/zellij-shim,$fish_pid,0"
set -gx TMUX_PANE "%0"

# Initialize state directory — this is the security keystone.
# FIFOs, eval'd env files, and command delivery all live here.
# chmod 700 MUST succeed; if it doesn't, the shim is unsafe.
# Secure the per-user root directory first, then create the per-session subdir.
if test -L "$_shim_root"
    echo "zellij-tmux-shim: ERROR: state root is a symlink, refusing to activate" >&2
    return 1
end
mkdir -p "$_shim_root"
chmod 700 "$_shim_root"
set -l _owner (stat -c '%u' "$_shim_root" 2>/dev/null; or stat -f '%u' "$_shim_root" 2>/dev/null)
if test "$_owner" != (id -u)
    echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2
    return 1
end
# Per-session subdir inherits root's 700 protection
mkdir -p "$ZELLIJ_TMUX_SHIM_STATE"

# Initialize next_id counter (start at 1, %0 is reserved for the host pane)
if not test -f "$ZELLIJ_TMUX_SHIM_STATE/next_id"
    echo "1" > "$ZELLIJ_TMUX_SHIM_STATE/next_id"
end

# Initialize sessions file
if not test -f "$ZELLIJ_TMUX_SHIM_STATE/sessions"
    touch "$ZELLIJ_TMUX_SHIM_STATE/sessions"
end

# Sweep stale state from prior crashed sessions: remove state files
# for PIDs that no longer exist.
for _pidfile in (command find "$ZELLIJ_TMUX_SHIM_STATE" -maxdepth 1 -name '*.pid' 2>/dev/null)
    set -l _pid (cat "$_pidfile" 2>/dev/null)
    if test -n "$_pid"; and not kill -0 "$_pid" 2>/dev/null
        set -l _key (basename "$_pidfile" .pid)
        rm -f "$ZELLIJ_TMUX_SHIM_STATE/$_key.pid" \
              "$ZELLIJ_TMUX_SHIM_STATE/$_key.zellij_id" \
              "$ZELLIJ_TMUX_SHIM_STATE/$_key.fifo" \
              "$ZELLIJ_TMUX_SHIM_STATE/$_key.ready" \
              "$ZELLIJ_TMUX_SHIM_STATE/$_key.cmd" \
              "$ZELLIJ_TMUX_SHIM_STATE/$_key.named" \
              "$ZELLIJ_TMUX_SHIM_STATE/$_key.group"
    end
end

# Clean up orphaned .zellij_id files (no matching .pid = dead pane)
for _idfile in (command find "$ZELLIJ_TMUX_SHIM_STATE" -maxdepth 1 -name '*.zellij_id' 2>/dev/null)
    set -l _key (basename "$_idfile" .zellij_id)
    if not test -f "$ZELLIJ_TMUX_SHIM_STATE/$_key.pid"
        rm -f "$_idfile"
    end
end

# Remove stale env snapshot and lock from prior sessions
rm -f "$ZELLIJ_TMUX_SHIM_STATE/parent.env"
rm -rf "$ZELLIJ_TMUX_SHIM_STATE/next_id.lock"

set -gx ZELLIJ_TMUX_SHIM_ACTIVE 1
