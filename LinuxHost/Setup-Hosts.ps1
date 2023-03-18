if(!(Get-Command docker -ErrorAction 'SilentlyContinue')) {
	. $PSScriptRoot/Install-Docker.ps1
}

. $PSScriptRoot/Setup-Docker.ps1
. $PSScriptRoot/Setup-PowerShell.ps1

Get-Content /home/thomaz/.docker-variables
	| Where-Object {$_ -match "=" }
	| Foreach-Object { Invoke-Expression "`$env:$($_.Replace('=', '=`"'))`"" }

. $PSScriptRoot/../modules/shell/Setup-Git.ps1

sudo update-alternatives --config editor

