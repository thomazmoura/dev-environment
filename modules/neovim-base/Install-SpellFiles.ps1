. "$HOME/.modules/powershell/Check-Failure.ps1"

# NeoVim only bundles en.utf-8.spl. modules/vim/ftplugin/markdown.vim asks for
# `spelllang=en_us,pt_br`, and without these files every markdown buffer opens
# with `Cannot find word list "pt.utf-8.spl"`.
#
# The region suffix is not part of the file name: pt.utf-8.spl carries both the
# pt_br and pt_pt regions, so this single file covers both.
#
# There is no companion pt.utf-8.sug upstream (only English and a handful of
# other languages ship one), so `z=` falls back to Vim's own suggestion
# algorithm for Portuguese. That is expected, not a missing download.
#
# This lands in $HOME/.local/share/nvim/site/spell, which is a symlink into
# modules/vim in this repo, so modules/vim/.gitignore keeps it untracked.

$SpellDirectory = "$HOME/.local/share/nvim/site/spell"
$SpellMirror = "https://ftp.nluug.nl/pub/vim/runtime/spell"

Write-Output "`n->> Installing Portuguese spell files (for NeoVim - spellcheck)"
New-Item -Force -Type Directory -Path $SpellDirectory

foreach ($SpellFile in @("pt.utf-8.spl")) {
  $Destination = Join-Path $SpellDirectory $SpellFile
  if (Test-Path $Destination) {
    Write-Output "$SpellFile is already present, skipping download"
    continue
  }
  Write-Output "Downloading $SpellFile"
  Invoke-WebRequest "$SpellMirror/$SpellFile" -OutFile $Destination -ErrorAction Stop
}

Throw-ExceptionOnNativeFailure
