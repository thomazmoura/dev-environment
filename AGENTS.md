# AGENTS.md

Personal dotfiles + dev environment. Each tool is a folder in `modules/`, deployed to a Docker image (Debian trixie), to an Ubuntu/WSL2 host (`~/.modules` → this repo's `modules/`, so edits take effect without re-running setup), and to Dev Containers. There are no tests and no build step locally.

## Where things are

| When asked about | Look in | Details |
|---|---|---|
| tmux bindings (`prefix,t,s`, `prefix+N`), layouts, picker/tool panes, popups, ssh/Docker sessions, status bar | `modules/tmux/` (`common.conf` + `scripts/`), `modules/wsl2/tmux.conf` | `.claude/skills/tmux-config/SKILL.md` |
| Git pane / git-radar, Agents pane / agent-radar, agent notifications | `modules/git-radar/`, `modules/agent-radar/` | `.claude/skills/radars/SKILL.md` |
| NeoVim, the Notes pane, Workhorse/Paperboy in NeoVim | `modules/nvim-config/` | `.claude/skills/nvim-config/SKILL.md` |
| Dockerfiles, CI, `host-setup.sh`, symlinks, new modules/tools/LSP servers | `*Dockerfile`, `LinuxDevEnv/`, `modules/entrypoint-config/` | `.claude/skills/deploy/SKILL.md` |
| PowerShell profile and its environment (`~/.profile.ps1`) | `modules/powershell-config/` | |
| Script library (`prefix,s`) | `modules/scripts/` | its `README.md` |
| Global Claude Code skills (linked into `~/.claude/skills`) | `modules/skills/` | |

Read the matching skill file before changing an area (Claude Code loads it automatically).

## Rules

- **Language:** PowerShell for new module scripts, bash where a tool or tmux needs it. Every setup script is idempotent.
- **Header comments:** scripts open with a comment saying what they're for and which binding calls them. Keep them accurate, and match the surrounding comment style.
- **Platforms:** Docker scripts must work on Debian. Host-only, machine-specific setup goes in its own script in `LinuxDevEnv/`.
- **Never:**
  - commit binaries or downloaded artifacts;
  - edit `.docker-variables`;
  - move or rename a module without updating every reference to it (see the deploy skill).
