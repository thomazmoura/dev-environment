. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output ">>> Installing NeoVim"
New-Item -Type Directory -Force "$HOME/neovim/"
New-Item -Type Directory -Force "$HOME/.local/bin/"
Invoke-WebRequest https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz -OutFile nvim-linux64.tar.gz
& tar -xzf nvim-linnux64.tar.fz
Move-Item nvim-linnux64/* "$HOME/neovim/"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/nvim" -Target "$HOME/neovim/bin/nvim"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/vim" -Target "$HOME/neovim/bin/nvim"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/vi" -Target "$HOME/neovim/bin/nvim"

Throw-ExceptionOnNativeFailure

