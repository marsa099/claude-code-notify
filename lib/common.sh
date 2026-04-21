#!/bin/bash
# claude-code-notify: shared library
# Sourced by all hooks and scripts. Provides notification, WM, and utility functions.

# --- Paths and config ---
CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
CN_CONFIG="${CN_CONFIG:-$HOME/.config/claude-notify/config}"
CN_STATE_DIR="/tmp/claude-permissions"
CN_LOG="$HOME/.cache/claude/hooks.log"
CN_ICON="${CN_ICON:-$CN_DIR/icons/claude-code.png}"

# Defaults (overridden by config file)
CN_NOTIFY_BACKEND="${CN_NOTIFY_BACKEND:-dunst}"
CN_WM_BACKEND="${CN_WM_BACKEND:-none}"
CN_TERMINAL_APP_ID="${CN_TERMINAL_APP_ID:-com.mitchellh.ghostty}"
CN_INPUT_METHOD="${CN_INPUT_METHOD:-wtype}"
CN_KEY_ALLOW="${CN_KEY_ALLOW:-Ctrl+Super+Y}"
CN_KEY_ALWAYS_ALLOW="${CN_KEY_ALWAYS_ALLOW:-Ctrl+Super+A}"
CN_KEY_DENY="${CN_KEY_DENY:-Ctrl+Super+N}"
CN_KEY_NEXT="${CN_KEY_NEXT:-Ctrl+Super+P}"
CN_KEY_GOTO="${CN_KEY_GOTO:-Ctrl+Super+O}"

# Load user config
[ -f "$CN_CONFIG" ] && source "$CN_CONFIG"

mkdir -p "$CN_STATE_DIR" "$(dirname "$CN_LOG")"

# --- Logging ---
cn_ts() { date '+%Y-%m-%dT%H:%M:%S.%3N'; }
cn_log() { echo "$(cn_ts) $*" >> "$CN_LOG"; }

# --- Instance ID ---
cn_instance_id() {
    if [ -n "$TMUX_PANE" ]; then
        echo "${TMUX_PANE#%}"
    else
        local pts_num
        pts_num=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ' | grep -oP 'pts/\K\d+')
        [ -n "$pts_num" ] && echo "d${pts_num}"
    fi
}

cn_instance_type() {
    [ -n "$TMUX_PANE" ] && echo "tmux" || echo "direct"
}

# --- HTML escaping (for notification markup) ---
cn_esc() {
    local s="${1//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    echo "$s"
}

# --- Notification backend ---

# Send a notification. Returns the notification ID on stdout.
# Args: title body [urgency] [timeout] [replace_id]
cn_notify() {
    local title="$1" body="$2" urgency="${3:-critical}" timeout="${4:-0}" replace_id="$5"
    case "$CN_NOTIFY_BACKEND" in
        dunst)
            local args=(-u "$urgency" -t "$timeout" -I "$CN_ICON" -p)
            [ -n "$replace_id" ] && args+=(-r "$replace_id")
            dunstify "$title" "$body" "${args[@]}" 2>>"$CN_LOG"
            ;;
        *)
            notify-send "$title" "$body" -u "$urgency" -t "$timeout" -i "$CN_ICON" 2>/dev/null
            echo ""
            ;;
    esac
}

# Send a low-priority transient notification (no ID tracking needed)
cn_notify_transient() {
    local title="$1" body="$2" tag="${3:-claude-nav}"
    case "$CN_NOTIFY_BACKEND" in
        dunst)
            dunstify "$title" "$body" --stack-tag "$tag" -I "$CN_ICON" -u low -t 3000 2>/dev/null
            ;;
        *)
            notify-send "$title" "$body" -u low -t 3000 -i "$CN_ICON" 2>/dev/null
            ;;
    esac
}

# Close a notification by ID
cn_notify_close() {
    local nid="$1"
    [ -z "$nid" ] && return
    case "$CN_NOTIFY_BACKEND" in
        dunst) dunstify -C "$nid" 2>/dev/null ;;
        # generic notify-send has no close support
    esac
}

# --- WM backend ---

# Get the focused window ID
cn_wm_focused_wid() {
    case "$CN_WM_BACKEND" in
        niri)
            niri msg focused-window 2>/dev/null | awk '/^Window ID/ {print $3; exit}' | tr -d ':'
            ;;
        sway)
            swaymsg -t get_tree 2>/dev/null | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused == true) | .id'
            ;;
        hyprland)
            hyprctl activewindow -j 2>/dev/null | jq -r '.address'
            ;;
        *) echo "" ;;
    esac
}

