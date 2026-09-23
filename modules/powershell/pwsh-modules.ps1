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

function Update-PSReadline() {
  Write-Verbose "`n->> Updating PSReadLine"
  Install-Module -Name PSReadLine -Force
}

function Start-DevSession() {
  if( !(Test-Path "$HOME/.dev-session-started") -and (Test-Path "$HOME/.modules/entrypoint/Start-DevSession.ps1") ) {
    Write-Information "Setting initial dev-environment configuration"
    . "$HOME/.modules/entrypoint/Start-DevSession.ps1" &&
      Get-Date > "$HOME/.dev-session-started"
  } else {
    Write-Verbose "Initial dev-environment configuration already set"
  }
}
