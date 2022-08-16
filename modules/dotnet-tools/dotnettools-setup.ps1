Write-Output "`n->> Installing global .net tools"
& dotnet tool install --global --version 0.5.2 csharp-ls
& dotnet tool install --global dotnet-ef
& dotnet tool install --global dotnet-outdated-tool

