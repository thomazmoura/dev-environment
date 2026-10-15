#!/usr/bin/env pwsh

. "$HOME/.modules/powershell/Check-Failure.ps1"

# sqlcmd, the SQL Server command-line client. This is go-sqlcmd, the single
# static binary Microsoft publishes on GitHub, rather than the apt mssql-tools18
# package, which pulls in the ODBC driver, needs ACCEPT_EULA and installs off the
# PATH in /opt. The same tarball works on the Debian image and the Ubuntu host.
$SqlcmdVersion = "v1.10.0"
$BinDirectory = "$HOME/.local/bin"
$SqlcmdPath = "$BinDirectory/sqlcmd"

$Architecture = & uname -m
$Package = switch ( $Architecture ) {
  "x86_64"  { "sqlcmd-linux-amd64.tar.bz2" }
  "aarch64" { "sqlcmd-linux-arm64.tar.bz2" }
  "arm64"   { "sqlcmd-linux-arm64.tar.bz2" }
  default   { throw "Unsupported architecture for sqlcmd: $Architecture" }
}

Write-Output "`n->> Installing sqlcmd $SqlcmdVersion"
New-Item -Force -Type Directory -Path $BinDirectory

# `sqlcmd --version` prints a banner with a "Version: v1.10.0" line
$InstalledVersion = if (Test-Path $SqlcmdPath) { & $SqlcmdPath --version | Select-String -Pattern '^Version:' } else { "" }
if ("$InstalledVersion" -match "\b$([regex]::Escape($SqlcmdVersion))$") {
  Write-Output "sqlcmd $SqlcmdVersion is already installed, skipping download"
  return
}

$Archive = "$HOME/$Package"
Invoke-WebRequest "https://github.com/microsoft/go-sqlcmd/releases/download/$SqlcmdVersion/$Package" -OutFile $Archive -ErrorAction Stop
# The archive also holds a sqlcmd_debug build and NOTICE.md; only the binary is kept
& tar --extract --bzip2 --file $Archive --directory $BinDirectory sqlcmd
& chmod +x $SqlcmdPath
Remove-Item $Archive

(& $SqlcmdPath --version | Select-String -Pattern '^Version:').Line

Throw-ExceptionOnNativeFailure
