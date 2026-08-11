#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Detects - and optionally stops - running `dotnet watch test` sessions.

.DESCRIPTION
    `dotnet watch test` spawns a process tree: the watcher itself, an MSBuild
    node, vstest.console, and one or more testhost processes. Terminating only
    the watcher can leave orphaned testhost/MSBuild processes behind, still
    holding file locks on bin/obj. This script resolves the full descendant
    tree and shuts it down from the root.

    By default the script is read-only: it reports what it finds and exits.
    Pass -Stop to actually terminate.

    Works on Windows PowerShell 5.1 and on PowerShell 7+ (Windows, Linux, macOS).

.PARAMETER Stop
    Terminate the sessions that were found. Without this switch nothing is killed.

.PARAMETER Force
    Skip the graceful shutdown attempt and kill immediately. On Windows every
    termination is forceful anyway - there is no portable equivalent of sending
    SIGTERM to an unrelated process.

.PARAMETER GracePeriodSeconds
    How long to wait after SIGTERM before force-killing whatever survived.

.PARAMETER Match
    Extra substring that must appear in the watcher's command line. Useful when
    several solutions are being watched at once, e.g. -Match 'SGI.Testes'.

.PARAMETER Quiet
    Emit a single boolean ($true if at least one session was found) instead of
    detail objects. Handy in scripts and CI gates.

.EXAMPLE
    ./Stop-DotnetWatchTest.ps1
    Lists any running sessions.

.EXAMPLE
    ./Stop-DotnetWatchTest.ps1 -Stop -Confirm:$false -Verbose
    Stops every session without prompting, logging each step.

.EXAMPLE
    if (./Stop-DotnetWatchTest.ps1 -Quiet) { 'watcher is up' }

.EXAMPLE
    ./Stop-DotnetWatchTest.ps1 -Stop -Match 'SGI.Testes' -Force
    Force-kills only the watcher whose command line mentions SGI.Testes.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch] $Stop,
    [switch] $Force,

    [ValidateRange(0, 300)]
    [double] $GracePeriodSeconds = 8,

    [string] $Match,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $IsWindows only exists in PowerShell Core; on 5.1 we are always on Windows.
$script:OnWindows = $true
if (Test-Path -Path 'variable:IsWindows') { $script:OnWindows = $IsWindows }

#region helpers -----------------------------------------------------------

function Get-ProcessSnapshot {
    <# Returns ProcessId / ParentProcessId / CommandLine for every process. #>
    if ($script:OnWindows) {
        Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, CommandLine |
            ForEach-Object {
                [pscustomobject]@{
                    ProcessId       = [int]$_.ProcessId
                    ParentProcessId = [int]$_.ParentProcessId
                    CommandLine     = [string]$_.CommandLine
                }
            }
    }
    else {
        # -ww disables the terminal-width truncation that would clip long args.
        foreach ($line in (& ps '-ww' '-eo' 'pid=,ppid=,args=')) {
            if ($line -match '^\s*(\d+)\s+(\d+)\s+(.+)$') {
                [pscustomobject]@{
                    ProcessId       = [int]$Matches[1]
                    ParentProcessId = [int]$Matches[2]
                    CommandLine     = $Matches[3]
                }
            }
        }
    }
}

function Test-WatchTestCommandLine {
    <#
        True when the command line looks like `dotnet watch ... test ...`.
        The lookarounds keep path fragments from counting: /src/test/Foo.csproj
        contains "test" but not as a bare argument.
    #>
    param([string] $CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    if ($CommandLine -notmatch '(?i)(^|[\\/"''])dotnet(\.exe)?("|''|\s|$)') { return $false }
    if ($CommandLine -notmatch '(?i)(?<![\w\\/.-])watch(?![\w\\/.-])')       { return $false }
    if ($CommandLine -notmatch '(?i)(?<![\w\\/.-])test(?![\w\\/.-])')        { return $false }

    return $true
}

function Get-ProcessDescendant {
    <# Breadth-first walk of the child index; cycle-safe. #>
    param(
        [Parameter(Mandatory)] [int]       $ProcessId,
        [Parameter(Mandatory)] [hashtable] $ChildIndex
    )

    $found = [System.Collections.Generic.List[object]]::new()
    $seen  = [System.Collections.Generic.HashSet[int]]::new()
    $queue = [System.Collections.Generic.Queue[int]]::new()

    [void]$seen.Add($ProcessId)
    $queue.Enqueue($ProcessId)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $ChildIndex.ContainsKey($current)) { continue }
        foreach ($child in $ChildIndex[$current]) {
            if ($seen.Add($child.ProcessId)) {
                $found.Add($child)
                $queue.Enqueue($child.ProcessId)
            }
        }
    }

    return $found
}

