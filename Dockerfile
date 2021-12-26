FROM mcr.microsoft.com/powershell:7.2.0-ubuntu-20.04

RUN pwsh -c 'Install-Module posh-git -Force'

RUN apt update \
  && apt install -y \
    software-properties-common \
  && add-apt-repository ppa:neovim-ppa/stable \
  && apt update \
  && apt install -y \
    bash-completion \
    bat \
    curl \
    fd-find \
    fzf \
    git \
    less \
    neovim \
    silversearcher-ag \
    tmux \
    unzip \
    wget \
    ;

RUN pwsh -c 'Install-Module nvm -Force; \
  Import-Module nvm; \
  Install-NodeVersion 12; \
  Install-NodeVersion 14; \
  Install-NodeVersion 16; \
  Set-NodeVersion 16;'

COPY DockerUbuntu/vimrc /root/.vimrc
COPY DockerUbuntu/bashrc /root/.bashrc
COPY DockerUbuntu/tmux.conf /root/.tmux.conf
COPY DockerUbuntu/config/powershell/profile.ps1 /opt/microsoft/powershell/7/profile.ps1
COPY Kernel/config/ /root/.config/
COPY Kernel/shell/ /root/.shell/

WORKDIR /root/git

CMD ["bash"]

