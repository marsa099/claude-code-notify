#!/bin/bash
# Hook: Notification (fallback)
# Fires for all Claude Code notification types. If a styled permission
# notification already exists for this instance, leaves it alone.

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
            # Claude moved on — clean up stale notification
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
else
    cn_notify "$TITLE" "$MESSAGE" normal 0
    cn_log "[notification-hook] sent notification"
fi
