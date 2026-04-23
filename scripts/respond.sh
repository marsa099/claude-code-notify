#!/bin/bash
# Send a response to the currently selected Claude Code permission prompt.
# Called by WM keybinding.
# Usage: respond.sh <1|2|3>
#   1 = Allow/Yes, 2 = Always Allow, 3 = Deny/No

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

KEY="$1"
if [ -z "$KEY" ]; then
    cn_log "[respond] error: no key argument"
    exit 1
fi

LAST_NAV_FILE="$CN_STATE_DIR/.last-navigate"

# Use navigated selection if available, otherwise most recent
LATEST=""
if [ -f "$LAST_NAV_FILE" ]; then
    NAV_TARGET=$(cat "$LAST_NAV_FILE")
    [ -f "$CN_STATE_DIR/$NAV_TARGET" ] && LATEST="$NAV_TARGET"
fi
if [ -z "$LATEST" ]; then
    LATEST=$(cn_pending_ids | head -1)
fi

if [ -z "$LATEST" ]; then
    cn_log "[respond] error: no pending permissions"
    exit 1
fi

STATE_FILE="$CN_STATE_DIR/$LATEST"
INSTANCE_TYPE=$(grep '^instance_type=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)

# Skip input-waiting notifications (no keystroke to send)
PROMPT_TYPE=$(grep '^prompt_type=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
if [ "$PROMPT_TYPE" = "input" ]; then
    cn_log "[respond] skipped: input notification, not a permission prompt"
    exit 0
fi

# Remap keys for Yes/No prompts
SEND_KEY="$KEY"
if [ "$PROMPT_TYPE" = "yesno" ]; then
    case "$KEY" in
        2|3) SEND_KEY="2" ;; # Always Allow / Deny -> No
    esac
fi

# Send keystroke
if [ "$INSTANCE_TYPE" = "tmux" ]; then
    PANE=$(grep '^pane=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ -z "$PANE" ]; then
        cn_log "[respond] error: empty pane in state file $LATEST"
        rm -f "$STATE_FILE"
        exit 1
    fi
    tmux send-keys -t "$PANE" "$SEND_KEY" 2>>"$CN_LOG"
    RESULT=$?
else
    WINDOW_ID=$(grep '^window_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ -z "$WINDOW_ID" ]; then
        cn_log "[respond] error: no window_id in state file $LATEST"
        rm -f "$STATE_FILE"
        exit 1
    fi
    cn_wm_focus_wid "$WINDOW_ID"
    sleep 0.1
    case "$CN_INPUT_METHOD" in
        xdotool) xdotool key "$SEND_KEY" ;;
        *) wtype "$SEND_KEY" ;;
    esac
    RESULT=$?
fi

# Close notification
cn_notify_close
cn_log "[respond] closing notification for instance=$LATEST"

# Clean up state
rm -f "$STATE_FILE" "$CN_STATE_DIR/tool-info-${LATEST}.json" "$LAST_NAV_FILE"

LABELS=("" "Allow" "Always Allow" "Deny")
YESNO_LABELS=("" "Yes" "No" "No")
if [ "$PROMPT_TYPE" = "yesno" ]; then
    cn_log "[respond] sent key=$SEND_KEY (${YESNO_LABELS[$KEY]}) to=$LATEST type=$INSTANCE_TYPE exit=$RESULT [yesno]"
else
    cn_log "[respond] sent key=$SEND_KEY (${LABELS[$KEY]}) to=$LATEST type=$INSTANCE_TYPE exit=$RESULT"
fi

# Re-render remaining notifications
if [ -n "$(cn_pending_ids)" ]; then
    bash "$CN_DIR/scripts/navigate.sh" </dev/null 2>/dev/null
fi
