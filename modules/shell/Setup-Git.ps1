Get-Content /home/thomaz/.docker-variables
	| Where-Object {$_ -match "=" }
	| Foreach-Object { Invoke-Expression "`$env:$($_.Replace('=', '=`"'))`"" }

Write-Information "`n->> Setting git config for $env:GIT_USERNAME"
& git config --global user.name "$env:GIT_USERNAME"
& git config --global user.email "$env:GIT_EMAIL"
