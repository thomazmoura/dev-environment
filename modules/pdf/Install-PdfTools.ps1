#!/usr/bin/env pwsh
# Installs pdf2md (prints a PDF as Markdown) and pdfcat (opens one in NeoVim,
# which renders that Markdown); called by host-setup.sh and Dockerfile, with no
# key binding.
#
# The converter is pymupdf4llm, in a venv of its own. Both versions are pinned
# on purpose: pymupdf4llm after 0.3.x, and pymupdf from 2.0, require
# pymupdf-layout, with onnxruntime and a much larger install.

. "$HOME/.modules/powershell/Check-Failure.ps1"

$PyMuPdfVersion = "1.28.2"
$PyMuPdf4LlmVersion = "0.3.4"
$VenvDirectory = "$HOME/.local/share/pdf-tools"
$BinDirectory = "$HOME/.local/bin"
$Python = "$VenvDirectory/bin/python"

Write-Output "`n->> Installing the PDF tools (pymupdf4llm $PyMuPdf4LlmVersion)"

# Importing, rather than asking pip, also catches a venv that an OS upgrade to a
# new Python left unable to load its packages
$UpToDate = $false
if (Test-Path $Python) {
  $Check = "import pymupdf; pymupdf.no_recommend_layout(); import pymupdf4llm; print(pymupdf.__version__, pymupdf4llm.__version__)"
  $Installed = & $Python -I -c $Check 2>$null
  $UpToDate = $LASTEXITCODE -eq 0 -and "$Installed" -eq "$PyMuPdfVersion $PyMuPdf4LlmVersion"
}

if ($UpToDate) {
  Write-Output "The PDF tools are already installed, skipping download"
} else {
  & python3 -m venv --clear $VenvDirectory
  Throw-ExceptionOnNativeFailure
  & $Python -m pip install --quiet --disable-pip-version-check "pymupdf==$PyMuPdfVersion" "pymupdf4llm==$PyMuPdf4LlmVersion"
  Throw-ExceptionOnNativeFailure
}

New-Item -Force -Type Directory -Path $BinDirectory | Out-Null
foreach ($Tool in "pdf2md", "pdfcat") {
  $Target = "$HOME/.modules/pdf/$Tool"
  $Link = "$BinDirectory/$Tool"
  $Existing = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
  if ($Existing -and $Existing.LinkType -eq 'SymbolicLink' -and $Existing.Target -eq $Target) { continue }
  if ($Existing -and $Existing.LinkType -ne 'SymbolicLink') {
    throw "Refusing to replace an existing file: $Link"
  }
  New-Item -Force -Type SymbolicLink -Path $Link -Target $Target | Out-Null
}
