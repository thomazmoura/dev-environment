if( Test-Path "$HOME/.storage/powershell/profile.ps1") {
	. "$HOME/.storage/powershell/profile.ps1"
}

. "$HOME/.config/powershell/linux-profile.ps1"


Set-Alias nvs "$HOME/.nvs/nvs.ps1" # Node Version Switcher
