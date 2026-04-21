#!/bin/bash
# Hook: Notification (fallback)
# Fires for all Claude Code notification types. If a styled permission
# notification already exists for this instance, leaves it alone.
# For "waiting for input" messages: saves state and integrates with the
# single-notification system via .last-navigate.

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

INPUT=$(cat)
TITLE=$(echo "$INPUT" | jq -r '.title // "Claude Code"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // "Needs attention"')

cn_log "[notification-hook] title='$TITLE' message='$MESSAGE'"

ID=$(cn_instance_id)

# Check if a permission notification is active for this instance
HAS_ACTIVE_PERMISSION=false
if [ -n "$ID" ] && [ -f "$CN_STATE_DIR/$ID" ]; then
    HAS_ACTIVE_PERMISSION=true
fi

# If permission still pending, don't touch the styled notification
if [ "$HAS_ACTIVE_PERMISSION" = true ]; then
    case "$MESSAGE" in
        *"waiting for your input"*)
            # Claude moved on — clean up stale permission notification
            NID_FILE="$CN_STATE_DIR/notif-id-${ID}"
            if [ -f "$NID_FILE" ]; then
                cn_notify_close "$(cat "$NID_FILE")"
                rm -f "$NID_FILE"
            fi
            WATCHER_PID_FILE="$CN_STATE_DIR/watcher-${ID}.pid"
            if [ -f "$WATCHER_PID_FILE" ]; then
                kill "$(cat "$WATCHER_PID_FILE")" 2>/dev/null
                rm -f "$WATCHER_PID_FILE"
            fi
            rm -f "$CN_STATE_DIR/$ID" "$CN_STATE_DIR/tool-info-${ID}.json"
            cn_log "[notification-hook] cleaned stale permission for instance=$ID"
            # If this was the active notification, clear it so we create fresh
            NAV="$CN_STATE_DIR/.last-navigate"
            if [ -f "$NAV" ] && [ "$(cat "$NAV")" = "$ID" ]; then
                rm -f "$NAV"
            fi
            ;;
        *)
            cn_log "[notification-hook] skipped: permission notification active for instance=$ID"
            exit 0
            ;;
    esac
fi

if cn_should_skip_notification; then
    cn_log "[notification-hook] skipped: terminal focused"
    exit 0
fi

# Determine instance info for state
INPUT_STATE_ID=""
if [ -n "$ID" ]; then
    INPUT_STATE_ID="i${ID}"
    TYPE=$(cn_instance_type)

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

    TERMINAL_WID=""
    [ "$TYPE" = "direct" ] && TERMINAL_WID=$(cn_wm_find_terminal_wid)

    # Clean up any previous input state for this instance
    OLD_NID_FILE="$CN_STATE_DIR/notif-id-${INPUT_STATE_ID}"
    if [ -f "$OLD_NID_FILE" ]; then
        cn_notify_close "$(cat "$OLD_NID_FILE")"
        rm -f "$OLD_NID_FILE"
    fi
    OLD_WATCHER="$CN_STATE_DIR/watcher-${INPUT_STATE_ID}.pid"
    if [ -f "$OLD_WATCHER" ]; then
        kill "$(cat "$OLD_WATCHER")" 2>/dev/null
        rm -f "$OLD_WATCHER"
    fi
    rm -f "$CN_STATE_DIR/$INPUT_STATE_ID"

    # Save state for goto/navigate
    {
        printf 'instance_type=%s\n' "$TYPE"
        printf 'label=%s\n' "$LABEL"
        printf 'prompt_type=%s\n' "input"
        printf 'message=%s\n' "$MESSAGE"
        [ "$TYPE" = "tmux" ] && printf 'pane=%s\nsession=%s\n' "$PANE" "$SESSION"
        [ "$TYPE" = "direct" ] && printf 'window_id=%s\n' "$TERMINAL_WID"
    } > "$CN_STATE_DIR/$INPUT_STATE_ID"
fi

# Integrate with single-notification system via .last-navigate
LAST_NAV="$CN_STATE_DIR/.last-navigate"
if [ ! -f "$LAST_NAV" ]; then
    # No active notification — this input becomes the active one
    BODY=$(cn_build_full_notification "$INPUT_STATE_ID")
    NOTIF_ID=$(cn_notify "> Claude - ${LABEL:-notification}" "$BODY" critical 0)
    [ -n "$INPUT_STATE_ID" ] && echo "$INPUT_STATE_ID" > "$LAST_NAV"
    [ -n "$NOTIF_ID" ] && [ -n "$INPUT_STATE_ID" ] && echo "$NOTIF_ID" > "$CN_STATE_DIR/notif-id-${INPUT_STATE_ID}"
    cn_log "[notification-hook] created active notification id='$NOTIF_ID'"
else
    # Update existing active notification with new count
    ACTIVE_ID=$(cat "$LAST_NAV")
    ACTIVE_LABEL=$(grep '^label=' "$CN_STATE_DIR/$ACTIVE_ID" 2>/dev/null | cut -d= -f2)
    [ -z "$ACTIVE_LABEL" ] && ACTIVE_LABEL="claude:?"
    BODY=$(cn_build_full_notification "$ACTIVE_ID")
    REPLACE_ID_FILE="$CN_STATE_DIR/notif-id-${ACTIVE_ID}"
    REPLACE_ID=""
    [ -f "$REPLACE_ID_FILE" ] && REPLACE_ID=$(cat "$REPLACE_ID_FILE")
    NOTIF_ID=$(cn_notify "> Claude - $ACTIVE_LABEL" "$BODY" critical 0 "$REPLACE_ID")
    [ -n "$NOTIF_ID" ] && echo "$NOTIF_ID" > "$REPLACE_ID_FILE"
    cn_log "[notification-hook] updated active count id='$NOTIF_ID' active=$ACTIVE_ID"
fi

# Background watcher: close when terminal is focused, using cleanup-instance
# for proper promotion of next pending item
if [ -n "$INPUT_STATE_ID" ]; then
    WATCHER_PID_FILE="$CN_STATE_DIR/watcher-${INPUT_STATE_ID}.pid"
    [ -f "$WATCHER_PID_FILE" ] && kill "$(cat "$WATCHER_PID_FILE")" 2>/dev/null
    (
        sleep 2
        while [ -f "$CN_STATE_DIR/$INPUT_STATE_ID" ]; do
            if cn_should_skip_notification; then
                bash "$CN_DIR/hooks/cleanup-instance.sh" "$INPUT_STATE_ID"
                cn_log "[notification-hook] watcher: closed input notification for $INPUT_STATE_ID (terminal focused)"
                break
            fi
            sleep 2
        done
        rm -f "$WATCHER_PID_FILE"
    ) &>/dev/null &
    echo $! > "$WATCHER_PID_FILE"
fi
