{
  description = "Desktop notifications for Claude Code permission prompts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "claude-code-notify";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              mkdir -p $out/share/claude-notify/{lib,hooks,scripts,icons,keybindings}

              cp lib/common.sh $out/share/claude-notify/lib/
              cp hooks/*.sh $out/share/claude-notify/hooks/
              cp scripts/*.sh $out/share/claude-notify/scripts/
              cp -r icons/* $out/share/claude-notify/icons/ 2>/dev/null || true
              cp -r keybindings/* $out/share/claude-notify/keybindings/ 2>/dev/null || true
              cp config.example $out/share/claude-notify/
              cp install.sh uninstall.sh $out/share/claude-notify/

              chmod +x $out/share/claude-notify/hooks/*.sh
              chmod +x $out/share/claude-notify/scripts/*.sh

              # Create wrapper scripts in bin/
              mkdir -p $out/bin

              for hook in permission-request post-tool-use notification cleanup-instance; do
                makeWrapper ${pkgs.bash}/bin/bash $out/bin/claude-notify-$hook \
                  --set CN_DIR "$out/share/claude-notify" \
                  --add-flags "$out/share/claude-notify/hooks/$hook.sh" \
                  --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.tmux pkgs.procps ]}
              done

              for script in navigate goto respond; do
                makeWrapper ${pkgs.bash}/bin/bash $out/bin/claude-notify-$script \
                  --set CN_DIR "$out/share/claude-notify" \
                  --add-flags "$out/share/claude-notify/scripts/$script.sh" \
                  --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.tmux pkgs.procps ]}
              done

              # Setup script
              cat > $out/bin/claude-notify-setup <<'SETUP_EOF'
#!/bin/bash
set -euo pipefail

CN_SHARE_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")/share/claude-notify"
INSTALL_DIR="$HOME/.config/claude-notify"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Setting up claude-code-notify (Nix)..."

# Symlink share dir for hook access
mkdir -p "$INSTALL_DIR"
for dir in lib hooks scripts icons; do
    rm -rf "$INSTALL_DIR/$dir"
    ln -sf "$CN_SHARE_DIR/$dir" "$INSTALL_DIR/$dir"
done

# Create config if missing
if [ ! -f "$INSTALL_DIR/config" ]; then
    cp "$CN_SHARE_DIR/config.example" "$INSTALL_DIR/config"
    echo "Created config at $INSTALL_DIR/config — edit to match your setup."
else
    echo "Config exists at $INSTALL_DIR/config — skipping."
fi

# Configure Claude Code hooks
mkdir -p "$(dirname "$SETTINGS_FILE")"
HOOK_CMD_PREFIX="bash $INSTALL_DIR/hooks"

if [ -f "$SETTINGS_FILE" ]; then
    if grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
        echo "Hooks already configured — skipping."
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
echo "Done! Next steps:"
echo "  1. Edit $INSTALL_DIR/config"
echo "  2. Add keybindings (see: $CN_SHARE_DIR/keybindings/)"
echo "  3. Restart Claude Code"
SETUP_EOF
              chmod +x $out/bin/claude-notify-setup
            '';

            meta = with pkgs.lib; {
              description = "Desktop notifications for Claude Code permission prompts";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          };
        }
      );
    };
}
