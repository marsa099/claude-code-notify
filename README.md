# claude-code-notify

Desktop notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission prompts with multi-instance support.

When Claude Code needs permission to run a tool, you get a styled notification with tool details, and can respond via global keybindings — without switching to the terminal.

## Features

- Instant notification on permission requests (bypasses Claude Code's ~8s notification delay)
- Styled notifications showing tool name, command, file path, and description
- Multi-instance support: track and cycle through multiple pending permissions
- Global keybindings: Allow, Always Allow, Deny, Navigate, Go to instance
- Cross-session tmux navigation
- Smart suppression: no notification when the terminal is focused and visible
- Background watcher for cleanup when prompts are answered directly in the TUI

## Requirements

- **Linux** (Wayland or X11)
- **bash** 4+, **jq**
- **Notification daemon**: dunst (recommended, full support) or any libnotify-compatible daemon (basic support)
- **Optional**: tmux (multi-instance), wtype or xdotool (respond from outside terminal)

### Supported window managers

| WM | Focus detection | Go to instance |
|---|---|---|
| niri | Yes | Yes |
| sway / i3 | Yes | Yes |
| Hyprland | Yes | Yes |
| Other / none | No (always notifies) | tmux only |

### Supported terminals

Any terminal works. Set `CN_TERMINAL_APP_ID` in config to match yours:

| Terminal | App ID |
|---|---|
| Ghostty | `com.mitchellh.ghostty` |
| Alacritty | `Alacritty` |
| kitty | `kitty` |
| foot | `foot` |
| WezTerm | `org.wezfurlong.wezterm` |

## Install

### NixOS (flake)

Add to your `flake.nix` inputs:

```nix
claude-code-notify.url = "github:marsa099/claude-code-notify";
```

Add to system packages:

```nix
environment.systemPackages = [
  inputs.claude-code-notify.packages.${system}.default
];
```

Rebuild. Then configure Claude Code's hooks — either run `claude-notify-setup` or add them manually to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [{ "matcher": "", "hooks": [{ "type": "command", "command": "claude-notify-permission-request" }] }],
    "PostToolUse": [{ "matcher": "", "hooks": [{ "type": "command", "command": "claude-notify-post-tool-use" }] }],
    "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "claude-notify-notification" }] }]
  }
}
```

Finally, add WM keybindings using the wrapper binaries (e.g., `claude-notify-navigate`). See `keybindings/` for ready-to-use examples.

### Standalone Nix

```bash
nix profile install github:marsa099/claude-code-notify
claude-notify-setup  # or add hooks to settings.json manually (see above)
```

### Manual (non-Nix)

```bash
git clone https://github.com/marsa099/claude-code-notify.git
cd claude-code-notify
bash install.sh
```

The install script copies scripts to `~/.config/claude-notify/` and configures hooks in `~/.claude/settings.json`. Then add WM keybindings — see `keybindings/` for examples.

## Configuration

Configuration is optional — sensible defaults are built in (dunst, no WM detection).

To override defaults, create `~/.config/claude-notify/config` with only the settings you want to change. New settings added in updates automatically use their defaults without requiring config changes.

```bash
# Notification backend: dunst | generic
CN_NOTIFY_BACKEND=dunst

# Window manager: niri | sway | hyprland | none
CN_WM_BACKEND=niri

# Terminal app ID
CN_TERMINAL_APP_ID=com.mitchellh.ghostty

# Input method for non-tmux response: wtype | xdotool
CN_INPUT_METHOD=wtype

# Keybinding labels (cosmetic — shown in notifications)
CN_KEY_ALLOW="Ctrl+Super+Y"
CN_KEY_ALWAYS_ALLOW="Ctrl+Super+A"
CN_KEY_DENY="Ctrl+Super+N"
CN_KEY_NEXT="Ctrl+Super+P"
CN_KEY_GOTO="Ctrl+Super+O"
```

## Keybindings

The notification shows keybinding hints. You need to configure matching keybindings in your WM. See `keybindings/` for ready-to-use examples for niri, sway, and Hyprland.

| Action | Default | Description |
|---|---|---|
| Allow | `Ctrl+Super+Y` | Accept the permission request |
| Always Allow | `Ctrl+Super+A` | Always allow this tool |
| Deny | `Ctrl+Super+N` | Deny the request |
| Next | `Ctrl+Super+P` | Cycle to next pending notification |
| Go to | `Ctrl+Super+O` | Focus the Claude instance |

## How it works

Claude Code fires hook events that trigger shell scripts:

1. **PermissionRequest** fires instantly when Claude needs permission. The hook saves tool info, builds a styled notification, and starts a background watcher.
2. **PostToolUse** fires after a tool completes. The hook cleans up the notification and promotes the next pending instance.
3. **Notification** is Claude Code's built-in notification (delayed ~8s). The hook suppresses it when a styled permission notification is already showing.
4. The **background watcher** monitors the tmux pane for the permission prompt disappearing — handling the case where the user responds directly in the TUI.

## Adding a notification backend

To add support for a new notification daemon, edit `lib/common.sh` and add a case to `cn_notify`, `cn_notify_close`, and `cn_notify_transient`. The backend needs to support:

- Sending notifications with urgency and timeout
- Returning a notification ID (for close/replace support)
- Closing notifications by ID

## License

MIT
