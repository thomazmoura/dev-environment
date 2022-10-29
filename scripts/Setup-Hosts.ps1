. $PSScriptRoot/Setup-Docker.ps1

Get-Content /home/thomaz/.docker-variables
	| Where-Object {$_ -match "=" }
	| Foreach-Object { Invoke-Expression "`$env:$($_.Replace('=', '=`"'))`"" }

. $PSScriptRoot/../modules/shell/Setup-Git.ps1

sudo update-alternatives --config editor

