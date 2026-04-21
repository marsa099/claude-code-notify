#!/bin/bash
set -euo pipefail

# claude-code-notify installer
# Copies scripts, creates config, and configures Claude Code hooks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.config/claude-notify"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Installing claude-code-notify..."

# Copy files
mkdir -p "$INSTALL_DIR"/{lib,hooks,scripts,icons}
cp "$SCRIPT_DIR/lib/common.sh" "$INSTALL_DIR/lib/"
cp "$SCRIPT_DIR/hooks/"*.sh "$INSTALL_DIR/hooks/"
cp "$SCRIPT_DIR/scripts/"*.sh "$INSTALL_DIR/scripts/"
cp "$SCRIPT_DIR/icons/"* "$INSTALL_DIR/icons/" 2>/dev/null || true
chmod +x "$INSTALL_DIR/hooks/"*.sh "$INSTALL_DIR/scripts/"*.sh

# Create config if it doesn't exist
if [ ! -f "$INSTALL_DIR/config" ]; then
    cp "$SCRIPT_DIR/config.example" "$INSTALL_DIR/config"
    echo "Created config at $INSTALL_DIR/config — edit to match your setup."
else
    echo "Config already exists at $INSTALL_DIR/config — skipping."
fi

# Configure Claude Code hooks in settings.json
mkdir -p "$(dirname "$SETTINGS_FILE")"

HOOK_CMD_PREFIX="bash $INSTALL_DIR/hooks"

if [ -f "$SETTINGS_FILE" ]; then
    # Check if already configured
    if grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
        echo "Claude Code hooks already configured — skipping settings.json."
    else
        echo "Merging hooks into $SETTINGS_FILE..."
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
        # Merge hook entries
        jq --arg prefix "$HOOK_CMD_PREFIX" '
            .hooks //= {} |
            .hooks.PermissionRequest //= [] |
            .hooks.PostToolUse //= [] |
            .hooks.Notification //= [] |
            .hooks.PermissionRequest += [{
                "matcher": "",
                "hooks": [{"type": "command", "command": ("bash " + $prefix + "/permission-request.sh")}]
            }] |
            .hooks.PostToolUse += [{
                "matcher": "",
                "hooks": [{"type": "command", "command": ("bash " + $prefix + "/post-tool-use.sh")}]
            }] |
            .hooks.Notification += [{
                "matcher": "",
                "hooks": [{"type": "command", "command": ("bash " + $prefix + "/notification.sh")}]
            }]
        ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "Hooks merged. Backup at ${SETTINGS_FILE}.bak"
    fi
else
    # Create fresh settings.json
    jq -n --arg prefix "$HOOK_CMD_PREFIX" '{
        hooks: {
            PermissionRequest: [{
                matcher: "",
                hooks: [{type: "command", command: ("bash " + $prefix + "/permission-request.sh")}]
            }],
            PostToolUse: [{
                matcher: "",
                hooks: [{type: "command", command: ("bash " + $prefix + "/post-tool-use.sh")}]
            }],
            Notification: [{
                matcher: "",
                hooks: [{type: "command", command: ("bash " + $prefix + "/notification.sh")}]
            }]
        }
    }' > "$SETTINGS_FILE"
    echo "Created $SETTINGS_FILE with hooks."
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Edit $INSTALL_DIR/config (set your WM, notification backend, terminal)"
echo "  2. Add keybindings to your WM config (see keybindings/ for examples)"
echo "  3. Restart Claude Code to pick up the hooks"
