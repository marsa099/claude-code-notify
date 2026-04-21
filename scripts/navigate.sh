#!/bin/bash
# Cycle through pending permission notifications.
# Called by WM keybinding. Shows one notification at a time.

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

LAST_NAV_FILE="$CN_STATE_DIR/.last-navigate"

mapfile -t PANES < <(cn_pending_ids)

if [ ${#PANES[@]} -eq 0 ]; then
    cn_notify_transient "Claude Code" "No pending permissions"
    cn_log "[navigate] no pending permissions"
    exit 0
fi

# Cycle from current selection
LAST_NAV=$(cat "$LAST_NAV_FILE" 2>/dev/null)
TARGET="${PANES[0]}"

if [ -n "$LAST_NAV" ]; then
    for i in "${!PANES[@]}"; do
        if [ "${PANES[$i]}" = "$LAST_NAV" ]; then
            NEXT_IDX=$(( (i + 1) % ${#PANES[@]} ))
            TARGET="${PANES[$NEXT_IDX]}"
            break
        fi
    done
fi

echo "$TARGET" > "$LAST_NAV_FILE"

# Close all existing notifications
for pane_num in "${PANES[@]}"; do
    old_id_file="$CN_STATE_DIR/notif-id-${pane_num}"
    if [ -f "$old_id_file" ]; then
        cn_notify_close "$(cat "$old_id_file")"
        rm -f "$old_id_file"
    fi
done

# Show the target notification
local_state="$CN_STATE_DIR/$TARGET"
label=$(grep '^label=' "$local_state" 2>/dev/null | cut -d= -f2)
[ -z "$label" ] && label="claude:?"
prompt_type=$(grep '^prompt_type=' "$local_state" 2>/dev/null | cut -d= -f2)

if [ "$prompt_type" = "input" ]; then
    msg=$(grep '^message=' "$local_state" 2>/dev/null | cut -d= -f2-)
    body="<i>${msg:-Waiting for input}</i>"
    body="$body\n\nGo to <b>($CN_KEY_GOTO)</b>\nNext <b>($CN_KEY_NEXT)</b>"
else
    body=$(cn_build_tool_body "$TARGET")
    body="$body\n\n$(cn_keybinding_text "$prompt_type")"
fi

EXTRA=$(( ${#PANES[@]} - 1 ))
[ "$EXTRA" -gt 0 ] && body="$body\n\n<i>+${EXTRA} more</i>"

notif_id=$(cn_notify "> Claude - $label" "$body" critical 0)
[ -n "$notif_id" ] && echo "$notif_id" > "$CN_STATE_DIR/notif-id-${TARGET}"

cn_log "[navigate] selected target=$TARGET (${#PANES[@]} pending) id='$notif_id'"
