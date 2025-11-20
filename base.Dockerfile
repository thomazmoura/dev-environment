FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive
  
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    locales \
    tzdata; \
  # Microsoft docs recommend installing the repository via the packages-microsoft-prod helper deb
  # (no software-properties-common needed on recent Debian images).
  curl -sSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb; \
  dpkg -i /tmp/packages-microsoft-prod.deb; \
  rm /tmp/packages-microsoft-prod.deb; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
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
    wget; \
  apt-get autoremove -y; \
  rm -rf /var/lib/apt/lists/*; \
  echo "C.UTF-8 UTF-8" > /etc/locale.gen; \
  locale-gen;

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

# Debugger installation
COPY --chown=developer:developer modules/debugging /home/developer/.modules/debugging
RUN pwsh -NoProfile -File /home/developer/.modules/debugging/Install-NetCoreDbg.ps1