# Get all windows as "wid pid" pairs (one per line)
cn_wm_windows() {
    case "$CN_WM_BACKEND" in
        niri)
            niri msg windows 2>/dev/null | awk '
                /^Window ID/ { id = $3; sub(/:$/, "", id) }
                /PID:/ { print id, $2 }
            '
            ;;
        sway)
            swaymsg -t get_tree 2>/dev/null | jq -r '
                recurse(.nodes[]?, .floating_nodes[]?) |
                select(.pid != null and .id != null) |
                "\(.id) \(.pid)"
            '
            ;;
        hyprland)
            hyprctl clients -j 2>/dev/null | jq -r '.[] | "\(.address) \(.pid)"'
            ;;
        *) echo "" ;;
    esac
}

# Focus a window by its WM window ID
cn_wm_focus_wid() {
    local wid="$1"
    [ -z "$wid" ] && return
    case "$CN_WM_BACKEND" in
        niri) niri msg action focus-window --id "$wid" 2>/dev/null ;;
        sway) swaymsg "[con_id=$wid] focus" 2>/dev/null ;;
        hyprland) hyprctl dispatch focuswindow "address:$wid" 2>/dev/null ;;
    esac
}

# Find the terminal window by walking the PID tree up to a WM window
cn_wm_find_terminal_wid() {
    [ "$CN_WM_BACKEND" = "none" ] && return 1
    local windows
    windows=$(cn_wm_windows)
    [ -z "$windows" ] && return 1
    local pid=$$
    while [ "$pid" != "1" ] && [ -n "$pid" ] && [ "$pid" != "0" ]; do
        local wid
        wid=$(echo "$windows" | awk -v p="$pid" '$2 == p {print $1; exit}')
        if [ -n "$wid" ]; then
            echo "$wid"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# Find terminal window by app ID pattern
cn_wm_find_terminal_by_app_id() {
    [ "$CN_WM_BACKEND" = "none" ] && return 1
    local app_id="$CN_TERMINAL_APP_ID"
    case "$CN_WM_BACKEND" in
        niri)
            niri msg windows 2>/dev/null | awk -v app="$app_id" '
                /^Window ID/ { id = $3; sub(/:$/, "", id) }
                /App ID:/ && index($0, app) { print id; exit }
            '
            ;;
        sway)
            swaymsg -t get_tree 2>/dev/null | jq -r --arg app "$app_id" '
                recurse(.nodes[]?, .floating_nodes[]?) |
                select(.app_id == $app or (.window_properties.class // "") == $app) |
                .id' | head -1
            ;;
        hyprland)
            hyprctl clients -j 2>/dev/null | jq -r --arg app "$app_id" '
                .[] | select(.class == $app or .initialClass == $app) |
                .address' | head -1
            ;;
        *) echo "" ;;
    esac
}

# --- Focus detection ---

# Check if the terminal running this hook is currently focused
cn_is_terminal_focused() {
    [ "$CN_WM_BACKEND" = "none" ] && return 1
    local focused_wid
    focused_wid=$(cn_wm_focused_wid)
    [ -z "$focused_wid" ] && return 1
    local start_pid=$$
    if [ -n "$TMUX" ]; then
        start_pid=$(tmux display-message -t "${TMUX_PANE:-}" -p '#{client_pid}' 2>/dev/null)
    fi
    [ -z "$start_pid" ] && return 1
    local windows
    windows=$(cn_wm_windows)
    local pid=$start_pid
    while [ "$pid" != "1" ] && [ -n "$pid" ] && [ "$pid" != "0" ]; do
        local wid
        wid=$(echo "$windows" | awk -v p="$pid" '$2 == p {print $1; exit}')
        if [ -n "$wid" ]; then
            [ "$wid" = "$focused_wid" ] && return 0
            return 1
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# Check if the tmux pane is the active one in the client's view
cn_is_pane_visible() {
    if [ -n "$TMUX_PANE" ]; then
        local session
        session=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}' 2>/dev/null)
        local client_pane
        client_pane=$(tmux list-clients -t "$session" -F '#{pane_id}' 2>/dev/null | head -1)
        [ "$client_pane" = "$TMUX_PANE" ]
    else
        return 0
    fi
}

