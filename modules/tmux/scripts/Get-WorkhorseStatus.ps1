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
    [int]$ErrorCacheTTLSeconds = 10,
    [int]$MaxTitleLength = 80
)

$ErrorActionPreference = 'Stop'

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
        $cacheContent = Get-Content $CacheFile -Raw -ErrorAction Stop
        if (-not $cacheContent) {
            return $null
        }

        $cache = $cacheContent | ConvertFrom-Json -ErrorAction Stop
        $cacheTime = [DateTime]::ParseExact($cache.timestamp, "o", [System.Globalization.CultureInfo]::InvariantCulture)
        $cacheAge = (Get-Date) - $cacheTime

        # Use shorter TTL for error/empty results
        $ttl = if ($cache.success -eq $true) { $CacheTTLSeconds } else { $ErrorCacheTTLSeconds }

        if ($cacheAge.TotalSeconds -lt $ttl -and $cache.queryId -eq $QueryId) {
            return $cache.display
        }
    }
    catch {
        # Cache is corrupted or unreadable, will be refreshed
        return $null
    }

    return $null
}

function Set-CachedResult {
    param(
        [string]$Display,
        [bool]$Success = $true
    )

    try {
        if (-not (Test-Path $CacheDir)) {
            New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        }

        # Use atomic write: write to temp file, then rename
        $tempFile = "$CacheFile.tmp.$PID"
        @{
            timestamp = (Get-Date).ToString("o")
            display   = $Display
            queryId   = $QueryId
            success   = $Success
        } | ConvertTo-Json | Set-Content $tempFile -ErrorAction Stop

        Move-Item -Path $tempFile -Destination $CacheFile -Force -ErrorAction Stop
    }
    catch {
        # Clean up temp file if it exists
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
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
        $display = 'Unable to get query results. Check the connection to the Azure DevOps Server/Service'
        Set-CachedResult -Display $display -Success $false
        Write-Output $display
        exit 0
    }

    $workItems = $queryResult | ConvertFrom-Json

    if (-not $workItems -or $workItems.Count -eq 0) {
        $display = "No items returned by the query. Check if there's any active work-items"
        Set-CachedResult -Display $display -Success $false
        Write-Output $display
        exit 0
    }

    # Sort query results by Stack Rank (highest first, null goes last)
    $sortedItems = $workItems | Sort-Object {
        $rank = $_.fields.'Microsoft.VSTS.Common.StackRank'
        if ($null -eq $rank) { [double]::MinValue } else { [double]$rank }
    }

    $firstItem = $sortedItems | Select-Object -First 1

    if (-not $firstItem) {
        $display = "No items returned by the query. Check if there's any active work-items"
        Set-CachedResult -Display $display -Success $false
        Write-Output $display
        exit 0
    }

    $id = $firstItem.id
    $title = Get-TruncatedTitle -Title $firstItem.fields.'System.Title' -MaxLength $MaxTitleLength
    $display = "#$id | $title"

    Set-CachedResult -Display $display
    Write-Output $display
}
catch {
    $display = 'Unable to get query results. Check the connection to the Azure DevOps Server/Service'
    Set-CachedResult -Display $display -Success $false
    Write-Output $display
    exit 0
}
