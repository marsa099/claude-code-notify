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

# Show the target notification (replaces any existing one via fixed ID)
local_state="$CN_STATE_DIR/$TARGET"
label=$(grep '^label=' "$local_state" 2>/dev/null | cut -d= -f2)
[ -z "$label" ] && label="claude:?"
prompt_type=$(grep '^prompt_type=' "$local_state" 2>/dev/null | cut -d= -f2)
[ -z "$prompt_type" ] && prompt_type="permission"

body=$(cn_build_full_notification "$TARGET")
cn_notify_actions "> Claude - $label" "$body" "$prompt_type"

cn_log "[navigate] selected target=$TARGET (${#PANES[@]} pending)"
