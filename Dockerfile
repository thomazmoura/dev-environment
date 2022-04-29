FROM mcr.microsoft.com/powershell:7.2.0-ubuntu-20.04

  
RUN apt update \
  && apt install -y \
    software-properties-common \
  && add-apt-repository ppa:neovim-ppa/unstable \
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
    openssh-server \
    silversearcher-ag \
    tmux \
    unzip \
    wget \
    ;

RUN pwsh -c 'Install-Module nvm -Force -Scope AllUsers; \
  Install-Module posh-git -Force -Scope AllUsers; \
  Import-Module nvm; \
  Install-NodeVersion 12; \
  Install-NodeVersion 14; \
  Install-NodeVersion 16; \
  Set-NodeVersion 16;'

RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

RUN useradd -ms /bin/bash user
RUN usermod -a -G root user

COPY DockerUbuntu/vimrc /home/user/.vimrc
COPY DockerUbuntu/bashrc /home/user/.bashrc
COPY DockerUbuntu/tmux.conf /home/user/.tmux.conf
COPY Kernel/config/ /home/user/.config/
COPY DockerUbuntu/config/powershell/ /home/user/.config/powershell/
COPY DockerUbuntu/init/ /home/user/.config/init/
COPY Kernel/shell/ /home/user/.shell/
COPY Kernel/vim /home/user/.vim/
COPY Kernel/vim /home/user/.config/nvim
COPY Kernel/vim/autoload /home/user/.local/share/nvim/site

RUN chown -R user:user /home/user

USER user:user

RUN pwsh -c 'nvim -es -u /home/user/.vim/plug.vimrc -i NONE -c "PlugInstall" -c "qa"'
RUN pwsh -c 'nvim +"CocInstall -sync coc-angular coc-css coc-emmet coc-html coc-json coc-prettier coc-eslint coc-tsserver coc-powershell coc-yaml coc-omnisharp coc-git" +qall'

ENV TERM xterm-256color

WORKDIR /home/user/git

CMD ["/opt/microsoft/powershell/7/pwsh", "-c", "vtmux"]

