# claude-code-notify

Desktop notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission prompts with multi-instance support.

When Claude Code needs permission to run a tool, you get a styled notification with tool details, and can respond via global keybindings — without switching to the terminal.

## Features

- Instant notification on permission requests (bypasses Claude Code's ~8s notification delay)
- Styled notifications showing tool name, command, file path, and description
- **Inline action buttons** on dunst — Allow / Always Allow / Deny / Next / Go to — no keybindings required
- Optional global keybindings as an alternative or fallback (and the only option on non-dunst backends)
- Multi-instance support: track and cycle through multiple pending permissions
- Cross-session tmux navigation
- Smart suppression: no notification when the terminal is focused and visible
- Background watcher for cleanup when prompts are answered directly in the TUI

## Requirements

- **Linux** (Wayland or X11)
- **bash** 4+, **jq**
- **Notification daemon**: dunst (recommended — full support including clickable action buttons) or any libnotify-compatible daemon (basic support, keybindings only)
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

Rebuild (and on later updates, bump the flake input and `nixos-rebuild switch` — or `nix profile upgrade` for the standalone flow). Then configure Claude Code's hooks — either run `claude-notify-setup` or add them manually to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [{ "matcher": "", "hooks": [{ "type": "command", "command": "claude-notify-permission-request" }] }],
    "PostToolUse": [{ "matcher": "", "hooks": [{ "type": "command", "command": "claude-notify-post-tool-use" }] }],
    "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "claude-notify-notification" }] }]
  }
}
```

On dunst that's all you need — the notifications already carry clickable buttons. WM keybindings are optional (and required only on non-dunst daemons); see `keybindings/` for ready-to-use examples that bind the wrapper binaries (e.g. `claude-notify-respond 1`, `claude-notify-navigate`).

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

The install script copies scripts to `~/.config/claude-notify/` and configures hooks in `~/.claude/settings.json`. To update later, `git pull` and re-run `bash install.sh` from the same checkout — it overwrites the installed scripts in place and skips `settings.json` if hooks are already wired up.

On dunst the notifications are clickable out of the box. On other daemons (or if you prefer keys), add WM keybindings — see `keybindings/` for examples.

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

## Responding to a notification

There are two ways to respond, and you can use either or both.

### 1. Inline action buttons (dunst only, default)

On the dunst backend the notification ships with clickable actions: **Allow**,
**Always Allow**, **Deny**, **Next**, **Go to** (or **Yes** / **No** for
yes/no prompts; **Go to** / **Next** for waiting-for-input prompts).

How buttons surface depends on your `dunstrc`. Common setups:

- Default dunst — actions are accessible via the **context menu** (right click
  by default, or `dunstctl context`).
- For a one-click "Allow" experience, bind the default mouse action to
  `do_action`:
  ```
  # ~/.config/dunst/dunstrc
  mouse_left_click = do_action, close_current
  ```
- Some launchers (e.g. `rofi -dmenu`) integrate via `dunstctl context` for a
  pop-up picker.

When the active backend is `generic` (any non-dunst libnotify daemon),
buttons aren't supported — use keybindings instead.

### 2. Global WM keybindings (optional, fallback)

You can configure your WM to invoke the same scripts via keybindings. This is
required on the `generic` backend and useful as a faster alternative on
dunst. See `keybindings/` for ready-to-use examples for niri, sway, and
Hyprland.

| Action | Default key | Description |
|---|---|---|
| Allow | `Ctrl+Super+Y` | Accept the permission request |
| Always Allow | `Ctrl+Super+A` | Always allow this tool |
| Deny | `Ctrl+Super+N` | Deny the request |
| Next | `Ctrl+Super+P` | Cycle to next pending notification |
| Go to | `Ctrl+Super+O` | Focus the Claude instance |

The labels above are displayed inside the notification body **only** on the
`generic` backend (since dunst already shows them as buttons). Override them
in `~/.config/claude-notify/config` via `CN_KEY_*`.

## How it works

Claude Code fires hook events that trigger shell scripts:

1. **PermissionRequest** fires instantly when Claude needs permission. The hook saves tool info, builds a styled notification, and starts a background watcher.
2. **PostToolUse** fires after a tool completes. The hook cleans up the notification and promotes the next pending instance.
3. **Notification** is Claude Code's built-in notification (delayed ~8s). The hook suppresses it when a styled permission notification is already showing.
4. The **background watcher** monitors the tmux pane for the permission prompt disappearing — handling the case where the user responds directly in the TUI.
5. On dunst, every active-notification render also spawns a backgrounded `dunstify` **action listener** (PID tracked in `/tmp/claude-permissions/.listener.pid`) that blocks until the user picks a button and then dispatches to `respond.sh` / `navigate.sh` / `goto.sh`. Replacing or closing the notification kills the previous listener so only one is ever live at a time.

## Adding a notification backend

To add support for a new notification daemon, edit `lib/common.sh` and add a case to `cn_notify`, `cn_notify_close`, and `cn_notify_transient`. The backend needs to support:

- Sending notifications with urgency and timeout
- Returning a notification ID (for close/replace support)
- Closing notifications by ID

To also enable inline action buttons on the new backend, extend
`cn_actions_supported` to return 0 for it and add a backend-specific branch
to `cn_notify_actions` (the dunst path is the reference implementation —
spawn a backgrounded listener, write its PID to `$CN_LISTENER_PID_FILE`,
clear that PID file before dispatching to a script so the dispatched
`cn_notify_close` doesn't kill its own parent shell).

## License

MIT
