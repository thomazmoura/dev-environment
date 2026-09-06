sudo apt update \
  && sudo apt install -y \
    apt-transport-https \
    curl \
    gnupg \
    software-properties-common \
  && curl -sSL -O https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
  && sudo dpkg -i packages-microsoft-prod.deb \
  && sudo apt update \
  && sudo apt install -y \
    apt-utils \
    bat \
    build-essential \
    fd-find \
    git \
    htop \
    iproute2 \
    iputils-ping \
    less \
    locales \
    lsb-release \
    make \
    man-db \
    net-tools \
    pkg-config \
    powershell \
    procps \
    pipx \
    python3 \
    python3-pip \
    ripgrep \
    silversearcher-ag \
    strace \
    tmux \
    tzdata \
    unzip \
    wget \
  && sudo apt autoremove -y \
  && sudo rm -rf /var/lib/apt/lists/* \
  && sudo locale-gen C.UTF-8;

echo "Setting environment variables"
environment_file="/etc/environment"
if ! grep -q "^TZ" $environment_file; then
    echo "TZ=America/Sao_Paulo" | sudo tee -a $environment_file
fi
if ! grep -q "^LANG" $environment_file; then
    echo "LANG=C.UTF-8" | sudo tee -a $environment_file
fi
if ! grep -q "^LC_ALL" $environment_file; then
    echo "LC_ALL=C.UTF-8" | sudo tee -a $environment_file
fi
if ! grep -q "^LANGUAGE" $environment_file; then
    echo "LANGUAGE=C.UTF-8" | sudo tee -a $environment_file
fi
if ! grep -q "^TERM" $environment_file; then
    echo "TERM=xterm-256color" | sudo tee -a $environment_file
fi
if ! grep -q "^DOTNET_WATCH_RESTART_ON_RUDE_EDIT" $environment_file; then
    echo "DOTNET_WATCH_RESTART_ON_RUDE_EDIT=1" | sudo tee -a $environment_file
fi
# Skip the telemetry upload and first-run banner on every dotnet invocation
if ! grep -q "^DOTNET_CLI_TELEMETRY_OPTOUT" $environment_file; then
    echo "DOTNET_CLI_TELEMETRY_OPTOUT=1" | sudo tee -a $environment_file
fi
if ! grep -q "^DOTNET_NOLOGO" $environment_file; then
    echo "DOTNET_NOLOGO=1" | sudo tee -a $environment_file
fi
# The first-run experience re-extracts bundled assets; nothing here needs it
if ! grep -q "^DOTNET_SKIP_FIRST_TIME_EXPERIENCE" $environment_file; then
    echo "DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1" | sudo tee -a $environment_file
fi

echo "Installing fzf (newer version)"
pwsh -NoProfile -Command "Invoke-WebRequest https://github.com/junegunn/fzf/releases/download/v0.54.3/fzf-0.54.3-linux_amd64.tar.gz -OutFile fzf.tar.gz && tar -xzvf ./fzf.tar.gz -C $HOME/.local/bin && rm ./fzf.tar.gz"

# Make fdfind be callable as fd
sudo pwsh -NoProfile -Command 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

# Get the current modules path and make a symbolic link to it on $HOME/.modules
script_path="$(cd "$(dirname "$0")" && pwd)"
modules_path="$script_path/../modules"
echo "Creating symbolink link on $HOME/.modules to $modules_path"
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.modules -Target $modules_path"
sudo pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path /root/.modules -Target $modules_path"

# dotnet installation
sudo pwsh -NoProfile -Command "$HOME/.modules/dotnet/ubuntu-24-04-dotnet-setup.ps1"

# PowerShell modules installation
pwsh -NoProfile -File "$HOME/.modules/powershell/pwsh-setup.ps1"

# NeoVim Installation
pwsh -NoProfile -File "$HOME/.modules/neovim-install/Install-Neovim.ps1"

# Debugger installation
pwsh -NoProfile -File "$HOME/.modules/debugging/Install-NetCoreDbg.ps1"

# Node installation
pwsh -NoProfile -File $HOME/.modules/node/Setup-NVS.ps1 &&
pwsh -NoProfile -File $HOME/.modules/node/Setup-NVS.ps1

# NeoVim Requirements
pwsh -NoProfile -File $HOME/.modules/neovim-base/neovim-setup.ps1

# Tree-sitter CLI (required by nvim-treesitter's main branch, and by the
# :TSUpdate that runs as part of PlugInstall below)
pwsh -NoProfile -File $HOME/.modules/neovim-treesitter/Install-TreeSitterCli.ps1

# NeoVim Plug Modules installation
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.local/share/nvim/site/autoload -Target $modules_path/vim-autoload"
pwsh -NoProfile -Command '& $HOME/neovim/bin/nvim -n -u $HOME/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"' || pwsh -Command '& $HOME/neovim/bin/nvim -n -u $HOME/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"' 

# Azure-CLI extensions installation
export PATH="$HOME/.local/bin:$PATH" && pipx install azure-cli && chmod +x $HOME/.modules/azure-cli-extensions/azure-extensions-setup.sh && $HOME/.modules/azure-cli-extensions/azure-extensions-setup.sh

# Delta diff installation
pwsh -NoProfile -File $HOME/.modules/git/delta-setup.ps1

# demux (tmux session dashboard, bound to prefix + e as a sticky sidebar)
pwsh -NoProfile -File $HOME/.modules/demux/Install-Demux.ps1

# herdr (terminal multiplexer used as the runtime for coding agents; also
# installs the agent state hooks and the Claude Code agent skill)
pwsh -NoProfile -File $HOME/.modules/herdr/Install-Herdr.ps1

# agent-radar (reads each coding agent's screen to say which one is waiting on
# you; bound to prefix + t then a/A, and summarised in the status bar). No
# installer: the scripts run in place out of $HOME/.modules, so only the
# executable bit has to be guaranteed.
chmod +x $HOME/.modules/agent-radar/scripts/*

# Tmux plugins installation
pwsh -NoProfile -Command "'source $HOME/.modules/wsl2/tmux.conf' > $HOME/.tmux.conf"
chmod +x $HOME/.modules/tmux/tpm-setup.sh && export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" && $HOME/.modules/tmux/tpm-setup.sh

# NeoVim LSP Configuration
pwsh -NoProfile -File $HOME/.modules/neovim-lsp/Setup-NeoVimLSP.ps1

# Postgres Language Server (VS Code extension Supabase.postgrestools)
pwsh -NoProfile -File "$script_path/Install-PostgresLanguageServer.ps1"

# Shell config folders and .files
pwsh -NoProfile -Command "New-Item -ItemType SymbolicLink -Path $HOME/.vim -Target $HOME/.local/share/nvim/site"

pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.shell -Target $modules_path/shell"

pwsh -NoProfile -Command "New-Item -Type Directory $HOME/.config -Force"
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.config/powershell -Target $modules_path/powershell-config"

pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.config/nvim -Target $modules_path/nvim-config"

# demux config (the file, not the directory: demux writes its state DB and log
# next to it and those must not land in the repo)
pwsh -NoProfile -Command "New-Item -Type Directory -Path $HOME/.config/demux -Force"
pwsh -NoProfile -Command "New-Item -Force -Type SymbolicLink -Path $HOME/.config/demux/demux.toml -Target $modules_path/demux/demux.toml"

# herdr config (the file, not the directory: herdr writes its logs, sockets and
# session state next to it and those must not land in the repo)
pwsh -NoProfile -Command "New-Item -Type Directory -Path $HOME/.config/herdr -Force"
pwsh -NoProfile -Command "New-Item -Force -Type SymbolicLink -Path $HOME/.config/herdr/config.toml -Target $modules_path/herdr/config.toml"

# Terminal emulators (both act as hosts for tmux)
pwsh -NoProfile -Command "New-Item -Force -Type SymbolicLink -Path $HOME/.config/ghostty -Target $modules_path/ghostty"
pwsh -NoProfile -Command "New-Item -Force -Type SymbolicLink -Path $HOME/.wezterm.lua -Target $modules_path/wezterm/wezterm.lua"

# Ghostty background image: the photo is not part of this repo. Whichever
# of ~/.terminal-background.{png,jpg,jpeg} exists is wired into the
# optional `config-file = ?background.conf` include; with none present the
# include is simply absent and Ghostty stays on the theme background.
# (wezterm.lua probes the same paths on its own.)
ghostty_background=""
for ext in png jpg jpeg; do
    if [ -f "$HOME/.terminal-background.$ext" ]; then
        ghostty_background="$HOME/.terminal-background.$ext"
        break
    fi
done
if [ -n "$ghostty_background" ]; then
    sed "s|@IMAGE@|$ghostty_background|" \
        "$modules_path/ghostty/background.conf.template" \
        > "$modules_path/ghostty/background.conf"
else
    rm -f "$modules_path/ghostty/background.conf"
fi

pwsh -NoProfile -Command "New-Item -Type Directory -Path $HOME/.local/share/nvim -Force"
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.local/share/nvim/site -Target $modules_path/vim"

# Spell files (needs the site symlink above, since it writes through it)
pwsh -NoProfile -File $HOME/.modules/neovim-base/Install-SpellFiles.ps1

# User environment variables
pwsh -NoProfile -Command "if ( ! (Test-Path $HOME/.profile.ps1) ) { New-Item -Path $HOME/.profile.ps1 }"
powershell_profile="$HOME/.profile.ps1"
if ! grep -q "^\$env:ASPNETCORE_Kestrel__Certificates__Default__Path" $powershell_profile; then
    echo "\$env:ASPNETCORE_Kestrel__Certificates__Default__Path=\"$HOME/.shared/aspnet-localhost.pfx\"" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:ASPNETCORE_Kestrel__Certificates__Default__Password" $powershell_profile; then
    echo "\$env:ASPNETCORE_Kestrel__Certificates__Default__Password=\"p455W0rd\"" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:DOTNET_SKIP_AUTO_URLS" $powershell_profile; then
    echo "\$env:DOTNET_SKIP_AUTO_URLS=\$True" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:DOTNET_WATCH_RESTART_ON_RUDE_EDIT" $powershell_profile; then
    echo "\$env:DOTNET_WATCH_RESTART_ON_RUDE_EDIT=1" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:DOTNET_CLI_TELEMETRY_OPTOUT" $powershell_profile; then
    echo "\$env:DOTNET_CLI_TELEMETRY_OPTOUT=1" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:DOTNET_NOLOGO" $powershell_profile; then
    echo "\$env:DOTNET_NOLOGO=1" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:DOTNET_ROOT" $powershell_profile; then
    echo "\$env:DOTNET_ROOT='/usr/share/dotnet'" | tee -a $powershell_profile
fi
if ! grep -q "^\$env:PATH" $powershell_profile; then # To add clip.exe, explorer.exe and win32yank.exe
    echo "\$env:PATH="\${env:PATH}:/mnt/c/Windows/system32:/mnt/c/Windows:/mnt/c/Program Files/Neovim/bin/"
" | tee -a $powershell_profile
fi

# Create a symbolic link to win32yank.exe
sudo pwsh -Command 'if (Test-Path "/mnt/c/Program Files/Neovim/bin/win32yank.exe") { New-Item -Force -Type SymbolicLink -Path "/usr/bin/win32yank.exe" -Target "/mnt/c/Program Files/Neovim/bin/win32yank.exe" }'

# Increase the number of inotify watchers
if ! grep -q "^fs\.inotify\.max_user_instances" /etc/sysctl.conf; then
    echo fs.inotify.max_user_instances=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
fi

# Run environment initialization
pwsh -File $HOME/.modules/wsl2/Start-DevSession.ps1

