if( (service docker status *> $null) ) {
	Write-Information "`n->> Starting docker service"
	sudo service docker start
}

if( Test-Path "$HOME/.storage/powershell/profile.ps1") {
	. "$HOME/.storage/powershell/profile.ps1"
}

. "$HOME/.config/powershell/linux-profile.ps1"


