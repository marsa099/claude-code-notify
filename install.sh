#!/bin/bash
set -euo pipefail

# claude-code-notify installer (non-Nix)
# Copies scripts and configures Claude Code hooks in settings.json.

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

# Configure Claude Code hooks in settings.json
mkdir -p "$(dirname "$SETTINGS_FILE")"

HOOK_CMD_PREFIX="bash $INSTALL_DIR/hooks"

if [ -f "$SETTINGS_FILE" ]; then
    if grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
        echo "Hooks already configured — skipping settings.json."
    else
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
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
        echo "Hooks merged into $SETTINGS_FILE (backup at ${SETTINGS_FILE}.bak)"
    fi
else
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
echo "Installed! Optionally:"
echo "  - Create $INSTALL_DIR/config to override defaults (see config.example)"
echo "  - Add WM keybindings (see keybindings/ for examples)"
echo "  - Restart Claude Code to pick up the hooks"
