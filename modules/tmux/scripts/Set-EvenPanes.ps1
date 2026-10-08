#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sizes the content panes of a window evenly (prefix+C-v).
.DESCRIPTION
    The content area is every pane right of the radar column (Git, Agents,
    Notes), or the whole window when there is no column. Every split in it
    shares its space out equally: four panes side by side get a quarter of
    the width each, two stacked panes half the height each, and the same
    again inside each of them.

    Two sizes stay as they are: the radar column's width, and the height of
    the terminal row (prefix+V, prefix+") -- the row is shared out across
    its own panes, but keeps its height above or below the rest.

    Works on tmux's own description of the window (#{window_layout}): the
    tree of splits is read, its sizes rewritten, and the result applied with
    one select-layout, so the panes jump straight to their new sizes. A
    window zoomed with prefix+z is zoomed out first.
.PARAMETER Pane
    A pane of the window to size, as a tmux pane id (%12).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Pane
)

$ErrorActionPreference = 'Stop'

# A prefix+z zoom parks the other panes in a stash window: put them back, so
# the whole window is sized.
& bash "$HOME/.modules/tmux/scripts/Switch-PaneZoom.sh" --restore $Pane

$layout = & tmux display-message -p -t $Pane '#{window_layout}'
$roles = @{}
foreach ($line in & tmux list-panes -t $Pane -F '#{pane_id}|#{@layout_role}') {
    $id, $role = $line.Split('|', 2)
    $roles[$id.TrimStart('%')] = $role
}

# The layout string, past its checksum: "WxH,X,Y" then ",ID" for a pane, or
# "{...}" for panes side by side, or "[...]" for panes stacked, the children
# separated by commas.
$script:text = $layout.Substring($layout.IndexOf(',') + 1)
$script:at = 0

function Read-Number {
    $start = $script:at
    while ($script:at -lt $script:text.Length -and [char]::IsDigit($script:text[$script:at])) { $script:at++ }
    [int]$script:text.Substring($start, $script:at - $start)
}

function Read-Cell {
    $cell = @{ Children = @(); Split = $null; Id = $null }
    $cell.Width = Read-Number; $script:at++   # x
    $cell.Height = Read-Number; $script:at++  # ,
    $cell.X = Read-Number; $script:at++       # ,
    $cell.Y = Read-Number
    $next = if ($script:at -lt $script:text.Length) { $script:text[$script:at] } else { '' }
    if ($next -eq ',' -and [char]::IsDigit($script:text[$script:at + 1]) -and
        # A pane id ends the cell; a sibling's "WxH" would have an x in it.
        $script:text.Substring($script:at + 1) -match '^\d+(?=[,}\]]|$)') {
        $script:at++
        $cell.Id = [string](Read-Number)
    } elseif ($next -eq '{' -or $next -eq '[') {
        $cell.Split = if ($next -eq '{') { 'Columns' } else { 'Rows' }
        $close = if ($next -eq '{') { '}' } else { ']' }
        $script:at++
        while ($true) {
            $cell.Children += , (Read-Cell)
            $char = $script:text[$script:at]; $script:at++
            if ($char -eq $close) { break }
        }
    }
    $cell
}

function Get-PaneIds($cell) {
    if ($cell.Id) { return , $cell.Id }
    foreach ($child in $cell.Children) { Get-PaneIds $child }
}

# A child of a split that keeps its size: the radar column, and -- along the
# height -- whatever holds the terminal row.
function Test-Fixed($cell, $split) {
    $cellRoles = foreach ($id in Get-PaneIds $cell) { $roles[$id] }
    if ($cellRoles | Where-Object { $_ -in 'git', 'agents', 'notes' }) { return $true }
    $split -eq 'Rows' -and $cellRoles -contains 'terminal'
}

# Moves a cell to the given place, sharing its size out among its children:
# the fixed ones keep theirs, the others split what is left equally (the first
# ones getting a cell more when it doesn't divide), each border taking one.
function Set-CellSize($cell, $x, $y, $width, $height) {
    $cell.X = $x; $cell.Y = $y; $cell.Width = $width; $cell.Height = $height
    if (-not $cell.Split) { return }

    $axis = if ($cell.Split -eq 'Columns') { 'Width' } else { 'Height' }
    $children = $cell.Children
    $fixed = @($children | ForEach-Object { Test-Fixed $_ $cell.Split })
    $flexible = @($fixed | Where-Object { -not $_ }).Count
    $space = $cell.$axis - ($children.Count - 1)
    for ($i = 0; $i -lt $children.Count; $i++) {
        if ($fixed[$i]) { $space -= $children[$i].$axis }
    }
    # Too little room to share out: the children keep their sizes along this
    # axis, and are only moved and fitted across it.
    $sizes = foreach ($i in 0..($children.Count - 1)) { $children[$i].$axis }
    if ($flexible -gt 0 -and $space -ge $flexible) {
        $share = [math]::Floor($space / $flexible)
        $extra = $space % $flexible
        $sizes = foreach ($i in 0..($children.Count - 1)) {
            if ($fixed[$i]) { $children[$i].$axis }
            else { $share + [int]($extra-- -gt 0) }
        }
    }

    $offset = if ($axis -eq 'Width') { $x } else { $y }
    for ($i = 0; $i -lt $children.Count; $i++) {
        if ($axis -eq 'Width') { Set-CellSize $children[$i] $offset $y $sizes[$i] $height }
        else { Set-CellSize $children[$i] $x $offset $width $sizes[$i] }
        $offset += $sizes[$i] + 1
    }
}

function Format-Cell($cell) {
    $head = "$($cell.Width)x$($cell.Height),$($cell.X),$($cell.Y)"
    if ($cell.Id) { return "$head,$($cell.Id)" }
    $body = ($cell.Children | ForEach-Object { Format-Cell $_ }) -join ','
    if ($cell.Split -eq 'Columns') { "$head{$body}" } else { "$head[$body]" }
}

# tmux's layout_checksum: a 16-bit rotate-and-add over the layout string.
function Get-LayoutChecksum([string]$body) {
    $sum = 0
    foreach ($char in $body.ToCharArray()) {
        $sum = (($sum -shr 1) + (($sum -band 1) -shl 15)) -band 0xffff
        $sum = ($sum + [int]$char) -band 0xffff
    }
    '{0:x4}' -f $sum
}

$root = Read-Cell
Set-CellSize $root $root.X $root.Y $root.Width $root.Height
$body = Format-Cell $root
$new = "$(Get-LayoutChecksum $body),$body"
if ($new -ne $layout) {
    & tmux select-layout -t $Pane $new
}

# A laid-out window remembers the layout Set-NeovimLayout.sh left it in, and
# Repair-Layouts.sh redoes the layout whenever the window no longer matches.
# This one keeps the sizes that run fits, so it is recorded as fitted too.
if (& tmux display-message -p -t $Pane '#{@layout_fitted}') {
    & tmux set -w -t $Pane @layout_fitted (& tmux display-message -p -t $Pane '#{window_layout}')
}
