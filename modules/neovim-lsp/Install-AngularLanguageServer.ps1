param(
  [Parameter(Mandatory)] [ValidateRange(11, 14)] [int] $Major,
  [switch] $ForcarAtualizacao
)

# The Angular language server for projects older than Angular 15, one prefix
# per major (~/.language-servers/angular/<major>). The current ngserver fills
# their templates with false errors; the release of the project's own major
# understands them. NeoVim runs this in the background the first time it opens
# such a project (modules/nvim-config/lua/plugins/lsp.lua), so modern projects
# never pay for it.

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()

$Prefix = "$HOME/.language-servers/angular/$Major"
$Marker = "$Prefix/.installed"

if( !($ForcarAtualizacao) -and (Test-Path $Marker) ) {
  Write-Verbose "`n-->> Angular $Major language server already installed"
  return;
}

# ngserver 11 and 12 declare node < 15, and 13 and 14 still accept 14: one old
# node serves them all
$NodeVersion = '14'
$Nvs = "$HOME/.nvs/nvs.ps1"
& $Nvs add $NodeVersion
$NodeExe = & $Nvs which $NodeVersion | Select-Object -Last 1
if( !$NodeExe -or !(Test-Path $NodeExe) ) {
  # nvs could not resolve it (e.g. offline): the newest node 14 already installed
  $NodeExe = Get-ChildItem "$HOME/.nvs/node" -Directory -Filter "$NodeVersion.*" |
    Sort-Object { [version]$_.Name } |
    Select-Object -Last 1 |
    ForEach-Object { "$($_.FullName)/x64/bin/node" }
}
if( !$NodeExe -or !(Test-Path $NodeExe) ) {
  Write-Error "No node $NodeVersion found for the Angular $Major language server. Install it with: nvs add $NodeVersion"
  exit 1
}

New-Item -ItemType Directory $Prefix -Force | Out-Null
New-Item -ItemType SymbolicLink -Path "$Prefix/node" -Target $NodeExe -Force | Out-Null
$env:PATH = "$(Split-Path $NodeExe):$env:PATH"

# The project's own typescript comes first; this one, of the same era, is only
# the fallback for a project without node_modules
$TypeScript = @{ 11 = '~4.1.0'; 12 = '~4.3.0'; 13 = '~4.5.0'; 14 = '~4.7.0' }[$Major]

npm install --prefix $Prefix `
  "@angular/language-server@$Major" `
  "typescript@$TypeScript"

# The marker is a receipt for a successful install, so a failed one is retried
if( $LASTEXITCODE -eq 0 ) {
  New-Item -ItemType File -Path $Marker -Force | Out-Null
} else {
  Write-Warning "npm install failed with exit code $LASTEXITCODE. Not marking the Angular $Major language server as installed."
  exit $LASTEXITCODE
}

$stopwatch.Stop(); Write-Verbose "`n-->> Angular $Major language server installation took: $($stopwatch.ElapsedMilliseconds)"
