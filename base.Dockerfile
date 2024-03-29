FROM debian
  
RUN apt update \
  && apt install -y \
    apt-transport-https \
    curl \
    gnupg \
    software-properties-common \
  && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
  && sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-debian-bullseye-prod bullseye main" > /etc/apt/sources.list.d/microsoft.list' \
  && apt update \
  && apt install -y \
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
  && apt autoremove -y \
  && rm -rf /var/lib/apt/lists/* \
  && locale-gen C.UTF-8;

ENV TZ="America/Sao_Paulo"
ENV LANG="C.UTF-8"
ENV LC_ALL="C.UTF-8"
ENV LANGUAGE="C.UTF-8"

# Make fdfind be callable as fd
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

# Tools for command line available to every user
COPY modules/bin-tools /usr/bin
# Make terminal-based yank accessible both as yank and clip
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/clip -Target /usr/bin/yank' && chmod +x /usr/bin/clip && chmod +x /usr/bin/yank

# dotnet installation
COPY modules/dotnet /root/.modules/dotnet
COPY modules/powershell /root/.modules/powershell
RUN pwsh -c /root/.modules/dotnet/dotnet-setup.ps1 -ErrorAction 'Stop'

# Create the developer user to be used dynamically
RUN useradd --user-group --system --create-home --no-log-init developer --shell /bin/bash
# Allow the user to override the hosts file on the $HOME/.hosts folder (which will be symbolic linked to .storage if present)
RUN chown developer:developer /etc/host.conf && mkdir /home/developer/.hosts && pwsh -c "New-Item -ItemType HardLink -Path /home/developer/.hosts/host.conf -Target /etc/host.conf"
USER developer

# PowerShell modules installation
COPY --chown=developer:developer modules/powershell /home/developer/.modules/powershell
RUN pwsh -NoProfile -Command /home/developer/.modules/powershell/pwsh-setup.ps1

# NeoVim Installation
COPY --chown=developer:developer modules/neovim-install /home/developer/.modules/neovim-install
RUN pwsh -NoProfile -File /home/developer/.modules/neovim-install/Install-Neovim.ps1

