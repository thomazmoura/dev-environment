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

RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

COPY DockerUbuntu/vimrc /root/.vimrc
COPY DockerUbuntu/bashrc /root/.bashrc
COPY DockerUbuntu/tmux.conf /root/.tmux.conf
COPY Kernel/config/ /root/.config/
COPY DockerUbuntu/config/powershell/ /root/.config/powershell/
COPY DockerUbuntu/init/ /root/.config/init/
COPY Kernel/shell/ /root/.shell/
COPY Kernel/vim /root/.vim/
COPY Kernel/vim /root/.config/nvim
COPY Kernel/vim/autoload /root/.local/share/nvim/site

RUN pwsh -c 'nvim -es -u /root/.vim/plug.vimrc -i NONE -c "PlugInstall" -c "qa"'
RUN pwsh -c 'nvim +"CocInstall -sync coc-angular coc-css coc-emmet coc-html coc-json coc-prettier coc-eslint coc-tsserver coc-powershell coc-yaml coc-omnisharp coc-git" +qall'

ENV TERM xterm-256color

WORKDIR /root/git

CMD ["pwsh", "-c", "vtmux", "nvim", "pwsh"]

