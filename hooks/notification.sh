#!/bin/bash
# Hook: Notification (fallback)
# Fires for all Claude Code notification types. If a styled permission
# notification already exists for this instance, leaves it alone.
# For "waiting for input" messages: saves state for goto/navigate and
# starts a watcher that closes the notification when terminal is focused.

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
                nid_val=$(cat "$NID_FILE")
                cn_notify_close "$nid_val"
                cn_log "[notification-hook] cleaned stale notification id=$nid_val for instance=$ID"
            fi
            rm -f "$CN_STATE_DIR/$ID" "$CN_STATE_DIR/tool-info-${ID}.json" "$NID_FILE"
            NAV="$CN_STATE_DIR/.last-navigate"
            if [ -f "$NAV" ]; then
                nav_val=$(cat "$NAV")
                if [ "$nav_val" = "$ID" ] || [ -z "$(cn_pending_ids)" ]; then
                    rm -f "$NAV"
                fi
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

# Build notification body
BODY="<i>$MESSAGE</i>"
BODY="$BODY\n\nGo to <b>($CN_KEY_GOTO)</b>"
PENDING=$(cn_pending_ids)
if [ -n "$PENDING" ]; then
    COUNT=$(echo "$PENDING" | wc -l)
    BODY="$BODY\nNext <b>($CN_KEY_NEXT)</b>"
    BODY="$BODY\n\n<i>+${COUNT} permissions pending</i>"
fi

NOTIF_ID=$(cn_notify "> Claude - ${LABEL:-notification}" "$BODY" normal 0)
cn_log "[notification-hook] sent notification id='$NOTIF_ID'"

# Save notification ID for cleanup
if [ -n "$INPUT_STATE_ID" ] && [ -n "$NOTIF_ID" ]; then
    echo "$NOTIF_ID" > "$CN_STATE_DIR/notif-id-${INPUT_STATE_ID}"

    # Background watcher: close when terminal is focused
    WATCHER_PID_FILE="$CN_STATE_DIR/watcher-${INPUT_STATE_ID}.pid"
    [ -f "$WATCHER_PID_FILE" ] && kill "$(cat "$WATCHER_PID_FILE")" 2>/dev/null
    (
        sleep 2
        while [ -f "$CN_STATE_DIR/$INPUT_STATE_ID" ]; do
            if cn_should_skip_notification; then
                cn_notify_close "$NOTIF_ID"
                rm -f "$CN_STATE_DIR/$INPUT_STATE_ID" "$CN_STATE_DIR/notif-id-${INPUT_STATE_ID}"
                cn_log "[notification-hook] watcher: closed input notification for $ID (terminal focused)"
                break
            fi
            sleep 2
        done
        rm -f "$WATCHER_PID_FILE"
    ) &>/dev/null &
    echo $! > "$WATCHER_PID_FILE"
fi
