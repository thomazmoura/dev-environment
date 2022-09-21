Write-Output "`n->> Installing global .net tools"
& dotnet tool install --global csharp-ls
& dotnet tool install --global dotnet-ef
& dotnet tool install --global dotnet-outdated-tool

Write-Output "`n->> Installing omnisharp-vim"
nvim -n -u /home/developer/.modules/dotnet-tools/omnisharp-setup.vimrc +"OmnisharpInstalll

