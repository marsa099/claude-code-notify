#!/bin/bash
# Shared cleanup: close notification for an instance and promote the next
# pending one if any remain. Called by post-tool-use.sh and the watcher.
# Usage: cleanup-instance.sh <instance-id>

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

ID="$1"
[ -z "$ID" ] && exit 0

# Close this instance's notification
NID_FILE="$CN_STATE_DIR/notif-id-${ID}"
if [ -f "$NID_FILE" ]; then
    cn_notify_close "$(cat "$NID_FILE")"
fi
rm -f "$CN_STATE_DIR/$ID" "$CN_STATE_DIR/tool-info-${ID}.json" "$NID_FILE"

NAV="$CN_STATE_DIR/.last-navigate"
nav_val=""
[ -f "$NAV" ] && nav_val=$(cat "$NAV")
REMAINING=$(find "$CN_STATE_DIR" -maxdepth 1 -type f ! -name '.*' ! -name '*-*' ! -name '*.json' 2>/dev/null)

if [ -z "$REMAINING" ]; then
    rm -f "$NAV"
    cn_log "[cleanup] instance=$ID no more pending"
    exit 0
fi

# Promote next pending instance
TARGET_ID=""
if [ -n "$nav_val" ] && [ "$nav_val" != "$ID" ] && [ -f "$CN_STATE_DIR/$nav_val" ]; then
    TARGET_ID="$nav_val"
else
    TARGET_ID=$(basename "$(echo "$REMAINING" | head -1)")
fi
echo "$TARGET_ID" > "$NAV"

TARGET_LABEL=$(grep '^label=' "$CN_STATE_DIR/$TARGET_ID" 2>/dev/null | cut -d= -f2)
[ -z "$TARGET_LABEL" ] && TARGET_LABEL="claude:?"

BODY=$(cn_build_full_notification "$TARGET_ID")

REPLACE_ID_FILE="$CN_STATE_DIR/notif-id-${TARGET_ID}"
REPLACE_ID=""
[ -f "$REPLACE_ID_FILE" ] && REPLACE_ID=$(cat "$REPLACE_ID_FILE")

NOTIF_ID=$(cn_notify "> Claude - $TARGET_LABEL" "$BODY" critical 0 "$REPLACE_ID")
[ -n "$NOTIF_ID" ] && echo "$NOTIF_ID" > "$REPLACE_ID_FILE"

total=$(echo "$REMAINING" | wc -l)
cn_log "[cleanup] instance=$ID promoted=$TARGET_ID notif=$NOTIF_ID remaining=$total"
