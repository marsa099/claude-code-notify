#!/bin/bash
# Hook: PermissionRequest
# Fires immediately when Claude Code requests permission. Saves state and sends
# a styled desktop notification with tool details and keybinding hints.

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

# Read tool info from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Skip non-permission events (e.g. feedback surveys)
[ "$TOOL_NAME" = "AskUserQuestion" ] && exit 0

ID=$(cn_instance_id)
[ -z "$ID" ] && exit 0
TYPE=$(cn_instance_type)

# Save tool info for navigate/goto scripts
echo "$INPUT" | jq -c '{tool_name: .tool_name, tool_input: .tool_input}' \
    > "$CN_STATE_DIR/tool-info-${ID}.json" 2>/dev/null

cn_log "[permission-request] tool=$TOOL_NAME id=$ID"

# Determine label
if [ "$TYPE" = "tmux" ]; then
    PANE="$TMUX_PANE"
    SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null)
    WINDOW_IDX=$(tmux display-message -t "$PANE" -p '#{window_index}' 2>/dev/null)
    LABEL="${SESSION:-claude}:${WINDOW_IDX}"
else
    PANE=""
    LABEL=$(basename "$PWD" 2>/dev/null)
    [ -z "$LABEL" ] && LABEL="direct"
fi

# Find window ID for direct terminal instances
TERMINAL_WID=""
[ "$TYPE" = "direct" ] && TERMINAL_WID=$(cn_wm_find_terminal_wid)

# Save state
{
    printf 'instance_type=%s\n' "$TYPE"
    printf 'label=%s\n' "$LABEL"
    printf 'prompt_type=%s\n' "permission"
    [ "$TYPE" = "tmux" ] && printf 'pane=%s\nsession=%s\n' "$PANE" "$SESSION"
    [ "$TYPE" = "direct" ] && printf 'window_id=%s\n' "$TERMINAL_WID"
} > "$CN_STATE_DIR/$ID"
cn_log "[permission-request] saved state: id=$ID type=$TYPE"

cn_log "[permission-request] notification: tool=$TOOL_NAME"

# Send notification if terminal is not focused
if cn_should_skip_notification; then
    cn_log "[permission-request] skipped notification: terminal focused"
else
    LAST_NAV="$CN_STATE_DIR/.last-navigate"
    if [ ! -f "$LAST_NAV" ]; then
        BODY=$(cn_build_full_notification "$ID")
        cn_notify "> Claude - $LABEL" "$BODY" critical 0
        echo "$ID" > "$LAST_NAV"
        cn_log "[permission-request] created active notification"
    else
        ACTIVE_ID=$(cat "$LAST_NAV")
        ACTIVE_LABEL=$(grep '^label=' "$CN_STATE_DIR/$ACTIVE_ID" 2>/dev/null | cut -d= -f2)
        [ -z "$ACTIVE_LABEL" ] && ACTIVE_LABEL="claude:?"
        BODY=$(cn_build_full_notification "$ACTIVE_ID")
        cn_notify "> Claude - $ACTIVE_LABEL" "$BODY" critical 0
        cn_log "[permission-request] updated active notification active=$ACTIVE_ID"
    fi
fi

# Background watcher: detect when permission prompt disappears (denial or accept)
# and clean up. Handles denial case where PostToolUse never fires.
if [ "$TYPE" = "tmux" ] && [ -n "$PANE" ]; then
    WATCHER_PID_FILE="$CN_STATE_DIR/watcher-${ID}.pid"
    [ -f "$WATCHER_PID_FILE" ] && kill "$(cat "$WATCHER_PID_FILE")" 2>/dev/null
    (
        # Wait for the permission prompt to appear (up to 30s)
        SEEN=false
        for _ in $(seq 1 30); do
            if tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -q "Esc to cancel"; then
                SEEN=true
                break
            fi
            sleep 1
        done
        # Only watch for disappearance if we actually saw the prompt
        if [ "$SEEN" = true ]; then
            while tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -q "Esc to cancel"; do
                sleep 2
            done
            [ -f "$CN_STATE_DIR/$ID" ] && bash "$CN_DIR/hooks/cleanup-instance.sh" "$ID"
        fi
        rm -f "$WATCHER_PID_FILE"
    ) &>/dev/null &
    echo $! > "$WATCHER_PID_FILE"
fi