# Combined check: should we skip sending a notification?
cn_should_skip_notification() {
    cn_is_terminal_focused && cn_is_pane_visible
}

# --- Notification body builders ---

# Build tool details body from a tool-info JSON file
cn_build_tool_body() {
    local id="$1"
    local info="$CN_STATE_DIR/tool-info-${id}.json"
    local tn="" tc="" tf="" td="" tp="" tpt="" ts=""
    if [ -f "$info" ]; then
        tn=$(jq -r '.tool_name // empty' "$info" 2>/dev/null)
        tc=$(jq -r '.tool_input.command // empty' "$info" 2>/dev/null)
        tf=$(jq -r '.tool_input.file_path // empty' "$info" 2>/dev/null)
        td=$(jq -r '.tool_input.description // empty' "$info" 2>/dev/null)
        tp=$(jq -r '.tool_input.pattern // empty' "$info" 2>/dev/null)
        tpt=$(jq -r '.tool_input.prompt // empty' "$info" 2>/dev/null)
        ts=$(jq -r '.tool_input.subagent_type // empty' "$info" 2>/dev/null)
    fi
    tc=$(cn_esc "$tc"); tf=$(cn_esc "$tf"); td=$(cn_esc "$td")
    tp=$(cn_esc "$tp"); tpt=$(cn_esc "$tpt")
    [ -n "$tc" ] && [ ${#tc} -gt 200 ] && tc="${tc:0:200}..."
    local b
    if [ -n "$ts" ]; then b="<b>${tn:-Tool}</b> (${ts})"; else b="<b>${tn:-Tool}</b>"; fi
    [ -n "$tc" ] && b="$b\n<tt>$tc</tt>"
    [ -n "$tf" ] && b="$b\n$tf"
    [ -n "$tp" ] && b="$b\nPattern: $tp"
    [ -n "$td" ] && b="$b\n<i>$td</i>"
    if [ -n "$tpt" ]; then
        local trunc="${tpt:0:200}"
        [ ${#tpt} -gt 200 ] && trunc="${trunc}..."
        b="$b\n${trunc}"
    fi
    echo "$b"
}

# Build keybinding hint text
cn_keybinding_text() {
    local prompt_type="$1"
    if [ "$prompt_type" = "yesno" ]; then
        echo "Yes <b>($CN_KEY_ALLOW)</b>\nNo <b>($CN_KEY_DENY)</b>\nNext <b>($CN_KEY_NEXT)</b>\nGo to <b>($CN_KEY_GOTO)</b>"
    else
        echo "Allow <b>($CN_KEY_ALLOW)</b>\nAlways Allow <b>($CN_KEY_ALWAYS_ALLOW)</b>\nDeny <b>($CN_KEY_DENY)</b>\nNext <b>($CN_KEY_NEXT)</b>\nGo to <b>($CN_KEY_GOTO)</b>"
    fi
}

# Build full notification body with keybindings and pending count.
# Reads prompt_type from the state file to handle both permission and input types.
cn_build_full_notification() {
    local id="$1"
    local state_file="$CN_STATE_DIR/$id"
    local prompt_type
    prompt_type=$(grep '^prompt_type=' "$state_file" 2>/dev/null | cut -d= -f2)
    [ -z "$prompt_type" ] && prompt_type="permission"
    local body
    if [ "$prompt_type" = "input" ]; then
        local msg
        msg=$(grep '^message=' "$state_file" 2>/dev/null | cut -d= -f2-)
        body="<i>${msg:-Waiting for input}</i>"
        body="$body\n\nGo to <b>($CN_KEY_GOTO)</b>\nNext <b>($CN_KEY_NEXT)</b>"
    else
        body=$(cn_build_tool_body "$id")
        body="$body\n\n$(cn_keybinding_text "$prompt_type")"
    fi
    local total
    total=$(find "$CN_STATE_DIR" -maxdepth 1 -type f ! -name '.*' ! -name '*-*' ! -name '*.json' 2>/dev/null | wc -l)
    local extra=$((total - 1))
    [ "$extra" -gt 0 ] && body="$body\n\n<i>+${extra} more pending</i>"
    echo "$body"
}

# --- State helpers ---

cn_pending_ids() {
    find "$CN_STATE_DIR" -maxdepth 1 -type f ! -name '.*' ! -name '*-*' ! -name '*.json' \
        -printf '%T@ %f\n' 2>/dev/null | sort -n | awk '{print $2}'
}
