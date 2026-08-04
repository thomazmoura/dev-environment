. "$HOME/.modules/powershell/Check-Failure.ps1"

# nvim-treesitter's main branch requires the tree-sitter CLI to generate parsers
# for grammars that do not ship a pre-generated src/parser.c. Upstream is
# explicit that the npm package is not a supported install route, so this pulls
# the release binary the same way modules/neovim-lsp installs its servers.

$TreeSitterVersion = "v0.26.11"
$BinDirectory = "$HOME/.local/bin"
$TreeSitterPath = "$BinDirectory/tree-sitter"

Write-Output "`n->> Installing the tree-sitter CLI (for NeoVim - parser generation)"
New-Item -Force -Type Directory -Path $BinDirectory

$InstalledVersion = if (Test-Path $TreeSitterPath) { & $TreeSitterPath --version } else { "" }
if ($InstalledVersion -match [regex]::Escape($TreeSitterVersion.TrimStart("v"))) {
  Write-Output "tree-sitter $TreeSitterVersion is already installed, skipping download"
  return
}

Push-Location $BinDirectory
Invoke-WebRequest "https://github.com/tree-sitter/tree-sitter/releases/download/$TreeSitterVersion/tree-sitter-linux-x64.gz" -OutFile "tree-sitter-linux-x64.gz" -ErrorAction Stop
& gzip --decompress --force "tree-sitter-linux-x64.gz"
& mv --force "tree-sitter-linux-x64" $TreeSitterPath
& chmod +x $TreeSitterPath
Pop-Location

& $TreeSitterPath --version

Throw-ExceptionOnNativeFailure
