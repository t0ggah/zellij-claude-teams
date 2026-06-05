# Source this file to deactivate the zellij-tmux-shim (fish shell).
# Usage: source deactivate.fish

if not set -q ZELLIJ_TMUX_SHIM_ACTIVE
    echo "zellij-tmux-shim: not active, nothing to deactivate" >&2
    return 0
end

# Kill any remaining wrapper processes and clean up their panes
if test -d "$ZELLIJ_TMUX_SHIM_STATE"
    for pidfile in (command find "$ZELLIJ_TMUX_SHIM_STATE" -maxdepth 1 -name '*.pid' 2>/dev/null)
        set -l pid (cat "$pidfile" 2>/dev/null)
        if test -n "$pid"; and kill -0 "$pid" 2>/dev/null
            kill "$pid" 2>/dev/null
        end
    end
    rm -rf "$ZELLIJ_TMUX_SHIM_STATE"
end

# Restore original PATH (stored colon-joined by activate.fish)
if set -q ZELLIJ_TMUX_SHIM_ORIG_PATH
    set -gx PATH (string split ':' "$ZELLIJ_TMUX_SHIM_ORIG_PATH")
end

# Unset all shim env vars
set -e TMUX
set -e TMUX_PANE
set -e ZELLIJ_TMUX_SHIM_ACTIVE
set -e ZELLIJ_TMUX_SHIM_DIR
set -e ZELLIJ_TMUX_SHIM_STATE
set -e ZELLIJ_TMUX_SHIM_REAL_TMUX
set -e ZELLIJ_TMUX_SHIM_ORIG_PATH
set -e ZELLIJ_TMUX_SHIM_DEBUG
