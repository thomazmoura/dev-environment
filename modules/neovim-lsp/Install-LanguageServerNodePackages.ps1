param(
  [switch] $ForcarAtualizacao
)

# The node-based language servers live in their own prefix and run on their own
# node (~/.language-servers/node/node), the way Copilot runs on ~/.nvs/copilot-node.
# They only read a project's node_modules, so a project pinned to an old node by
# its .node-version still gets servers that need a current one -- and NeoVim
# starts without switching node or checking packages first
# (modules/nvim-config/lua/plugins/lsp.lua).

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()

$Prefix = "$HOME/.language-servers/node"
$Marker = "$Prefix/.installed"

if( !($ForcarAtualizacao) -and (Test-Path $Marker) ) {
  Write-Verbose "`n-->> Language server packages already installed"
  return;
}

$Nvs = "$HOME/.nvs/nvs.ps1"
& $Nvs add lts
$NodeExe = & $Nvs which lts | Select-Object -Last 1
if( !$NodeExe -or !(Test-Path $NodeExe) ) {
  # nvs could not resolve lts (e.g. offline): the newest node already installed
  $NodeExe = Get-ChildItem "$HOME/.nvs/node" -Directory |
    Sort-Object { [version]$_.Name } |
    Select-Object -Last 1 |
    ForEach-Object { "$($_.FullName)/x64/bin/node" }
}
if( !$NodeExe -or !(Test-Path $NodeExe) ) {
  Write-Error "No node found for the language servers. Install one with nvs (modules/node/Setup-NVS.ps1)."
  return
}

New-Item -ItemType Directory $Prefix -Force | Out-Null
New-Item -ItemType SymbolicLink -Path "$Prefix/node" -Target $NodeExe -Force | Out-Null
$env:PATH = "$(Split-Path $NodeExe):$env:PATH"

# A local install (not --global): the servers land in node_modules/.bin and
# typescript at the top of node_modules, where ngserver probes for it (7 is
# the Go port, without the tsserverlibrary both servers load)
npm install --prefix $Prefix `
  'typescript@<7' `
  'vscode-langservers-extracted' `
  'typescript-language-server' `
  '@angular/language-server' `
  'yaml-language-server' `
  'vim-language-server' `
  'emmet-ls' `
  '@cucumber/language-server'

# The marker is a receipt for a successful install, so a failed one is retried
if( $LASTEXITCODE -eq 0 ) {
  New-Item -ItemType File -Path $Marker -Force | Out-Null
} else {
  Write-Warning "npm install failed with exit code $LASTEXITCODE. Not marking the language servers as installed."
}

$stopwatch.Stop(); Write-Verbose "`n-->> Node package installation took: $($stopwatch.ElapsedMilliseconds)"
