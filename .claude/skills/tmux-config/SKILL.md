---
name: tmux-config
description: How this repo's tmux setup is built - prefix (C-Space) bindings, key tables, layouts, tool/picker panes, popups, ssh and Docker sessions, themes and the status bar.
when_to_use: Use when asked to add or change a tmux binding (written like `prefix,t,s` or `prefix+N`), a layout, a pane kind, a picker or popup, an ssh/remote session behavior, a tmux theme or status bar segment, or when editing anything in modules/tmux or modules/wsl2/tmux.conf.
---

# tmux configuration

## Files

| File | What lives there |
|---|---|
| `modules/tmux/common.conf` | Almost everything: options, every custom binding, hooks. Sections: terminal, behavior, prefix, pane navigation, number keys, fuzzy pickers, layouts and tool panes, key list, hooks, theme and status bar |
| `modules/wsl2/tmux.conf` | Host entry point: sets the theme, sources common.conf, puts the Workhorse segment after the window list |
| `modules/tmux/tmux.conf` | Container entry point: the same, with the Workhorse segment in `status-right` |
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
- `PANE_KINDS` / `pane_kind`: the kinds the picker pane offers (NeoVim, Terminal, Claude Code, Copilot, Codex, Open Code, Workhorse, Workhorse (builds), Paperboy, DadBod (database), Scripts) and what each runs.
- `label_pane`: sets `@pane_label`, which layouts, zoom and pane jumping key on.
- `die` / `warn`: fail inside a popup (waits for a key press) or as a tmux message.
- `ssh-helpers.sh`: ssh sessions (`ssh_option`, `remote_run`, `ssh_command`, remote agent unlock). `worktree-helpers.sh`: the `prefix,t,w` worktree registry. `link-helpers.sh`: linked machines (`link_probe`, `link_make`, `open_on_peer`).

## Concepts you'll be asked about

- **Standard layout** (`Set-NeovimLayout.sh`): a narrow radar column on the left (Git feed above, Agents feed below, optional Notes pane) plus a **picker pane** (`Select-PaneKind.sh`) filling the rest. `-H` builds the home layout (Paperboy | Workhorse, both always, configured or not).
- **Opening panes:** pane bindings call either `Select-PaneKind.sh` (a pane kind or the picker: `prefix,e/E/Space/n/c`) or `New-ToolPane.sh` (a labelled command pane: agents, radars, project-specific .NET/Angular panes). Both close the pane when its command exits. `Restore-PickerPane.sh` puts a picker back when only the radars are left.
- **Popups:** every popup binding wraps its command in `Invoke-Popup.sh`, which keeps SpotlightDimmer's spotlight on the popup.
- **Sessions:**
  - `prefix,/`: a new project session under `~/code` (`New-CodeSession.sh`).
  - `prefix,N` / `prefix,C-n` (always asks for the host): an ssh session (`New-SshSession.sh`), where every pane is a shell on one remote host. Named `<host>-<dir>`, or `user@<host>-<dir>` while two users have sessions on that host (`ssh_session_name`; `Rename-SshSessions.sh` renames the open ones on open and on session-closed). Look a session up with `open_session_named`, not by its exact name.
  - `prefix,D`: the same in a Docker container (`-D`, through `Invoke-Remote.sh`).
  - **Linked machines** replace ssh sessions for a host that has this dev-environment: `prefix,N` links the two machines instead (`link_probe` decides; any other host still gets an ssh session). Each machine keeps its own tmux server; the peer's sessions show in `prefix,?`, the Git and Agents panes, and its first-level code folders in `prefix,/`, all in grey. `prefix,t,l` lists the links and removes one.
    - `tmux_link.py` is the library (identity `user@hostname`, the peers file `~/.config/tmux-link/peers`, `--serve` over ssh); `Start-TmuxLink.py` the sampler on the radars' cache; `Get-TmuxLink.py` the CLI.
    - A peer's session is named `<host>:<session>` everywhere. **Never `switch-client` to a picked session: call `Switch-LinkSession.sh <key> [pane]`**, which switches locally or, for a peer key, runs `detach-client -E "Connect-Tmux.sh --handoff …"`.
    - `Connect-Tmux.sh` is the loop around the tmux client (vtmux, tmuxa, and `tmux-link` on Termux run it instead of `tmux attach`): on a handoff it attaches locally or over one ssh to the other machine, so the device being typed on is never more than one ssh away. That holds only while the loop runs on the device: started in an ssh login on a machine (`ssh -t <host> "pwsh -C vtmux"`), it makes the hops from there, and it says so (`… is a second ssh hop away`) before each one. The phone's clipboard sockets reach only the machine it ssh's into, so on Termux use `tmux-link`. A device reaches an identity through `~/.config/tmux-link/aliases`, then `peers`, then the identity itself. A machine with no tmux sessions at all answers `--remote` with exit 3 (a group's current session can outlive its server), and the loop goes back to the local tmux as it does for a lost connection.
    - **SpotlightDimmer** follows the panes of a linked machine's tmux through a second ssh the loop runs beside the first (`Connect-Tmux.sh --spotlight <id>` there, piped into SpotlightDimmer's `spotlight-dimmer-tmux-relay.sh receive` here). The title's `sd:#{client_tty}@#{host_short}` is what tells the daemon the client is on another machine. Both machines need SpotlightDimmer's tools (`make install-tools` in `~/code/spotlight-dimmer/SpotlightDimmer.LinuxDaemon`).
    - A folder picked on a peer is opened there by `New-CodeSession.sh -d` over ssh (`create_on_peer`/`open_on_peer`), then the client hops. `New-CodeSession.sh -d` with no directory is the same picker from outside tmux: vtmux's when no tmux is running (it opens the home session beside the pick), printing the session (preceded by the peer's identity for a linked folder) for the caller to attach to.
    - **Groups** (`Sync-LinkGroup.sh`): a current and a previous session spanning the linked machines, per group name, in `~/.cache/tmux-link/groups/<group>` on each machine (sessions written `<host>:<session>`, own host included; newest stamp wins). `prefix,l`/`L`/`Tab` swap them (`last`). A terminal's group comes from `Connect-Tmux.sh -g`, else `~/.config/tmux-link/group` on the device, else `shared`; it rides the tmux client's environment as `TMUX_LINK_GROUP` and is read back from `/proc/<client_pid>/environ`. **Recording is the `client-session-changed`/`client-attached` hooks' job (`record ##{hook_client}`, since `#{client_name}` is the wrong client for a `switch-client -c` from a script): nothing that switches records anything itself.** A record moves the group's other local clients and is pushed to every peer over ssh (`receive`), whose clients follow. An attach naming no session goes to the group's current one; `current` drops it when it is gone, asking a peer with a plain `tmux has-session` over ssh (works against an older peer; an unreachable one is left to the attach).
  - On every client arrival, `Sync-SshClientTerminal.sh` writes the client's terminal (name, Sixel, passthrough, cell size) to a file on the remote, which the panes find through `$TMUX_CLIENT_TERMINAL`. A remote nvim can't ask this tmux, and DA1 is answered by tmux itself (always Sixel), so paperboy.nvim's image previews read this file instead.
  - `prefix,?` / `prefix,C-p`: session picker (`Select-Session.sh`). `prefix,h`: home session.
