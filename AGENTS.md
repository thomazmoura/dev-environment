# AGENTS.md

Guidance for AI agents (Claude Code, Codex, or similar) working in this repository.

## What this repo is

A personal dotfiles + development environment repo. The same configuration is deployed three ways:

1. **Docker images** — built by CI and published to Docker Hub as `thomazmoura/dev-environment`.
2. **Physical Linux host** — `LinuxDevEnv/host-setup.sh` applies the same setup to an Ubuntu 24.04 machine and symlinks `modules/` into `~/.modules`.
3. **Dev Containers** — `.devcontainer/` definitions for VS Code / GitHub Codespaces.

There are no application tests and no compilation step to run locally. The only "tests" are the Docker builds triggered by CI.

## The module system — the central concept

`modules/` is the heart of the repo. Every tool has its own subdirectory with the scripts or config files for that tool. A module may contain:

- A PowerShell script (`*.ps1`) that installs or configures the tool.
- A shell script (`*.sh`) for tools that need bash.
- Config files (vimrc, tmux.conf, profile, etc.) that get symlinked into place.

**Docker** — each module is `COPY`-ed into the image at its relevant build stage.

**Linux host / WSL2** — `host-setup.sh` creates a single symlink `~/.modules → <repo>/modules/` and then calls into each module's setup script. Changes committed to the repo are immediately reflected in a running host session without re-running setup.

Do not move or rename modules without updating every place they are referenced: `base.Dockerfile`, `Dockerfile`, `qmk-base.Dockerfile`, `LinuxDevEnv/host-setup.sh`, and `LinuxHost/Setup-PowerShell.ps1`.

## Key files

| File | Role |
|---|---|
| `base.Dockerfile` | Stage 1 Docker image: apt packages, PowerShell, .NET, NeoVim, debugger |
| `Dockerfile` | Stage 2 Docker image: Node, vim-plug, Azure CLI, tmux, LSP, dotfile symlinks |
| `qmk-base.Dockerfile` | Stage 3 (optional): QMK + Rust on top of base |
| `LinuxDevEnv/host-setup.sh` | Master setup script for a bare Ubuntu 24.04 host |
| `modules/entrypoint-config/Start-DevSession.ps1` | Container startup: folders, certs, dotfile symlinks, dotnet tools |
| `modules/wsl2/Start-DevSession.ps1` | WSL2 session startup (subset of the container entrypoint) |
| `modules/vim/` | All NeoVim config: vimrc, Lua files, keybindings, plugin settings |
| `modules/nvim-config/init.vim` | NeoVim entry point (sources `modules/vim/vimrc`) |
| `modules/powershell-config/` | PowerShell profiles and Oh My Posh theme |
| `modules/shell/` | Bash config, global gitignore, inputrc, git setup scripts |
| `modules/neovim-plug/plug.vimrc` | vim-plug plugin list |
| `.docker-variables` | Template for environment variables (git identity, Azure org, cert paths) |
| `.github/workflows/main.yml` | CI: builds and pushes all Docker tags on push |

## Config symlink map

When setup runs, these symlinks are created (both in Docker and on the host):

| Symlink | Target inside `modules/` |
|---|---|
| `~/.local/share/nvim/site` | `vim/` |
| `~/.vim` | `~/.local/share/nvim/site` |
| `~/.config/nvim` | `nvim-config/` |
| `~/.config/powershell` | `powershell-config/` |
| `~/.shell` | `shell/` |
| `~/.modules` | `modules/` (host symlink) or the directory itself (Docker COPY) |

## Docker image layers

```
base.Dockerfile  →  :base
                        ↓
                    Dockerfile  →  :latest   (main dev image)
                        ↓
                    qmk-base.Dockerfile  →  :qmk_base  →  Dockerfile  →  :qmk
```

The `Dockerfile` and `qmk-base.Dockerfile` both accept a `DockerBase` build argument that selects the upstream image. CI wires them together; see `.github/workflows/main.yml`.

## Conventions

**Shell / scripting language**: Setup scripts are written in PowerShell (`.ps1`) and shell (`.sh`). PowerShell is the primary shell inside the container and on the host. Use PowerShell for new module scripts unless you have a specific reason not to (e.g. the tool's own installer requires bash).

**Idempotency**: Setup scripts check before they act (e.g. `if ! grep -q ...`, `if( !(Test-Path ...) )`). New scripts should follow the same pattern — running setup twice should not break anything.

**No local tests**: There is no test suite. To verify a change works, build the Docker image locally:
```bash
docker build --build-arg DockerBase=thomazmoura/dev-environment:base -f Dockerfile .
```

**NeoVim config**: All NeoVim configuration lives in `modules/vim/` (Lua and vimrc files) and `modules/nvim-config/` (entry point). Plugin declarations are in `modules/neovim-plug/plug.vimrc`. LSP server installers are in `modules/neovim-lsp/`.

**Environment variables**: System-wide variables (timezone, locale, TERM) are set in `/etc/environment` on the host or via `ENV` directives in Dockerfiles. User-level PowerShell variables go in `~/.profile.ps1` (created by `host-setup.sh`).

**`~/.storage` vs `~/.shared`**: Inside the Docker container, `~/.storage` is the persistent volume mount point. Subdirectories like `.storage/ssh`, `.storage/azure`, `.storage/dotnet-tools` are symlinked from their expected home locations so data survives container recreation. `~/.shared` holds the ASP.NET localhost certificate accessible to the host.

## Common tasks for agents

**Add a new tool**: Create a new directory under `modules/<tool-name>/` with an install script. Add the corresponding `COPY` line to `Dockerfile` (or `base.Dockerfile` if it needs root) and the corresponding `pwsh -File` call to `LinuxDevEnv/host-setup.sh`.

**Update a NeoVim plugin**: Edit `modules/neovim-plug/plug.vimrc`. The plugin is installed via `PlugInstall` at build time; no other files need changing unless the plugin requires Lua config, which goes in `modules/vim/lua/`.

**Change a dotfile**: Edit the file directly in `modules/vim/`, `modules/shell/`, `modules/powershell-config/`, etc. Because the host uses a symlink to `modules/`, the change is live immediately on the host without re-running setup.

**Add a new LSP server**: Edit `modules/neovim-lsp/Setup-NeoVimLSP.ps1` to download and install the server binary into `~/.language-servers/`. Then add the corresponding configuration in `modules/vim/lua/lsp-settings.lua`.

**Add a Linux host utility**: Create a script in `LinuxDevEnv/` for utilities specific to the physical machine (terminal emulators, display server tweaks, systemd services). These are not part of the Docker image.

## CI behaviour

- Every push triggers a Docker build.
- `main` branch: publishes `:base`, `:latest`, `:qmk_base`, `:qmk`.
- Any other branch: publishes branch-namespaced tags (slashes in branch names become underscores).
- Credentials: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` must be set as repository secrets.
- Build cache: all stages use `--cache-from` against the previously published tag.

## What agents should not do

- Do not commit binary files or large downloaded artifacts (`.deb`, `.tar.gz`, compiled binaries). Downloads happen at build/setup time, not at commit time.
- Do not modify `.docker-variables` — it contains placeholder values. Each user fills in their own copy locally.
- Do not add features to `LinuxDevEnv/host-setup.sh` that are machine-specific (screen resolution, specific hardware drivers). Those belong in separate scripts in `LinuxDevEnv/`.
- Do not assume the host is Ubuntu — the Docker base image is Debian trixie. Host-only scripts can target Ubuntu 24.04 but Docker scripts must work on Debian.
