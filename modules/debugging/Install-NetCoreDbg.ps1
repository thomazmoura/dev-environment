. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output "`n->> Downloading netcoredbg"
Invoke-WebRequest https://github.com/Samsung/netcoredbg/releases/download/2.2.3-992/netcoredbg-linux-amd64.tar.gz -OutFile "$HOME/netcoredbg-linux-amd64.tar.gz"

Write-Output "`n->> Extracting the package"
& tar -xzf "$HOME/netcoredbg-linux-amd64.tar.gz" -C "$HOME/.local"

Write-Output "`n->> Creating symbolinc link to the binary"
New-Item -Type SymbolicLink -Path "$HOME/.local/bin/netcoredbg" -Target "$HOME/.local/netcoredbg/netcoredbg"

Write-Output "`n->> Removing downloaded package"
Remove-Item "$HOME/netcoredbg-linux-amd64.tar.gz"

Throw-ExceptionOnNativeFailure

