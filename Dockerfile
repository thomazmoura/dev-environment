FROM mcr.microsoft.com/powershell:7.2.0-ubuntu-20.04
  
RUN apt-get update \
  && apt-get install -y \
    software-properties-common \
  && add-apt-repository ppa:neovim-ppa/unstable \
  && apt-get update \
  && apt-get install -y \
    apt-transport-https \
    apt-utils \
    bash-completion \
    bat \
    build-essential \
    curl \
    fd-find \
    fzf \
    git \
    icu-devtools \
    less \
    lsb-release \
    neovim \
    openssh-server \
    python \
    python3 \
    python3-pip \
    silversearcher-ag \
    strace \
    tmux \
    unzip \
    wget \
    ;

# Make fdfind be callable as fd
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/fd -Target /usr/bin/fdfind'

# Tools for command line available to every user
COPY Kernel/modules/bin /usr/bin
# Make terminal-based yank accessible both as yank and clip
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/clip -Target /usr/bin/yank' && chmod +x /usr/bin/clip && chmod +x /usr/bin/yank

# Create the developer user to be used dynamically
RUN useradd --user-group --system --create-home --no-log-init developer
USER developer

# Node installation
RUN mkdir -p /home/developer/.modules
COPY --chown=developer:developer Kernel/modules/node /home/developer/.modules/node
RUN chmod +x /home/developer/.modules/node/nvs-setup.ps1 && pwsh -NoProfile -Command /home/developer/.modules/node/nvs-setup.ps1

# PowerShell modules installation
COPY --chown=developer:developer Kernel/modules/powershell /home/developer/.modules/powershell
RUN pwsh -NoProfile -Command /home/developer/.modules/powershell/pwsh-setup.ps1

# Shell config folders
RUN mkdir -p /home/developer/.config/powershell
COPY --chown=developer:developer DockerUbuntu/config/powershell/profile.ps1 /home/developer/.config/powershell/Microsoft.PowerShell_profile.ps1
COPY --chown=developer:developer Kernel/shell /home/developer/.shell
COPY --chown=developer:developer Kernel/config /home/developer/.config

# NeoVim Plug Modules installation
RUN mkdir -p /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer Kernel/vim/autoload /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer Kernel/modules/neovim-plug/plug.vimrc /home/developer/.modules/neovim-plug/plug.vimrc
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"'

# NeoVim CoC Modules installation
COPY --chown=developer:developer Kernel/modules/neovim-coc /home/developer/.modules/neovim-coc
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-coc/coc-setup.vimrc +"CocInstall -sync coc-angular coc-css coc-emmet coc-html coc-json coc-prettier coc-eslint coc-tsserver coc-powershell coc-snippets coc-yaml coc-omnisharp coc-git" +qall'

# NeoVim Settings
WORKDIR /home/developer/code
COPY --chown=developer:developer DockerUbuntu/vimrc /home/developer/.config/nvim/init.vim
COPY --chown=developer:developer Kernel/vim /home/developer/.vim


CMD ["/opt/microsoft/powershell/7/pwsh"]






#RUN cp -rf /home/developer/.vim /home/user/.vim
#RUN cp -rf /home/developer/.config /home/user/.config
#RUN chown -R 1000:1000 /home/user

#CMD ["/opt/microsoft/powershell/7/pwsh"]





#COPY DockerUbuntu/vimrc /home/user/.vimrc
#COPY DockerUbuntu/bashrc /home/user/.bashrc
#COPY DockerUbuntu/tmux.conf /home/user/.tmux.conf
#COPY Kernel/config/ /home/user/.config/
#COPY DockerUbuntu/config/powershell/ /home/user/.config/powershell/
#COPY DockerUbuntu/init/ /home/user/.config/init/
#COPY Kernel/shell/ /home/user/.shell/
#COPY Kernel/vim /home/user/.vim/
#COPY Kernel/vim /home/user/.config/nvim
#COPY Kernel/vim/autoload /home/user/.local/share/nvim/site

#RUN chown -R user:user /home/user

#USER user:user

#ENV TERM xterm-256color

#WORKDIR /home/user/git

#CMD ["/opt/microsoft/powershell/7/pwsh", "-c", "vtmux"]

