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

              # Setup script — only configures ~/.claude/settings.json
              cat > $out/bin/claude-notify-setup <<'SETUP_EOF'
#!/bin/bash
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Setting up claude-code-notify..."

# Configure Claude Code hooks in settings.json
mkdir -p "$(dirname "$SETTINGS_FILE")"

if [ -f "$SETTINGS_FILE" ]; then
    if grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
        echo "Hooks already configured in $SETTINGS_FILE — nothing to do."
        exit 0
    fi
    cp "$SETTINGS_FILE" "''${SETTINGS_FILE}.bak"
    jq '
        .hooks //= {} |
        .hooks.PermissionRequest //= [] |
        .hooks.PostToolUse //= [] |
        .hooks.Notification //= [] |
        .hooks.PermissionRequest += [{
            "matcher": "",
            "hooks": [{"type": "command", "command": "claude-notify-permission-request"}]
        }] |
        .hooks.PostToolUse += [{
            "matcher": "",
            "hooks": [{"type": "command", "command": "claude-notify-post-tool-use"}]
        }] |
        .hooks.Notification += [{
            "matcher": "",
            "hooks": [{"type": "command", "command": "claude-notify-notification"}]
        }]
    ' "$SETTINGS_FILE" > "''${SETTINGS_FILE}.tmp" && mv "''${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "Hooks merged into $SETTINGS_FILE (backup at ''${SETTINGS_FILE}.bak)"
else
    jq -n '{
        hooks: {
            PermissionRequest: [{
                matcher: "",
                hooks: [{type: "command", command: "claude-notify-permission-request"}]
            }],
            PostToolUse: [{
                matcher: "",
                hooks: [{type: "command", command: "claude-notify-post-tool-use"}]
            }],
            Notification: [{
                matcher: "",
                hooks: [{type: "command", command: "claude-notify-notification"}]
            }]
        }
    }' > "$SETTINGS_FILE"
    echo "Created $SETTINGS_FILE with hooks."
fi

echo ""
echo "Done! Optionally:"
echo "  - Create ~/.config/claude-notify/config to override defaults (see config.example)"
echo "  - Add WM keybindings for navigate/goto/respond (see keybindings/)"
echo "  - Restart Claude Code to pick up the hooks"
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
