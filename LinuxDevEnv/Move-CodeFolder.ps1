#!/usr/bin/env pwsh
<#
  .SYNOPSIS
    Moves the code folder (~/code) to another place, /Git by default, and puts
    back everything that pointed into it. Host only, run by hand once per
    machine; idempotent, and -WhatIf shows what it would do.

  .DESCRIPTION
    Why /Git: on the company's machines Kaspersky scans /Git under the lighter
    policy meant for source code, which ~/code does not get.

    The repo itself does not care where the code folder is: tmux, pwsh, NeoVim
    and the linked machines resolve it with the same rule
    (modules/tmux/scripts/code-folder.sh), which falls through to /Git once
    ~/code is gone. No ~/code symlink is left behind: work done through it
    would be scanned as if the folder had never moved, so everything that
    named ~/code is rewritten instead (and a link from an earlier run is
    removed).

    Run it from a plain terminal with no tmux server and nothing inside the
    code folder -- ~/.modules, the tmux config and the radars' code all live in
    dev-environment, which moves too. It refuses otherwise. Claude Code must be
    closed as well: its per-project state is keyed by path and is moved here.
    When ~/code is already gone (moved by hand, or by an earlier run) the move
    and its checks are skipped and only the repairs run, so it can be run
    again at any time. It asks for sudo for /root/.modules.

    In order:
      1. moves every entry of ~/code into the destination (a rename: both must
         be on the same file system), refusing on any name already there;
      2. re-points the symlinks under ~ (four levels down: ~/.local/share/nvim/
         site) and /root/.modules that pointed into ~/code;
      3. repairs the git worktrees of the repositories in the destination (two
         levels down: AT/<repo> too), whose links still name the old paths,
         and only then removes the emptied ~/code;
      4. rewrites the old paths in the caches that hold them: the worktree
         registry (~/.worktrees) and the home session's and named sessions'
         folders (~/.cache/tmux);
      5. moves Claude Code's per-project folders (~/.claude/projects, history
         and memory) to the new paths' names and rewrites ~/.claude.json;
      6. rewrites the old paths in the hand-written dotfiles (~/.profile,
         ~/.profile.ps1, the user docker.service) and drops ~/.gitconfig's
         includeIf for ~/code/, each with a .before-move-code-folder backup,
         then lists any symlink or dotfile that still names ~/code.

    Afterwards, by hand: log in again (or open a new login shell) so ~/.profile
    is re-read, restore/rebuild .NET projects (obj/ holds absolute paths),
    rebuild sql-assist (modules/sql-assist/Build-SqlAssist.ps1), recreate
    Python virtual environments, and start tmux again.

  .EXAMPLE
    pwsh ~/.modules/../LinuxDevEnv/Move-CodeFolder.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Destination = "/Git",
  [string]$Source = "$HOME/code"
)

$ErrorActionPreference = "Stop"
$Source = $Source.TrimEnd('/')
$Destination = $Destination.TrimEnd('/')

function Write-Step($message) { Write-Host "`n->> $message" -ForegroundColor Cyan }

# Claude Code's folder name for a project: every character but letters and
# digits becomes a dash (/home/me/code/x -> -home-me-code-x).
function Get-ClaudeSlug($path) { $path -replace '[^A-Za-z0-9]', '-' }

if (!(Test-Path -LiteralPath $Destination -PathType Container)) {
  throw "$Destination does not exist. Create it first (sudo mkdir $Destination; sudo chown $(id -un):$(id -gn) $Destination)."
}

# --- Preconditions ------------------------------------------------------------

$sourceItem = Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue
# Gone (moved by hand, or by an earlier run), or the symlink older versions of
# this script left: nothing to move, only the repairs below to (re)do.
$alreadyMoved = !$sourceItem -or $sourceItem.LinkType -eq 'SymbolicLink'

