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

if ! grep -q "^TZ" "/etv/environment"; then
    sudo echo "TZ=America/Sao_Paulo" >> /etc/environment
fi
if ! grep -q "^LANG" "/etv/environment"; then
    sudo echo "LANG=C.UTF-8" >> /etc/environment
fi
if ! grep -q "^LC_ALL" "/etv/environment"; then
    sudo echo "LC_ALL=C.UTF-8" >> /etc/environment
fi
if ! grep -q "^LANGUAGE" "/etv/environment"; then
    sudo echo "LANGUAGE=C.UTF-8" >> /etc/environment

# Make fdfind be callable as fd
pwsh -c 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind' -ErrorAction 'Stop'

# Get the current modules path and make a symbolic link to it on $HOME/.modules
script_path="$(cd "$(dirname "$0")" && pwd)"
modules_path="$script_path/../../modules"
pwsh -c "New-Item -Type HardLink -Path $HOME/.modules -Target $script_path" -ErrorAction 'Stop'

# dotnet installation
sudo pwsh -c "$HOME/.modules/dotnet/dotnet-setup.ps1" -ErrorAction 'Stop'

# PowerShell modules installation
pwsh -NoProfile -Command "$HOME/.modules/powershell/pwsh-setup.ps1"

# NeoVim Installation
COPY --chown=developer:developer modules/neovim-install $HOME/.modules/neovim-install
RUN pwsh -NoProfile -File "$HOME/.modules/neovim-install/Install-Neovim.ps1"

# Debugger installation
COPY --chown=developer:developer modules/debugging $HOME/.modules/debugging
RUN pwsh -NoProfile -File "$HOME/.modules/debugging/Install-NetCoreDbg.ps1"


