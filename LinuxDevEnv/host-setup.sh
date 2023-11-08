sudo apt update \
  && sudo apt install -y \
    apt-transport-https \
    curl \
    gnupg \
    software-properties-common \
  && curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - \
  && sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-debian-bullseye-prod bullseye main" > /etc/apt/sources.list.d/microsoft.list' \
  && sudo apt update \
  && sudo apt install -y \
    apt-utils \
    bat \
    build-essential \
    fd-find \
    fzf \
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

# Make fdfind be callable as fd
sudo pwsh -NoProfile -Command 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

# Get the current modules path and make a symbolic link to it on $HOME/.modules
script_path="$(cd "$(dirname "$0")" && pwd)"
modules_path="$script_path/../modules"
echo "Creating symbolink link on $HOME/.modules to $modules_path"
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.modules -Target $modules_path"
sudo pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path /root/.modules -Target $modules_path"

# dotnet installation
sudo pwsh -NoProfile -Command "$HOME/.modules/dotnet/dotnet-setup.ps1"

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

# NeoVim Plug Modules installation
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.local/share/nvim/site/autoload -Target $modules_path/vim-autoload"
pwsh -NoProfile -Command '& $HOME/neovim/bin/nvim -n -u $HOME/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"' || pwsh -Command '& $HOME/neovim/bin/nvim -n -u $HOME/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"' 

# Azure-CLI extensions installation
export PATH="$HOME/.local/bin:$PATH" && pipx install azure-cli && chmod +x $HOME/.modules/azure-cli-extensions/azure-extensions-setup.sh && $HOME/.modules/azure-cli-extensions/azure-extensions-setup.sh

# Delta diff installation
pwsh -NoProfile -File $HOME/.modules/git/delta-setup.ps1

# Tmux plugins installation
pwsh -NoProfile -Command "'source $HOME/.modules/wsl2/tmux.conf' > $HOME/.tmux.conf"
chmod +x $HOME/.modules/tmux/tpm-setup.sh && export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" && $HOME/.modules/tmux/tpm-setup.sh

# NeoVim LSP Configuration
pwsh -NoProfile -File $HOME/.modules/neovim-lsp/Setup-NeoVimLSP.ps1

# Shell config folders and .files
pwsh -NoProfile -Command "New-Item -ItemType SymbolicLink -Path $HOME/.vim -Target $HOME/.local/share/nvim/site"

pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.shell -Target $modules_path/shell"

pwsh -NoProfile -Command "New-Item -Type Directory $HOME/.config -Force"
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.config/powershell -Target $modules_path/powershell-config"

pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.config/nvim -Target $modules_path/nvim-config"

pwsh -NoProfile -Command "New-Item -Type Directory -Path $HOME/.local/share/nvim -Force"
pwsh -NoProfile -Command "New-Item -Type SymbolicLink -Path $HOME/.local/share/nvim/site -Target $modules_path/vim"

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
if ! grep -q "^\$env:PATH" $powershell_profile; then # To add clip.exe, explorer.exe and win32yank.exe
    echo "\$env:PATH="\${env:PATH}:/mnt/c/Windows/system32:/mnt/c/Windows:/mnt/c/Program Files/Neovim/bin/"
" | tee -a $powershell_profile
fi

# Run environment initialization
pwsh -File $HOME/.modules/wsl2/Start-DevSession.ps1

