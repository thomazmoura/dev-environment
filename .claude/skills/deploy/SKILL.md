---
name: deploy
description: How dev-environment is installed and published - Dockerfiles, CI, host-setup.sh, the dotfile symlink map, adding a module, tool or LSP server.
when_to_use: Use when changing base.Dockerfile, Dockerfile, qmk-base.Dockerfile, .github/workflows, LinuxDevEnv/host-setup.sh, WSL2/container startup (Start-DevSession.ps1), the ~/.storage persistence, or when adding a new module, tool, dotfile symlink or language server.
---

# Deploying dev-environment

The same `modules/` are deployed three ways:

1. **Docker images**, built by CI and pushed to Docker Hub as `thomazmoura/dev-environment`.
2. **Physical Linux host / WSL2**: `LinuxDevEnv/host-setup.sh` sets up an Ubuntu 24.04 machine and symlinks `~/.modules` to `<repo>/modules/`, so changes to the repo take effect without re-running setup.
3. **Dev Containers**: `.devcontainer/` for VS Code / Codespaces.

There are no local tests and no compile step. The Docker build is the test:

```bash
docker build --build-arg DockerBase=thomazmoura/dev-environment:base -f Dockerfile .
```

## Key files

| File | Role |
|---|---|
| `base.Dockerfile` | Stage 1: apt packages, PowerShell, .NET, NeoVim, debugger |
| `Dockerfile` | Stage 2: Node, Azure CLI, tmux, LSP, dotfile symlinks, `modules/skills` → `~/.claude/skills` |
| `qmk-base.Dockerfile` | Stage 3 (optional): QMK + Rust on top of base |
| `LinuxDevEnv/host-setup.sh` | Master setup for a bare Ubuntu 24.04 host |
| `modules/entrypoint-config/Start-DevSession.ps1` | Container startup: folders, certs, dotfile symlinks, dotnet tools |
| `modules/wsl2/Start-DevSession.ps1` | WSL2 session startup (subset of the container entrypoint) |
| `.docker-variables` | Template env vars (git identity, Azure org, cert paths). Never edit: users fill in their own copy |
| `.github/workflows/main.yml` | CI: builds and pushes every tag on push |

## Image layers

```
base.Dockerfile  →  :base  →  Dockerfile  →  :latest
                      ↓
              qmk-base.Dockerfile  →  :qmk_base  →  Dockerfile  →  :qmk
```

`Dockerfile` and `qmk-base.Dockerfile` take a `DockerBase` build arg that picks the upstream image.

CI behavior:
- `main` publishes `:base`, `:latest`, `:qmk_base` and `:qmk`.
- Other branches publish branch-namespaced tags (`/` → `_`).
- Every stage uses `--cache-from` against the last published tag.
- Needs the `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets.

## Symlink map (Docker and host)

| Link | Target in `modules/` |
|---|---|
| `~/.local/share/nvim/site` | `vim/` (spell and swap files only) |
| `~/.vim` | `~/.local/share/nvim/site` |
| `~/.config/nvim` | `nvim-config/` |
| `~/.config/powershell` | `powershell-config/` |
| `~/.shell` | `shell/` |
| `~/.config/herdr/config.toml` | `herdr/config.toml` |
| `~/.config/ghostty` | `ghostty/` |
| `~/.wezterm.lua` | `wezterm/wezterm.lua` |
| `~/.claude/skills/<name>` | `skills/<name>/` (global skills, for every project) |
| `~/.modules` | `modules/` (host symlink, or the Docker COPY) |

On the host, `~/.tmux.conf` is a local file that sources `~/.modules/wsl2/tmux.conf`. The container uses `modules/tmux/tmux.conf`.

## Environment and persistence

- System-wide variables (timezone, locale, TERM) go in `/etc/environment` on the host, or in Dockerfile `ENV` lines.
- Per-user variables go in `~/.profile.ps1`, which `host-setup.sh` creates and the PowerShell profile dot-sources. In the container it's `~/.storage/powershell/profile.ps1`.
- In the container, `~/.storage` is the persistent volume. `.storage/ssh`, `.storage/azure`, `.storage/dotnet-tools` and similar are symlinked from their usual home locations.
- `~/.shared` holds the ASP.NET localhost certificate shared with the host.

## Recipes

- **New tool:**
  1. Create `modules/<tool>/` with an install script (PowerShell unless the tool's own installer needs bash).
  2. Add a `COPY` line to `Dockerfile`, or to `base.Dockerfile` if it needs root.
  3. Add a `pwsh -File` call to `LinuxDevEnv/host-setup.sh`.
- **Moving or renaming a module:** update `base.Dockerfile`, `Dockerfile`, `qmk-base.Dockerfile`, `LinuxDevEnv/host-setup.sh` and `LinuxHost/Setup-PowerShell.ps1`.
- **New LSP server:**
  1. Download the binary into `~/.language-servers/` from `modules/neovim-lsp/Setup-NeoVimLSP.ps1`. npm servers go in the package list of `Install-LanguageServerNodePackages.ps1` instead: they install into `~/.language-servers/node` with their own node, and `lsp.lua` starts them through `node_server(...)`, so they never run on a project's `.node-version`.
  2. Configure the server in `modules/nvim-config/lua/plugins/lsp.lua` and add its name to `vim.lsp.enable`.
  3. Angular 11–14 is a special case. `lsp.lua` reads the `@angular/core` major and runs that major's ngserver from `~/.language-servers/angular/<major>` on node 14. `Install-AngularLanguageServer.ps1` installs it in the background the first time such a project opens. Angular < 11 gets only `ts_ls`.
- **Host-only utility** (terminal emulators, display tweaks, systemd services, hardware): put it in its own script in `LinuxDevEnv/`, not in `host-setup.sh`, and not in the image.

## Rules

- Docker scripts must work on Debian trixie. Host-only scripts can target Ubuntu 24.04.
- Scripts are idempotent: check before acting (`if ! grep -q ...`, `if (!(Test-Path ...))`).
- Never commit binaries or downloaded artifacts (`.deb`, `.tar.gz`). Download them at build or setup time.
