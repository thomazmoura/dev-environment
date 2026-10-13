# Links GitHub Copilot CLI skills into the user's skill directory; called by host-setup.sh
# and Dockerfile, with no key binding. Repository edits stay live through the links.
param(
  [string]$Destination = "$HOME/.copilot/skills"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($skill in Get-ChildItem -LiteralPath $PSScriptRoot -Directory) {
  if (!(Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
  $link = Join-Path $Destination $skill.Name
  $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
  if ($existing -and $existing.LinkType -ne 'SymbolicLink') {
    throw "Refusing to replace an existing non-symlink skill: $link"
  }
  New-Item -ItemType SymbolicLink -Path $link -Target $skill.FullName -Force | Out-Null
}
