. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output ">>> Installing NeoVim"
Set-Location $HOME
New-Item -Type Directory -Force "$HOME/neovim/"

Write-Output "=>> Ensuring the ~/.local/bin directory exists"
New-Item -Type Directory -Force "$HOME/.local/bin/"

Write-Output "=>> Downloading Neovim's realease tar package"
Invoke-WebRequest https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz -OutFile nvim-linux64.tar.gz

Write-Output "=>> Extracting Neovim package"
& tar -xzf nvim-linux64.tar.gz

Write-Output "=>> Moving Neovim files to expected destination"
Move-Item nvim-linux64/* "$HOME/neovim/"

Write-Output "=>> Making nvim (Neovim) executable"
& chmod +x $HOME/neovim/bin/nvim

Write-Output "=>> Creating symbolic links"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/nvim" -Target "$HOME/neovim/bin/nvim"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/vim" -Target "$HOME/neovim/bin/nvim"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/vi" -Target "$HOME/neovim/bin/nvim"

Write-Output "=>> Cleaning up"
Remove-Item -Recure -Force nvim-linux64.tar.gz
Remove-Item -Recure -Force nvim-linux64

Throw-ExceptionOnNativeFailure

