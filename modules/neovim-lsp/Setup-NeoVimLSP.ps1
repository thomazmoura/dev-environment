. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output "Make node available to the script"
& $HOME/.nvs/nvs.ps1 use lts

. "$HOME/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1"

Write-Output "`n->> Creating default Language Servers folder"
New-Item -Force -Type Directory -Path $HOME/.language-servers
Push-Location $HOME/.language-servers

Write-Output "`n->> Installing the Roslyn Language Server (.NET LSP)"
# Replaces OmniSharp, which was archived upstream. This is the same server VS Code's
# C# extension uses, and roslyn.nvim finds it on PATH via ~/.dotnet/tools.
# The Azure DevOps feed is updated several times a day; nuget.org lags well behind.
$RoslynFeed = "https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json"
& dotnet tool update --global roslyn-language-server --prerelease --source $RoslynFeed

Write-Output "`n->> Copying custom language config files to user folder"
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

