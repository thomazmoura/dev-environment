Write-Output "->> Installing pynvim from pip (for NeoVim - Python integration)"
& python3 -m pip install --user --upgrade pynvim

Write-Output "->> Installing neovim from npm (for NeoVim - Node integration)"
/home/developer/.nvs/nvs.ps1 use lts
& npm install --global neovim

