#!/bin/bash
# Focus the currently selected Claude Code instance.
# Called by WM keybinding. Uses navigate selection or most recent.

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

LAST_NAV_FILE="$CN_STATE_DIR/.last-navigate"

# Use navigated selection if available, otherwise most recent
TARGET=""
if [ -f "$LAST_NAV_FILE" ]; then
    NAV_TARGET=$(cat "$LAST_NAV_FILE")
    [ -f "$CN_STATE_DIR/$NAV_TARGET" ] && TARGET="$NAV_TARGET"
fi
if [ -z "$TARGET" ]; then
    TARGET=$(cn_pending_ids | head -1)
fi

if [ -z "$TARGET" ]; then
    cn_notify_transient "Claude Code" "No pending permissions"
    cn_log "[goto] no pending permissions"
    exit 0
fi

STATE_FILE="$CN_STATE_DIR/$TARGET"
INSTANCE_TYPE=$(grep '^instance_type=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)

if [ "$INSTANCE_TYPE" = "tmux" ]; then
    PANE=$(grep '^pane=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ -z "$PANE" ]; then
        cn_log "[goto] error: empty pane in state file $TARGET"
        exit 1
    fi
    SESSION=$(grep '^session=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    # Focus the terminal window
    TERM_WID=$(cn_wm_find_terminal_by_app_id)
    [ -n "$TERM_WID" ] && cn_wm_focus_wid "$TERM_WID"
    # Switch to the correct tmux session, then select window and pane
    [ -n "$SESSION" ] && tmux switch-client -t "$SESSION" 2>/dev/null
    tmux select-window -t "$PANE" 2>/dev/null
    tmux select-pane -t "$PANE" 2>/dev/null
    cn_log "[goto] focused pane=$PANE session=$SESSION target=$TARGET [tmux]"
    # Clean up input notifications after goto (we're now focused)
    PROMPT_TYPE=$(grep '^prompt_type=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ "$PROMPT_TYPE" = "input" ]; then
        NID_FILE="$CN_STATE_DIR/notif-id-${TARGET}"
        [ -f "$NID_FILE" ] && cn_notify_close "$(cat "$NID_FILE")"
        rm -f "$STATE_FILE" "$NID_FILE" "$CN_STATE_DIR/watcher-${TARGET}.pid"
    fi
else
    WINDOW_ID=$(grep '^window_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ -z "$WINDOW_ID" ]; then
        cn_log "[goto] error: no window_id in state file $TARGET"
        exit 1
    fi
    cn_wm_focus_wid "$WINDOW_ID"
    cn_log "[goto] focused window=$WINDOW_ID target=$TARGET [direct]"
    # Clean up input notifications after goto
    PROMPT_TYPE=$(grep '^prompt_type=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ "$PROMPT_TYPE" = "input" ]; then
        NID_FILE="$CN_STATE_DIR/notif-id-${TARGET}"
        [ -f "$NID_FILE" ] && cn_notify_close "$(cat "$NID_FILE")"
        rm -f "$STATE_FILE" "$NID_FILE" "$CN_STATE_DIR/watcher-${TARGET}.pid"
    fi
fi