if (!$alreadyMoved) {
  if (& tmux list-sessions 2>$null) {
    throw "A tmux server is running. Close it (tmux kill-server) and run this from a plain terminal."
  }
  $inside = foreach ($proc in Get-ChildItem /proc -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^\d+$') {
    $cwd = try { [IO.Directory]::ResolveLinkTarget("/proc/$($proc.Name)/cwd", $false).FullName } catch { $null }
    if ($cwd -and ($cwd -eq $Source -or $cwd.StartsWith("$Source/")) -and $proc.Name -ne "$PID") {
      "$($proc.Name) $(Get-Content -Raw "/proc/$($proc.Name)/comm" -ErrorAction SilentlyContinue)".Trim() + " in $cwd"
    }
  }
  if ($inside) {
    throw "These processes are inside $Source -- close them first:`n$($inside -join "`n")"
  }
}
$claudeRunning = [bool](& pgrep -x claude 2>$null)

# --- 1. Move the folder -------------------------------------------------------

Write-Step "Moving $Source into $Destination"
if (!$sourceItem) {
  Write-Host "$Source is gone: already moved"
}
elseif ($alreadyMoved) {
  Write-Host "$Source is already a symlink to $($sourceItem.Target)"
}
else {
  if ((& stat -c %d $Source) -ne (& stat -c %d $Destination)) {
    throw "$Source and $Destination are on different file systems: this script only renames."
  }
  $entries = Get-ChildItem -LiteralPath $Source -Force
  $clashes = $entries | Where-Object { Test-Path -LiteralPath (Join-Path $Destination $_.Name) }
  if ($clashes) {
    throw "Already in ${Destination}: $($clashes.Name -join ', '). Sort them out by hand first."
  }
  foreach ($entry in $entries) {
    if ($PSCmdlet.ShouldProcess($entry.FullName, "Move to $Destination")) {
      & mv -n -- $entry.FullName "$Destination/"
      if ($LASTEXITCODE) { throw "mv failed for $($entry.FullName)" }
    }
  }
}

# --- 2. Symlinks into the old place ------------------------------------------

Write-Step "Re-pointing symlinks into $Source"
# Four levels: ~/.local/share/nvim/site, which ~/.vim and NeoVim's treesitter
# queries go through.
$links = & fd --hidden --no-ignore --type symlink --max-depth 4 . $HOME 2>$null
foreach ($link in $links) {
  $link = $link.TrimEnd('/')
  if ($link -eq $Source) { continue }
  $target = (Get-Item -LiteralPath $link -Force).Target
  if ($target -and $target.StartsWith("$Source/")) {
    $newTarget = $Destination + $target.Substring($Source.Length)
    if ($PSCmdlet.ShouldProcess($link, "Point at $newTarget")) {
      & ln -sfn -- $newTarget $link
    }
  }
}
# Asks for the password when there is a terminal to ask on; without one (run
# from a tool) sudo fails at once and this is left for a run by hand.
$rootTarget = & sudo readlink /root/.modules 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Warning "Could not read /root/.modules (no sudo). Run this again from a terminal, or check it by hand: sudo readlink /root/.modules"
}
elseif ($rootTarget -and $rootTarget.StartsWith("$Source/")) {
  $newTarget = $Destination + $rootTarget.Substring($Source.Length)
  if ($PSCmdlet.ShouldProcess("/root/.modules", "Point at $newTarget")) {
    & sudo ln -sfn -- $newTarget /root/.modules
  }
}

# --- 3. Git worktrees ---------------------------------------------------------

Write-Step "Repairing git worktrees under $Destination"
$repos = & fd --hidden --no-ignore --type directory --max-depth 4 '^worktrees$' $Destination 2>$null |
  Where-Object { $_ -match '/\.git/worktrees/?$' } |
  ForEach-Object { $_ -replace '/\.git/worktrees/?$', '' }
foreach ($repo in $repos) {
  # Each worktree as git still records it, mapped to where it is now: under the
  # destination, or still where it was when it lived outside the code folder.
  # @(): one worktree alone would be a bare string, which git would get one
  # character per argument.
  $paths = @(& git -C $repo worktree list --porcelain | Where-Object { $_ -like 'worktree *' } |
    ForEach-Object { $_.Substring(9) } | Select-Object -Skip 1 |
    ForEach-Object { if ($_.StartsWith("$Source/")) { $Destination + $_.Substring($Source.Length) } else { $_ } } |
    Where-Object { Test-Path -LiteralPath $_ })
  if ($paths -and $PSCmdlet.ShouldProcess($repo, "git worktree repair ($($paths.Count))")) {
    & git -C $repo worktree repair $paths 2>&1 | Out-Null
  }
  $stale = & git -C $repo worktree list | Select-String 'prunable'
  if ($stale) { Write-Warning "Still prunable in ${repo} (gone? check, then git worktree prune):`n$($stale -join "`n")" }
  # Through a ~/code symlink (left by an older version of this script) the old
  # paths resolve, and git sees nothing to repair; the next run, with the link
  # gone, fixes them.
  $old = & git -C $repo worktree list --porcelain | Where-Object { $_ -like "worktree $Source/*" }
  if ($old -and $alreadyMoved -and !$WhatIfPreference) { Write-Warning "Still recorded under ${Source} in ${repo} (run this again):`n$($old -join "`n")" }
}

# --- Nothing left at the old place --------------------------------------------

# Last, after the worktrees: while their old paths lead nowhere, git worktree
# repair sees them as broken. No symlink takes its place -- anything run through
# ~/code would be scanned as if the folder had never moved.
$sourceItem = Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue
if ($sourceItem -and $sourceItem.LinkType -eq 'SymbolicLink') {
  Write-Step "Removing the $Source symlink to $($sourceItem.Target)"
  if ($PSCmdlet.ShouldProcess($Source, "Remove symlink")) {
    [IO.File]::Delete($Source)
  }
}
elseif ($sourceItem -and !(Get-ChildItem -LiteralPath $Source -Force)) {
  Write-Step "Removing the emptied $Source"
  if ($PSCmdlet.ShouldProcess($Source, "Remove empty folder")) {
    [IO.Directory]::Delete($Source)
  }
}

# --- 4. Caches holding paths --------------------------------------------------

Write-Step "Rewriting cached paths"
$cacheHome = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { "$HOME/.cache" }
$files = @("$HOME/.worktrees", "$cacheHome/tmux/home-session-path", "$cacheHome/tmux/home-session-ssh", "$cacheHome/tmux/session-names")
foreach ($file in $files | Where-Object { Test-Path -LiteralPath $_ }) {
  $text = [IO.File]::ReadAllText($file)
  $new = $text.Replace("$Source/", "$Destination/")
  if ($new -ne $text -and $PSCmdlet.ShouldProcess($file, "Replace $Source/ with $Destination/")) {
    [IO.File]::WriteAllText($file, $new)
  }
}

# --- 5. Claude Code's per-project state ---------------------------------------

Write-Step "Moving Claude Code's per-project state"
if ($claudeRunning) {
  Write-Warning "Claude Code is running: skipped. Close every Claude Code and run this again."
}
else {
  $oldSlug = Get-ClaudeSlug $Source
  $newSlug = Get-ClaudeSlug $Destination
  $projects = "$HOME/.claude/projects"
  foreach ($dir in Get-ChildItem -LiteralPath $projects -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq $oldSlug -or $_.Name.StartsWith("$oldSlug-") }) {
    $newPath = Join-Path $projects ($newSlug + $dir.Name.Substring($oldSlug.Length))
    if (Test-Path -LiteralPath $newPath) {
      # Both exist (Claude Code was used on the new path already): move over what
      # the new one lacks, and leave the rest for a look by hand.
      foreach ($child in Get-ChildItem -LiteralPath $dir.FullName -Force) {
        $to = Join-Path $newPath $child.Name
        if (Test-Path -LiteralPath $to) { Write-Warning "Kept both, merge by hand: $($child.FullName) and $to"; continue }
        if ($PSCmdlet.ShouldProcess($child.FullName, "Move to $newPath")) { Move-Item -LiteralPath $child.FullName -Destination $to }
      }
    }
    elseif ($PSCmdlet.ShouldProcess($dir.FullName, "Rename to $newPath")) {
      Move-Item -LiteralPath $dir.FullName -Destination $newPath
    }
  }

  $claudeJson = "$HOME/.claude.json"
  if (Test-Path -LiteralPath $claudeJson) {
    $text = [IO.File]::ReadAllText($claudeJson)
    if ($text.Contains("`"$Source/") -or $text.Contains("`"$Source`"")) {
      # A project already opened at its new path has a key of its own: the
      # rename below would make two, so the old one goes and the new one wins.
      $json = $text | ConvertFrom-Json -AsHashtable -DateKind String
      if ($json.projects) {
        foreach ($key in @($json.projects.Keys)) {
          if ($key -ne $Source -and !$key.StartsWith("$Source/")) { continue }
          $newKey = $Destination + $key.Substring($Source.Length)
          if ($json.projects.Contains($newKey)) {
            Write-Warning "Claude Code already knows ${newKey}: dropping its settings under $key"
            $json.projects.Remove($key)
          }
        }
      }
      # Only whole JSON strings that are the folder or start inside it.
      $new = ($json | ConvertTo-Json -Depth 100).Replace("`"$Source/", "`"$Destination/").Replace("`"$Source`"", "`"$Destination`"")
      # The same checkout listed under both paths for a GitHub repo, once now.
      $json = $new | ConvertFrom-Json -AsHashtable -DateKind String
      if ($json.githubRepoPaths) {
        foreach ($repo in @($json.githubRepoPaths.Keys)) {
          $json.githubRepoPaths[$repo] = @($json.githubRepoPaths[$repo] | Select-Object -Unique)
        }
      }
      $new = $json | ConvertTo-Json -Depth 100
      if ($PSCmdlet.ShouldProcess($claudeJson, "Replace $Source with $Destination")) {
        Copy-Item -LiteralPath $claudeJson -Destination "$claudeJson.before-move-code-folder"
        [IO.File]::WriteAllText($claudeJson, $new)
      }
    }
  }
}

# --- 6. Hand-written dotfiles -------------------------------------------------

# With no ~/code left, whatever still names it is broken rather than slow.
Write-Step "Rewriting $Source in dotfiles"
$dotfiles = @("$HOME/.profile", "$HOME/.profile.ps1", "$HOME/.config/systemd/user/docker.service")
$serviceChanged = $false
foreach ($file in $dotfiles | Where-Object { Test-Path -LiteralPath $_ }) {
  $text = [IO.File]::ReadAllText($file)
  # The folder itself ends in a quote, a colon (PATH) or the line; inside it, a slash.
  $new = [regex]::Replace($text, [regex]::Escape($Source) + '(?=[/''":\s]|$)', $Destination.Replace('$', '$$'))
  if ($new -ne $text -and $PSCmdlet.ShouldProcess($file, "Replace $Source with $Destination")) {
    Copy-Item -LiteralPath $file -Destination "$file.before-move-code-folder"
    [IO.File]::WriteAllText($file, $new)
    if ($file -like '*.service') { $serviceChanged = $true }
  }
}
if ($serviceChanged) {
  & systemctl --user daemon-reload 2>$null
  if ($LASTEXITCODE) { Write-Warning "systemctl --user daemon-reload failed (no user session bus?): run it by hand" }
}

# git matches includeIf gitdir: against the real path, so a ~/code/ one can no
# longer match; the move's own block for the destination is kept.
$gitconfig = "$HOME/.gitconfig"
$tildeSource = $Source -replace "^$([regex]::Escape($HOME))", '~'
if (Test-Path -LiteralPath $gitconfig) {
  $text = [IO.File]::ReadAllText($gitconfig)
  $pattern = '(?m)^\[includeIf "gitdir:(' + [regex]::Escape($Source) + '|' + [regex]::Escape($tildeSource) + ')/[^"]*"\]\r?\n(?:[ \t]+[^\r\n]*\r?\n)*'
  $new = [regex]::Replace($text, $pattern, '')
  if ($new -ne $text -and $PSCmdlet.ShouldProcess($gitconfig, "Drop includeIf blocks for $tildeSource/")) {
    Copy-Item -LiteralPath $gitconfig -Destination "$gitconfig.before-move-code-folder"
    [IO.File]::WriteAllText($gitconfig, $new)
  }
}

# What is still left, for a look by hand.
if (!$WhatIfPreference) {
  $left = @(& fd --hidden --no-ignore --type symlink --max-depth 4 . $HOME 2>$null | ForEach-Object {
      $target = (Get-Item -LiteralPath $_.TrimEnd('/') -Force).Target
      if ($target -and ($target -eq $Source -or $target.StartsWith("$Source/"))) { "$_ -> $target" }
    })
  $left += @(& rg -n --no-messages -F -e $Source -e "$tildeSource/" -- @($dotfiles + $gitconfig))
  if ($left) { Write-Warning "Still naming ${Source}:`n$($left -join "`n")" }
}

Write-Step "Done"
Write-Host @"
Left for you:
  - log in again (or open a new login shell) so ~/.profile is re-read
  - .NET: dotnet restore (or a clean build) in the projects you work on; obj/ holds absolute paths
  - sql-assist: pwsh $Destination/dev-environment/modules/sql-assist/Build-SqlAssist.ps1
  - Python virtual environments: recreate them (their scripts name the old path)
  - start tmux again
"@
