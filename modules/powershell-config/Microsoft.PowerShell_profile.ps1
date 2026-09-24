if( [IO.File]::Exists("$HOME/.storage/powershell/profile.ps1") ) {
  . "$HOME/.storage/powershell/profile.ps1"
}

. "$HOME/.config/powershell/linux-profile.ps1"

