---
name: tmux-config
description: How this repo's tmux setup is built - prefix (C-Space) bindings, key tables, layouts, tool/picker panes, popups, ssh and Docker sessions, themes and the status bar.
when_to_use: Use when asked to add or change a tmux binding (written like `prefix,t,s` or `prefix+N`), a layout, a pane kind, a picker or popup, an ssh/remote session behavior, a tmux theme or status bar segment, or when editing anything in modules/tmux or modules/wsl2/tmux.conf.
---

# tmux configuration

## Files

| File | What lives there |
|---|---|
| `modules/tmux/common.conf` | Almost everything: options, every custom binding, hooks. Sections: terminal, behavior, prefix, pane navigation, number keys, fuzzy pickers, layouts and tool panes, key list, hooks, plugins |
| `modules/wsl2/tmux.conf` | Host entry point: sources common.conf, sets the theme and TPM, puts status segments after the window list |
| `modules/tmux/tmux.conf` | Container entry point: the same, with status segments prepended to `status-right` |
| `modules/tmux/native-overrides.conf` | Overrides inside the `native` table (prefix+C-b). Can't live in common.conf, see below |
| `modules/tmux/scripts/` | One script per binding. **Each opens with a header comment naming its binding and usage: read it first** |

The host's `~/.tmux.conf` is a local file that sources `~/.modules/wsl2/tmux.conf`. Since `~/.modules` links to the repo, edits take effect on reload: `prefix,u` (reload) or `prefix,U` (pull, then reload, via `Update-DevEnvironment.sh`).

## Key tables

- **Prefix is `C-Space`.** The prefix table is emptied and holds only the custom bindings.
- **tmux defaults live behind `prefix,C-b`** (the `native` table). `Set-NativeKeyTable.sh` copies them from a config-less tmux at load. Overriding a default there goes in `native-overrides.conf`, since a binding in common.conf would be overwritten.
- **`prefix,t`** opens the `custom-t-menu` table: agents, worktrees, scripts, pane jump.
- **`-` before the last key opens the pane below instead of on the right:** `custom-below-menu` and `custom-t-below-menu`. When you add a binding that opens a pane, also add its `-` variant (`New-ToolPane.sh -v`).
- **Every binding needs `-N "note"`.** `prefix,C-b,?` lists all tables, and a new table must also be added to that list in native-overrides.conf.
- **Root-table `C-h/j/k/l`** move between tmux panes and NeoVim splits (vim-tmux-navigator), including in ssh sessions.

## Building blocks (`scripts/tmux-helpers.sh`, sourced, never run)

- `new_pane` / `new_window`: every pane the bindings open goes through these.
- `pane_command <pane> <cmd>`: the command a new pane split off `<pane>` runs. It's `pwsh_invocation` locally (`PWSH_LEAN=1 pwsh -Command`, so the profile's environment is there) and `ssh_command` when `<pane>` belongs to an ssh session. Always build commands through it, so a binding works in ssh sessions with no extra code.
- `PANE_KINDS` / `pane_kind`: the kinds the picker pane offers (NeoVim, Terminal, Claude Code, Copilot, Codex, Open Code, Workhorse, Workhorse (builds), Paperboy, Scripts) and what each runs.
- `label_pane`: sets `@pane_label`, which layouts, zoom and pane jumping key on.
- `die` / `warn`: fail inside a popup (waits for a key press) or as a tmux message.
- `ssh-helpers.sh`: ssh sessions (`ssh_option`, `remote_run`, `ssh_command`, remote agent unlock). `worktree-helpers.sh`: the `prefix,t,w` worktree registry.

## Concepts you'll be asked about

- **Standard layout** (`Set-NeovimLayout.sh`): a narrow radar column on the left (Git feed above, Agents feed below, optional Notes pane) plus a **picker pane** (`Select-PaneKind.sh`) filling the rest. `-H` builds the home layout (Paperboy | Workhorse).
- **Opening panes:** pane bindings call either `Select-PaneKind.sh` (a pane kind or the picker: `prefix,e/E/Space/n/c`) or `New-ToolPane.sh` (a labelled command pane: agents, radars, project-specific .NET/Angular panes). Both close the pane when its command exits. `Restore-PickerPane.sh` puts a picker back when only the radars are left.
- **Popups:** every popup binding wraps its command in `Invoke-Popup.sh`, which keeps SpotlightDimmer's spotlight on the popup.
- **Sessions:**
  - `prefix,/`: a new project session under `~/code` (`New-CodeSession.sh`).
  - `prefix,N` / `prefix,C-n` (always asks for the host): an ssh session (`New-SshSession.sh`), where every pane is a shell on one remote host.
  - `prefix,D`: the same in a Docker container (`-D`, through `Invoke-Remote.sh`).
  - `prefix,?` / `prefix,C-p`: session picker (`Select-Session.sh`). `prefix,h`: home session.
- **Themes:** `Set-SshTheme.sh` recolors ssh (violet) and Docker (blue) sessions and restores the color when you switch back. `Set-PaneBackground.sh` makes backgrounds opaque only while a Termux client is attached.
- **Status bar:** segments are `#()` jobs. Optional ones are gated by user options that `Set-StatusSegments.sh` sets at config load (`@paperboy_enabled`, `@workhorse_enabled`).
- **Git and Agents panes** are separate modules: load the `radars` skill.

## Gotchas

- **TPM re-sources the config**, and so does every reload. `set -ag` / `-gwa` stack duplicates, so guard appends or assign the whole value.
- **tmux-power assigns `status-right` and the window formats when it loads.** Anything added to them goes *after* the `run '~/.tmux/plugins/tpm/tpm'` line, in both tmux.conf files.
- **Escaping:** inside `run-shell '... tmux set ... "##(...)"'`, use `##(` and `##{` to keep formats literal. A style's commas split a `#{?...}` conditional, so put styled segments in a user option and expand them with `#{E:@opt}`.
- **`run-shell -b`** is needed whenever the script calls back into tmux during config load.
- **The tmux server's environment doesn't include `~/.profile.ps1` variables** (tmux starts from bash). Read them through a lean pwsh, as `Start-PaperboyUnread.sh` and `Set-StatusSegments.sh` do.
- **Host and container both load common.conf.** A change to one entry point (wsl2/tmux.conf vs tmux/tmux.conf) usually needs a twin in the other.

## Testing

- Use a scratch server so the live session isn't disturbed:

  ```bash
  tmux -L test -f modules/wsl2/tmux.conf new -d -s t; sleep 3
  tmux -L test show -g status-right; tmux -L test list-keys -T custom-t-menu
  tmux -L test kill-server
  ```

- To check a script against the scratch server, run it through `tmux -L test run-shell '<script>'`.
- Check scripts with `bash -n`.
