# Points Claude Code's status line at modules/claude/statusline.py, idempotently.
#
# ~/.claude/settings.json is not versioned (it holds permissions, hooks and
# machine paths), so only the `statusLine` key is managed here; everything else
# in the file is left alone. The script itself lives behind ~/.modules, so edits
# to it are live without re-running this.

$settingsPath = "$HOME/.claude/settings.json"

$wanted = [ordered]@{
  type                 = "command"
  command              = "~/.modules/claude/statusline.py"
  padding              = 0
  hideVimModeIndicator = $true
}

if( Test-Path $settingsPath ) {
  $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
} else {
  New-Item -Type Directory -Path (Split-Path $settingsPath) -Force | Out-Null
  $settings = [ordered]@{}
}

$current = if( $settings.Contains("statusLine") ) { $settings["statusLine"] | ConvertTo-Json -Compress } else { $null }
if( $current -eq ($wanted | ConvertTo-Json -Compress) ) {
  Write-Host "Claude Code status line already configured"
  return
}

if( Test-Path $settingsPath ) {
  Copy-Item $settingsPath "$settingsPath.bak-statusline" -Force
}
$settings["statusLine"] = $wanted
$settings | ConvertTo-Json -Depth 100 | Set-Content $settingsPath
Write-Host "Claude Code status line configured in $settingsPath"
