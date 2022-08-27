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
    python3 \
    python3-pip \
    silversearcher-ag \
    strace \
    tmux \
    tzdata \
    unzip \
    wget \
  && apt autoremove -y \
  && rm -rf /var/lib/apt/lists/* \
  && locale-gen en_US.UTF-8;

ENV TZ="America/Sao_Paulo"
ENV LANG="en_US.UTF-8"
ENV LC_ALL="en_US.UTF-8"
ENV LANGUAGE="en_US.UTF-8"

# Make fdfind be callable as fd
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

# Tools for command line available to every user
COPY modules/bin-tools /usr/bin
# Make terminal-based yank accessible both as yank and clip
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/clip -Target /usr/bin/yank' && chmod +x /usr/bin/clip && chmod +x /usr/bin/yank

# NeoVim Installation (from channel testing)
COPY modules/testing-packages /root/.modules/testing-packages
RUN pwsh -NoProfile -File /root/.modules/testing-packages/testing-setup.ps1 && apt -t testing install neovim -y

# dotnet installation
COPY modules/dotnet /root/.modules/dotnet
COPY modules/powershell /root/.modules/powershell
RUN pwsh -c /root/.modules/dotnet/dotnet-setup.ps1 -ErrorAction 'Stop'

# Create the developer user to be used dynamically
RUN useradd --user-group --system --create-home --no-log-init developer --shell /bin/bash
# Allow the user to override the hosts file on the $HOME/.hosts folder (which will be symbolic linked to .storage if present)
RUN chown developer:developer /etc/host.conf && mkdir /home/developer/.hosts && pwsh -c "New-Item -ItemType HardLink -Path /home/developer/.hosts/host.conf -Target /etc/host.conf"
USER developer

