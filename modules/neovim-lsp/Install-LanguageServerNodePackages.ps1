param(
  [switch] $ForcarAtualizacao
)

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()

# Verifies if there is any .node-version on levels below and change to it if found
# This is useful to open NeoVim with the correct node version on .NET + Angular projects
$nodeVersionFile = fd -H .node-version -d 2
if( $nodeVersionFile ) {
  #nvs use (cat $nodeVersionFile)
}

$NodeVersion = node --version
$InstalledNodeVersionsFolder = "$HOME/.installed-node-versions"
$NodeVersionCache = "$InstalledNodeVersionsFolder/$NodeVersion"

if( !($ForcarAtualizacao) -and (Test-Path $NodeVersionCache) ) {
  Write-Verbose "`n-->> Packages already installed"
  return;
}

if( !(Test-Path $InstalledNodeVersionsFolder) ) {
  New-Item -ItemType Directory $InstalledNodeVersionsFolder -Force
}
New-Item -ItemType File -Path $NodeVersionCache -Force

npm install --global 'vscode-langservers-extracted'
npm install --global 'typescript-language-server'
npm install --global '@angular/language-server'
npm install --global 'yaml-language-server'
npm install --global 'vim-language-server'
npm install --global 'emmet-ls'
npm install --global '@cucumber/language-server'

$stopwatch.Stop(); Write-Verbose "`n-->> Node package installation took: $($stopwatch.ElapsedMilliseconds)"

