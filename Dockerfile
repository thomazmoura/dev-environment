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
COPY bin-tools /usr/bin
# Make terminal-based yank accessible both as yank and clip
RUN pwsh -c 'New-Item -Type HardLink -Path /usr/bin/clip -Target /usr/bin/yank' && chmod +x /usr/bin/clip && chmod +x /usr/bin/yank

# NeoVim Universal-ctags requirement
COPY universal-ctags /root/.modules/ctags
RUN chmod +x /root/.modules/ctags/ctags-setup.sh && /root/.modules/ctags/ctags-setup.sh

# dotnet installation
COPY dotnet /root/.modules/dotnet
RUN pwsh -c /root/.modules/dotnet/dotnet-setup.ps1

# Azure CLI installation
COPY azure-cli /root/.modules/azure-cli
RUN chmod +x /root/.modules/azure-cli/azurecli-setup.sh && /root/.modules/azure-cli/azurecli-setup.sh
ENV AZURE_CONFIG_DIR home/developer/.storage/azure

# Create the developer user to be used dynamically
RUN useradd --user-group --system --create-home --no-log-init developer --shell /bin/bash
USER developer

# Node installation
RUN mkdir -p /home/developer/.modules
COPY --chown=developer:developer node /home/developer/.modules/node
RUN chmod +x /home/developer/.modules/node/nvs-setup.ps1 && pwsh -NoProfile -Command /home/developer/.modules/node/nvs-setup.ps1

# PowerShell modules installation
COPY --chown=developer:developer powershell /home/developer/.modules/powershell
RUN pwsh -NoProfile -Command /home/developer/.modules/powershell/pwsh-setup.ps1

# NeoVim Requirements
COPY --chown=developer:developer neovim-base /home/developer/.modules/neovim-base
RUN pwsh -NoProfile -File /home/developer/.modules/neovim-base/neovim-setup.ps1

# Container startup configuration
COPY --chown=developer:developer entrypoint-config /home/developer/.modules/entrypoint
ENTRYPOINT ["pwsh", "-NoProfile", "-Command", "/home/developer/.modules/entrypoint/Start-DevSession.ps1"]

# NeoVim Plug Modules installation
RUN mkdir -p /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer vim-autoload /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer neovim-plug/plug.vimrc /home/developer/.modules/neovim-plug/plug.vimrc
RUN pwsh -c 'nvim -n -u /home/developer/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"'

# NeoVim TreeSitter compilation
COPY --chown=developer:developer neovim-treesitter /home/developer/.modules/neovim-treesitter
RUN chmod +x /home/developer/.modules/neovim-treesitter/treesitter-install.sh && /home/developer/.modules/neovim-treesitter/treesitter-install.sh

# Dotnet tools instalation
COPY --chown=developer:developer dotnet-tools /home/developer/.modules/dotnet-tools
RUN pwsh -NoProfile -File /home/developer/.modules/dotnet-tools/dotnettools-setup.ps1

# NeoVim CoC Modules installation
COPY --chown=developer:developer neovim-coc /home/developer/.modules/neovim-coc
RUN pwsh -c '/home/developer/.nvs/nvs.ps1 use lts && nvim -n -u /home/developer/.modules/neovim-coc/coc-setup.vimrc +"CocInstall -sync coc-angular coc-css coc-emmet coc-html coc-json coc-prettier coc-eslint coc-tsserver coc-powershell coc-snippets coc-yaml coc-git" +qall'

# Delta diff installation
COPY --chown=developer:developer git /home/developer/.modules/git
RUN pwsh -NoProfile -File /home/developer/.modules/git/delta-setup.ps1

# Tmux plugins installation
COPY --chown=developer:developer tmux /home/developer/.modules/tmux
COPY --chown=developer:developer DockerUbuntu/tmux.conf /home/developer/.tmux.conf
ENV TMUX_PLUGIN_MANAGER_PATH /home/developer/.tmux/plugins/
RUN chmod +x /home/developer/.modules/tmux/tpm-setup.sh && /home/developer/.modules/tmux/tpm-setup.sh

# Shell config folders and .files
RUN pwsh -c "New-Item -ItemType SymbolicLink -Path /home/developer/.vim -Target /home/developer/.local/share/nvim/site"
COPY --chown=developer:developer DockerUbuntu/config/powershell/profile.ps1 /home/developer/.config/powershell/Microsoft.PowerShell_profile.ps1
COPY --chown=developer:developer DockerUbuntu/bashrc /home/developer/.bashrc
COPY --chown=developer:developer DockerUbuntu/vimrc /home/developer/.config/nvim/init.vim

COPY --chown=developer:developer shell /home/developer/.shell
COPY --chown=developer:developer powershell-config /home/developer/.config/powershell
COPY --chown=developer:developer nvim-config /home/developer/.config/nvim
COPY --chown=developer:developer vim /home/developer/.local/share/nvim/site

# Start the environment
ENV TERM xterm-256color
WORKDIR /home/developer/code
CMD ["/opt/microsoft/powershell/7/pwsh", "-c", "tail", "-f", "/dev/null"]

