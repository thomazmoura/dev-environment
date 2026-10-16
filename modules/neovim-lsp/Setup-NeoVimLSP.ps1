. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output "`n->> Installing the node-based Language Servers (with their own node)"
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


Write-Output "`n->> Installing the Postgres Language Server"
New-Item -Force -Type Directory -Path $HOME/.language-servers/postgres
Invoke-WebRequest "https://github.com/supabase-community/postgres-language-server/releases/download/0.28.2/postgres-language-server_x86_64-unknown-linux-gnu" -OutFile "$HOME/.language-servers/postgres/postgres-language-server"
& chmod +x "$HOME/.language-servers/postgres/postgres-language-server"


Write-Output "`n->> Installing SQL Tools Service (SQL Server LSP)"
# The server behind VS Code's mssql extension, self-contained (no dotnet needed).
# Emptied first so an update leaves none of the previous version's DLLs behind.
Invoke-WebRequest "https://github.com/microsoft/sqltoolsservice/releases/download/6.0.20261002.1/Microsoft.SqlTools.ServiceLayer-linux-x64-net10.0.tar.gz" -OutFile "sqltoolsservice.tar.gz"
Remove-Item -Recurse -Force -Path $HOME/.language-servers/sqlserver -ErrorAction SilentlyContinue
New-Item -Force -Type Directory -Path $HOME/.language-servers/sqlserver
& tar -xzf "./sqltoolsservice.tar.gz" -C "$HOME/.language-servers/sqlserver"
& Remove-Item "./sqltoolsservice.tar.gz"

Pop-Location

Throw-ExceptionOnNativeFailure

