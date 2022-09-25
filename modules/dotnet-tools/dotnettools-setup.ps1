Write-Output "`n->> Installing global .net tools"
& dotnet tool install --global csharp-ls
& dotnet tool install --global dotnet-ef
& dotnet tool install --global dotnet-outdated-tool

Invoke-WebRequest "https://github.com/OmniSharp/omnisharp-roslyn/releases/download/v1.39.1/omnisharp-linux-x64-net6.0.tar.gz" -OutFile "omnisharp-linux-x64-net6.tar.gz"
New-Item -Force -Type Directory -Path $HOME/.omnisharp
& tar -xzvf "./omnisharp-linux-x64-net6.tar.gz" -C "$HOME/.omnisharp"
& Remove-Item "./omnisharp-linux-x64-net6.tar.gz"