- **Themes:** `Set-Theme.sh` draws the powerline bar and every theme colour from `@theme` (a name or `#rrggbb`, set by each entry point *before* it sources common.conf). There are no tmux plugins. `Set-SshTheme.sh` recolors ssh (violet) and Docker (blue) sessions and restores the color when you switch back. `Set-PaneBackground.sh` makes backgrounds opaque only while a Termux client is attached.
- **Status bar:** `Set-Theme.sh` builds it from user options expanded at draw time: `@status_left_host`, `@status_right_lead`, `@status_right_inner`, `@status_right_outer`, `@status_after_windows` (after the session:window), and `@toast` first in status-right. Change a segment by setting its option, anywhere in the config; don't append to `status-left`/`status-right` or the window formats. Segments are `#()` jobs. Optional ones are gated by user options that `Set-StatusSegments.sh` sets at config load (`@paperboy_enabled`, `@workhorse_enabled`). `prefix,C-k` (`Select-StatusSource.sh`) can point the Workhorse and Paperboy segments at an ssh session's host (`@status_source`): `Get-RemoteStatus.sh` then runs that host's own segment scripts over the session's connection, in its profile's environment (`remote_profile_command`); choosing a host also starts its Paperboy daemon. Toasts and the agent count always stay local.
- **Git and Agents panes** are separate modules: load the `radars` skill.

## Gotchas

- **Every reload re-sources the config.** `set -ag` / `-gwa` stack duplicates, so guard appends or assign the whole value.
- **`Set-Theme.sh` assigns the status formats and theme styles at every load** (at the end of common.conf). Theme colours written anywhere else get overwritten; per-session colours go through `Set-Theme.sh -t <session> <colour>`.
- **Escaping:** inside `run-shell '... tmux set ... "##(...)"'`, use `##(` and `##{` to keep formats literal. A style's commas split a `#{?...}` conditional, so put styled segments in a user option and expand them with `#{E:@opt}`.
- **`run-shell -b`** is needed whenever the script calls back into tmux during config load.
- **One ssh-agent per machine** at `~/.ssh/tmux-agent/agent.sock` (`Unlock-SshAgent.sh`): every pane gets that socket from the server's global environment (`SSH_AUTH_SOCK`/`SSH_AGENT_PID` are kept out of `update-environment`, so an attaching client never replaces it), the pwsh profile points at it, and an ssh session's panes on a host use that host's one. It ends only by its 12h lifetime; nothing kills it on session close.
- **An ssh in a popup must not inherit the popup's terminal** unless it is there to ask something. Over a shared connection (`SSH_OPTS`) ssh hands its stdin, stdout and stderr to the master, and a master whose network went away keeps them open after the script is gone: tmux then leaves the popup up with nobody in it, every key echoed (`^[`, `^C`) until the master gives up. Redirect all three, and wait through `run_cancellable` in `New-SshSession.sh` (Esc, Ctrl+C, a time limit, and the command ended as a group).
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
