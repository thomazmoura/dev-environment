function Import-PsFzf() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module PsFzf -ListAvailable) ) {
    Write-Information "`n->> PSFzf not found. Installing"
    Install-Module -Force -AcceptLicense PSFzf 
  }
  Write-Verbose "`n->> Importing PSFzf"
  Import-Module PSFzf -ErrorAction Stop
  Write-Information "`n->> Overriding keybinding"
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do PsFzf demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PsAWS([string]$region = "sa-east-1") {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module AWSPowerShell.NetCore -ListAvailable) ) {
    Write-Information "`n->> AWSPowerShell.NetCore not found. Installing"
    Install-Module -Force -AcceptLicense -Name AWSPowerShell.NetCore
  }
  Write-Verbose "`n->> Importing AWS CLI"
  Import-Module -Name AWSPowerShell.NetCore -ErrorAction Stop
  Set-DefaultAWSRegion -Region $region -Scope Global
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do PsAWS demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-DockerCompletion() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if(Get-Command docker -ErrorAction SilentlyContinue) {
    if ( !(Get-Module DockerCompletion -ListAvailable) ) {
      Write-Information "`n->> DockerCompletion not found. Installing"
      Install-Module -Force -AcceptLicense DockerCompletion -ErrorAction Stop
    }
    Write-Verbose "`n->> Importing DockerCompletion"
    Import-Module DockerCompletion -ErrorAction Stop
  } else {
      Write-Verbose "`n->> Docker not found. Skipping DockerCompletion"
  }
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do autocomplete do docker demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PoshGit() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module posh-git -ListAvailable) ) {
    Write-Information "`n->> Posh-git not found. Installing"
    Install-Module -Force -AcceptLicense posh-git -ErrorAction Stop
  }
  Write-Verbose "`n->> Importing posh-git"
  Import-Module posh-git -ErrorAction Stop
  if ($global:GitPromptSettings) {
    # Keep tmux pane titles untouched by posh-git
    $global:GitPromptSettings.WindowTitle = $false
  }
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do Posh-git demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-SqlServer() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module SqlServer -ListAvailable) ) {
    Write-Information "`n->> SqlServer module not found. Installing"
    Install-Module -Force -AcceptLicense SqlServer -ErrorAction Stop
  }
  Write-Verbose "`n->> Importing SqlServer Module"
  Import-Module SqlServer -ErrorAction Stop
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do SqlServer demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-OhMyPoshOnLinux() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  Write-Verbose "`n->> Activating oh-my-posh"
  $ompVersion = "31.3.0"
  $ompBinary = "$HOME/.local/bin/oh-my-posh"
  $ompConfig = "$HOME/.config/powershell/linux.omp.json"
  # Asking the binary its version would launch it on every shell start, so the
  # installed version is recorded in a file next to it instead.
  $ompVersionFile = "$HOME/.local/share/oh-my-posh/version"
  $installedVersion = if (Test-Path $ompVersionFile) { (Get-Content -Raw $ompVersionFile).Trim() }
  if( !(Test-Path $ompBinary) -or $installedVersion -ne $ompVersion ) {
    Write-Information "`n->> Installing oh-my-posh v$ompVersion"
    New-Item -Force -ItemType Directory -Path (Split-Path $ompBinary), (Split-Path $ompVersionFile) | Out-Null
    # Downloaded beside the binary and moved over it: other shells' `serve`
    # processes keep the old binary open, and writing into it fails while they run.
    wget -q "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v$ompVersion/posh-linux-amd64" -O "$ompBinary.download"
    if( $LASTEXITCODE -eq 0 ) {
      chmod +x "$ompBinary.download"
      Move-Item -Force "$ompBinary.download" $ompBinary
      Set-Content $ompVersionFile $ompVersion
    } else {
      Remove-Item -Force -ErrorAction Ignore "$ompBinary.download"
      Write-Warning "Could not download oh-my-posh v$ompVersion"
    }
  } else {
    Write-Verbose "OhMyPosh instalado corretamente"
  }
  if( !(Test-Path $ompBinary) ) { return }
  # Not `init --print`: that output pins one POSH_SESSION_ID for every shell
  # loading it and never applies a theme's `async`. The plain `init` output loads a
  # script oh-my-posh keeps cached in ~/.cache/oh-my-posh on its own.
  & $ompBinary init pwsh --config=$ompConfig | Invoke-Expression
  Write-Verbose "Carregado o arquivo $ompConfig"
  $stopwatch.Stop();
  Write-Verbose "`n-->> Importação do Oh-My-Posh demorou: $($stopwatch.ElapsedMilliseconds)"
}

