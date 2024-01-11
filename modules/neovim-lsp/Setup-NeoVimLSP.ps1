. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output "Make node available to the script"
& $HOME/.nvs/nvs.ps1 use lts

. "$HOME/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1"

Write-Output "`n->> Creating default Language Servers folder"
New-Item -Force -Type Directory -Path $HOME/.language-servers
Push-Location $HOME/.language-servers

Write-Output "`n->> Installing OmniSharp (.NET LSP)"
Invoke-WebRequest "https://github.com/OmniSharp/omnisharp-roslyn/releases/download/v1.39.10/omnisharp-linux-x64-net6.0.tar.gz" -OutFile "omnisharp-linux-x64-net6.tar.gz"
New-Item -Force -Type Directory -Path $HOME/.language-servers/omnisharp
& tar -xzvf "./omnisharp-linux-x64-net6.tar.gz" -C "$HOME/.language-servers/omnisharp"
& Remove-Item "./omnisharp-linux-x64-net6.tar.gz"

Write-Output "`n->> Copying custom language config files to user folder"
New-Item -Force -Type Directory -Path $HOME/.omnisharp
Copy-Item "$HOME/.modules/neovim-lsp/omnisharp.json" "$HOME/.omnisharp/omnisharp.json"
Copy-Item "$HOME/.modules/neovim-lsp/editorconfig" "$HOME/.editorconfig"


Write-Output "`n->> Installing PowerShell Editor Services (PowerShell LSP)"
Invoke-WebRequest "https://github.com/PowerShell/PowerShellEditorServices/releases/download/v3.5.4/PowerShellEditorServices.zip" -OutFile "PowerShellEditorServices.zip"
New-Item -Force -Type Directory -Path $HOME/.language-servers/powershell
& Expand-Archive -Force -Path "PowerShellEditorServices.zip" -DestinationPath "$HOME/.language-servers/powershell"
& Remove-Item "PowerShellEditorServices.zip"


Write-Output "`n->> Installing Lua Language Server"
Invoke-WebRequest "https://github.com/LuaLS/lua-language-server/releases/download/3.6.13/lua-language-server-3.6.13-linux-x64.tar.gz" -OutFile "lua-language-server-3.6.13-linux-x64.tar.gz"
New-Item -Force -Type Directory -Path $HOME/.language-servers/lua
& tar -xzvf "./lua-language-server-3.6.13-linux-x64.tar.gz" -C "$HOME/.language-servers/lua"
& Remove-Item "./lua-language-server-3.6.13-linux-x64.tar.gz"

Pop-Location

Throw-ExceptionOnNativeFailure

