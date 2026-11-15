# Installs the jdtls bundles behind Java debugging in NeoVim (config/java_debug, nvim-jdtls):
# java-debug (the debug adapter, run inside jdtls) and vscode-java-test (JUnit/TestNG
# runs for <Leader>dt). Both come from their VS Code extensions on Open VSX, which ship
# the built jars under extension/server; only those jars are kept, in
# ~/.language-servers/java-debug and ~/.language-servers/java-test.
# Run by base.Dockerfile and LinuxDevEnv/host-setup.sh; skips a version already there.
. "$HOME/.modules/powershell/Check-Failure.ps1"

$Bundles = @(
  @{ Extension = 'vscode-java-debug'; Version = '0.60.0'; Folder = 'java-debug' },
  @{ Extension = 'vscode-java-test'; Version = '0.47.0'; Folder = 'java-test' }
)

foreach ($Bundle in $Bundles) {
  $InstallDir = "$HOME/.language-servers/$($Bundle.Folder)"
  $Marker = "$InstallDir/.version"
  if ((Test-Path $Marker) -and (([string](Get-Content $Marker -Raw)).Trim() -eq $Bundle.Version)) {
    Write-Output "`n->> $($Bundle.Extension) $($Bundle.Version) is already installed"
    continue
  }

  Write-Output "`n->> Downloading $($Bundle.Extension) $($Bundle.Version)"
  $Name = "vscjava.$($Bundle.Extension)-$($Bundle.Version)"
  $Work = Join-Path ([System.IO.Path]::GetTempPath()) $Name
  if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
  New-Item -ItemType Directory $Work -Force | Out-Null
  $Vsix = "$Work/$Name.vsix"
  Invoke-WebRequest "https://open-vsx.org/api/vscjava/$($Bundle.Extension)/$($Bundle.Version)/file/$Name.vsix" -OutFile $Vsix

  # A vsix is a zip: only its server jars are needed
  & unzip -q -o $Vsix 'extension/server/*' -d $Work
  Throw-ExceptionOnNativeFailure

  # Emptied first, so an update leaves none of the previous version's jars behind
  if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
  New-Item -ItemType Directory $InstallDir -Force | Out-Null
  Copy-Item "$Work/extension/server/*.jar" $InstallDir
  Set-Content -Path $Marker -Value $Bundle.Version
  Remove-Item -Recurse -Force $Work
}