# The default prompt: linux.omp.json's look, drawn by pwsh itself. oh-my-posh and
# Starship spend 1-2s of every shell start having pwsh compile their init scripts;
# this costs a few ms, plus one `git status` per prompt inside a repository.
# `omp` still loads oh-my-posh.
function Set-NativePrompt() {
  $osId = 'linux'
  if ([IO.File]::Exists('/etc/os-release')) {
    foreach ($line in [IO.File]::ReadAllLines('/etc/os-release')) {
      if ($line.StartsWith('ID=')) { $osId = $line.Substring(3).Trim('"'); break }
    }
  }
  $osIcon = switch ($osId) { 'ubuntu' { "`u{f31b}" } 'debian' { "`u{f306}" } default { "`u{f17c}" } }
  $rootIcon = if ([Environment]::UserName -eq 'root') { "`e[38;2;205;94;66m`u{e3bf} " } else { '' }

  # Literal escapes on purpose: every call made here is paid on each shell start.
  # Colors are linux.omp.json's; red is the terminal's own, like omp's "red".
  $global:NativePromptStyle = @{
    Path       = "`e[48;2;122;162;247m`e[38;2;0;0;0m"
    PathToNext = "`e[38;2;122;162;247m`e[48;2;59;66;97m`u{e0b0}`e[38;2;122;162;247m"
    GitToTime  = "`e[38;2;59;66;97m`u{e0b0}`e[38;2;122;162;247m"
    TimeToOk   = "`e[38;2;59;66;97m`e[48;2;46;149;153m`u{e0b0}`e[38;2;255;255;255m `u{f469} `e[0m`e[38;2;46;149;153m`u{e0b0}`e[0m"
    TimeToErr  = "`e[38;2;59;66;97m`e[41m`u{e0b0}`e[38;2;255;255;255m `u{f11ce} `e[0m`e[31m`u{e0b0}`e[0m"
    Second     = "`n$rootIcon`e[38;2;153;170;255m$osIcon `e[38;2;38;198;218m`u{276f}`e[38;2;69;241;194m`u{276f} " +
                 "`e[38;2;205;66;119m`e[1m$osId`e[22m `e[38;2;38;198;218m`u{276f}`e[38;2;69;241;194m`u{276f}`e[0m "
    Home       = "`u{f015} "
    Branch     = " `u{e0a0} "
    Staging    = " `u{e0b1} `e[38;2;255;255;255m`u{f046} "
    Working    = " `u{e0b1} `e[38;2;170;170;170m`u{f044} "
    GitFg      = "`e[38;2;122;162;247m"
    Time       = " `u{f253} "
    First      = $true
  }

  # Two-line prompt: PSReadLine's -ExtraPromptLineCount 1 is set with the rest
  # of its options, on the first idle tick (kernel-profile.ps1).

  function global:prompt {
    $ok = $?
    $exitCode = $global:LASTEXITCODE
    $s = $global:NativePromptStyle

    $cwd = $ExecutionContext.SessionState.Path.CurrentLocation
    $path = $cwd.Path
    if ($cwd.Provider.Name -eq 'FileSystem') {
      $path = $cwd.ProviderPath
      if ($path -eq $HOME -or $path.StartsWith("$HOME/")) { $path = $s.Home + $path.Substring($HOME.Length) }
    }

    # Walking up for .git first keeps git from running outside a repository; a .git
    # file (worktree, submodule) points at the real git dir.
    $git = $null
    if ($cwd.Provider.Name -eq 'FileSystem') {
      $dir = $cwd.ProviderPath
      while ($dir) {
        $dotGit = [IO.Path]::Combine($dir, '.git')
        $gitDir = $null
        if ([IO.Directory]::Exists($dotGit)) { $gitDir = $dotGit }
        elseif ([IO.File]::Exists($dotGit)) {
          $link = [IO.File]::ReadAllText($dotGit).Trim()
          if ($link.StartsWith('gitdir: ')) { $gitDir = [IO.Path]::GetFullPath($link.Substring(8), $dir) }
        }
        if ($gitDir) { $git = Get-NativePromptGit $dir; break }
        $dir = [IO.Path]::GetDirectoryName($dir)
      }
    }

    $ms = 0
    $last = Get-History -Count 1
    if ($last) { $ms = [int]($last.EndExecutionTime - $last.StartExecutionTime).TotalMilliseconds }
    $elapsed = if ($ms -lt 1000) { "${ms}ms" }
               elseif ($ms -lt 60000) { '{0:0.##}s' -f ($ms / 1000) }
               else { '{0}m {1}s' -f [math]::Floor($ms / 60000), [math]::Floor(($ms % 60000) / 1000) }

    $failed = !$ok
    $out = if ($s.First) { '' } else { "`n" }
    $s.First = $false
    $out += $s.Path + " $path "
    $out += $s.PathToNext
    if ($git) { $out += $git + $s.GitToTime }
    $out += $s.Time + $elapsed + ' '
    $out += if ($failed) { $s.TimeToErr } else { $s.TimeToOk }
    $out += $s.Second

    $global:LASTEXITCODE = $exitCode
    $out
  }
  # The git segment's text: one `git status --porcelain=v2 --branch` gives the branch,
  # ahead/behind and both change counts, written the way omp's git segment does. omp's
  # host icon (GitHub, Azure DevOps...) is left out: reading it cost 25-55ms on the
  # first prompt.
  function global:Get-NativePromptGit($root) {
    $s = $global:NativePromptStyle
    $lines = & git -C $root --no-optional-locks status --porcelain=v2 --branch 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $head = ''; $oid = ''; $ab = $null
    $sa = $sm = $sd = $sr = 0; $wu = $wm = $wd = 0; $conflicts = 0
    foreach ($l in $lines) {
      $c = $l[0]
      if ($c -eq '#') {
        if ($l.StartsWith('# branch.head ')) { $head = $l.Substring(14) }
        elseif ($l.StartsWith('# branch.oid ')) { $oid = $l.Substring(13) }
        elseif ($l.StartsWith('# branch.ab ')) { $ab = $l.Substring(12).Split(' ') }
      }
      elseif ($c -eq '?') { $wu++ }
      elseif ($c -eq 'u') { $conflicts++ }
      elseif ($c -eq '1' -or $c -eq '2') {
        switch ($l[2]) { 'A' { $sa++ } 'M' { $sm++ } 'T' { $sm++ } 'D' { $sd++ } 'R' { $sr++ } 'C' { $sa++ } }
        switch ($l[3]) { 'M' { $wm++ } 'T' { $wm++ } 'D' { $wd++ } }
      }
    }

    # Like omp: ≢ when the branch has no upstream or it is gone.
    $status = if (!$ab) { "`u{2262}" }
              elseif ($ab[0] -eq '+0' -and $ab[1] -eq '-0') { "`u{2261}" }
              else { $(if ($ab[0] -ne '+0') { "`u{2191}" + $ab[0].Substring(1) }) + $(if ($ab[1] -ne '-0') { "`u{2193}" + $ab[1].Substring(1) }) }
    if ($head -eq '(detached)') { $head = "detached at `u{f417}" + $oid.Substring(0, [Math]::Min(7, $oid.Length)) }
    $out = ' ' + $s.Branch + $head + ' ' + $status
    $staged = @(); if ($sa) { $staged += "+$sa" }; if ($sm) { $staged += "~$sm" }; if ($sd) { $staged += "-$sd" }; if ($sr) { $staged += ">$sr" }; if ($conflicts) { $staged += "x$conflicts" }
    $working = @(); if ($wu) { $working += "?$wu" }; if ($wm) { $working += "~$wm" }; if ($wd) { $working += "-$wd" }
    if ($staged) { $out += $s.Staging + ($staged -join ' ') + $s.GitFg }
    if ($working) { $out += $s.Working + ($working -join ' ') + $s.GitFg }
    $out + ' '
  }
}

function Update-PSReadline() {
  Write-Verbose "`n->> Updating PSReadLine"
  Install-Module -Name PSReadLine -Force
}

# Runs on every shell start, so .NET checks rather than Test-Path (see
# kernel-profile.ps1); the cmdlets only run the one time it has work to do.
function Start-DevSession() {
  if( ![IO.File]::Exists("$HOME/.dev-session-started") -and [IO.File]::Exists("$HOME/.modules/entrypoint/Start-DevSession.ps1") ) {
    Write-Information "Setting initial dev-environment configuration"
    . "$HOME/.modules/entrypoint/Start-DevSession.ps1" &&
      Get-Date > "$HOME/.dev-session-started"
  }
}
