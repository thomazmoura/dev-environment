FROM mcr.microsoft.com/powershell:7.2.0-ubuntu-20.04
  
RUN apt-get update \
  && apt-get install -y \
    software-properties-common \
  && add-apt-repository ppa:neovim-ppa/unstable \
  && apt-get update \
  && apt-get install -y \
    apt-transport-https \
    apt-utils \
    automake \
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
    make \
    neovim \
    openssh-server \
    pkg-config \
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

# NeoVim Universal-ctags requirement
COPY Kernel/modules/universal-ctags/ctags-setup.sh /root/ctags-setup.sh
RUN chmod +x /root/ctags-setup.sh && /root/ctags-setup.sh

# dotnet installation
COPY Kernel/modules/dotnet /root/.modules/dotnet
RUN pwsh -c /root/.modules/dotnet/dotnet-setup.ps1

# Azure CLI installation
COPY Kernel/modules/azure-cli /root/.modules/azure-cli
RUN pwsh -c /root/.modules/azure-cli/Install-AzureCLI.ps1 -ErrorAction Stop

# Create the developer user to be used dynamically
RUN useradd --user-group --system --create-home --no-log-init developer --shell /bin/bash
USER developer

# Node installation
RUN mkdir -p /home/developer/.modules
COPY --chown=developer:developer Kernel/modules/node /home/developer/.modules/node
RUN chmod +x /home/developer/.modules/node/nvs-setup.ps1 && pwsh -NoProfile -Command /home/developer/.modules/node/nvs-setup.ps1

# PowerShell modules installation
COPY --chown=developer:developer Kernel/modules/powershell /home/developer/.modules/powershell
RUN pwsh -NoProfile -Command /home/developer/.modules/powershell/pwsh-setup.ps1

# NeoVim Requirements
COPY --chown=developer:developer Kernel/modules/neovim-base /home/developer/.modules/neovim-base
RUN pwsh -NoProfile -File /home/developer/.modules/neovim-base/neovim-setup.ps1

# NeoVim Plug Modules installation
RUN mkdir -p /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer Kernel/vim/autoload /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer Kernel/modules/neovim-plug/plug.vimrc /home/developer/.modules/neovim-plug/plug.vimrc
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"'

# NeoVim TreeSitter compilation
COPY --chown=developer:developer Kernel/modules/neovim-treesitter /home/developer/.modules/neovim-treesitter
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync c_sharp" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync cpp" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync css" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync dockerfile" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync html" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync json" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync lua" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync regex" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync typescript" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync vim" +qall'
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-treesitter/treesitter-setup.vimrc +"TSInstallSync yaml" +qall'

# Dotnet tools instalation
COPY --chown=developer:developer Kernel/modules/dotnet-tools /home/developer/.modules/dotnet-tools
RUN pwsh -NoProfile -File /home/developer/.modules/dotnet-tools/dotnettools-setup.ps1

# NeoVim CoC Modules installation
COPY --chown=developer:developer Kernel/modules/neovim-coc /home/developer/.modules/neovim-coc
RUN pwsh -c '/home/developer/.nvs/nvs.ps1 use lts && nvim -n -u /home/developer/.modules/neovim-coc/coc-setup.vimrc +"CocInstall -sync coc-angular coc-css coc-emmet coc-html coc-json coc-prettier coc-eslint coc-tsserver coc-powershell coc-snippets coc-yaml coc-git" +qall'

# Delta diff installation
COPY --chown=developer:developer Kernel/modules/git /home/developer/.modules/git
RUN pwsh -NoProfile -File /home/developer/.modules/git/delta-setup.ps1

# Shell config folders and .files
RUN mkdir -p /home/developer/.config/powershell
RUN pwsh -c "New-Item -ItemType SymbolicLink -Path /home/developer/.vim -Target /home/developer/.local/share/nvim/site"
COPY --chown=developer:developer DockerUbuntu/config/powershell/profile.ps1 /home/developer/.config/powershell/Microsoft.PowerShell_profile.ps1
COPY --chown=developer:developer DockerUbuntu/tmux.conf /home/developer/.tmux.conf
COPY --chown=developer:developer DockerUbuntu/bashrc /home/developer/.bashrc
COPY --chown=developer:developer Kernel/shell /home/developer/.shell
COPY --chown=developer:developer Kernel/config /home/developer/.config

# Tmux plugins installation
COPY --chown=developer:developer Kernel/modules/tmux /home/developer/.modules/tmux
RUN pwsh -NoProfile -File /home/developer/.modules/tmux/tpm-setup.ps1

# NeoVim Settings
COPY --chown=developer:developer DockerUbuntu/vimrc /home/developer/.config/nvim/init.vim
COPY --chown=developer:developer Kernel/vim /home/developer/.local/share/nvim/site

# Make PowerShell history inside the container easier to map to volumes
RUN mkdir /home/developer/.local/share/powershell/PSReadLine && pwsh -c 'New-Item -Type SymbolicLink -Path /home/developer/.powershell_history -Target /home/developer/.local/share/powershell/PSReadLine'

# Start the environment
ENV TERM xterm-256color
RUN mkdir /home/developer/code && mkdir /home/developer/.ssh
WORKDIR /home/developer/code
CMD ["/opt/microsoft/powershell/7/pwsh"]

