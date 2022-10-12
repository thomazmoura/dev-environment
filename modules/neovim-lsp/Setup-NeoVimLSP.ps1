. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output "`n->> Setting up LTS node version"
nvs use lts

Write-Output "`n->> Creating default Language Servers folder"
New-Item -Force -Type Directory -Path $HOME/.language-servers

Push-Location $HOME/.language-servers

Write-Output "`n->> Installing OmniSharp (.NET LSP)"
Invoke-WebRequest "https://github.com/OmniSharp/omnisharp-roslyn/releases/download/v1.39.1/omnisharp-linux-x64-net6.0.tar.gz" -OutFile "omnisharp-linux-x64-net6.tar.gz"
New-Item -Force -Type Directory -Path $HOME/.language-servers/omnisharp
& tar -xzvf "./omnisharp-linux-x64-net6.tar.gz" -C "$HOME/.language-servers/omnisharp"
& Remove-Item "./omnisharp-linux-x64-net6.tar.gz"

Write-Output "`n->> Installing Lua Language Server"
Invoke-WebRequest "https://github.com/sumneko/lua-language-server/releases/download/3.5.6/lua-language-server-3.5.6-linux-x64.tar.gz" -OutFile "lua-language-server-3.5.6-linux-x64.tar.gz"
New-Item -Force -Type Directory -Path $HOME/.language-servers/lua
& tar -xzvf "./lua-language-server-3.5.6-linux-x64.tar.gz" -C "$HOME/.language-servers/lua"
& Remove-Item "./lua-language-server-3.5.6-linux-x64.tar.gz"

Write-Output "`n->> Installing Json Language Server"
npm install --global vscode-langservers-extracted

Write-Output "`n->> Installing tsserver - TypeScript Language Server"
npm install --global typescript typescript-language-server

Write-Output "`n->> Installing Angular Language Server"
npm install --global @angular/language-server

Pop-Location

Throw-ExceptionOnNativeFailure

