---
name: radars
description: How the tmux Git pane (git-radar) and Agents pane (agent-radar) work - samplers, curses feeds, pane keys, popups, agent state detection, notifications and ssh support.
when_to_use: Use when asked about the Git pane, git-radar, the Agents pane, agent-radar, agent detection (Claude Code, Copilot, Codex, Open Code) or agent states (waiting/working/done/idle), Telegram or desktop agent notifications, the agent summary in the status bar or session picker, or when editing anything in modules/git-radar or modules/agent-radar.
---

# git-radar and agent-radar

Two tools with the same architecture, both shown in the radar column of the standard tmux layout:

- **Git pane** (`modules/git-radar`): where each tmux session's repo stands (branch, ahead/behind, dirty). Opened with `prefix,R`.
- **Agents pane** (`modules/agent-radar`): which coding agent is waiting, working, done or idle, read off each agent pane's screen. Opened with `prefix,r`; popup picker `prefix,t,a`; status bar `●2●1`.

Each module's `README.md` is the deep reference (design reasons, ssh, states, rules). Read the relevant section rather than the whole file: they're 480 and 700 lines.

## Architecture (shared)

```
one detached sampler per machine (Start-GitRadar.py / Start-AgentRadar.py)
   └─ publishes a snapshot file (radar_cache.py: publish, read, flock liveness, spawn-if-missing)
        ├─ curses feed panes (Watch-GitFeed.py / Watch-AgentFeed.py, drawn with radar_ui.py)
        ├─ CLIs  (Get-GitState.py / Get-AgentState.py, --cached, --format=tsv|json|fzf|status)
        └─ status bar / session picker (Get-AgentSummary.sh, Select-Session.sh)
```

- Shared code is in `modules/tmux/scripts/`:
  - `radar_cache.py`: the snapshot file.
  - `radar_ui.py`: curses palette, two-line entries, banding, truncation, focus events.
  - `radar_remote.py`: the ssh poller thread per host.
  - `Request-RadarSample.sh`: the close hooks' "sample now".
- **ssh sessions** (`prefix,N`): the local radar asks the remote host's radar about that session's panes (`git_remote.py` / `agent_remote.py`, which run `--serve` there). New features must work for ssh-session rows too: that's a recurring request.
- Consumers never sample themselves. They read the snapshot, and the first one to notice the sampler is missing starts it.

## Git pane keys (`Watch-GitFeed.py`, the main key loop near the end)

| Key | Action |
|---|---|
| `j/k/g/G`, Enter | Move, jump to the session |
| `f/F` | Fetch |
| `p` / `P` | Pull / push |
| `c` | Commit (`Show-GitCommit.sh`) |
| `s` | Status (`Show-GitStatus.sh`) |
| `h` | History (`Show-GitHistory.sh`) |
| `m` | Merge (`Show-GitMerge.sh`) |
| `H` | Home session |
| `r` / `R` | Reload / restart |
| `q`/`d` | Quit |

- Popup actions follow one pattern: a `start_*`/`show_*` function runs a `Show-Git*.sh` script in a tmux popup from a worker thread. Copy an existing one (`show_status` is the simplest).
- Failures go through `failure_note` → `Show-GitFailure.sh`.
- Operation states appear as glyphs on the row, not words.

## Agents pane

- **Detection** is screen-based: `agent_radar.py` (identification, regions, gates, classification) with one TOML rule file per agent in `rules/`. `agent_feed.py` decides what gets published, the debounce, and the `done` state.
- **Rule loop:** see "Writing rules" / "The loop" in its README:
  1. `Show-AgentSnapshot.sh`: what the matcher sees.
  2. `Test-AgentRules.py`: why each rule did or didn't fire.
  3. Edit `rules/*.toml`. No restart needed.
  4. `Test-Fixtures.sh`: regression check over `fixtures/`. Run it after every rule change.
- **Claude Code hook** (optional second witness): `hooks/Set-AgentRadarState.sh`, registered by `Install-AgentRadarHooks.sh`.
- **Notifications** (`agent_notify.py`, `--test` to try it): fire when an agent enters `waiting`/`done`.
  - Actions: `telegram`, `desktop`, `tmux`. Each is on when its requirement is met. `AGENT_RADAR_NOTIFY=telegram,tmux` (or `off`) narrows them per machine. Set it in the untracked `~/.profile`/`~/.profile.ps1`, not in the repo. See the README's "Notifications" section.
  - Telegram needs `BOT_TOKEN` and `CHAT_ID` in the **sampler's** environment. The sampler is detached and started by whichever consumer notices it's missing, so check where that process got its environment when notifications don't arrive.

## Verifying

- Run the CLIs without tmux bindings: `Get-GitState.py [--cached] [--format=json]`, `Get-AgentState.py --format=tsv`.
- Restart a running pane with `R` in it, after code changes.
- Run `python3 -m py_compile` on edited files.
