Write-Information "`n->> Install packages"
sudo apt install fzf fd-find -y

Write-Information "`n->> Create .modules folder"
New-Item -Force -Type Directory "$HOME/.modules"

Write-Information "`n->> Create .config/powershell symbolic link"
New-Item -Force -Type Directory "$HOME/.config"
if(Test-Path "$HOME/.config/powershell") {
	Remove-Item -Force -Recurse "$HOME/.config/powershell"
}
$PowerShellConfigFolder = (Get-Item "$PSScriptRoot/../modules/powershell-config").FullName
Write-Information "`n->> Creating Symbolic Link from $PowerShellConfigFolder to $HOME/.config/powershell"
New-Item -Force -Type SymbolicLink -Path $HOME/.config/powershell -Target $PowerShellConfigFolder

Write-Information "`n->> Shell files"
$DockerHostModuleFolder = (Get-Item "$PSScriptRoot/../LinuxHost").FullName
Copy-Item -Force $DockerHostModuleFolder/config/powershell/profile.ps1 $HOME/.config/powershell/
Copy-Item -Force $DockerHostModuleFolder/bashrc $HOME/.bashrc

Write-Information "`n->> Create .shell symbolic link"
$ShellModuleFolder = (Get-Item "$PSScriptRoot/../modules/shell").FullName
Write-Information "`n->> Creating Symbolic Link from $ShellModuleFolder to $HOME/.shell"
New-Item -Force -Type SymbolicLink -Path $HOME/.shell -Target $ShellModuleFolder

Write-Information "`n->> Create .powershell symbolic link"
$PowerShellModuleFolder = (Get-Item "$PSScriptRoot/../modules/powershell").FullName
Write-Information "`n->> Creating Symbolic Link from $PowerShellModuleFolder to $HOME/.modules/powershell"
New-Item -Force -Type SymbolicLink -Path $HOME/.modules/powershell -Target $PowerShellModuleFolder

chmod +x $HOME/.modules/powershell/pwsh-setup.ps1
chmod +x $HOME/.modules/powershell/pwsh-modules.ps1
pwsh -NoProfile -Command $HOME/.modules/powershell/pwsh-setup.ps1

Write-Information "`n->> Install modules"
. $HOME/.modules/powershell/pwsh-modules.ps1
Import-OhMyPoshOnLinux

Write-Information "`n->> Setting environment variables and configuring Git"
Get-Content /home/thomaz/.docker-variables
	| Where-Object {$_ -match "=" }
	| Foreach-Object { Invoke-Expression "`$env:$($_.Replace('=', '=`"'))`"" }
"$PSScriptRoot/../modules/shell/"