function Test-ProcessAlive {
    param([int] $ProcessId)
    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Stop-ProcessSafely {
    param([int] $ProcessId, [string] $Label)

    if (-not (Test-ProcessAlive $ProcessId)) { return }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Write-Verbose "Killed PID $ProcessId ($Label)"
    }
    catch {
        Write-Warning "Could not stop PID $ProcessId ($Label): $($_.Exception.Message)"
    }
}

function Stop-WatchSession {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Descendants,
        [double] $Grace,
        [switch] $Immediate
    )

    # Graceful path: SIGTERM lets dotnet watch tear its own children down and
    # release file handles cleanly. Unix only - Stop-Process is always brutal.
    if (-not $Immediate -and -not $script:OnWindows) {
        Write-Verbose "Sending SIGTERM to PID $($Root.ProcessId)"
        & kill '-s' 'TERM' $Root.ProcessId 2>$null

        $deadline = (Get-Date).AddSeconds($Grace)
        while ((Get-Date) -lt $deadline -and (Test-ProcessAlive $Root.ProcessId)) {
            Start-Sleep -Milliseconds 250
        }
        if (-not (Test-ProcessAlive $Root.ProcessId)) {
            Write-Verbose "PID $($Root.ProcessId) exited gracefully"
        }
    }

    # Root first, so the watcher cannot respawn a testhost we just killed.
    Stop-ProcessSafely -ProcessId $Root.ProcessId -Label 'dotnet watch test'

    $leftovers = @($Descendants)
    if ($leftovers.Count -gt 1) { [array]::Reverse($leftovers) }
    foreach ($child in $leftovers) {
        Stop-ProcessSafely -ProcessId $child.ProcessId -Label 'child'
    }
}

#endregion ----------------------------------------------------------------

$snapshot = @(Get-ProcessSnapshot)

$byPid      = @{}
$childIndex = @{}
foreach ($proc in $snapshot) {
    $byPid[$proc.ProcessId] = $proc
    if (-not $childIndex.ContainsKey($proc.ParentProcessId)) {
        $childIndex[$proc.ParentProcessId] = [System.Collections.Generic.List[object]]::new()
    }
    $childIndex[$proc.ParentProcessId].Add($proc)
}

$candidates = @(
    $snapshot | Where-Object {
        $_.ProcessId -ne $PID -and (Test-WatchTestCommandLine $_.CommandLine)
    }
)

if ($PSBoundParameters.ContainsKey('Match') -and $Match) {
    $candidates = @($candidates | Where-Object { $_.CommandLine -like "*$Match*" })
}

# Keep only topmost matches, so a matching child never gets treated as its own
# session.
$candidateIds = @($candidates | ForEach-Object { $_.ProcessId })
$roots = @(
    foreach ($candidate in $candidates) {
        $nested  = $false
        $walker  = $candidate.ParentProcessId
        $hops    = 0
        while ($walker -gt 0 -and $hops -lt 64) {
            if ($candidateIds -contains $walker) { $nested = $true; break }
            if (-not $byPid.ContainsKey($walker)) { break }
            $walker = $byPid[$walker].ParentProcessId
            $hops++
        }
        if (-not $nested) { $candidate }
    }
)

if ($Quiet) {
    # Still honour -Stop, just say less about it.
    if ($Stop) {
        foreach ($root in $roots) {
            $kids = @(Get-ProcessDescendant -ProcessId $root.ProcessId -ChildIndex $childIndex)
            if ($kids.ProcessId -contains $PID) { continue }
            if ($PSCmdlet.ShouldProcess("PID $($root.ProcessId)", 'Stop dotnet watch test')) {
                Stop-WatchSession -Root $root -Descendants $kids -Grace $GracePeriodSeconds -Immediate:$Force
            }
        }
    }
    return [bool]($roots.Count -gt 0)
}

if ($roots.Count -eq 0) {
    Write-Verbose 'No `dotnet watch test` session found.'
    return
}

foreach ($root in $roots) {
    $descendants = @(Get-ProcessDescendant -ProcessId $root.ProcessId -ChildIndex $childIndex)

    # Never take out the shell that launched this script.
    if ($descendants.ProcessId -contains $PID) {
        Write-Warning "Skipping PID $($root.ProcessId): this script is running inside that process tree."
        continue
    }

    $stopped = $false
    if ($Stop) {
        $target = "PID $($root.ProcessId) plus $($descendants.Count) child process(es)"
        if ($PSCmdlet.ShouldProcess($target, 'Stop dotnet watch test')) {
            Stop-WatchSession -Root $root -Descendants $descendants -Grace $GracePeriodSeconds -Immediate:$Force
            $stopped = -not (Test-ProcessAlive $root.ProcessId)
        }
    }

    [pscustomobject]@{
        ProcessId   = $root.ProcessId
        CommandLine = $root.CommandLine
        ChildCount  = $descendants.Count
        Children    = $descendants
        Stopped     = $stopped
    }
}
