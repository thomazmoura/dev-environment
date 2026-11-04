# Installs netcoredbg, the .NET debugger NeoVim's nvim-dap uses (lua/plugins/debug.lua,
# config/dotnet_debug), into ~/.local/netcoredbg with ~/.local/bin/netcoredbg linking to it.
# Run by base.Dockerfile and LinuxDevEnv/host-setup.sh; skips when the version is already there.
. "$HOME/.modules/powershell/Check-Failure.ps1"

$Version = "3.2.0-1092"
$InstallDir = "$HOME/.local/netcoredbg"
$Link = "$HOME/.local/bin/netcoredbg"

$Installed = if (Test-Path "$InstallDir/netcoredbg") { & "$InstallDir/netcoredbg" --version 2>$null | Select-Object -First 1 } else { "" }
# --version prints "NET Core debugger 3.2.0-1 (...)": the build number after the dash differs
if ($Installed -match [regex]::Escape(($Version -split '-')[0])) {
    Write-Output "`n->> netcoredbg $Version is already installed"
    exit 0
}

$Arch = switch (& uname -m) {
    "aarch64" { "arm64" }
    default { "amd64" }
}
$Archive = "$HOME/netcoredbg-linux-$Arch.tar.gz"

Write-Output "`n->> Downloading netcoredbg $Version ($Arch)"
Invoke-WebRequest "https://github.com/Samsung/netcoredbg/releases/download/$Version/netcoredbg-linux-$Arch.tar.gz" -OutFile $Archive

Write-Output "`n->> Extracting the package"
if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
& tar -xzf $Archive -C "$HOME/.local"
Throw-ExceptionOnNativeFailure

Write-Output "`n->> Creating symbolic link to the binary"
New-Item -ItemType Directory -Force -Path "$HOME/.local/bin" | Out-Null
New-Item -ItemType SymbolicLink -Force -Path $Link -Target "$InstallDir/netcoredbg" | Out-Null

Write-Output "`n->> Removing downloaded package"
Remove-Item $Archive
