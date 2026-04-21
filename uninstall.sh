#!/bin/bash
set -euo pipefail

# claude-code-notify uninstaller

INSTALL_DIR="$HOME/.config/claude-notify"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Uninstalling claude-code-notify..."

# Remove hook entries from settings.json
if [ -f "$SETTINGS_FILE" ] && grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
    jq '
        if .hooks then
            .hooks |= with_entries(
                .value |= map(
                    .hooks |= map(select(.command | test("claude-notify") | not))
                ) | map(select(.hooks | length > 0))
            ) |
            .hooks |= with_entries(select(.value | length > 0))
        else . end |
        if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "Removed hooks from $SETTINGS_FILE (backup at ${SETTINGS_FILE}.bak)"
fi

# Clean up state
rm -rf /tmp/claude-permissions

# Remove installed files (keep config for potential reinstall)
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR/lib" "$INSTALL_DIR/hooks" "$INSTALL_DIR/scripts" "$INSTALL_DIR/icons"
    echo "Removed scripts from $INSTALL_DIR"
    echo "Config preserved at $INSTALL_DIR/config (delete manually if unwanted)"
fi

echo "Uninstall complete."
