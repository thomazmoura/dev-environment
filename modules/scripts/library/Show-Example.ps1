#!/usr/bin/env pwsh
# The same example in PowerShell, to show the picker running either one.
#
# The extension is what decides: Invoke-Script.sh hands a .ps1 to pwsh and a .sh
# to bash, so a library script needs no executable bit and no shebang.

Write-Host "Show-Example.ps1`n"
Write-Host ("  interpreter  PowerShell {0}" -f $PSVersionTable.PSVersion)
Write-Host ("  directory    {0}" -f (Get-Location).Path)
Write-Host ("  host         {0}" -f [System.Net.Dns]::GetHostName())
