param(
  [switch] $ForcarAtualizacao
)

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()

$NodeVersion = node --version
$InstalledNodeVersionsFolder = "$HOME/.installed-node-versions"
$NodeVersionCache = "$InstalledNodeVersionsFolder/$NodeVersion"
if( !($ForcarAtualizacao) -and (Test-Path $NodeVersionCache) ) {
  return;
}

npm install --global 'vscode-langservers-extracted'
npm install --global 'typescript-language-server'
npm install --global '@angular/language-server'
npm install --global 'yaml-language-server'
npm install --global 'vim-language-server'
npm install --global 'emmet-ls'

if( !(Test-Path $InstalledNodeVersionsFolder) ) {
  New-Item -ItemType Directory $InstalledNodeVersionsFolder
}
New-Item -ItemType File -Path $NodeVersionCache

$stopwatch.Stop(); Write-Verbose "`n-->> Instalação de pacotes Node demorou: $($stopwatch.ElapsedMilliseconds)"

