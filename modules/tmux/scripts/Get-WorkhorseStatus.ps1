#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Gets the first work item from a saved Azure DevOps query for tmux status bar.
.DESCRIPTION
    Reads from WORKHORSE_TMUX_QUERY_ID environment variable, queries Azure DevOps,
    sorts by Stack Rank, and returns the first item in format "#ID | Title".
    Uses file-based caching to avoid excessive API calls.
#>
[CmdletBinding()]
param(
    [int]$CacheTTLSeconds = 60,
    [int]$MaxTitleLength = 80
)

$ErrorActionPreference = 'SilentlyContinue'

# Exit silently if env var not set (opt-in behavior)
$QueryId = $env:WORKHORSE_TMUX_QUERY_ID
if (-not $QueryId) {
    exit 0
}

# Cache configuration
$CacheDir = "$HOME/.cache/workhorse"
$CacheFile = "$CacheDir/tmux-status.json"

function Get-CachedResult {
    if (-not (Test-Path $CacheFile)) {
        return $null
    }

    try {
        $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
        $cacheAge = (Get-Date) - [DateTime]::Parse($cache.timestamp)

        if ($cacheAge.TotalSeconds -lt $CacheTTLSeconds -and $cache.queryId -eq $QueryId) {
            return $cache.display
        }
    }
    catch {
        return $null
    }

    return $null
}

function Set-CachedResult {
    param([string]$Display)

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    @{
        timestamp = (Get-Date).ToString("o")
        display   = $Display
        queryId   = $QueryId
    } | ConvertTo-Json | Set-Content $CacheFile
}

function Get-TruncatedTitle {
    param([string]$Title, [int]$MaxLength)

    if ($Title.Length -le $MaxLength) {
        return $Title
    }

    return $Title.Substring(0, $MaxLength - 3) + "..."
}

# Check cache first
$cached = Get-CachedResult
if ($null -ne $cached) {
    Write-Output $cached
    exit 0
}

# Fetch work items from saved query
try {
    $queryResult = az boards query --id $QueryId --output json 2>$null
    if (-not $queryResult) {
        Set-CachedResult -Display ""
        exit 0
    }

    $workItems = $queryResult | ConvertFrom-Json

    if (-not $workItems -or $workItems.Count -eq 0) {
        Set-CachedResult -Display ""
        exit 0
    }

    # Get work item IDs
    $ids = $workItems | ForEach-Object { $_.id }

    # Fetch full work item details with Stack Rank field
    $idsString = $ids -join ","
    $fields = "System.Id,System.Title,Microsoft.VSTS.Common.StackRank"
    $itemsJson = az boards work-item show --ids $idsString --fields $fields --output json 2>$null

    if (-not $itemsJson) {
        # Fallback: use query results directly (without Stack Rank sorting)
        $firstItem = $workItems | Select-Object -First 1
        $title = Get-TruncatedTitle -Title $firstItem.fields.'System.Title' -MaxLength $MaxTitleLength
        $display = "#$($firstItem.id) | $title"
        Set-CachedResult -Display $display
        Write-Output $display
        exit 0
    }

    $items = $itemsJson | ConvertFrom-Json

    # Handle single item (az returns object instead of array)
    if ($items -isnot [array]) {
        $items = @($items)
    }

    # Sort by Stack Rank ascending (null/missing goes last), then by ID as tiebreaker
    $sortedItems = $items | Sort-Object {
        $rank = $_.fields.'Microsoft.VSTS.Common.StackRank'
        if ($null -eq $rank) { [double]::MaxValue } else { [double]$rank }
    }, { $_.id }

    $firstItem = $sortedItems | Select-Object -First 1

    if (-not $firstItem) {
        Set-CachedResult -Display ""
        exit 0
    }

    # Format output: #123 | Work item title
    $id = $firstItem.id
    $title = Get-TruncatedTitle -Title $firstItem.fields.'System.Title' -MaxLength $MaxTitleLength
    $display = "#$id | $title"

    Set-CachedResult -Display $display
    Write-Output $display
}
catch {
    # Silent failure - don't clutter tmux status bar with errors
    exit 0
}
