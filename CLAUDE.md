# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

`claude-code-notify` is a small Bash project that turns Claude Code's permission
prompts into proper desktop notifications, with multi-instance support, focus
suppression, and inline action buttons (or keybindings as a fallback).

It is intentionally lightweight: pure Bash, no daemons of its own, and no
runtime state beyond a directory of small files in `/tmp/claude-permissions`.

## Repo map

- `lib/common.sh` — shared library, sourced by every hook and script. Owns the
  notification backend (`cn_notify`, `cn_notify_actions`, `cn_notify_close`),
  WM helpers (focus detection, window lookup), state helpers, and the
  notification body builder.
- `hooks/` — Claude Code hook entry points:
  - `permission-request.sh` — fires on `PermissionRequest`, saves state, sends
    the styled notification, starts a tmux watcher.
  - `post-tool-use.sh` — fires on `PostToolUse`, delegates to cleanup.
  - `notification.sh` — fires on Claude Code's built-in `Notification`, used
    for "waiting for input" prompts and as a no-op when a styled permission
    notification is already showing.
  - `cleanup-instance.sh` — shared cleanup: closes the notification, kills the
    tmux watcher, promotes the next pending instance if any.
- `scripts/` — user-facing scripts triggered by buttons or WM keybindings:
  - `respond.sh <1|2|3>` — Allow / Always Allow / Deny.
  - `navigate.sh` — cycle to the next pending notification.
  - `goto.sh` — focus the Claude instance.
- `keybindings/` — example WM configs (niri, sway, hyprland) for users who
  prefer keybindings over (or in addition to) the inline buttons.
- `icons/`, `config.example`, `flake.nix`, `install.sh`, `uninstall.sh` —
  packaging.

## Architecture in one paragraph

There is exactly one active styled notification at a time, identified by a
fixed `CN_NOTIF_ID` so every send replaces the previous one. Per-instance
state lives in `$CN_STATE_DIR` (`/tmp/claude-permissions/<pane-or-pty-id>`).
A pointer file `.last-navigate` tracks which instance is currently shown.
When an actions-capable backend is in use (`dunst` or `mako`), every
active-notification render also spawns a backgrounded listener (PID tracked
in `.listener.pid`) — `dunstify --action=...` on dunst, `notify-send --wait
-A ...` on mako — that blocks until the user picks an action and then
dispatches to `scripts/respond.sh|navigate.sh|goto.sh`. On the generic
backend the listener is skipped and keybinding hint text is rendered into
the notification body instead.

## Conventions

- **Bash style**: `#!/bin/bash`, prefer the existing `cn_` helpers over inline
  shelling out, log via `cn_log` rather than `echo`.
- **Single notification invariant**: only call `cn_notify_actions` (or
  `cn_notify` for transient/one-shot toasts) — never `dunstify`/`notify-send`
  directly. This keeps the replace-by-fixed-ID scheme intact.
- **Backend-agnostic features**: anything visible to the user must work on
  both `dunst` and `generic` backends. Use `cn_actions_supported` to branch.
- **State files** are tiny `key=value` lines parsed with `grep | cut`. Keep
  them that way; don't reach for jq.
- **No new runtime deps without strong reason.** Current deps are bash 4+,
  jq, a notification daemon (dunst, mako, or any libnotify-compatible), and
  (optionally) tmux / wtype / xdotool. The mako backend additionally needs
  libnotify 0.8+ (`notify-send --wait`) and `gdbus` (from `glib`).
- **Keep code lean.** No comments that restate the code. Add a comment only
  when the *why* is non-obvious (e.g., the self-kill avoidance in
  `cn_notify_actions`).

## Documentation rule (always)

When you change behaviour, defaults, install steps, or anything user-visible,
update **both** `README.md` and this `CLAUDE.md` in the same change. The user
should not have to ask for it. Specifically:

- New or changed config keys → `config.example` + `README.md` config table.
- New or changed install/update steps → `README.md` Install section + the
  relevant section below.
- New or changed user interaction (buttons, keybindings, behaviours) →
  `README.md` Keybindings/How-it-works + the architecture summary above.
- New or changed runtime deps → `README.md` Requirements + `flake.nix`
  `makeBinPath` if the dep needs to be on the wrapper PATH.

## OS / packaging notes

The project supports any Linux with a libnotify-compatible notification
daemon. There are two install paths and they must both keep working:

- **NixOS / Nix**: `flake.nix` builds a derivation that copies the project
  into `$out/share/claude-notify` and generates wrapped binaries in
  `$out/bin` (`claude-notify-permission-request`, `…-post-tool-use`,
  `…-notification`, `…-cleanup-instance`, `…-navigate`, `…-goto`,
  `…-respond`, `…-setup`). Wrappers set `CN_DIR` and `--prefix PATH` with
  `jq coreutils gnugrep tmux procps libnotify glib` (libnotify provides
  `notify-send` for the mako backend; glib provides `gdbus` for closing
  notifications on mako). `dunstify` is NOT on the wrapper PATH — the dunst
  backend relies on the system-installed `dunstify` (same as the daemon).
  Updates: `nix profile upgrade` (standalone) or `nixos-rebuild switch`
  after bumping the flake input. If you add a new hook/script that needs to
  run as a wrapped binary, add a matching `makeWrapper` line in
  `flake.nix`. If you add a new runtime command, add it to `makeBinPath`.
- **Other Linux (manual)**: `install.sh` copies `lib/`, `hooks/`,
  `scripts/`, `icons/` to `~/.config/claude-notify/`, chmods the scripts,
  and merges hook entries into `~/.claude/settings.json`. Updates: re-run
  `bash install.sh` from a fresh checkout — it overwrites scripts in place
  and skips `settings.json` if hooks are already configured. If you add a
  new directory or file under `lib/`, `hooks/`, or `scripts/`, make sure
  `install.sh` copies it (the current globs cover `*.sh` and the listed
  dirs).

Two actions-capable backends are supported: `dunst` (actions via context
menu / `do_action`) and `mako` (inline buttons). The listener mechanism is
gated on `cn_actions_supported`. The generic `notify-send` fallback
renders keybinding hint text into the body and relies on the user binding
`scripts/respond.sh|navigate.sh|goto.sh` in their WM. All three flows
must be preserved.

### Mako caveats

- `notify-send --wait` with action handling requires libnotify 0.8+ (2022).
  Older systems will simply never print an action key, so clicks won't
  dispatch — document that we need 0.8+.
- mako closes the notification itself on action invocation, so
  `cn_notify_close` only needs to fire for replace/cleanup flows. The
  implementation uses the portable `gdbus CloseNotification` call.
- The same fixed `CN_NOTIF_ID` is passed via `-r`, so mako replaces in
  place just like dunst.

## Useful one-liners

- Tail the log: `tail -f ~/.cache/claude/hooks.log`
- Inspect state: `ls -la /tmp/claude-permissions/`
- Reset state: `rm -rf /tmp/claude-permissions/*`
- Syntax-check a script: `bash -n path/to/script.sh`

## Things not to do

- Don't introduce per-notification IDs — the single-ID replace scheme is
  load-bearing for the navigate/promote flow.
- Don't `cn_notify_close` from inside a script that was itself invoked by the
  listener without first ensuring the listener has cleared its own PID file;
  see `cn_notify_actions` for the established pattern.
- Don't add backwards-compat shims for old config keys — change the key, bump
  `config.example`, document in README.
