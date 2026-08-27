. "$HOME/.modules/powershell/Check-Failure.ps1"

# demux is a tmux session dashboard. Upstream only documents `brew install` and
# `go install`, neither of which is available here, so this pulls the prebuilt
# release tarball instead.
$DemuxVersion = "v1.11.0"

$Architecture = & uname -m
$Package = switch ( $Architecture ) {
  "x86_64"  { "demux_linux_amd64.tar.gz" }
  "aarch64" { "demux_linux_arm64.tar.gz" }
  "arm64"   { "demux_linux_arm64.tar.gz" }
  default   { throw "Unsupported architecture for demux: $Architecture" }
}

$InstalledVersion = $null
if ( Test-Path "$HOME/demux/demux" ) {
  # `demux --version` prints "demux version 1.11.0" (no leading "v")
  $InstalledVersion = (& "$HOME/demux/demux" --version | Select-Object -First 1) -replace '^demux version\s+', ''
}

if ( ($InstalledVersion -ne $DemuxVersion.TrimStart("v")) -or ! (Test-Path "$HOME/.local/bin/demux") ) {
  if ( $InstalledVersion ) {
    Write-Output ">>> Updating demux from $InstalledVersion to $DemuxVersion"
  } else {
    Write-Output ">>> Installing demux $DemuxVersion"
  }
  Set-Location $HOME

  Write-Output "=>> Removing any previous installation"
  Remove-Item -Recurse -Force "$HOME/demux/" -ErrorAction SilentlyContinue
  New-Item -Type Directory -Force "$HOME/demux/"

  Write-Output "=>> Ensuring the ~/.local/bin directory exists"
  New-Item -Type Directory -Force "$HOME/.local/bin/"

  Write-Output "=>> Downloading demux's release tar package ($Package)"
  Invoke-WebRequest https://github.com/rtalexk/demux/releases/download/$DemuxVersion/$Package -OutFile $Package

  Write-Output "=>> Extracting demux package"
  & tar -xzf $Package -C "$HOME/demux/"

  Write-Output "=>> Making demux executable"
  & chmod +x $HOME/demux/demux

  Write-Output "=>> Creating symbolic links"
  New-Item -Force -Type SymbolicLink -Path "$HOME/.local/bin/demux" -Target "$HOME/demux/demux"

  Write-Output "=>> Cleaning up"
  Remove-Item -Recurse -Force $Package
}

Throw-ExceptionOnNativeFailure
