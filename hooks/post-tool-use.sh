#!/bin/bash
# Hook: PostToolUse
# Clean up permission notification state after a tool use completes.

CN_DIR="${CN_DIR:-$HOME/.config/claude-notify}"
source "$CN_DIR/lib/common.sh"

ID=$(cn_instance_id)
[ -z "$ID" ] && exit 0
[ -f "$CN_STATE_DIR/$ID" ] || exit 0

bash "$CN_DIR/hooks/cleanup-instance.sh" "$ID"
