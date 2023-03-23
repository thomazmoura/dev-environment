if(!(Get-Command docker -ErrorAction 'SilentlyContinue')) {
	. $PSScriptRoot/Install-Docker.ps1
}

. $PSScriptRoot/Setup-Docker.ps1
. $PSScriptRoot/Setup-PowerShell.ps1

Get-Content /home/thomaz/.docker-variables
	| Where-Object {$_ -match "=" }
	| Foreach-Object { Invoke-Expression "`$env:$($_.Replace('=', '=`"'))`"" }

. $PSScriptRoot/../modules/shell/Setup-Git.ps1

if(!(Get-Command nvs -ErrorAction SilentlyContinue)) {
	. $PSScriptRoot/../modules/node/Setup-NVS.ps1
}

if( !(Test-Path "$HOME/.docker-variables") ) {
	Copy-Item "$PSScriptRoot/../.docker-variables" "$HOME/.docker-variables"
}

sudo update-alternatives --config editor

